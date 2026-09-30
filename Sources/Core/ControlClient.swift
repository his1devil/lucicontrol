import Foundation

/// The panel's end of the control channel: requests with replies, and a stream of pushes.
/// It reads lines from one FileHandle and writes to another; `DaemonProcess` supplies them.
public actor ControlClient {
  public typealias Handler = @Sendable (DaemonMessage) -> Void

  private let input: FileHandle
  private let output: FileHandle
  private var nextID = 1
  private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
  private let onPush: Handler
  private var reader: Task<Void, Never>?
  private var closed = false

  public init(reading input: FileHandle, writing output: FileHandle, onPush: @escaping Handler) {
    self.input = input
    self.output = output
    self.onPush = onPush
  }

  /// Starts reading; the daemon's first message (after hello) is `ready`.
  public func start(app: String) async throws {
    reader = Task { [weak self] in
      guard let self else { return }
      do {
        for try await line in self.input.bytes.lines {
          guard let data = line.data(using: .utf8), !line.isEmpty else { continue }
          do {
            let msg = try JSONDecoder().decode(DaemonMessage.self, from: data)
            await self.dispatch(msg)
          } catch {
            // A line we do not understand is not fatal; the daemon may be newer than us.
            continue
          }
        }
      } catch {}
      await self.closeAll(with: ControlError.closed)
    }
    try write(["op": "hello", "app": app, "wire": 1])
  }

  public func stop() {
    reader?.cancel()
    closed = true
  }

  /// One request; the reply's `result`, or the daemon's error.
  public func call(_ method: String, _ params: [String: JSONValue] = [:]) async throws -> JSONValue {
    if closed { throw ControlError.closed }
    let id = nextID
    nextID += 1
    let data = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))
    return try await withCheckedThrowingContinuation { c in
      pending[id] = c
      do {
        try output.write(contentsOf: data + Data([0x0a]))
      } catch {
        pending[id] = nil
        c.resume(throwing: error)
      }
    }
  }

  private func dispatch(_ msg: DaemonMessage) {
    if msg.op == "reply", let id = msg.id, let c = pending.removeValue(forKey: id) {
      if let e = msg.error {
        c.resume(throwing: e)
      } else {
        c.resume(returning: msg.result ?? .null)
      }
      return
    }
    onPush(msg)
  }

  private func closeAll(with error: ControlError) {
    closed = true
    for (_, c) in pending { c.resume(throwing: error) }
    pending = [:]
    onPush(DaemonMessage(op: "closed"))
  }

  private func write(_ obj: [String: any Sendable]) throws {
    let data = try JSONSerialization.data(withJSONObject: obj)
    try output.write(contentsOf: data + Data([0x0a]))
  }
}

public enum ControlError: Error, Equatable {
  case closed
}

extension DaemonMessage {
  init(op: String) {
    self.op = op
  }
}
