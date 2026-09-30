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
    var s = Session(id: t.id, agent: .codex, directory: t.cwd, title: t.title.isEmpty ? "（没有标题）" : t.title, state: state,
                    updatedAt: Date(timeIntervalSince1970: Double(t.updatedAt) / 1000), shared: t.shared ?? false, heldBy: t.heldBy ?? "")
    if let locked = t.locked, !locked.isEmpty { s.activity = "电脑上的设置不允许手机操作" }
    return s
  }

  public static func device(_ d: WireDevice, removed: Set<String>) -> Device {
    Device(id: d.id, label: d.label?.isEmpty == false ? d.label! : (d.user.isEmpty ? d.id : d.user + " 的手机"), user: d.user,
           isOwner: d.owner, online: d.online, watching: d.watching, blocked: d.blocked, removed: removed.contains(d.id))
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
                agentVersion: state.agent.version ?? machine?.agentVersion ?? "", tokenExpiresAt: state.tokenExpiresAt.map { Date(timeIntervalSince1970: Double($0)) })
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

  /// The share list to send back after a change on the panel.
  public static func shares(_ dirs: [SharedDirectory], existing: [WireShare]) -> [WireShare] {
    dirs.map { d in
      if var e = existing.first(where: { $0.path == d.path }) {
        e.new = d.sharesNewSessions
        return e
      }
      return WireShare(path: d.path, addedAt: Int64(Date().timeIntervalSince1970 * 1000), existing: true, new: d.sharesNewSessions)
    }
  }
}
