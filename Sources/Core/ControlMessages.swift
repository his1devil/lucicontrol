import Foundation

// The control channel (lucirund docs/wire.md §7): one JSON object per line each way.
// These are the wire shapes; `Model.swift` has what the panel shows, and `Mapping.swift`
// turns one into the other.

/// A message from the daemon.
public struct DaemonMessage: Decodable, Sendable {
  public var op: String
  public var id: Int?
  public var result: JSONValue?
  public var error: RPCError?
  public var reason: String?
  public var code: String?
  public var msg: String?
  public var machine: WireMachine?
  public var threads: [WireThread]?
  public var devices: [WireDevice]?
  public var state: WireState?
  public var pair: WirePair?
}

public struct RPCError: Decodable, Sendable, Error, Equatable {
  public var code: String
  public var msg: String
  public init(code: String, msg: String) {
    self.code = code
    self.msg = msg
  }
}

public struct WireShare: Codable, Sendable, Equatable {
  public var path: String
  public var with: [String]?
  public var addedAt: Int64?
  public var existing: Bool?
  public var new: Bool?
  public init(path: String, with: [String]? = nil, addedAt: Int64? = nil, existing: Bool? = nil, new: Bool? = nil) {
    self.path = path
    self.with = with
    self.addedAt = addedAt
    self.existing = existing
    self.new = new
  }
}

public struct WireMachine: Decodable, Sendable {
  public var id: String
  public var label: String
  public var os: String?
  public var agent: String?
  public var agentVersion: String?
  public var version: String?
  public var enabled: Bool
  public var until: Int64?
  public var shares: [WireShare]
  public var viewers: Int?
  public var pending: Int?
}

public struct WireThread: Decodable, Sendable {
  public var id: String
  public var cwd: String
  public var title: String
  public var updatedAt: Int64
  public var status: String
  public var waiting: Bool
  public var running: Bool
  public var locked: String?
  public var createdAt: Int64?
  public var shared: Bool?
  public var heldBy: String?
}

public struct WireDevice: Decodable, Sendable {
  public var id: String
  public var user: String
  public var label: String?
  public var owner: Bool
  public var online: Bool
  public var verified: Bool
  public var watching: Int
  public var blocked: Bool
}

public struct WireState: Decodable, Sendable {
  public struct Daemon: Decodable, Sendable {
    public var version: String
    public var pid: Int
  }
  public struct Link: Decodable, Sendable {
    public var online: Bool
    public var error: String?
  }
  public struct Agent: Decodable, Sendable {
    public var found: Bool
    public var running: Bool
    public var version: String?
    public var mode: String?
    public var error: String?
    /// nil until the daemon asked Codex; false means nobody is signed in there.
    public var loggedIn: Bool?
    public var account: String?
  }
  public var paired: Bool
  public var owner: String?
  public var daemon: Daemon
  public var link: Link
  public var agent: Agent
  /// Unix seconds, as in the token (the other times on the wire are milliseconds).
  public var tokenExpiresAt: Int64?
  /// Whether the daemon renews the token itself (false: the retired development key's,
  /// which means pairing again before it expires), and why the last renewal failed.
  public var tokenRenews: Bool?
  public var tokenRenewError: String?
}

public struct WirePair: Decodable, Sendable {
  public var state: String
  public var code: String?
  public var payload: String?
  public var expiresAt: Int64?
  public var user: String?
  public var error: String?
  public init(state: String, code: String?, payload: String?, expiresAt: Int64?, user: String?, error: String?) {
    self.state = state
    self.code = code
    self.payload = payload
    self.expiresAt = expiresAt
    self.user = user
    self.error = error
  }
}

public struct WireCandidate: Decodable, Sendable {
  public var path: String
  public var threads: Int
  public var updatedAt: Int64
  public var shared: Bool
}

public struct WireShareCatalog: Decodable, Sendable {
  public var shares: [WireShare]
  public var candidates: [WireCandidate]
}

public struct WireDoctorCheck: Decodable, Sendable, Equatable {
  public var ok: Bool
  public var what: String
  public var detail: String?
}

/// Any JSON, kept for replies whose shape depends on the method.
public enum JSONValue: Codable, Sendable, Equatable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  public init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if c.decodeNil() { self = .null; return }
    if let b = try? c.decode(Bool.self) { self = .bool(b); return }
    if let n = try? c.decode(Double.self) { self = .number(n); return }
    if let s = try? c.decode(String.self) { self = .string(s); return }
    if let a = try? c.decode([JSONValue].self) { self = .array(a); return }
    self = .object(try c.decode([String: JSONValue].self))
  }

  public func encode(to encoder: Encoder) throws {
    var c = encoder.singleValueContainer()
    switch self {
    case .null: try c.encodeNil()
    case .bool(let b): try c.encode(b)
    case .number(let n): try c.encode(n)
    case .string(let s): try c.encode(s)
    case .array(let a): try c.encode(a)
    case .object(let o): try c.encode(o)
    }
  }

  /// Re-encodes this value so a typed struct can be decoded from it.
  public func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(self)
    return try JSONDecoder().decode(T.self, from: data)
  }
}

/// A request to the daemon. `params` is encoded as given.
public struct RPCRequest: Encodable, Sendable {
  public var op = "rpc"
  public var id: Int
  public var method: String
  public var params: [String: JSONValue]
  public init(id: Int, method: String, params: [String: JSONValue]) {
    self.id = id
    self.method = method
    self.params = params
  }
}

public extension JSONValue {
  init(_ b: Bool) { self = .bool(b) }
  init(_ s: String) { self = .string(s) }
  init(_ n: Int) { self = .number(Double(n)) }
  init(_ n: Int64) { self = .number(Double(n)) }
  init(_ shares: [WireShare]) {
    self = .array(shares.map { s in
      var o: [String: JSONValue] = ["path": .string(s.path)]
      if let w = s.with { o["with"] = .array(w.map { .string($0) }) }
      if let a = s.addedAt { o["addedAt"] = .number(Double(a)) }
      if let e = s.existing { o["existing"] = .bool(e) }
      if let n = s.new { o["new"] = .bool(n) }
      return .object(o)
    })
  }
}
