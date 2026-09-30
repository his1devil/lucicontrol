import XCTest

final class SmokeTests: XCTestCase {
  func testBundleLoads() {
    XCTAssertNotNil(Bundle(identifier: "com.his1devil.lucicontrol"))
  }
}
