import Foundation

/// Text rules shared by the panel and the tests.
public enum Format {
  /// "刚刚", "2 分钟前", "3 小时前", "昨天", "3 天前", or the date.
  public static func relative(_ date: Date, now: Date = Date()) -> String {
    let s = now.timeIntervalSince(date)
    if s < 60 { return "刚刚" }
    if s < 3600 { return "\(Int(s / 60)) 分钟前" }
    if s < 86400 { return "\(Int(s / 3600)) 小时前" }
    let days = Int(s / 86400)
    if days == 1 { return "昨天" }
    if days < 30 { return "\(days) 天前" }
    let f = DateFormatter()
    f.dateFormat = "M 月 d 日"
    return f.string(from: date)
  }

  /// Paths under the home directory read as `~/…`.
  public static func shortPath(_ path: String, home: String = NSHomeDirectory()) -> String {
    if path == home { return "~" }
    if path.hasPrefix(home + "/") { return "~" + path.dropFirst(home.count) }
    return path
  }

  /// The pairing code as the phone shows it: ABC-DEF.
  public static func pairCode(_ code: String) -> String {
    let n = code.uppercased()
    guard n.count > 3 else { return n }
    return String(n.prefix(3)) + "-" + String(n.dropFirst(3))
  }

  /// "4:52" for the seconds left on a pairing code.
  public static func countdown(until: Date, now: Date = Date()) -> String {
    let s = max(0, Int(until.timeIntervalSince(now).rounded(.down)))
    return String(format: "%d:%02d", s / 60, s % 60)
  }

  /// The row's subtitle: the state, then what the daemon knows about the activity.
  public static func sessionSubtitle(_ session: Session, now: Date = Date()) -> String {
    let state: String
    switch session.state {
    case .waiting: state = "等待审批"
    case .running: state = "运行中"
    case .idle: state = "空闲"
    }
    if !session.heldBy.isEmpty { return "\(session.heldBy)正在使用 · \(state)" }
    if !session.activity.isEmpty { return "\(state) · \(session.activity)" }
    if session.state == .idle { return "\(state) · \(relative(session.updatedAt, now: now))" }
    return state
  }
}

/// How sessions are grouped into sections and ordered inside them.
public enum Grouping {
  /// The sessions that belong to a shared directory: those whose cwd is the directory or
  /// lies inside it (case-insensitive, like the file system).
  public static func sessions(in directory: SharedDirectory, from all: [Session]) -> [Session] {
    let root = directory.path.lowercased()
    return all.filter { s in
      guard s.agent == directory.agent else { return false }
      let cwd = s.directory.lowercased()
      return cwd == root || cwd.hasPrefix(root + "/")
    }
  }

  /// Waiting first, then running, then the rest by recency.
  public static func ordered(_ sessions: [Session]) -> [Session] {
    sessions.sorted { a, b in
      if a.state != b.state { return rank(a.state) < rank(b.state) }
      return a.updatedAt > b.updatedAt
    }
  }

  private static func rank(_ s: SessionState) -> Int {
    switch s {
    case .waiting: 0
    case .running: 1
    case .idle: 2
    }
  }

  /// Every waiting or running session shows; idle ones beyond `visibleIdle` fold away.
  public static func split(_ ordered: [Session], visibleIdle: Int = 5) -> (shown: [Session], folded: [Session]) {
    var shown: [Session] = []
    var folded: [Session] = []
    var idle = 0
    for s in ordered {
      if s.state == .idle {
        idle += 1
        if idle > visibleIdle {
          folded.append(s)
          continue
        }
      }
      shown.append(s)
    }
    return (shown, folded)
  }
}
