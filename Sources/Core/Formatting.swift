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

  /// The settings page's token line, and whether it needs the person's attention.
  public static func token(expires: Date, renews: Bool?, renewError: String, now: Date = Date()) -> (text: String, attention: Bool) {
    let day = DateFormatter()
    day.dateFormat = "yyyy-MM-dd"
    let date = day.string(from: expires)
    if expires <= now { return ("已于 \(date) 过期，需要重新配对", true) }
    if !renewError.isEmpty { return ("\(date) 到期 · 续期失败：\(renewError)", true) }
    switch renews {
    case false?:
      // A development token: nothing renews it, the machine pairs again before the date.
      return ("\(date) 到期 · 不能自动续期，到期前要重新配对", expires.timeIntervalSince(now) < 30 * 86400)
    case true?:
      return ("\(date) 到期，自动续期", false)
    case nil:
      return ("\(date) 到期", false)
    }
  }

  /// The phone a pairing connected: "xiaolu 的 iPhone 17 Pro Max", or "xiaolu 的手机" when
  /// the relay did not say which phone it was (it does not today).
  public static func pairedDevice(user: String, label: String) -> String {
    label.isEmpty ? "\(user) 的手机" : "\(user) 的 \(label)"
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

  /// A device row's subtitle: where the phone stands, whose it is, what it is doing.
  /// `macOnline` is this Mac's own relay link; without it the roster is old news.
  public static func deviceSubtitle(_ device: Device, macOnline: Bool) -> String {
    let presence = DevicePresence(device, macOnline: macOnline)
    var parts: [String] = []
    switch presence {
    case .unknown: parts.append("状态未知")
    case .offline: parts.append("离线")
    // A blocked phone is never let in, so "not connected here" says nothing new.
    case .onlineElsewhere: parts.append(device.blocked ? "在线" : "在线 · 未连接这台 Mac")
    case .connected: parts.append("在线")
    }
    if !device.isOwner { parts.append("共享给 \(device.user)") }
    if device.blocked {
      parts.append("已禁用访问")
    } else if presence == .connected, device.watching > 0 {
      parts.append("正在看 \(device.watching) 个会话")
    }
    return parts.joined(separator: " · ")
  }
}

/// How sessions are grouped into sections and ordered inside them.
public enum Grouping {
  /// Every session under a shared directory: those whose cwd is the directory or lies inside
  /// it (case-insensitive, like the file system), nested shared directories included.
  public static func sessions(in directory: SharedDirectory, from all: [Session]) -> [Session] {
    all.filter { holds(directory, $0) }
  }

  /// The sessions a directory's section lists: those whose innermost shared directory it
  /// is, the one whose options the daemon applies. A folder shared inside another lists
  /// its own sessions; each session shows once.
  public static func sessions(ownedBy directory: SharedDirectory, among dirs: [SharedDirectory], from all: [Session]) -> [Session] {
    // Of two shared directories that both hold a session, the longer path is the inner one.
    let deeper = dirs.filter { $0.id != directory.id && $0.agent == directory.agent && $0.path.count > directory.path.count }
    return all.filter { s in holds(directory, s) && !deeper.contains { holds($0, s) } }
  }

  private static func holds(_ directory: SharedDirectory, _ session: Session) -> Bool {
    guard session.agent == directory.agent else { return false }
    let root = directory.path.lowercased()
    let cwd = session.directory.lowercased()
    return cwd == root || cwd.hasPrefix(root + "/")
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
