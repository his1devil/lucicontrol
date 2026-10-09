import XCTest
@testable import LuciControlCore

final class ControlClientTests: XCTestCase, @unchecked Sendable {
  func testShutdownDeadlineReturnsWhenDaemonNeverReplies() async {
    let channel = ControlTestChannel()
    defer { channel.close() }
    let finished = expectation(description: "shutdown deadline returned")
    let request = Task {
      do {
        _ = try await withTimeout(seconds: 0.05) { try await channel.client.call("shutdown") }
        XCTFail("An unanswered shutdown must time out")
      } catch {
        XCTAssertEqual(error as? ControlError, .closed)
      }
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 1)
    request.cancel()
    await channel.client.stop()
  }

  func testCancellingPendingRequestKeepsChannelUsable() async throws {
    let written = expectation(description: "request written")
    let channel = ControlTestChannel { id in
      if id == 1 { written.fulfill() }
    }
    defer { channel.close() }
    try await channel.client.start(app: "test")
    let cancelled = expectation(description: "request cancelled")
    let request = Task {
      do {
        _ = try await channel.client.call("status")
        XCTFail("The cancelled request must throw")
      } catch {
        XCTAssertTrue(error is CancellationError)
      }
      cancelled.fulfill()
    }
    await fulfillment(of: [written], timeout: 1)
    request.cancel()
    await fulfillment(of: [cancelled], timeout: 1)

    // A reply racing with cancellation must not resume the continuation twice.
    try channel.reply(id: 1)
    let replied = expectation(description: "next request succeeded")
    channel.onRequest { id in
      if id == 2 { try? channel.reply(id: id) }
    }
    let next = Task {
      do {
        let value = try await withTimeout(seconds: 5) { try await channel.client.call("status") }
        XCTAssertEqual(value, .bool(true))
      } catch {
        XCTFail("The channel must remain usable: \(error)")
      }
      replied.fulfill()
    }
    // Also verifies a successful reply cancels the long deadline promptly.
    await fulfillment(of: [replied], timeout: 1)
    next.cancel()
    await channel.client.stop()
  }

  func testStopFinishesAllPendingRequestsAndRejectsNewOnes() async {
    let written = expectation(description: "both requests written")
    written.expectedFulfillmentCount = 2
    let channel = ControlTestChannel { _ in written.fulfill() }
    defer { channel.close() }
    let finished = expectation(description: "both requests closed")
    finished.expectedFulfillmentCount = 2
    let requests = (0..<2).map { _ in
      Task {
        do {
          _ = try await channel.client.call("status")
          XCTFail("Stopping the channel must close pending requests")
        } catch {
          XCTAssertEqual(error as? ControlError, .closed)
        }
        finished.fulfill()
      }
    }
    await fulfillment(of: [written], timeout: 1)
    await channel.client.stop()
    await channel.client.stop() // Closing twice must not resume requests twice.
    await fulfillment(of: [finished], timeout: 1)
    requests.forEach { $0.cancel() }
    do {
      _ = try await channel.client.call("status")
      XCTFail("A closed client must reject new requests")
    } catch {
      XCTAssertEqual(error as? ControlError, .closed)
    }
  }

  func testRawNELInAStringDoesNotSplitTheMessage() async throws {
    let channel = ControlTestChannel()
    defer { channel.close() }
    try await channel.client.start(app: "test")
    // Bytes as Go's encoding/json writes them: U+0085 stays raw inside the string.
    channel.onRequest { id in
      var line = Data(#"{"op":"reply","id":\#(id),"result":"a"#.utf8)
      line += Data([0xc2, 0x85])
      line += Data(#"b"}"#.utf8) + Data([0x0a])
      try? channel.send(line)
    }
    let value = try await channel.client.call("status", timeout: 2)
    XCTAssertEqual(value, .string("a\u{85}b"))
    await channel.client.stop()
  }

  func testMessageSplitAcrossWritesIsReassembled() async throws {
    let channel = ControlTestChannel()
    defer { channel.close() }
    try await channel.client.start(app: "test")
    channel.onRequest { id in
      let line = Data(#"{"op":"reply","id":\#(id),"result":true}"#.utf8) + Data([0x0a])
      try? channel.send(line.prefix(9))
      Thread.sleep(forTimeInterval: 0.05)
      try? channel.send(line.dropFirst(9))
    }
    let value = try await channel.client.call("status", timeout: 2)
    XCTAssertEqual(value, .bool(true))
    await channel.client.stop()
  }

  func testUnansweredCallTimesOutAndTheChannelStaysUsable() async throws {
    let channel = ControlTestChannel()
    defer { channel.close() }
    try await channel.client.start(app: "test")
    do {
      _ = try await channel.client.call("status", timeout: 0.05)
      XCTFail("An unanswered call must time out")
    } catch {
      XCTAssertEqual(error as? ControlError, .timeout)
    }
    channel.onRequest { id in try? channel.reply(id: id) }
    let value = try await channel.client.call("status", timeout: 2)
    XCTAssertEqual(value, .bool(true))
    await channel.client.stop()
  }

  func testAlreadyCancelledRequestIsNotWritten() async {
    let written = expectation(description: "no request should be written")
    written.isInverted = true
    let channel = ControlTestChannel { _ in written.fulfill() }
    defer { channel.close() }
    let finished = expectation(description: "pre-cancelled request returned")
    let request = Task {
      withUnsafeCurrentTask { $0?.cancel() }
      do {
        _ = try await channel.client.call("shutdown")
        XCTFail("An already cancelled request must throw")
      } catch {
        XCTAssertTrue(error is CancellationError)
      }
      finished.fulfill()
    }
    await fulfillment(of: [finished], timeout: 1)
    await fulfillment(of: [written], timeout: 0.1)
    request.cancel()
    await channel.client.stop()
  }
}

/// A local pipe peer; no real daemon, relay, or user configuration is involved.
private final class ControlTestChannel: @unchecked Sendable {
  let incoming = Pipe()
  let outgoing = Pipe()
  let client: ControlClient

  init(onRequest: @escaping @Sendable (Int) -> Void = { _ in }) {
    client = ControlClient(reading: incoming.fileHandleForReading,
                           writing: outgoing.fileHandleForWriting, onPush: { _ in })
    self.onRequest(onRequest)
  }

  func onRequest(_ handler: @escaping @Sendable (Int) -> Void) {
    outgoing.fileHandleForReading.readabilityHandler = { handle in
      for line in handle.availableData.split(separator: 0x0a) {
        guard let message = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
              message["op"] as? String == "rpc", let id = message["id"] as? Int else { continue }
        handler(id)
      }
    }
  }

  func reply(id: Int) throws {
    try send(Data("{\"op\":\"reply\",\"id\":\(id),\"result\":true}\n".utf8))
  }

  /// Raw bytes from the daemon's side, as they would come down its stdout.
  func send(_ bytes: some DataProtocol) throws {
    try incoming.fileHandleForWriting.write(contentsOf: bytes)
  }

  func close() {
    outgoing.fileHandleForReading.readabilityHandler = nil
    try? incoming.fileHandleForWriting.close()
    try? outgoing.fileHandleForWriting.close()
  }
}
