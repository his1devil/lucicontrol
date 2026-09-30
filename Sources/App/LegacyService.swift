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
  static func takeOver() throws {
    let domain = "gui/\(getuid())"
    let bootout = Process()
    bootout.executableURL = URL(fileURLWithPath: "/bin/launchctl")
    bootout.arguments = ["bootout", "\(domain)/\(label)"]
    bootout.standardError = FileHandle.nullDevice
    bootout.standardOutput = FileHandle.nullDevice
    try bootout.run()
    bootout.waitUntilExit()
    let backup = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/lucirund/legacy-launchagent.plist")
    try? FileManager.default.createDirectory(at: backup.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? FileManager.default.removeItem(at: backup)
    try? FileManager.default.copyItem(at: plistURL, to: backup)
    try FileManager.default.removeItem(at: plistURL)
    // launchctl returns before the job is gone; give it a moment.
    Thread.sleep(forTimeInterval: 0.5)
  }
}
