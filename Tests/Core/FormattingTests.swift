import XCTest
@testable import LuciControlCore

final class FormattingTests: XCTestCase {
  func testRelativeTimes() {
    let now = Date()
    XCTAssertEqual(Format.relative(now.addingTimeInterval(-5), now: now), "刚刚")
    XCTAssertEqual(Format.relative(now.addingTimeInterval(-120), now: now), "2 分钟前")
    XCTAssertEqual(Format.relative(now.addingTimeInterval(-3 * 3600), now: now), "3 小时前")
    XCTAssertEqual(Format.relative(now.addingTimeInterval(-86400 - 10), now: now), "昨天")
    XCTAssertEqual(Format.relative(now.addingTimeInterval(-4 * 86400), now: now), "4 天前")
  }

  func testShortPath() {
    XCTAssertEqual(Format.shortPath("/Users/kai/dev/app", home: "/Users/kai"), "~/dev/app")
    XCTAssertEqual(Format.shortPath("/Users/kai", home: "/Users/kai"), "~")
    XCTAssertEqual(Format.shortPath("/opt/x", home: "/Users/kai"), "/opt/x")
    XCTAssertEqual(Format.shortPath("/Users/kaiser/x", home: "/Users/kai"), "/Users/kaiser/x")
  }

  func testPairCodeAndCountdown() {
    XCTAssertEqual(Format.pairCode("abcdef"), "ABC-DEF")
    XCTAssertEqual(Format.pairCode("ab"), "AB")
    let now = Date()
    XCTAssertEqual(Format.countdown(until: now.addingTimeInterval(292), now: now), "4:52")
    XCTAssertEqual(Format.countdown(until: now.addingTimeInterval(-5), now: now), "0:00")
  }

  func testSubtitle() {
    let now = Date()
    var s = Session(id: "a", agent: .codex, directory: "/x", title: "t", state: .waiting, activity: "pnpm test", updatedAt: now, shared: true)
    XCTAssertEqual(Format.sessionSubtitle(s, now: now), "等待审批 · pnpm test")
    s.state = .idle
    s.activity = ""
    s.updatedAt = now.addingTimeInterval(-7200)
    XCTAssertEqual(Format.sessionSubtitle(s, now: now), "空闲 · 2 小时前")
    s.heldBy = "桌面版"
    XCTAssertEqual(Format.sessionSubtitle(s, now: now), "桌面版正在使用 · 空闲")
  }

  func testDeviceSubtitleFollowsTheMacsOwnLink() {
    var d = Device(id: "p1", label: "iPhone", user: "kai", isOwner: true, online: true, verified: true, watching: 2)
    XCTAssertEqual(Format.deviceSubtitle(d, macOnline: true), "在线 · 正在看 2 个会话")
    // Paused, connecting or restarting: the last roster says nothing about now.
    XCTAssertEqual(Format.deviceSubtitle(d, macOnline: false), "状态未知")
    d.verified = false
    XCTAssertEqual(Format.deviceSubtitle(d, macOnline: true), "在线 · 未连接这台 Mac")
    d.online = false
    XCTAssertEqual(Format.deviceSubtitle(d, macOnline: true), "离线")
    d = Device(id: "p2", label: "Pixel", user: "lin", isOwner: false, online: true, verified: false, watching: 1, blocked: true)
    XCTAssertEqual(Format.deviceSubtitle(d, macOnline: true), "在线 · 共享给 lin · 已禁用访问")
  }

  func testTokenLineSaysWhatHappensNext() {
    let now = Date(timeIntervalSince1970: 1_791_500_000)
    let soon = now.addingTimeInterval(10 * 86400)
    let later = now.addingTimeInterval(90 * 86400)
    XCTAssertFalse(Format.token(expires: later, renews: true, renewError: "", now: now).attention)
    XCTAssertTrue(Format.token(expires: later, renews: true, renewError: "", now: now).text.hasSuffix("到期，自动续期"))
    // A development token: nothing renews it; close to the date it asks for attention.
    XCTAssertFalse(Format.token(expires: later, renews: false, renewError: "", now: now).attention)
    XCTAssertTrue(Format.token(expires: soon, renews: false, renewError: "", now: now).attention)
    XCTAssertTrue(Format.token(expires: soon, renews: false, renewError: "", now: now).text.contains("不能自动续期"))
    let failed = Format.token(expires: later, renews: true, renewError: "issuer unreachable", now: now)
    XCTAssertTrue(failed.attention)
    XCTAssertTrue(failed.text.contains("续期失败：issuer unreachable"))
    XCTAssertTrue(Format.token(expires: now.addingTimeInterval(-60), renews: true, renewError: "", now: now).text.contains("过期"))
    XCTAssertFalse(Format.token(expires: later, renews: nil, renewError: "", now: now).text.contains("续期"))
  }

  func testPairedDevice() {
    XCTAssertEqual(Format.pairedDevice(user: "xiaolu", label: ""), "xiaolu 的手机")
    XCTAssertEqual(Format.pairedDevice(user: "xiaolu", label: "iPhone 17 Pro Max"), "xiaolu 的 iPhone 17 Pro Max")
  }

  /// A folder shared inside another lists its own sessions; each session shows once, under
  /// the innermost folder, whose options the daemon applies.
  func testNestedDirectoriesListEachSessionOnce() {
    let outer = SharedDirectory(path: "/w", agent: .codex, sharesNewSessions: true)
    let inner = SharedDirectory(path: "/w/app", agent: .codex, sharesNewSessions: false)
    let now = Date()
    let all = [
      Session(id: "a", agent: .codex, directory: "/w/app/src", title: "", state: .idle, updatedAt: now, shared: false),
      Session(id: "b", agent: .codex, directory: "/w/docs", title: "", state: .running, updatedAt: now, shared: true),
    ]
    for dirs in [[outer, inner], [inner, outer]] {
      XCTAssertEqual(Grouping.sessions(ownedBy: outer, among: dirs, from: all).map(\.id), ["b"])
      XCTAssertEqual(Grouping.sessions(ownedBy: inner, among: dirs, from: all).map(\.id), ["a"])
    }
    // Everything under the outer folder, for the "anything still running?" check.
    XCTAssertEqual(Grouping.sessions(in: outer, from: all).map(\.id), ["a", "b"])
  }

  func testGrouping() {
    let dir = SharedDirectory(path: "/Users/k/App", agent: .codex, sharesNewSessions: true)
    let now = Date()
    let all = [
      Session(id: "1", agent: .codex, directory: "/Users/k/App/sub", title: "in", state: .idle, updatedAt: now, shared: true),
      Session(id: "2", agent: .codex, directory: "/Users/k/Apple", title: "out", state: .idle, updatedAt: now, shared: true),
      Session(id: "3", agent: .codex, directory: "/users/k/app", title: "case", state: .running, updatedAt: now.addingTimeInterval(-10), shared: true),
      Session(id: "4", agent: .claudeCode, directory: "/Users/k/App", title: "other agent", state: .waiting, updatedAt: now, shared: true),
    ]
    let mine = Grouping.sessions(in: dir, from: all)
    XCTAssertEqual(mine.map(\.id), ["1", "3"])
    XCTAssertEqual(Grouping.ordered(mine).map(\.id), ["3", "1"])
    let many = (0..<8).map { i in Session(id: "i\(i)", agent: .codex, directory: "/x", title: "", state: .idle, updatedAt: now.addingTimeInterval(Double(-i)), shared: true) }
    let (shown, folded) = Grouping.split(Grouping.ordered(many), visibleIdle: 5)
    XCTAssertEqual(shown.count, 5)
    XCTAssertEqual(folded.count, 3)
  }
}
