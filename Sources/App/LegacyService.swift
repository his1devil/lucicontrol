import Foundation

/// The lucirund service `lucirund install` put in ~/Library/LaunchAgents. LuciControl runs
/// its own daemon, so that one has to go; the identity, config and journal in Application
/// Support stay where they are, and the command-line binary is left alone.
enum LegacyService {
  static let label = "com.his1devil.lucirund"

  static var plistURL: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/LaunchAgents/\(label).plist")
  }

  static var isInstalled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }

  /// Unloads the service and removes its plist. The plist is kept next to the daemon's
  /// data as `legacy-launchagent.plist`, in case someone wants the command-line service back.
  /// Taking over twice is harmless: with the plist already gone the backup stays as it is.
  /// Blocks for launchctl and a moment after it; call it off the main thread.
  static func takeOver() throws {
    let domain = "gui/\(getuid())"
    let bootout = Process()
    bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootout.arguments = ["bootout", "\(domain)/\(label)"]
    bootout.standardError = FileHandle.nullDevice
    bootout.standardOutput = FileHandle.nullDevice
    try bootout.run()
    bootout.waitUntilExit()
    let fm = FileManager.default
    if fm.fileExists(atPath: plistURL.path) {
      let backup = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/lucirund/legacy-launchagent.plist")
      try? fm.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
      try? fm.removeItem(at: backup)
      try? fm.copyItem(at: plistURL, to: backup)
      try fm.removeItem(at: plistURL)
    }
    // launchctl returns before the job is gone; give it a moment. If its daemon still holds
    // the lock after this, ours reports it and the panel retries (DaemonBackend).
    Thread.sleep(forTimeInterval: 0.5)
  }
}
