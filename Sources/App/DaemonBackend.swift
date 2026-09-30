import AppKit
import Foundation
import LuciControlCore

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
  /// Called when the panel should come forward on its own: the first run, and the takeover.
  var showPanel: (() -> Void)?
  private var firstReadyHandled = false

  init(model: PanelModel, executable: URL, dataDir: String?, relay: String?) {
    self.model = model
    self.relay = relay
    isolated = dataDir != nil
    var env: [String: String] = [:]
    if let dataDir { env["LUCIRUND_DIR"] = dataDir }
    process = DaemonProcess(executable: executable, environment: env, onEvent: { [weak self] e in self?.event(e) }, onPush: { [weak self] msg in
      Task { @MainActor in self?.push(msg) }
    })
    model.backend = self
  }

  func start() {
    model.launchAtLogin = LoginItem.isEnabled
    model.takeover = { [weak self] in self?.takeOverLegacy() }
    // An isolated data directory (development) has nothing to do with the old service.
    if !isolated, LegacyService.isInstalled {
      // The command-line service would fight our daemon over the relay: settle that first.
      model.sharing = .error("命令行版的 lucirund 还在运行")
      model.page = .takeover
      showPanel?()
      return
    }
    model.sharing = .starting
    process.start()
  }

  /// Stops the old service and starts our own daemon in its place.
  func takeOverLegacy() {
    do {
      try LegacyService.takeOver()
    } catch {
      model.lastError = "接管失败：\(error.localizedDescription)"
      return
    }
    model.page = .home
    model.sharing = .starting
    process.start()
  }

  func recheckCodex() {
    model.page = .home
    // A restart re-resolves codex and asks account/read again.
    Task {
      await process.stop()
      process.start()
    }
  }

  /// After the first folder is shared, ask once whether to start at login (on by default).
  func offerLoginItemOnce() {
    let key = "askedLoginItem"
    guard !UserDefaults.standard.bool(forKey: key), LoginItem.isAvailable, !LoginItem.isEnabled else { return }
    UserDefaults.standard.set(true, forKey: key)
    let alert = NSAlert()
    alert.messageText = "开机时启动 LuciControl？"
    alert.informativeText = "LuciControl 开着，手机才连得上这台 Mac。登录 macOS 后自动在菜单栏运行，之后可以在设置里改。"
    alert.addButton(withTitle: "开启")
    alert.addButton(withTitle: "不用")
    NSApp.activate(ignoringOtherApps: true)
    if alert.runModal() == .alertFirstButtonReturn {
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
    case .started:
      model.sharing = .starting
    case .exited(let code, let restartIn):
      if model.page == .takeover { return }
      model.sharing = restartIn == nil ? .paused : .starting
      if code != 0, let restartIn { model.lastError = "lucirund 退出了（\(code)），\(Int(restartIn)) 秒后重试" }
    case .fatal(let msg):
      model.sharing = .error(msg)
    }
  }

  private func push(_ msg: DaemonMessage) {
    switch msg.op {
    case "ready", "status":
      model.lastError = nil
      if let m = msg.machine { machine = m; shares = m.shares }
      if let s = msg.state { state = s }
      applyStatus()
      if let t = msg.threads { applyThreads(t) }
      if let d = msg.devices { applyDevices(d) }
      if msg.op == "ready" {
        ready = true
        refreshCandidates()
        let queued = whenReady
        whenReady = []
        queued.forEach { $0() }
        if !firstReadyHandled {
          firstReadyHandled = true
          // A machine that is not paired yet goes straight to the pairing page, in front.
          if let s = msg.state, !s.paired, model.page == .home {
            model.startPairing()
            showPanel?()
          }
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
    model.sharing = Mapping.sharing(state: state, machine: machine)
    model.machine = Mapping.machine(state: state, machine: machine, appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")
    model.directories = shares.map(Mapping.directory)
    model.codexAccount = state.agent.account ?? ""
    if !state.agent.found {
      model.codexProblem = .missing
      model.page = .codexMissing
    } else if state.agent.loggedIn == false {
      model.codexProblem = .notLoggedIn
      model.page = .codexMissing
    } else if model.page == .codexMissing {
      model.page = .home
    }
  }

  private func applyThreads(_ threads: [WireThread]) {
    model.sessions = threads.map(Mapping.session)
  }

  private func applyDevices(_ devices: [WireDevice]) {
    lastDevices = devices
    let removed = removed
    model.devices = devices.map { Mapping.device($0, removed: removed) }
  }

  // MARK: actions

  private func call(_ method: String, _ params: [String: JSONValue] = [:]) {
    guard let control else { return }
    Task {
      do {
        _ = try await control.call(method, params)
      } catch {
        await MainActor.run { self.model.lastError = "\(method): \(error)" }
      }
    }
  }

  func setSessionShared(_ id: String, _ shared: Bool) {
    call("threads.share", ["s": .string(id), "shared": .bool(shared)])
  }

  /// Sends the whole share list, built from the panel's directories and the options the
  /// daemon already had for them.
  func saveDirectories() {
    call("shares.set", ["shares": JSONValue(Mapping.shares(model.directories, existing: shares))])
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

  func setDeviceBlocked(_ id: String, _ blocked: Bool) {
    call("devices.block", ["device": .string(id), "blocked": .bool(blocked)])
  }

  func removeDevice(_ id: String) {
    var r = removed
    r.insert(id)
    removed = r
    setDeviceBlocked(id, true)
    applyDevices(lastDevices)
  }

  func restoreDevice(_ id: String) {
    var r = removed
    r.remove(id)
    removed = r
    setDeviceBlocked(id, false)
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
        await MainActor.run { self.model.pairing = .failed("连不上中继：\(error)") }
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
        await MainActor.run { self.model.pairing = .failed("\(error)") }
      }
    }
  }

  func cancelPairing() {
    call("pair.cancel")
  }

  func refreshCandidates() {
    guard let control else { return }
    Task {
      if let r = try? await control.call("shares.list"), let cat = try? r.decode(WireShareCatalog.self) {
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
