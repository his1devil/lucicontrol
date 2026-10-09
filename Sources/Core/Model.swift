import Foundation

/// A coding agent the panel can show. lucirund knows Codex today; Claude Code is a tab
/// whose sessions arrive once the daemon learns to drive it (PLAN.md §7, stage 7).
public enum AgentKind: String, Codable, CaseIterable, Sendable, Identifiable {
  case codex
  case claudeCode

  public var id: String { rawValue }

  /// The name on the tab and the chip.
  public var title: String {
    switch self {
    case .codex: "Codex"
    case .claudeCode: "Claude Code"
    }
  }

  /// The short name the tab bar uses when space is tight (the design's "Claude").
  public var shortTitle: String {
    switch self {
    case .codex: "Codex"
    case .claudeCode: "Claude"
    }
  }
}

/// What a session is doing right now, as the row's colour bar and subtitle tell it.
public enum SessionState: String, Codable, Sendable {
  /// Blocked on an approval or a question.
  case waiting
  /// A turn is running.
  case running
  case idle
}

/// One agent session (a Codex thread) in a shared directory.
public struct Session: Identifiable, Hashable, Codable, Sendable {
  public var id: String
  public var agent: AgentKind
  /// The directory the session runs in (its cwd), which decides the section it lands in.
  public var directory: String
  public var title: String
  public var state: SessionState
  /// What the agent is doing or did last: the command it waits on, the file it edits, a
  /// summary of the finished work. Empty when the daemon knows nothing beyond the state.
  public var activity: String
  public var updatedAt: Date
  /// Whether phones can see this session (the pill on the right).
  public var shared: Bool
  /// Who holds the session open in another process ("桌面版"), empty when nobody does.
  public var heldBy: String

  public init(id: String, agent: AgentKind, directory: String, title: String, state: SessionState, activity: String = "", updatedAt: Date, shared: Bool, heldBy: String = "") {
    self.id = id
    self.agent = agent
    self.directory = directory
    self.title = title
    self.state = state
    self.activity = activity
    self.updatedAt = updatedAt
    self.shared = shared
    self.heldBy = heldBy
  }
}

/// A directory shared with the phone. Sessions whose cwd is inside it belong to it.
public struct SharedDirectory: Identifiable, Hashable, Codable, Sendable {
  public var path: String
  public var agent: AgentKind
  /// Whether sessions started after the directory was added are shared by default.
  public var sharesNewSessions: Bool

  public var id: String { path }

  /// The last path component, which is what the section header shows.
  public var name: String { (path as NSString).lastPathComponent }

  public init(path: String, agent: AgentKind, sharesNewSessions: Bool) {
    self.path = path
    self.agent = agent
    self.sharesNewSessions = sharesNewSessions
  }
}

/// A phone on the machine's roster.
public struct Device: Identifiable, Hashable, Codable, Sendable {
  public var id: String
  public var label: String
  /// The yptd user the phone belongs to.
  public var user: String
  public var isOwner: Bool
  /// Connected to the relay, as of the last roster this Mac heard.
  public var online: Bool
  /// Said hello to this Mac with a valid token: it has a session here, not only the relay.
  public var verified: Bool
  /// Sessions the phone currently has open.
  public var watching: Int
  /// Blocked on this machine (the device page's switch off).
  public var blocked: Bool
  /// Removed from the list on this machine; still blocked, can be restored.
  public var removed: Bool

  public init(id: String, label: String, user: String, isOwner: Bool, online: Bool, verified: Bool = true, watching: Int = 0, blocked: Bool = false, removed: Bool = false) {
    self.id = id
    self.label = label
    self.user = user
    self.isOwner = isOwner
    self.online = online
    self.verified = verified
    self.watching = watching
    self.blocked = blocked
    self.removed = removed
  }
}

/// Where a phone stands, as the device page says it. The roster is only as good as this
/// Mac's own link: without it the last one heard says nothing about now.
public enum DevicePresence: Equatable, Sendable {
  /// This Mac is not connected (paused, connecting, restarting): nobody can tell.
  case unknown
  case offline
  /// On the relay, without a session with this Mac yet (just resumed, app in another view).
  case onlineElsewhere
  /// On the relay and connected to this Mac.
  case connected

  public init(_ device: Device, macOnline: Bool) {
    if !macOnline {
      self = .unknown
    } else if !device.online {
      self = .offline
    } else {
      self = device.verified ? .connected : .onlineElsewhere
    }
  }
}

/// The machine's sharing state as the footer and the menu bar icon show it.
public enum SharingState: Equatable, Sendable {
  /// Paired, enabled, relay link up.
  case sharing
  /// Enabled but the relay link is down or still being established.
  case connecting
  /// Switched off on purpose.
  case paused
  case unpaired
  /// The daemon is not up yet (starting, or restarting after a crash).
  case starting
  case error(String)

  public var label: String {
    switch self {
    case .sharing: "共享中"
    case .connecting: "连接中…"
    case .paused: "共享已暂停"
    case .unpaired: "还没连接手机"
    case .starting: "正在启动…"
    case .error(let msg): msg
    }
  }
}

/// A candidate folder for the add page: Codex has sessions there.
public struct DirectoryCandidate: Identifiable, Hashable, Codable, Sendable {
  public var path: String
  public var agent: AgentKind
  public var sessions: Int
  public var updatedAt: Date

  public var id: String { path }

  public init(path: String, agent: AgentKind, sessions: Int, updatedAt: Date) {
    self.path = path
    self.agent = agent
    self.sessions = sessions
    self.updatedAt = updatedAt
  }
}

/// Where the app's own update stands, driven by Sparkle callbacks.
public enum UpdateState: Equatable, Sendable {
  case unchecked
  case failed(message: String)
  case deferred(version: String)
  case latest(checkedAt: Date)
  case checking
  case available(version: String, notes: [String])
  case downloading(version: String, progress: Double?)
  case ready(version: String, notes: [String])
  case installing

  /// The version an update would bring, if one is known.
  public var pendingVersion: String? {
    switch self {
    case .available(let v, _), .downloading(let v, _), .ready(let v, _), .deferred(let v): v
    default: nil
    }
  }
}

/// Facts about this Mac's enrolment, for the settings page.
public struct MachineInfo: Hashable, Codable, Sendable {
  public var label: String
  public var owner: String
  public var appVersion: String
  public var daemonVersion: String
  public var agentVersion: String
  public var tokenExpiresAt: Date?
  /// Why the relay link is down, while it is; empty when it is up or nothing went wrong.
  public var linkError: String
  /// Why the daemon cannot reach Codex, while it cannot.
  public var agentError: String
  /// Whether the token renews itself; nil from a daemon that does not say.
  public var tokenRenews: Bool?
  /// Why the last renewal failed; empty once one succeeds.
  public var tokenRenewError: String

  public init(label: String, owner: String, appVersion: String, daemonVersion: String, agentVersion: String, tokenExpiresAt: Date?,
              linkError: String = "", agentError: String = "", tokenRenews: Bool? = nil, tokenRenewError: String = "") {
    self.label = label
    self.owner = owner
    self.appVersion = appVersion
    self.daemonVersion = daemonVersion
    self.agentVersion = agentVersion
    self.tokenExpiresAt = tokenExpiresAt
    self.linkError = linkError
    self.agentError = agentError
    self.tokenRenews = tokenRenews
    self.tokenRenewError = tokenRenewError
  }
}

/// Why the daemon cannot use Codex on this Mac.
public enum CodexProblem: Equatable, Sendable {
  case missing
  case notLoggedIn
}

/// The pairing flow's states, in order.
public enum PairingState: Equatable, Sendable {
  case idle
  /// A code is out; the phone has not claimed it yet.
  case waiting(code: String, payload: String, expiresAt: Date)
  /// A phone claimed the code; the person at the Mac confirms it was them.
  case claimed(code: String, user: String, deviceLabel: String)
  case done(user: String, deviceLabel: String)
  case failed(String)
}
