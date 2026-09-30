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

  public func start() {
    stopped = false
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
    p.standardError = FileHandle.standardError
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
}

/// Runs `body` with a deadline; on timeout it throws `ControlError.closed`.
func withTimeout<T: Sendable>(seconds: Double, _ body: @escaping @Sendable () async throws -> T) async throws -> T {
  try await withThrowingTaskGroup(of: T.self) { group in
    group.addTask { try await body() }
    group.addTask {
      try await Task.sleep(for: .seconds(seconds))
      throw ControlError.closed
    }
    let first = try await group.next()!
    group.cancelAll()
    return first
  }
}
