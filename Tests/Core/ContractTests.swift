import XCTest
@testable import LuciControlCore

/// What lucirund's control channel really sends, decoded the way the panel decodes it.
/// Fixtures/control.jsonl is written by lucirund's TestExportControlFixtures (see there): a
/// field renamed, a type or a unit changed on either side shows up here once it is rewritten.
final class ContractTests: XCTestCase {
  private func messages() throws -> [DaemonMessage] {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures/control.jsonl")
    return try Data(contentsOf: url).split(separator: 0x0a).map { try JSONDecoder().decode(DaemonMessage.self, from: Data($0)) }
  }

  func testEveryMessageDecodes() throws {
    XCTAssertEqual(try messages().map(\.op), ["ready", "reply", "threads", "reply", "devices", "reply", "status", "reply", "pair", "pair", "pair", "reply"])
  }

  func testReadyMapsWithTheRightUnits() throws {
    let ready = try XCTUnwrap(messages().first { $0.op == "ready" })
    let state = try XCTUnwrap(ready.state)
    let info = Mapping.machine(state: state, machine: ready.machine, appVersion: "0.3.0")
    XCTAssertEqual(info.tokenExpiresAt, Date(timeIntervalSince1970: 1_794_066_681), "seconds, as in the token")
    XCTAssertEqual(info.tokenRenews, true)
    XCTAssertEqual(info.tokenRenewError, "issuer unreachable")
    XCTAssertEqual(info.linkError, "dial tcp: connection refused")
    let session = Mapping.session(try XCTUnwrap(ready.threads?.first))
    XCTAssertEqual(session.title, "修复登录\u{85}页面", "U+0085 survives the pipe")
    XCTAssertEqual(session.updatedAt, Date(timeIntervalSince1970: 1_791_550_000), "milliseconds on the wire")
    XCTAssertEqual(session.state, .running)
    let device = Mapping.device(try XCTUnwrap(ready.devices?.first), removed: [])
    XCTAssertEqual(device.label, "iPhone 17 Pro Max")
    XCTAssertTrue(device.online)
    XCTAssertTrue(device.verified)
    XCTAssertEqual(device.watching, 1)
    // The share's options come along: the switch shows what is on file, and the list the
    // panel sends back keeps the date (a share without one shares every thread).
    let share = try XCTUnwrap(ready.machine?.shares.first)
    XCTAssertEqual(share.addedAt, 1_791_530_000_000)
    XCTAssertFalse(Mapping.directory(share).sharesNewSessions)
    let back = Mapping.shares([Mapping.directory(share)], existing: [share])
    XCTAssertEqual(back, [share])
  }

  func testRepliesAndPairing() throws {
    let all = try messages()
    let replies = all.filter { $0.op == "reply" }
    let catalog = try XCTUnwrap(replies.compactMap { try? $0.result?.decode(WireShareCatalog.self) }.first)
    XCTAssertEqual(catalog.shares.first?.new, false)
    XCTAssertEqual(catalog.candidates.first?.threads, 1)
    struct Doctor: Decodable { var checks: [WireDoctorCheck] }
    let doctor = try XCTUnwrap(replies.compactMap { try? $0.result?.decode(Doctor.self) }.first)
    XCTAssertEqual(doctor.checks.map(\.ok), [true, false])
    XCTAssertNotNil(replies.last?.error?.msg)
    let pairs = all.compactMap(\.pair).map(Mapping.pairing)
    XCTAssertEqual(pairs, [
      .waiting(code: "A7K3QD", payload: "lucirun://pair?code=A7K3QD", expiresAt: Date(timeIntervalSince1970: 1_791_550_300)),
      .claimed(code: "A7K3QD", user: "owner", deviceLabel: ""),
      .done(user: "owner", deviceLabel: ""),
    ])
  }
}
