import AppKit

extension PanelModel {
  /// NSAlert.runModal uses AppKit's modal-panel level, below our pop-up-menu panel.
  /// Keep the alert attached above its owner and temporarily lower only the owner;
  /// setting the alert's level before runModal is not enough because AppKit resets it.
  func runModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
    let parent = [dialogParentWindow, NSApp.keyWindow].compactMap { $0 }.first { $0.isVisible }
    let previousLevel = parent?.level
    let previousModalActive = modalActive
    modalActive = true
    alert.layout()
    let dialog = alert.window
    if let parent {
      if parent.level.rawValue >= NSWindow.Level.modalPanel.rawValue {
        parent.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
      }
      parent.addChildWindow(dialog, ordered: .above)
    }
    defer {
      dialog.orderOut(nil)
      parent?.removeChildWindow(dialog)
      if let parent, let previousLevel {
        parent.level = previousLevel
        if parent.isVisible { parent.makeKeyAndOrderFront(nil) }
      }
      modalActive = previousModalActive
    }
    NSApp.activate(ignoringOtherApps: true)
    return alert.runModal()
  }
}
