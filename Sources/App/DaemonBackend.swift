import AppKit
import Foundation
import LuciControlCore
import os

/// What happens to the daemon, for `log show --predicate 'subsystem == "com.his1devil.lucicontrol"'`.
private let log = Logger(subsystem: "com.his1devil.lucicontrol", category: "daemon")

/// Feeds the panel from a real lucirund and turns the panel's actions into requests to it.
/// The daemon is the truth: every change the panel makes is applied there and comes back
/// as a push, so the model here only ever reflects what the daemon said.
@MainActor
final class DaemonBackend {
  let model: PanelModel
  private var process: DaemonProcess!
  private var machine: WireMachine?
  private var state: WireState?
  private var shares: [WireShare] = []
  private var removed: Set<String> {
    get { Set(UserDefaults.standard.stringArray(forKey: "removedDevices") ?? []) }
    set { UserDefaults.standard.set(Array(newValue), forKey: "removedDevices") }
  }
  private var lastDevices: [WireDevice] = []
  private let relay: String?
  private let isolated: Bool
  /// Things asked for before the daemon was ready, run on `ready`.
  private var whenReady: [() -> Void] = []
  private var ready = false
  /// Test switches (`--test-auto-confirm`, `--test-add-dir`): the panel cannot be clicked
  /// from a script, so these do what the person would.
  var testAutoConfirm = false
  /// `--takeover`: stop the command-line service at start without showing the page.
  var takeOverAtStart = false
  /// Called when the panel should come forward on its own: the first run, and the takeover.
  var showPanel: (() -> Void)?
  private var firstReadyHandled = false
  /// Pushes counted over a few seconds, to notice a daemon that floods the channel.
  private var pushWindow = (start: Date(), count: 0)
  private var lastFloodLog = Date.distantPast

  init(model: PanelModel, executable: URL, dataDir: String?, relay: String?) {
    self.model = model
    self.relay = relay
    isolated = dataDir != nil
    var env: [String: String] = [:]
    if let dataDir { env["LUCIRUND_DIR"] = dataDir }
    process = DaemonProcess(executable: executable, environment: env, onEvent: { [weak self] e in self?.event(e) }, onPush: { [weak self] msg in
      Task { @MainActor in self?.receive(msg) }
    })
    model.backend = self
  }

  func start() {
    model.launchAtLogin = LoginItem.isEnabled
    model.takeover = { [weak self] in self?.takeOverLegacy() }
    // An isolated data directory (development) has nothing to do with the old service.
    if !isolated, LegacyService.isInstalled {
      if takeOverAtStart {
        takeOverLegacy()
        return
      }
      // The command-line service would fight our daemon over the relay: settle that first.
      model.sharing = .error("命令行版的 lucirund 还在运行")
      model.page = .takeover
      showPanel?()
      return
    }
    model.sharing = .starting
    process.start()
  }

  /// Stops the old service and starts our own daemon in its place. launchctl and the wait
  /// for the old daemon run off the main thread.
  func takeOverLegacy() {
    Task {
      do {
        try await Task.detached { try LegacyService.takeOver() }.value
      } catch {
        log.error("takeover failed: \(String(describing: error), privacy: .public)")
        model.showError("接管失败：\(error.localizedDescription)")
        return
      }
      log.notice("took over the command-line service")
      takenOverAt = Date()
      model.page = .home
      model.sharing = .starting
      process.start()
    }
  }

  /// When the command-line service was stopped. Its daemon may hold the lock for a moment
  /// longer: until then our daemon's "already running" is the wait, not another copy.
  private var takenOverAt: Date?
  private var waitingForTakeover: Bool { takenOverAt.map { Date().timeIntervalSince($0) < 30 } ?? false }

  func recheckCodex() {
    model.page = .home
    ready = false
    // A restart re-resolves codex and asks account/read again.
    Task {
      await process.stop()
      process.start()
    }
  }

  /// After the first folder is shared, ask once whether to start at login (on by default).
  func offerLoginItemOnce() {
    let key = "askedLoginItem"
    guard !UserDefaults.standard.bool(forKey: key), !LoginItem.isEnabled else { return }
    UserDefaults.standard.set(true, forKey: key)
    let alert = NSAlert()
    alert.messageText = "开机时启动 LuciControl？"
    alert.informativeText = "LuciControl 开着，手机才连得上这台 Mac。登录 macOS 后自动在菜单栏运行，之后可以在设置里改。"
    alert.addButton(withTitle: "开启")
    alert.addButton(withTitle: "不用").keyEquivalent = "\u{1b}"
    if model.runModalAlert(alert) == .alertFirstButtonReturn {
      model.setLaunchAtLogin(true)
    }
  }

  func stop() async {
    await process.stop()
  }

  private var control: ControlClient? { process.control }

  // MARK: pushes

  private func event(_ e: DaemonProcess.Event) {
    switch e {
    case .started(let pid):
      // notice, not info: macOS keeps notices, and a start is worth finding afterwards.
      log.notice("lucirund started, pid \(pid, privacy: .public)")
      ready = false
      update(\.sharing, .starting)
    case .exited(let code, let restartIn):
      if let restartIn {
        log.error("lucirund exited with \(code, privacy: .public), restarting in \(Int(restartIn), privacy: .public) s")
      } else {
        log.notice("lucirund stopped (\(code, privacy: .public))")
      }
      ready = false
      if model.page == .takeover { return }
      update(\.sharing, restartIn == nil ? .paused : .starting)
      if code != 0, let restartIn, !waitingForTakeover { model.showError("lucirund 退出了（\(code)），\(Int(restartIn)) 秒后重试") }
    case .fatal(let msg):
      log.fault("lucirund cannot run: \(msg, privacy: .public)")
      model.sharing = .error(msg)
    }
  }

  func receive(_ msg: DaemonMessage) {
    notePush()
    switch msg.op {
    case "ready", "status":
      if let m = msg.machine { machine = m; shares = m.shares }
      if let s = msg.state { state = s }
      applyStatus()
      if let t = msg.threads { applyThreads(t) }
      if let d = msg.devices { applyDevices(d) }
      if msg.op == "ready" {
        // A daemon that is (back) up makes older failures moot; a status push says nothing
        // about them, they go on their own (showError).
        update(\.lastError, nil)
        // Our daemon runs, so nothing else holds the lock: a takeover page is past.
        if model.page == .takeover { model.page = .home }
        ready = true
        refreshCandidates()
        let queued = whenReady
        whenReady = []
        queued.forEach { $0() }
      }
      // A missing/logged-out Codex detour must not consume first-run pairing.
      // Resume on either ready or a later status after Codex becomes available.
      if ready, !firstReadyHandled, let state, model.page == .home {
        firstReadyHandled = true
        if !state.paired {
          model.startPairing()
          showPanel?()
        }
      }
    case "threads":
      applyThreads(msg.threads ?? [])
    case "devices":
      applyDevices(msg.devices ?? [])
    case "pair":
      if let p = msg.pair {
        model.pairing = Mapping.pairing(p)
        if testAutoConfirm, p.state == "claimed" { confirmPairing(accept: true) }
      }
    case "fatal":
      log.fault("lucirund: \(msg.code ?? "", privacy: .public) \(msg.msg ?? "", privacy: .public)")
      if msg.code == "already-running", waitingForTakeover {
        // The command-line daemon is still on its way out; the restart backoff tries again.
        model.sharing = .starting
        return
      }
      model.sharing = .error(msg.msg ?? msg.code ?? "lucirund 退出了")
      if msg.code == "already-running" {
        // Another lucirund holds the lock: the command-line service, or an older copy of us.
        model.page = .takeover
      }
    case "closed":
      if case .error = model.sharing { return }
      model.sharing = .starting
    default:
      break
    }
  }

  private func applyStatus() {
    guard let state else { return }
    update(\.sharing, Mapping.sharing(state: state, machine: machine))
    update(\.machine, Mapping.machine(state: state, machine: machine, appVersion: Self.appVersion))
    update(\.directories, shares.map(Mapping.directory))
    update(\.codexAccount, state.agent.account ?? "")
    if !state.agent.found {
      update(\.codexProblem, .missing)
      update(\.page, .codexMissing)
    } else if state.agent.loggedIn == false {
      update(\.codexProblem, .notLoggedIn)
      update(\.page, .codexMissing)
    } else if model.page == .codexMissing {
      model.page = .home
    }
  }

  private func applyThreads(_ threads: [WireThread]) {
    update(\.sessions, threads.map(Mapping.session))
  }

  private func applyDevices(_ devices: [WireDevice]) {
    lastDevices = devices
    let removed = removed
    update(\.devices, devices.map { Mapping.device($0, removed: removed) })
    // Removed means blocked. A removed phone the daemon does not have blocked (the block
    // was lost on the way, or the config edited by hand) is blocked again.
    for d in devices where removed.contains(d.id) && !d.blocked && !reblocking.contains(d.id) && !restoring.contains(d.id) {
      reblocking.insert(d.id)
      log.notice("re-blocking removed device \(d.id, privacy: .public)")
      Task {
        _ = await setDeviceBlocked(d.id, true)
        reblocking.remove(d.id)
      }
    }
  }

  /// Removed phones whose block is on its way, and ones being restored (unblocked on purpose).
  private var reblocking: Set<String> = []
  private var restoring: Set<String> = []

  private static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"

  /// Writes only what changed. Every assignment to the observable model re-runs whatever
  /// reads it (the menu bar icon, the open page), equal value or not, and each push carries
  /// the whole status.
  private func update<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<PanelModel, T>, _ value: T) {
    if model[keyPath: keyPath] != value { model[keyPath: keyPath] = value }
  }

  /// Logs, once a minute at most, a daemon that pushes far more than it should: normally a
  /// few a minute, while a codex that kept exiting at once made it hundreds a second.
  private func notePush() {
    pushWindow.count += 1
    let now = Date()
    let seconds = now.timeIntervalSince(pushWindow.start)
    guard seconds >= 5 else { return }
    let rate = Double(pushWindow.count) / seconds
    if rate > 20, now.timeIntervalSince(lastFloodLog) > 60 {
      log.warning("lucirund is pushing \(Int(rate), privacy: .public) messages a second")
      lastFloodLog = now
    }
    pushWindow = (now, 0)
  }

  /// A failed request as a person reads it: the daemon's own message, not a type's dump.
  static func describe(_ error: any Error) -> String {
    switch error {
    case let e as RPCError: e.msg
    case ControlError.timeout: "后台没有响应"
    case ControlError.closed: "后台已断开"
    default: error.localizedDescription
    }
  }

  /// What each request does, for the footer when it fails.
  private static let actions = ["threads.share": "切换会话共享", "shares.set": "更新共享目录", "remote.set": "暂停或恢复共享",
                                "devices.block": "设置设备访问", "pair.cancel": "取消配对"]

  // MARK: actions

  /// One request, true when the daemon did it. A failure (no daemon, an error, no reply) is
  /// logged and shown in the footer; the caller puts back what it showed too early.
  private func perform(_ method: String, _ params: [String: JSONValue] = [:]) async -> Bool {
    let action = Self.actions[method] ?? method
    guard let control else {
      log.error("\(method, privacy: .public) dropped: lucirund is not running")
      model.showError("\(action)失败：后台尚未连接")
      return false
    }
    do {
      _ = try await control.call(method, params)
      return true
    } catch {
      log.error("\(method, privacy: .public) failed: \(String(describing: error), privacy: .public)")
      model.showError("\(action)失败：\(Self.describe(error))")
      return false
    }
  }

  /// A request whose result only comes back as a push (pause, the share list).
  private func call(_ method: String, _ params: [String: JSONValue] = [:]) {
    Task { _ = await perform(method, params) }
  }

  func setSessionShared(_ id: String, _ shared: Bool) async -> Bool {
    await perform("threads.share", ["s": .string(id), "shared": .bool(shared)])
  }

  func removeSession(_ id: String) async throws {
    try await remove("threads.remove", params: ["s": .string(id)])
  }

  func removeDirectory(_ path: String) async throws {
    try await remove("shares.remove", params: ["path": .string(path)])
  }

  private func remove(_ method: String, params: [String: JSONValue]) async throws {
    guard ready, let control else {
      throw NSError(domain: "LuciControl", code: 1, userInfo: [NSLocalizedDescriptionKey: "后台尚未连接，请稍后重试"])
    }
    _ = try await control.call(method, params)
  }

  /// Sends the whole share list, built from the panel's directories and the dates and
  /// options the daemon has for them; true when it took it.
  func saveDirectories() async -> Bool {
    await perform("shares.set", ["shares": JSONValue(Mapping.shares(model.directories, existing: shares))])
  }

  func addDirectories(_ paths: [String], shareExisting: Bool, shareNew: Bool) {
    guard ready else {
      whenReady.append { [weak self] in self?.addDirectories(paths, shareExisting: shareExisting, shareNew: shareNew) }
      return
    }
    var list = Mapping.shares(model.directories, existing: shares)
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    for p in paths where !list.contains(where: { $0.path == p }) {
      list.append(WireShare(path: p, addedAt: now, existing: shareExisting, new: shareNew))
    }
    call("shares.set", ["shares": JSONValue(list)])
  }

  func setPaused(_ paused: Bool) {
    call("remote.set", ["enabled": .bool(!paused), "until": .number(0)])
  }

  func setDeviceBlocked(_ id: String, _ blocked: Bool) async -> Bool {
    await perform("devices.block", ["device": .string(id), "blocked": .bool(blocked)])
  }

  /// Removed means blocked: a phone leaves the list only once the daemon has blocked it, so
  /// the list never hides one that can still connect.
  func removeDevice(_ id: String) async {
    guard await setDeviceBlocked(id, true) else { return }
    var r = removed
    r.insert(id)
    removed = r
    applyDevices(lastDevices)
  }

  /// Back on the list once the daemon lets it in again; until then it stays removed.
  func restoreDevice(_ id: String) async {
    restoring.insert(id)
    defer { restoring.remove(id) }
    guard await setDeviceBlocked(id, false) else { return }
    var r = removed
    r.remove(id)
    removed = r
    applyDevices(lastDevices)
  }

  func startPairing() {
    guard ready, let control else {
      whenReady.append { [weak self] in self?.startPairing() }
      return
    }
    model.pairing = .idle
    var params: [String: JSONValue] = [:]
    if let relay { params["relay"] = .string(relay) }
    Task {
      do {
        let r = try await control.call("pair.start", params)
        let info = try r.decode(PairReply.self)
        await MainActor.run { self.model.pairing = Mapping.pairing(info.pair) }
      } catch {
        log.error("pair.start failed: \(String(describing: error), privacy: .public)")
        self.model.pairing = .failed("连不上中继：\(Self.describe(error))")
      }
    }
  }

  func confirmPairing(accept: Bool) {
    guard let control else { return }
    Task {
      do {
        let r = try await control.call("pair.confirm", ["accept": .bool(accept)])
        let info = try r.decode(PairReply.self)
        await MainActor.run { self.model.pairing = accept ? Mapping.pairing(info.pair) : .idle }
      } catch {
        log.error("pair.confirm failed: \(String(describing: error), privacy: .public)")
        self.model.pairing = .failed(Self.describe(error))
      }
    }
  }

  func cancelPairing() {
    call("pair.cancel")
  }

  /// The whole roster as the daemon has it now, for the device page; pushes only come when
  /// something changes.
  func refreshDevices() {
    guard ready, let control else { return }
    struct Reply: Decodable { var devices: [WireDevice] }
    Task {
      if let r = try? await control.call("devices.list"), let reply = try? r.decode(Reply.self) {
        applyDevices(reply.devices)
      }
    }
  }

  /// The daemon's log, selected in Finder; its folder when there is no log yet.
  func openLogs() {
    let dir = DaemonProcess.logDirectory(environment: process.environment)
    let file = dir.appendingPathComponent("lucirund.log")
    if FileManager.default.fileExists(atPath: file.path) {
      NSWorkspace.shared.activateFileViewerSelecting([file])
    } else {
      NSWorkspace.shared.open(dir)
    }
  }

  func refreshCandidates() {
    guard let control else { return }
    Task {
      // shares.list lists threads first, which the daemon gives up to 20 s.
      if let r = try? await control.call("shares.list", timeout: 25), let cat = try? r.decode(WireShareCatalog.self) {
        await MainActor.run {
          self.shares = cat.shares
          self.model.candidates = cat.candidates.filter { !$0.shared }.map(Mapping.candidate)
        }
      }
    }
  }

  func doctor() async -> [WireDoctorCheck] {
    guard let control else { return [] }
    struct Reply: Decodable { var checks: [WireDoctorCheck] }
    return (try? (try await control.call("doctor")).decode(Reply.self).checks) ?? []
  }

  private struct PairReply: Decodable { var pair: WirePair }
}
