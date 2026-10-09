import AppKit
import LuciControlCore
import Observation
import XCTest
@testable import LuciControl

@MainActor
final class StabilityTests: XCTestCase {
  private func quitEvent(_ reason: OSType?, asParameter: Bool = false) -> NSAppleEventDescriptor {
    let event = NSAppleEventDescriptor(eventClass: AEEventClass(kCoreEventClass), eventID: AEEventID(kAEQuitApplication), targetDescriptor: nil,
                                       returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
    if let reason {
      let why = NSAppleEventDescriptor(typeCode: reason)
      if asParameter {
        event.setParam(why, forKeyword: AEKeyword(kAEQuitReason))
      } else {
        event.setAttribute(why, forKeyword: AEKeyword(kAEQuitReason))
      }
    }
    return event
  }

  /// A logout, restart or shutdown must not wait on 退出 LuciControl？; ⌘Q, the menu and the
  /// power button still ask.
  func testOnlyLogoutRestartAndShutdownSkipTheQuitQuestion() {
    XCTAssertTrue(AppDelegate.isSystemQuit(quitEvent(OSType(kAEReallyLogOut))))
    XCTAssertTrue(AppDelegate.isSystemQuit(quitEvent(OSType(kAERestart))))
    XCTAssertTrue(AppDelegate.isSystemQuit(quitEvent(OSType(kAEShutDown), asParameter: true)))
    XCTAssertFalse(AppDelegate.isSystemQuit(quitEvent(nil)))
    XCTAssertFalse(AppDelegate.isSystemQuit(nil))
  }

  /// The roster says nothing about now while this Mac is off the relay: no phone counts as
  /// connected, and quitting does not claim one is watching.
  func testPhonesCountAsConnectedOnlyWhileThisMacIs() {
    let model = PanelModel()
    model.devices = [Device(id: "p1", label: "iPhone", user: "kai", isOwner: true, online: true, verified: true, watching: 1)]
    model.sharing = .sharing
    XCTAssertEqual(model.connectedDevices.map(\.id), ["p1"])
    XCTAssertTrue(model.quitWarning.contains("iPhone 正在看"))
    for state in [SharingState.paused, .connecting, .starting, .error("断了")] {
      model.sharing = state
      XCTAssertTrue(model.connectedDevices.isEmpty, "\(state)")
      XCTAssertFalse(model.quitWarning.contains("正在看"), "\(state)")
    }
    model.sharing = .sharing
    model.devices[0].verified = false
    XCTAssertTrue(model.connectedDevices.isEmpty, "on the relay but not connected to this Mac")
  }

  private func backendWithoutDaemon(_ model: PanelModel) -> DaemonBackend {
    DaemonBackend(model: model, executable: URL(fileURLWithPath: "/usr/bin/false"), dataDir: "/tmp/lucicontrol-unused-test", relay: nil)
  }

  /// A switch shows the new value at once and goes back when the daemon did not take it.
  func testFailedSwitchesGoBack() async throws {
    let model = PanelModel()
    let backend = backendWithoutDaemon(model)
    _ = backend
    model.directories = [SharedDirectory(path: "/w", agent: .codex, sharesNewSessions: false)]
    model.sessions = [Session(id: "s", agent: .codex, directory: "/w", title: "t", state: .idle, updatedAt: Date(), shared: true)]
    model.devices = [Device(id: "p1", label: "iPhone", user: "kai", isOwner: true, online: true)]
    model.toggleSession("s")
    model.toggleDeviceBlocked("p1")
    model.setNewSessionsShared(model.directories[0], true)
    XCTAssertFalse(model.sessions[0].shared)
    XCTAssertTrue(model.devices[0].blocked)
    XCTAssertTrue(model.directories[0].sharesNewSessions)
    try await Task.sleep(for: .milliseconds(100))
    XCTAssertTrue(model.sessions[0].shared, "the session is still shared on the daemon")
    XCTAssertFalse(model.devices[0].blocked, "the phone can still connect")
    XCTAssertFalse(model.directories[0].sharesNewSessions)
    XCTAssertNotNil(model.lastError)
  }

  /// Removed means blocked: a phone the daemon has not blocked stays on the list.
  func testRemovalWithoutTheDaemonKeepsThePhoneListed() async {
    let model = PanelModel()
    let backend = backendWithoutDaemon(model)
    let before = UserDefaults.standard.stringArray(forKey: "removedDevices")
    await backend.removeDevice("p-test-never-removed")
    XCTAssertEqual(UserDefaults.standard.stringArray(forKey: "removedDevices"), before)
    XCTAssertNotNil(model.lastError)
  }

  /// "连接中…" for minutes says nothing; the footer names the relay and the reason.
  func testFooterSaysWhyTheRelayIsDown() {
    let model = PanelModel()
    model.sharing = .connecting
    model.machine = MachineInfo(label: "Mac", owner: "kai", appVersion: "0.3.0", daemonVersion: "0.3.0", agentVersion: "", tokenExpiresAt: nil, linkError: "token expired")
    XCTAssertEqual(model.footerStatus.text, "连不上中继，正在重试")
    XCTAssertEqual(model.footerStatus.help, "token expired")
    model.showError("更新共享目录失败：x")
    XCTAssertEqual(model.footerStatus.text, "更新共享目录失败：x")
    model.lastError = nil
    model.sharing = .sharing
    XCTAssertFalse(model.footerStatus.isError)
  }

  /// Once our daemon runs nothing else holds the lock, so a takeover page is past.
  func testReadyLeavesTheTakeoverPage() throws {
    let model = PanelModel()
    let backend = backendWithoutDaemon(model)
    model.page = .takeover
    backend.receive(try JSONDecoder().decode(DaemonMessage.self, from: Data("""
    {"op":"ready","threads":[],"state":{"paired":true,"daemon":{"version":"t","pid":1},"link":{"online":true},"agent":{"found":true,"running":true,"loggedIn":true}}}
    """.utf8)))
    XCTAssertEqual(model.page, .home)
  }

  func testDevicesBackGoesWhereItCameFrom() {
    let model = PanelModel()
    model.page = .home
    model.openDevices()
    XCTAssertEqual(model.page, .devices)
    XCTAssertEqual(model.devicesReturnPage, .home)
    model.page = .settings
    model.openDevices()
    XCTAssertEqual(model.devicesReturnPage, .settings)
  }

  /// Every push carries the whole status; one that changes nothing must not rewrite the
  /// model (each write re-runs the menu bar icon and the open page).
  func testRepeatedStatusDoesNotRewriteTheModel() throws {
    let model = PanelModel()
    let backend = DaemonBackend(model: model, executable: URL(fileURLWithPath: "/usr/bin/false"), dataDir: "/tmp/lucicontrol-unused-test", relay: nil)
    let status = try JSONDecoder().decode(DaemonMessage.self, from: Data("""
    {"op":"status","machine":{"id":"m","label":"Mac","enabled":true,"shares":[{"path":"/w","new":false}]},
     "state":{"paired":true,"owner":"kai","daemon":{"version":"t","pid":1},"link":{"online":true},"agent":{"found":true,"running":true,"loggedIn":true}}}
    """.utf8))
    backend.receive(status)
    XCTAssertEqual(model.sharing, .sharing)
    final class Count: @unchecked Sendable { var changes = 0 }
    let count = Count()
    withObservationTracking {
      _ = (model.sharing, model.machine, model.directories, model.lastError, model.codexAccount, model.page)
    } onChange: {
      count.changes += 1
    }
    backend.receive(status)
    XCTAssertEqual(count.changes, 0)
  }
}
