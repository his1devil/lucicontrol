import Foundation
import ServiceManagement

/// "开机时启动": the app registered as a launch agent from its own bundle. launchd starts it
/// at login and, with `KeepAlive: {SuccessfulExit: false}` in the plist, starts it again
/// after a crash but not after a normal quit (stage 0 verified the semantics). Sharing only
/// exists while the app runs, so this is on by default once the machine is set up.
@MainActor
enum LoginItem {
  static let plistName = "com.his1devil.lucicontrol.plist"

  /// The plain login item. The agent plist in the bundle (crash restart) is not used yet:
  /// registering an agent whose RunAtLoad is true starts a second copy of a running app.
  private static var service: SMAppService { .mainApp }

  static var isEnabled: Bool { service.status == .enabled }

  /// Whether the plist is in this bundle at all (development builds may lack it).
  static var isAvailable: Bool {
    Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/" + plistName).path.isEmpty == false
      && FileManager.default.fileExists(atPath: Bundle.main.bundleURL.appendingPathComponent("Contents/Library/LaunchAgents/" + plistName).path)
  }

  static func set(_ on: Bool) throws {
    if on {
      try service.register()
    } else {
      try service.unregister()
    }
  }

  /// A one-line description of the registration, for the settings page and the doctor.
  static var statusText: String {
    switch service.status {
    case .enabled: "已开启"
    case .requiresApproval: "等系统设置里批准"
    case .notRegistered: "未开启"
    case .notFound: "找不到登记"
    @unknown default: "未知"
    }
  }
}
