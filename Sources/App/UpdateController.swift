import AppKit
import LuciControlCore
import Sparkle

/// Sparkle owns download, signature verification, installation and recovery. This
/// adapter keeps our panel honest and lets the daemon finish before a relaunch.
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
  private let model: PanelModel
  private var controller: SPUStandardUpdaterController!
  private var preferenceObservers: [NSKeyValueObservation] = []
  private var pendingInstall: (() -> Void)?
  private(set) var isRestarting = false

  init(model: PanelModel, start: Bool = true) {
    self.model = model
    super.init()
    model.updater = self
    model.updateHints = UserDefaults.standard.object(forKey: "updateHints") as? Bool ?? true
    controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    preferenceObservers = [
      controller.updater.observe(\.automaticallyChecksForUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor [weak self] in self?.syncPreferences() }
      },
      controller.updater.observe(\.automaticallyDownloadsUpdates, options: [.new]) { [weak self] _, _ in
        Task { @MainActor [weak self] in self?.syncPreferences() }
      }
    ]
    if start { controller.startUpdater() }
    syncPreferences()
  }

  private func syncPreferences() {
    model.autoCheckUpdates = controller.updater.automaticallyChecksForUpdates
    model.autoInstallUpdates = controller.updater.automaticallyDownloadsUpdates
  }

  func setAutomaticChecks(_ enabled: Bool) {
    controller.updater.automaticallyChecksForUpdates = enabled
    syncPreferences()
  }

  func setAutomaticDownloads(_ enabled: Bool) {
    controller.updater.automaticallyDownloadsUpdates = enabled
    syncPreferences()
  }

  func checkForUpdates() {
    if pendingInstall != nil { installPendingUpdate(); return }
    if controller.updater.canCheckForUpdates { model.update = .checking }
    NSApp.activate(ignoringOtherApps: true)
    controller.checkForUpdates(nil)
  }

  func installPendingUpdate() {
    guard let install = pendingInstall else { checkForUpdates(); return }
    guard !model.updateRestartBlocked else {
      model.lastError = "请等待服务就绪并结束正在运行或等待确认的会话，再安装更新。"
      return
    }
    pendingInstall = nil
    isRestarting = true
    model.update = .installing
    // Actual process shutdown is awaited by applicationShouldTerminate. Sparkle
    // observes termination before replacing the app and its embedded daemon.
    install()
  }

  var supportsGentleScheduledUpdateReminders: Bool { true }

  func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
    // Menu bar and settings indicate pending updates without stealing focus.
    false
  }

  func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
    if pendingInstall == nil {
      model.update = .available(version: update.displayVersionString, notes: [])
    }
  }

  func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
    model.update = .available(version: item.displayVersionString, notes: [])
  }

  func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
    let info = (error as NSError).userInfo
    let reason = (info[SPUNoUpdateFoundReasonKey] as? NSNumber)?.intValue
    // Sparkle reasons 1 and 2: current version equals or exceeds the feed version.
    if reason == 1 || reason == 2 {
      model.update = .latest(checkedAt: Date())
    } else {
      model.update = .failed(message: "当前系统没有可用更新")
    }
  }

  func updater(_ updater: SPUUpdater, willDownloadUpdate item: SUAppcastItem, with request: NSMutableURLRequest) {
    // The standard Sparkle window reports byte progress; no simulated percentage.
    model.update = .downloading(version: item.displayVersionString, progress: nil)
  }

  func updater(_ updater: SPUUpdater, didExtractUpdate item: SUAppcastItem) {
    model.update = .ready(version: item.displayVersionString, notes: [])
  }

  func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem, immediateInstallationBlock: @escaping () -> Void) -> Bool {
    model.update = .ready(version: item.displayVersionString, notes: [])
    // Leave scheduling to Sparkle; background downloads never force a quit.
    return false
  }

  func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
    postponeRestart(version: item.displayVersionString, installHandler: installHandler)
  }

  func postponeRestart(version: String, installHandler: @escaping () -> Void) -> Bool {
    if model.updateRestartBlocked {
      pendingInstall = installHandler
      model.update = .deferred(version: version)
      return true
    }
    isRestarting = true
    model.update = .installing
    return false
  }

  func updaterWillRelaunchApplication(_ updater: SPUUpdater) {
    isRestarting = true
  }

  func userDidCancelDownload(_ updater: SPUUpdater) {
    model.update = .unchecked
  }

  func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
    isRestarting = false
    pendingInstall = nil
    let error = error as NSError
    // No-update is delivered separately with its compatibility reason.
    if error.domain == SUSparkleErrorDomain, error.code == 1001 { return }
    model.update = .failed(message: "更新未完成：\(error.localizedDescription)")
  }

  func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: Error?) {
    // Closing the update window without downloading must not leave 'checking'.
    if case .checking = model.update { model.update = .unchecked }
  }
}
