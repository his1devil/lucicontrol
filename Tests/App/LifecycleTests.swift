import XCTest
import LuciControlCore
@testable import LuciControl

@MainActor
final class LifecycleTests: XCTestCase {
  private func message(_ op: String = "ready", paired: Bool = false, found: Bool = true, loggedIn: Bool = true) throws -> DaemonMessage {
    try JSONDecoder().decode(DaemonMessage.self, from: Data("""
    {"op":"\(op)","threads":[],"state":{"paired":\(paired),"daemon":{"version":"test","pid":1},"link":{"online":false},"agent":{"found":\(found),"running":false,"loggedIn":\(loggedIn)}}}
    """.utf8))
  }

  func testPairingResumesAfterInstallingOrLoggingIntoCodex() throws {
    for missing in [true, false] {
      let model = PanelModel()
      let backend = DaemonBackend(model: model, executable: URL(fileURLWithPath: "/usr/bin/false"), dataDir: "/tmp/lucicontrol-unused-test", relay: nil)
      var shown = 0
      backend.showPanel = { shown += 1 }
      backend.receive(try message(found: !missing, loggedIn: false))
      XCTAssertEqual(model.page, .codexMissing)
      backend.receive(try message("status"))
      XCTAssertEqual(model.page, .pair)
      XCTAssertEqual(shown, 1)
      model.page = .home // Cancelling pairing must not immediately force it again.
      backend.receive(try message())
      XCTAssertEqual(model.page, .home)
      XCTAssertEqual(shown, 1)
    }
  }

  func testExistingPairingSurvivesRestart() throws {
    let model = PanelModel()
    let backend = DaemonBackend(model: model, executable: URL(fileURLWithPath: "/usr/bin/false"), dataDir: "/tmp/lucicontrol-unused-test", relay: nil)
    backend.receive(try message(paired: true))
    XCTAssertEqual(model.page, .home)
    XCTAssertEqual(model.update, .unchecked)
  }

  func testRunningAndWaitingSessionsDeferUpdateUntilExplicitIdleRetry() {
    for state in [SessionState.running, .waiting] {
      let model = PanelModel()
      let updater = UpdateController(model: model, start: false)
      model.sessions = [Session(id: "active", agent: .codex, directory: "/tmp", title: "Work", state: state, updatedAt: Date(), shared: false)]
      var installs = 0
      XCTAssertTrue(updater.postponeRestart(version: "0.1.2", installHandler: { installs += 1 }))
      XCTAssertEqual(model.update, .deferred(version: "0.1.2"))
      updater.installPendingUpdate()
      XCTAssertEqual(installs, 0)
      XCTAssertFalse(updater.isRestarting)
      model.sessions[0].state = .idle
      XCTAssertEqual(installs, 0)
      updater.installPendingUpdate()
      XCTAssertEqual(installs, 1)
      XCTAssertEqual(model.update, .installing)
      XCTAssertTrue(updater.isRestarting)
    }
  }

  func testStartupWaitsForDaemonBeforeUpdateRestart() {
    let model = PanelModel()
    let updater = UpdateController(model: model, start: false)
    model.sharing = .starting
    var installs = 0
    XCTAssertTrue(updater.postponeRestart(version: "0.1.2", installHandler: { installs += 1 }))
    updater.installPendingUpdate()
    XCTAssertEqual(installs, 0)
    model.sharing = .unpaired
    updater.installPendingUpdate()
    XCTAssertEqual(installs, 1)
  }

  func testIdleUpdateUsesNormalTerminationPath() {
    let model = PanelModel()
    let updater = UpdateController(model: model, start: false)
    XCTAssertFalse(updater.postponeRestart(version: "0.1.2", installHandler: { XCTFail("Sparkle retains this handler when not postponed") }))
    XCTAssertTrue(updater.isRestarting)
  }
}


@MainActor
final class RemovalTests: XCTestCase {
  func testDisconnectedRemovalPreservesRowsAndReportsFailure() async {
    let model = PanelModel()
    let dir = SharedDirectory(path: "/tmp/keep", agent: .codex, sharesNewSessions: false)
    let session = Session(id: "keep", agent: .codex, directory: dir.path, title: "Keep", state: .idle, updatedAt: Date(), shared: true)
    model.directories = [dir]
    model.sessions = [session]
    let backend = DaemonBackend(model: model, executable: URL(fileURLWithPath: "/usr/bin/false"), dataDir: "/tmp/lucicontrol-unused-test", relay: nil)
    _ = backend
    await model.removeSession(session)
    XCTAssertEqual(model.sessions.count, 1)
    XCTAssertNotNil(model.lastError)
    await model.removeDirectory(dir)
    XCTAssertEqual(model.directories.count, 1)
    XCTAssertNotNil(model.lastError)
    XCTAssertFalse(model.isRemoving)
  }

  func testActiveSessionsCannotBeHiddenByRemoval() async {
    for state in [SessionState.running, .waiting] {
      let model = PanelModel.demo()
      let dir = SharedDirectory(path: "/tmp/work", agent: .codex, sharesNewSessions: false)
      let session = Session(id: "active", agent: .codex, directory: dir.path, title: "Work", state: state, updatedAt: Date(), shared: false)
      model.directories = [dir]
      model.sessions = [session]
      XCTAssertFalse(model.canRemove(session))
      XCTAssertFalse(model.canRemove(dir))
      await model.removeSession(session)
      await model.removeDirectory(dir)
      XCTAssertEqual(model.sessions.count, 1)
      XCTAssertEqual(model.directories.count, 1)
      XCTAssertTrue(model.hasActiveSessions)
    }
  }

  func testOffKeepsSessionAndRemoveCleansUpDemoList() async {
    let model = PanelModel.demo()
    let dir = SharedDirectory(path: "/tmp/work", agent: .codex, sharesNewSessions: false)
    let session = Session(id: "idle", agent: .codex, directory: dir.path, title: "Done", state: .idle, updatedAt: Date(), shared: true)
    model.directories = [dir]
    model.sessions = [session]
    model.toggleSession(session.id)
    XCTAssertEqual(model.sessions.count, 1)
    XCTAssertFalse(model.sessions[0].shared)
    await model.removeSession(model.sessions[0])
    XCTAssertTrue(model.sessions.isEmpty)
    model.expanded.insert(dir.id)
    await model.removeDirectory(dir)
    XCTAssertTrue(model.directories.isEmpty)
    XCTAssertFalse(model.expanded.contains(dir.id))
  }
}
