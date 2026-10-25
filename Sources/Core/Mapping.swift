import Foundation

/// From the wire to what the panel shows.
public enum Mapping {
  public static func directory(_ s: WireShare) -> SharedDirectory {
    SharedDirectory(path: s.path, agent: .codex, sharesNewSessions: s.new ?? true)
  }

  public static func session(_ t: WireThread) -> Session {
    let state: SessionState
    if t.waiting {
      state = .waiting
    } else if t.running || t.status == "active" {
      state = .running
    } else {
      state = .idle
    }
    let claude = t.agent == "claude"
    var s = Session(id: t.id, agent: claude ? .claudeCode : .codex, directory: t.cwd, title: t.title.isEmpty ? "（没有标题）" : t.title, state: state,
                    updatedAt: Date(timeIntervalSince1970: Double(t.updatedAt) / 1000), shared: t.shared ?? false, heldBy: t.heldBy ?? "")
    if let locked = t.locked, !locked.isEmpty { s.activity = "电脑上的设置不允许手机操作" }
    if claude {
      if t.status == "notLoaded" {
        s.activity = "已结束"
      } else if let locked = t.locked, !locked.isEmpty {
        // Runs in a terminal but cannot be typed into from the phone (not joined, or no
        // terminal): watched only.
        s.activity = "手机只能看"
      } else if let mode = t.mode, !mode.isEmpty {
        s.activity = claudeModeWord(mode)
      }
    }
    return s
  }

  /// Claude Code's permission modes, as the row's subtitle names them.
  public static func claudeModeWord(_ mode: String) -> String {
    switch mode {
    case "default", "manual": "逐项询问"
    case "acceptEdits": "自动接受编辑"
    case "plan": "计划模式"
    case "auto": "自动判断"
    case "bypassPermissions": "跳过所有确认"
    case "dontAsk": "不询问"
    default: mode
    }
  }

  public static func device(_ d: WireDevice, removed: Set<String>) -> Device {
    Device(id: d.id, label: d.label?.isEmpty == false ? d.label! : (d.user.isEmpty ? d.id : d.user + " 的手机"), user: d.user,
           isOwner: d.owner, online: d.online, verified: d.verified, watching: d.watching, blocked: d.blocked, removed: removed.contains(d.id))
  }

  public static func candidate(_ c: WireCandidate) -> DirectoryCandidate {
    DirectoryCandidate(path: c.path, agent: .codex, sessions: c.threads, updatedAt: Date(timeIntervalSince1970: Double(c.updatedAt) / 1000))
  }

  public static func sharing(state: WireState, machine: WireMachine?) -> SharingState {
    guard state.paired else { return .unpaired }
    guard machine?.enabled ?? false else { return .paused }
    return state.link.online ? .sharing : .connecting
  }

  public static func machine(state: WireState, machine: WireMachine?, appVersion: String) -> MachineInfo {
    MachineInfo(label: machine?.label ?? "", owner: state.owner ?? "", appVersion: appVersion, daemonVersion: state.daemon.version,
                agentVersion: state.agent.version ?? machine?.agentVersion ?? "", tokenExpiresAt: state.tokenExpiresAt.map { Date(timeIntervalSince1970: Double($0)) },
                // The link's error is only news while the link is down.
                linkError: state.link.online ? "" : state.link.error ?? "", agentError: state.agent.error ?? "",
                tokenRenews: state.tokenRenews, tokenRenewError: state.tokenRenewError ?? "",
                claudeFound: state.claude?.found ?? false, claudeVersion: state.claude?.version ?? "", claudeForceAsk: state.claude?.forceAsk ?? false,
                claudeJoin: state.claude?.join?.enabled, claudeJoinProblem: joinProblem(state.claude?.join), claudeJoinHelpers: state.claude?.join?.helpers ?? 0)
  }

  /// Why joining every Claude session is on but not (fully) in place; empty when it is, or off.
  public static func joinProblem(_ j: WireState.Join?) -> String {
    guard let j, j.enabled else { return "" }
    if !j.status.helper { return "没找到会话助手 lucirund-claude，重装 LuciControl 试试" }
    if !j.status.sandbox { return "这台 Mac 没有 sandbox-exec，助手关不进沙盒，所以没装" }
    if !j.status.hooks || !j.status.mcp { return "Claude Code 的设置里少了 lucirund 的 hooks 或助手，一分钟内会自动补上" }
    return ""
  }

  public static func pairing(_ p: WirePair) -> PairingState {
    switch p.state {
    case "waiting":
      return .waiting(code: p.code ?? "", payload: p.payload ?? "", expiresAt: Date(timeIntervalSince1970: Double(p.expiresAt ?? 0) / 1000))
    case "claimed":
      return .claimed(code: p.code ?? "", user: p.user ?? "", deviceLabel: "")
    case "done":
      return .done(user: p.user ?? "", deviceLabel: "")
    case "expired":
      return .failed("连接码过期了，重新生成一个")
    case "cancelled":
      return .idle
    default:
      return .failed(p.error ?? p.state)
    }
  }

  /// The share list to send back after a change on the panel: each share as the daemon
  /// described it (date and options included), with the panel's switch.
  public static func shares(_ dirs: [SharedDirectory], existing: [WireShare], now: Date = Date()) -> [WireShare] {
    let stamp = Int64(now.timeIntervalSince1970 * 1000)
    return dirs.map { d in
      if var e = existing.first(where: { $0.path == d.path }) {
        // A share without a date (added from a phone, or taken over from the command line)
        // shares every thread, whatever its switch says. Switching it gives it a date: what
        // is there stays shared, sessions from now on follow the switch.
        if e.addedAt == nil, (e.new ?? true) != d.sharesNewSessions {
          e.addedAt = stamp
          e.existing = true
        }
        e.new = d.sharesNewSessions
        return e
      }
      return WireShare(path: d.path, addedAt: stamp, existing: true, new: d.sharesNewSessions)
    }
  }
}
