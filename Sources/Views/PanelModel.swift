import Foundation
import LuciControlCore
import Observation

/// Which page the panel shows.
enum PanelPage: Equatable {
  case home
  case add
  case pair
  case devices
  case settings
  case codexMissing
  /// A lucirund installed from the command line is still running as a service.
  case takeover
}

/// Everything the panel draws and every action it can take. In `--demo` the actions edit
/// the sample data in place; with a daemon they become control-channel calls.
@Observable
@MainActor
final class PanelModel {
  // Navigation
  var page: PanelPage = .home
  var agent: AgentKind = .codex

  // Data
  var directories: [SharedDirectory] = []
  var sessions: [Session] = []
  var devices: [Device] = []
  var candidates: [DirectoryCandidate] = []
  var sharing: SharingState = .unpaired
  var update: UpdateState = .unchecked
  var machine: MachineInfo?
  var pairing: PairingState = .idle
  /// Sections whose folded idle sessions are shown.
  var expanded: Set<String> = []
  /// Which agents the daemon can actually drive today.
  var supportedAgents: Set<AgentKind> = [.codex]

  // Settings
  var autoCheckUpdates = false
  var autoInstallUpdates = false
  var launchAtLogin = false
  var updateHints = true

  // Add page
  var addPath = ""
  var addSelected: Set<String> = []
  var addAgent: AgentKind = .codex
  var addShareExisting = true
  var addShareNew = false

  // Pair page
  var pairMode = 0

  var isDemo = false

  /// The daemon behind the panel; nil in `--demo`, where actions edit the sample data.
  @ObservationIgnored var backend: DaemonBackend?
  @ObservationIgnored weak var updater: UpdateController?

  /// The last request that failed, shown in the footer for a moment.
  var lastError: String?

  /// What is wrong with Codex on this Mac, when something is.
  var codexProblem: CodexProblem = .missing

  /// The signed-in Codex account, when known.
  var codexAccount = ""

  /// What the takeover page says and does.
  var takeover: (() -> Void)?

  /// True while a system dialog opened from the panel is up, so the panel stays open.
  var modalActive = false

  /// The panel is on screen; the clock only ticks while it is.
  var panelVisible = false

  /// How tall the panel may get on the screen it is on; lists scroll past it.
  var maxPanelHeight: CGFloat = DS.panelMaxHeight

  /// A live clock for relative times and the pairing countdown.
  var now = Date()

  init() {}

  static func demo() -> PanelModel {
    let m = PanelModel()
    m.isDemo = true
    m.directories = DemoData.directories()
    m.sessions = DemoData.sessions()
    m.devices = DemoData.devices()
    m.candidates = DemoData.candidates()
    m.sharing = .sharing
    m.machine = DemoData.machine()
    m.update = .available(version: "0.2.0", notes: DemoData.updateNotes)
    return m
  }

  // MARK: derived

  var agents: [AgentKind] { AgentKind.allCases }

  func directories(for agent: AgentKind) -> [SharedDirectory] {
    directories.filter { $0.agent == agent }
  }

  func sessions(in dir: SharedDirectory) -> [Session] {
    Grouping.ordered(Grouping.sessions(in: dir, from: sessions))
  }

  /// Sessions that live in one of the agent's shared directories.
  func sessions(for agent: AgentKind) -> [Session] {
    let dirs = directories(for: agent)
    return sessions.filter { s in dirs.contains { Grouping.sessions(in: $0, from: [s]).isEmpty == false } }
  }

  func hasWaiting(_ agent: AgentKind) -> Bool {
    sessions(for: agent).contains { $0.state == .waiting && $0.shared }
  }

  var waitingCount: Int { agents.reduce(0) { $0 + sessions(for: $1).filter { $0.state == .waiting && $0.shared }.count } }

  var visibleDevices: [Device] { devices.filter { !$0.removed } }

  /// Phones connected right now, i.e. online and not blocked.
  var connectedDevices: [Device] { devices.filter { $0.online && !$0.blocked } }

  var quitNeedsConfirmation: Bool {
    sharing == .sharing && (!connectedDevices.isEmpty || sessions.contains { $0.state == .running && $0.shared })
  }

  var quitWarning: String {
    var lines = [sharing == .sharing ? "退出后手机将连不上这台 Mac。" : "退出后 LuciControl 不再运行，手机连不上这台 Mac。"]
    let watching = connectedDevices.filter { $0.watching > 0 }
    if !watching.isEmpty { lines.append("\(watching.map(\.label).joined(separator: "、")) 正在看这台 Mac 上的会话。") }
    if sessions.contains(where: { $0.state == .running && $0.shared }) { lines.append("正在跑的会话会失去手机那边的控制。") }
    return lines.joined(separator: "\n")
  }
  var removedDevices: [Device] { devices.filter(\.removed) }

  var addCandidates: [DirectoryCandidate] {
    candidates.filter { c in c.agent == addAgent && !directories.contains { $0.path == c.path } }
  }

  var addCount: Int { addSelected.count + (addPath.isEmpty ? 0 : 1) }

  // MARK: actions

  func toggleSession(_ id: String) {
    guard let i = sessions.firstIndex(where: { $0.id == id }) else { return }
    sessions[i].shared.toggle()
    backend?.setSessionShared(id, sessions[i].shared)
  }

  func toggleExpanded(_ dir: SharedDirectory) {
    if expanded.contains(dir.id) { expanded.remove(dir.id) } else { expanded.insert(dir.id) }
  }

  func setNewSessionsShared(_ dir: SharedDirectory, _ on: Bool) {
    guard let i = directories.firstIndex(where: { $0.id == dir.id }) else { return }
    directories[i].sharesNewSessions = on
    backend?.saveDirectories()
  }

  func removeDirectory(_ dir: SharedDirectory) {
    directories.removeAll { $0.id == dir.id }
    backend?.saveDirectories()
  }

  func togglePause() {
    switch sharing {
    case .sharing, .connecting:
      if let backend { backend.setPaused(true) } else { sharing = .paused }
    case .paused:
      if let backend { backend.setPaused(false) } else { sharing = .sharing }
    default: break
    }
  }

  func toggleDeviceBlocked(_ id: String) {
    guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
    devices[i].blocked.toggle()
    backend?.setDeviceBlocked(id, devices[i].blocked)
  }

  func removeDevice(_ id: String) {
    guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
    if let backend {
      backend.removeDevice(id)
      return
    }
    devices[i].blocked = true
    devices[i].removed = true
  }

  func restoreDevice(_ id: String) {
    guard let i = devices.firstIndex(where: { $0.id == id }) else { return }
    if let backend {
      backend.restoreDevice(id)
      return
    }
    devices[i].blocked = false
    devices[i].removed = false
  }

  func openAdd(path: String = "") {
    addPath = path
    addSelected = []
    addAgent = supportedAgents.contains(agent) ? agent : .codex
    addShareExisting = true
    addShareNew = false
    page = .add
    backend?.refreshCandidates()
  }

  func toggleCandidate(_ path: String) {
    if addSelected.contains(path) { addSelected.remove(path) } else { addSelected.insert(path) }
  }

  func commitAdd() {
    var paths = Array(addSelected)
    if !addPath.isEmpty { paths.append(addPath) }
    if let backend {
      // Reading each folder once now makes macOS ask for permission (桌面、文稿、下载…)
      // while the person is at the Mac, not later when a phone runs something there.
      for p in paths { _ = try? FileManager.default.contentsOfDirectory(atPath: p) }
      backend.addDirectories(paths, shareExisting: addShareExisting, shareNew: addShareNew)
      agent = addAgent
      page = .home
      backend.offerLoginItemOnce()
      return
    }
    for p in paths where !directories.contains(where: { $0.path == p }) {
      directories.append(SharedDirectory(path: p, agent: addAgent, sharesNewSessions: addShareNew))
      if !addShareExisting {
        for i in sessions.indices where sessions[i].directory.hasPrefix(p) { sessions[i].shared = false }
      }
    }
    agent = addAgent
    page = .home
  }

  func startPairing() {
    page = .pair
    if let backend {
      backend.startPairing()
      return
    }
    pairing = .waiting(code: "A7K3QD", payload: "lucirun://pair?code=A7K3QD&relay=https%3A%2F%2Fim.zhanghuanyang.com%2Flucirund", expiresAt: Date().addingTimeInterval(292))
  }

  func cancelPairing() {
    backend?.cancelPairing()
    pairing = .idle
    page = .home
  }

  /// Demo only: pretend the phone claimed the code.
  func simulateClaim() {
    guard case .waiting(let code, _, _) = pairing else { return }
    pairing = .claimed(code: code, user: "xiaolu", deviceLabel: "iPhone 17 Pro Max")
  }

  func confirmPairing(accept: Bool) {
    guard case .claimed(_, let user, let device) = pairing else { return }
    if let backend {
      backend.confirmPairing(accept: accept)
      if !accept { page = .home }
      return
    }
    if accept {
      pairing = .done(user: user, deviceLabel: device)
      if sharing == .unpaired { sharing = .sharing }
    } else {
      pairing = .idle
      page = .home
    }
  }

  func finishPairing() {
    pairing = .idle
    page = directories.isEmpty ? .add : .home
  }

  func setLaunchAtLogin(_ on: Bool) {
    launchAtLogin = on
    guard !isDemo else { return }
    do {
      try LoginItem.set(on)
    } catch {
      lastError = "开机启动设置失败：\(error.localizedDescription)"
      launchAtLogin = LoginItem.isEnabled
    }
  }

  var hasActiveSessions: Bool {
    sessions.contains { $0.state == .running || $0.state == .waiting }
  }

  var updateRestartBlocked: Bool {
    hasActiveSessions || sharing == .starting
  }

  func setAutoCheckUpdates(_ on: Bool) {
    autoCheckUpdates = on
    updater?.setAutomaticChecks(on)
  }

  func setAutoInstallUpdates(_ on: Bool) {
    autoInstallUpdates = on
    updater?.setAutomaticDownloads(on)
  }

  func setUpdateHints(_ on: Bool) {
    updateHints = on
    if !isDemo { UserDefaults.standard.set(on, forKey: "updateHints") }
  }

  func checkForUpdates() {
    updater?.checkForUpdates()
  }

  func downloadUpdate() {
    updater?.checkForUpdates()
  }

  func installUpdate() {
    updater?.installPendingUpdate()
  }
}
