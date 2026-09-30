import XCTest
@testable import LuciControlCore

final class MappingTests: XCTestCase {
  func testDaemonMessageDecodes() throws {
    let json = """
    {"op":"ready","machine":{"id":"m1","label":"fatMac","enabled":true,"shares":[{"path":"/a","addedAt":5,"existing":true,"new":false}]},
     "threads":[{"id":"t1","cwd":"/a/x","title":"Hi","updatedAt":1700000000000,"status":"idle","waiting":true,"running":false,"shared":true,"createdAt":1}],
     "devices":[{"id":"p1","user":"kai","owner":true,"online":true,"verified":true,"watching":2,"blocked":false}],
     "state":{"paired":true,"owner":"kai","daemon":{"version":"0.2.0","pid":1},"link":{"online":true},"agent":{"found":true,"running":true,"version":"codex 1","mode":"managed"},"tokenExpiresAt":1793145600}}
    """
    let m = try JSONDecoder().decode(DaemonMessage.self, from: Data(json.utf8))
    XCTAssertEqual(m.op, "ready")
    let dirs = m.machine!.shares.map(Mapping.directory)
    XCTAssertEqual(dirs.first?.sharesNewSessions, false)
    let s = Mapping.session(m.threads![0])
    XCTAssertEqual(s.state, .waiting)
    XCTAssertTrue(s.shared)
    XCTAssertEqual(s.directory, "/a/x")
    let d = Mapping.device(m.devices![0], removed: [])
    XCTAssertEqual(d.label, "kai 的手机")
    XCTAssertEqual(Mapping.sharing(state: m.state!, machine: m.machine), .sharing)
    let info = Mapping.machine(state: m.state!, machine: m.machine, appVersion: "0.1.0")
    XCTAssertEqual(info.owner, "kai")
    XCTAssertEqual(info.agentVersion, "codex 1")
    XCTAssertNotNil(info.tokenExpiresAt)
  }

  func testSharingStates() throws {
    var state = try JSONDecoder().decode(WireState.self, from: Data("""
    {"paired":false,"daemon":{"version":"0","pid":1},"link":{"online":false},"agent":{"found":true,"running":false}}
    """.utf8))
    XCTAssertEqual(Mapping.sharing(state: state, machine: nil), .unpaired)
    state.paired = true
    let paused = try JSONDecoder().decode(WireMachine.self, from: Data(#"{"id":"m","label":"x","enabled":false,"shares":[]}"#.utf8))
    XCTAssertEqual(Mapping.sharing(state: state, machine: paused), .paused)
    let on = try JSONDecoder().decode(WireMachine.self, from: Data(#"{"id":"m","label":"x","enabled":true,"shares":[]}"#.utf8))
    XCTAssertEqual(Mapping.sharing(state: state, machine: on), .connecting)
  }

  func testSharesKeepOptionsAndAddNew() {
    let existing = [WireShare(path: "/a", addedAt: 5, existing: true, new: true)]
    let dirs = [SharedDirectory(path: "/a", agent: .codex, sharesNewSessions: false), SharedDirectory(path: "/b", agent: .codex, sharesNewSessions: true)]
    let out = Mapping.shares(dirs, existing: existing)
    XCTAssertEqual(out.count, 2)
    XCTAssertEqual(out[0].addedAt, 5)
    XCTAssertEqual(out[0].new, false)
    XCTAssertNotNil(out[1].addedAt)
    XCTAssertEqual(out[1].existing, true)
  }

  func testPairingStates() {
    let p = WirePair(state: "claimed", code: "ABC", payload: nil, expiresAt: nil, user: "kai", error: nil)
    XCTAssertEqual(Mapping.pairing(p), .claimed(code: "ABC", user: "kai", deviceLabel: ""))
    XCTAssertEqual(Mapping.pairing(WirePair(state: "cancelled", code: nil, payload: nil, expiresAt: nil, user: nil, error: nil)), .idle)
  }
}
