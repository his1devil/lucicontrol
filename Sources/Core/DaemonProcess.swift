import Foundation

/// Runs `lucirund run --stdio` as a child and keeps it running: when it dies it is
/// started again, a little later each time (1 s doubling to 30 s). Its stdin is the
/// control channel, so ending the child means closing that pipe; a `SIGKILL` on us has the
/// same effect from the child's side (stage 0 verified it exits on EOF).
@MainActor
public final class DaemonProcess {
  public enum Event: Sendable {
    case started(pid: Int32)
    case exited(code: Int32, restartIn: TimeInterval?)
    case fatal(String)
  }

  public let executable: URL
  public var environment: [String: String]
  public let onEvent: @MainActor (Event) -> Void
  public let onPush: ControlClient.Handler

  private var process: Process?
  private var client: ControlClient?
  private var backoff: TimeInterval = 1
  private var stopped = false
  private var lastStart = Date.distantPast

  public init(executable: URL, environment: [String: String] = [:], onEvent: @escaping @MainActor (Event) -> Void, onPush: @escaping ControlClient.Handler) {
    self.executable = executable
    self.environment = environment
    self.onEvent = onEvent
    self.onPush = onPush
  }

  public var control: ControlClient? { client }
  public var isRunning: Bool { process?.isRunning ?? false }

  /// The daemon's log directory, `$LUCIRUND_DIR/logs`, by default in Application Support.
  public static func logDirectory(environment: [String: String]) -> URL {
    let base = environment["LUCIRUND_DIR"].map { URL(fileURLWithPath: $0) }
      ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/lucirund")
    return base.appendingPathComponent("logs", isDirectory: true)
  }

  public func start() {
    stopped = false
    // A start while one runs (or is about to be restarted) must not orphan it.
    guard process == nil else { return }
    launch()
  }

  /// Asks the daemon to shut down (it tells the phones), then closes the pipe.
  public func stop() async {
    stopped = true
    if let client {
      _ = try? await withTimeout(seconds: 2) { try await client.call("shutdown") }
      await client.stop()
    }
    process?.standardInput.flatMap { ($0 as? Pipe)?.fileHandleForWriting.closeFile() }
    let p = process
    // Give it a moment to exit on its own before terminating it.
    try? await Task.sleep(for: .milliseconds(500))
    if let p, p.isRunning { p.terminate() }
    process = nil
    client = nil
  }

  private func launch() {
    let p = Process()
    p.executableURL = executable
    p.arguments = ["run", "--stdio"]
    var env = ProcessInfo.processInfo.environment
    for (k, v) in environment { env[k] = v }
    // launchd's PATH did not have the CLI's codex; the daemon looks in fixed places, but
    // `codex` on PATH is the last resort.
    if !(env["PATH"] ?? "").contains("/opt/homebrew/bin") {
      env["PATH"] = (env["PATH"] ?? "/usr/bin:/bin") + ":/opt/homebrew/bin:/usr/local/bin:" + NSHomeDirectory() + "/.local/bin"
    }
    p.environment = env
    let stdin = Pipe()
    let stdout = Pipe()
    p.standardInput = stdin
    p.standardOutput = stdout
    p.standardError = Self.stderrLog(in: Self.logDirectory(environment: env)) ?? FileHandle.standardError
    let c = ControlClient(reading: stdout.fileHandleForReading, writing: stdin.fileHandleForWriting, onPush: onPush)
    p.terminationHandler = { [weak self] proc in
      Task { @MainActor in self?.exited(proc) }
    }
    do {
      try p.run()
    } catch {
      onEvent(.fatal("启动 lucirund 失败：\(error.localizedDescription)"))
      return
    }
    process = p
    client = c
    lastStart = Date()
    onEvent(.started(pid: p.processIdentifier))
    Task { try? await c.start(app: "lucicontrol/" + (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev")) }
  }

  private func exited(_ proc: Process) {
    guard proc === process else { return }
    process = nil
    let code = proc.terminationStatus
    client = nil
    if stopped {
      onEvent(.exited(code: code, restartIn: nil))
      return
    }
    // A daemon that ran for a while earned a fresh backoff.
    if Date().timeIntervalSince(lastStart) > 60 { backoff = 1 }
    let delay = backoff
    backoff = min(backoff * 2, 30)
    onEvent(.exited(code: code, restartIn: delay))
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(delay))
      guard let self, !self.stopped, self.process == nil else { return }
      self.launch()
    }
  }

  /// The daemon's stderr, kept next to its log and rotated past 1 MB. A GUI app's own stderr
  /// goes nowhere, and stderr is where `main` reports a failure before the log is open and
  /// the Go runtime a crash.
  static func stderrLog(in dir: URL) -> FileHandle? {
    let fm = FileManager.default
    let url = dir.appendingPathComponent("lucirund.stderr.log")
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > 1 << 20 {
      let old = url.appendingPathExtension("1")
      try? fm.removeItem(at: old)
      try? fm.moveItem(at: url, to: old)
    }
    if !fm.fileExists(atPath: url.path) {
      fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
    }
    guard let handle = try? FileHandle(forWritingTo: url) else { return nil }
    _ = try? handle.seekToEnd()
    let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "dev"
    // Local time in lucirund.log's own format, so the two files line up.
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyy/MM/dd HH:mm:ss"
    try? handle.write(contentsOf: Data("--- \(stamp.string(from: Date())) lucirund started by LuciControl \(version)\n".utf8))
    return handle
  }
}

/// Runs a cancellation-cooperative `body` with a deadline; on timeout it throws `error`
/// (`ControlError.closed` unless told otherwise). The losing task must finish before the
/// group can return.
func withTimeout<T: Sendable>(seconds: Double, throwing error: any Error = ControlError.closed, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await body() }
    group.addTask {
      try await Task.sleep(for: .seconds(seconds))
      throw error
    }
    defer { group.cancelAll() }
    return try await group.next()!
  }
}
