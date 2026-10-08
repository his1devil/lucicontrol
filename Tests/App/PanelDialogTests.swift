import AppKit
import XCTest
@testable import LuciControl

@MainActor
final class PanelDialogTests: XCTestCase {
  func testRealModalAlertStaysAbovePanelAndRestoresItsLevel() {
    for response in [NSApplication.ModalResponse.alertFirstButtonReturn, .alertSecondButtonReturn] {
      let model = PanelModel()
      let parent = PanelWindow(contentRect: NSRect(x: 100, y: 100, width: 412, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
      parent.isReleasedWhenClosed = false
      parent.level = .popUpMenu
      model.dialogParentWindow = parent
      parent.makeKeyAndOrderFront(nil)
      defer { parent.orderOut(nil) }
      let alert = NSAlert()
      alert.messageText = "Dialog stacking regression test"
      alert.addButton(withTitle: "Confirm")
      alert.addButton(withTitle: "Cancel")
      var observed = false
      // Run inside the real AppKit modal loop, after NSAlert has applied its own level.
      let timer = Timer(timeInterval: 0.15, repeats: false) { _ in
        MainActor.assumeIsolated {
          observed = true
          XCTAssertTrue(model.modalActive)
          XCTAssertTrue(alert.window.isVisible)
          XCTAssertTrue(alert.window.parent === parent)
          XCTAssertTrue(parent.isVisible)
          XCTAssertGreaterThan(alert.window.level.rawValue, parent.level.rawValue)
          // NSApp.orderedWindows excludes non-main NSPanel windows; compare the actual
          // WindowServer order, which includes both the menu panel and the alert.
          let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
          let ordered = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
          if let dialogIndex = ordered.firstIndex(of: alert.window.windowNumber), let parentIndex = ordered.firstIndex(of: parent.windowNumber) {
            XCTAssertLessThan(dialogIndex, parentIndex)
          } else { XCTFail("Both the alert and its parent must remain on screen") }
          NSApp.stopModal(withCode: response)
        }
      }
      RunLoop.main.add(timer, forMode: .modalPanel)
      XCTAssertEqual(model.runModalAlert(alert), response)
      XCTAssertTrue(observed)
      XCTAssertEqual(parent.level, .popUpMenu)
      XCTAssertNil(alert.window.parent)
      XCTAssertFalse(alert.window.isVisible)
      XCTAssertTrue(parent.isVisible)
      XCTAssertFalse(model.modalActive)
    }
  }

  func testAlertWithoutVisiblePanelDoesNotReshowIt() {
    let model = PanelModel()
    let parent = PanelWindow(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    parent.level = .popUpMenu
    model.dialogParentWindow = parent
    let alert = NSAlert()
    alert.messageText = "Hidden panel regression test"
    let timer = Timer(timeInterval: 0.15, repeats: false) { _ in
      MainActor.assumeIsolated { NSApp.stopModal(withCode: .alertSecondButtonReturn) }
    }
    RunLoop.main.add(timer, forMode: .modalPanel)
    XCTAssertEqual(model.runModalAlert(alert), .alertSecondButtonReturn)
    XCTAssertFalse(parent.isVisible)
    XCTAssertEqual(parent.level, .popUpMenu)
    XCTAssertFalse(model.modalActive)
  }
}
