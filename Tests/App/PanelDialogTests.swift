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
      // The timer fires on the main run loop; its block is @Sendable by type only.
      nonisolated(unsafe) let panel = parent
      // Run inside the real AppKit modal loop, after NSAlert has applied its own level.
      let timer = Timer(timeInterval: 0.15, repeats: false) { _ in
        MainActor.assumeIsolated {
          observed = true
          XCTAssertTrue(model.modalActive)
          XCTAssertTrue(alert.window.isVisible)
          XCTAssertTrue(alert.window.parent === panel)
          XCTAssertTrue(panel.isVisible)
          XCTAssertGreaterThan(alert.window.level.rawValue, panel.level.rawValue)
          // NSApp.orderedWindows excludes non-main NSPanel windows; compare the actual
          // WindowServer order, which includes both the menu panel and the alert.
          let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
          let ordered = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
          if let dialogIndex = ordered.firstIndex(of: alert.window.windowNumber), let parentIndex = ordered.firstIndex(of: panel.windowNumber) {
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

  /// The folder picker (选择…) has an alert's level and opened partly under the panel, its
  /// 选择 button included; it must come up in front of the panel like the alerts do.
  func testFolderPickerOpensInFrontOfThePanel() {
    let model = PanelModel()
    let parent = PanelWindow(contentRect: NSRect(x: 100, y: 100, width: 412, height: 300), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    parent.isReleasedWhenClosed = false
    parent.level = .popUpMenu
    model.dialogParentWindow = parent
    parent.makeKeyAndOrderFront(nil)
    defer { parent.orderOut(nil) }
    let picker = NSOpenPanel()
    picker.canChooseDirectories = true
    picker.canChooseFiles = false
    var observed = false
    nonisolated(unsafe) let panel = parent
    // The picker takes a moment to come up; look once it has, inside its modal loop.
    let timer = Timer(timeInterval: 1.0, repeats: false) { _ in
      MainActor.assumeIsolated {
        observed = true
        XCTAssertTrue(model.modalActive)
        XCTAssertLessThan(panel.level.rawValue, NSWindow.Level.modalPanel.rawValue)
        let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] ?? []
        let ordered = windows.compactMap { $0[kCGWindowNumber as String] as? Int }
        if let pickerIndex = ordered.firstIndex(of: picker.windowNumber), let panelIndex = ordered.firstIndex(of: panel.windowNumber) {
          XCTAssertLessThan(pickerIndex, panelIndex, "the picker must be in front of the panel")
        } else { XCTFail("Both the picker and the panel must be on screen") }
        NSApp.stopModal(withCode: .cancel)
      }
    }
    RunLoop.main.add(timer, forMode: .modalPanel)
    XCTAssertEqual(model.runModalOpenPanel(picker), .cancel)
    XCTAssertTrue(observed)
    XCTAssertEqual(parent.level, .popUpMenu)
    XCTAssertFalse(model.modalActive)
  }
}
