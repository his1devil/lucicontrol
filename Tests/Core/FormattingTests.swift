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
