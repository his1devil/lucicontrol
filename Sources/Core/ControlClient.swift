import Foundation

/// The panel's end of the control channel: requests with replies, and a stream of pushes.
/// It reads lines from one FileHandle and writes to another; `DaemonProcess` supplies them.
public actor ControlClient {
  public typealias Handler = @Sendable (DaemonMessage) -> Void

  /// A line longer than this is dropped whole rather than held in memory.
  static let maxLine = 32 << 20

  private let input: FileHandle
  private let output: FileHandle
  private var nextID = 1
  private var pending: [Int: CheckedContinuation<JSONValue, any Error>] = [:]
  private let onPush: Handler
  private var reader: Task<Void, Never>?
  private var closed = false
  private let decoder = JSONDecoder()

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
        // One message per line, split on the newline byte only. `bytes.lines` also ends a
        // line at U+0085 and U+2028/2029, which may sit raw inside a JSON string: the
        // message came apart and both halves were dropped.
        var line: [UInt8] = []
        var overflow = false
        for try await byte in self.input.bytes {
          guard byte == 0x0a else {
            if line.count < Self.maxLine { line.append(byte) } else { overflow = true }
            continue
          }
          if !line.isEmpty, !overflow { await self.receive(Data(line)) }
          line.removeAll(keepingCapacity: true)
          overflow = false
        }
      } catch {}
      await self.closeAll(with: ControlError.closed)
    }
    try write(["op": "hello", "app": app, "wire": 1])
  }

  public func stop() {
    reader?.cancel()
    reader = nil
    closeAll(with: ControlError.closed)
  }

  /// One request; the reply's `result`, or the daemon's error. A reply that never comes (a
  /// daemon that hung, a line that got lost) ends in `ControlError.timeout` rather than a
  /// caller waiting forever.
  public func call(_ method: String, _ params: [String: JSONValue] = [:], timeout: Double = 15) async throws -> JSONValue {
    try await withTimeout(seconds: timeout, throwing: ControlError.timeout) {
      try await self.request(method, params)
    }
  }

  private func request(_ method: String, _ params: [String: JSONValue]) async throws -> JSONValue {
    if closed { throw ControlError.closed }
    let id = nextID
    nextID += 1
    let data = try JSONEncoder().encode(RPCRequest(id: id, method: method, params: params))
    return try await withTaskCancellationHandler {
      // Check inside the operation too: cancellation may precede registration.
      try Task.checkCancellation()
      return try await withCheckedThrowingContinuation { c in
        pending[id] = c
        do {
          try output.write(contentsOf: data + Data([0x0a]))
        } catch {
          pending[id] = nil
          c.resume(throwing: error)
        }
      }
    } onCancel: {
      // Actor isolation serializes cancellation with registration and replies.
      Task { await self.cancelRequest(id) }
    }
  }

  private func cancelRequest(_ id: Int) {
    pending.removeValue(forKey: id)?.resume(throwing: CancellationError())
  }

  private func receive(_ line: Data) {
    // A line we do not understand is not fatal; the daemon may be newer than us.
    guard let msg = try? decoder.decode(DaemonMessage.self, from: line) else { return }
    dispatch(msg)
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
    guard !closed else { return }
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
  /// No reply within the request's deadline.
  case timeout
}

extension DaemonMessage {
  init(op: String) {
    self.op = op
  }
}
