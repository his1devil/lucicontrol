import Foundation

/// Sample data for `--demo`: the shapes of the design canvas with this project's own names,
/// so the panel can be drawn and compared with `design/reference/` before the daemon exists.
public enum DemoData {
  public static let home = "/Users/antai"

  public static func directories() -> [SharedDirectory] {
    [
      SharedDirectory(path: home + "/Development/personal/yptd-mobile-app", agent: .codex, sharesNewSessions: false),
      SharedDirectory(path: home + "/Development/personal/lucirund", agent: .codex, sharesNewSessions: true),
    ]
  }

  public static func sessions(now: Date = Date()) -> [Session] {
    let app = home + "/Development/personal/yptd-mobile-app"
    let daemon = home + "/Development/personal/lucirund"
    return [
      Session(id: "s1", agent: .codex, directory: app, title: "私聊昵称跟着改名同步", state: .waiting, activity: "xcodebuild test -scheme yptd", updatedAt: now.addingTimeInterval(-20), shared: true),
      Session(id: "s2", agent: .codex, directory: app, title: "TestFlight 0.1.0 (15) 发布", state: .running, activity: "正在编辑 docs/releases/15.md", updatedAt: now.addingTimeInterval(-120), shared: true),
      Session(id: "s3", agent: .codex, directory: app, title: "通讯录重读时机", state: .idle, activity: "已完成 · 改动 12 个文件", updatedAt: now.addingTimeInterval(-3600), shared: false),
      Session(id: "s4", agent: .codex, directory: daemon, title: "审查修复：按变更号补差", state: .running, activity: "运行 go test ./...", updatedAt: now.addingTimeInterval(-30), shared: true),
      Session(id: "s5", agent: .codex, directory: daemon, title: "配对：主机出码，手机认领", state: .idle, updatedAt: now.addingTimeInterval(-86400 - 3600), shared: true),
    ]
  }

  public static func devices() -> [Device] {
    [
      Device(id: "p-c0z87t", label: "iPhone 17 Pro Max", user: "xiaolu", isOwner: true, online: true, watching: 2),
      Device(id: "p-9k2mxa", label: "iPad mini", user: "xiaolu", isOwner: true, online: true, watching: 0),
      Device(id: "p-old13", label: "旧 iPhone 13", user: "xiaolu", isOwner: true, online: false, watching: 0, blocked: true),
    ]
  }

  public static func candidates(now: Date = Date()) -> [DirectoryCandidate] {
    [
      DirectoryCandidate(path: home + "/Development/personal/fastllm", agent: .codex, sessions: 4, updatedAt: now.addingTimeInterval(-1800)),
      DirectoryCandidate(path: home + "/Development/personal/yptd-serve", agent: .codex, sessions: 2, updatedAt: now.addingTimeInterval(-86400 * 2)),
      DirectoryCandidate(path: home + "/Development/personal/x-relay", agent: .codex, sessions: 0, updatedAt: now.addingTimeInterval(-86400 * 9)),
    ]
  }

  public static func machine() -> MachineInfo {
    MachineInfo(label: "fatMac", owner: "xiaolu", appVersion: "0.3.1", daemonVersion: "0.3.1", agentVersion: "codex 0.159.0",
                tokenExpiresAt: Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 28)), tokenRenews: true)
  }

  public static let updateNotes = ["自动识别 Claude Code 会话", "中继连接断线后更快恢复", "修复目录开关偶尔不同步"]
}
