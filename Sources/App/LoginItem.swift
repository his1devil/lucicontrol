import Foundation
import ServiceManagement

/// "开机时启动": a plain login item for the app (SMAppService.mainApp). Sharing only exists
/// while the app runs, so this is on by default once the machine is set up.
///
/// It does not bring the app back after a crash. The launch agent in the bundle
/// (`KeepAlive: {SuccessfulExit: false}`, restart after a crash but not after a quit; stage 0
/// verified it) would, but registering an agent whose RunAtLoad is true starts a second copy
/// of the running app, so it is not registered. Taking it up means handing the running copy
/// over to launchd, which restarts the daemon and drops the phones for a moment.
@MainActor
enum LoginItem {
  private static var service: SMAppService { .mainApp }

  static var isEnabled: Bool { service.status == .enabled }

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
