import AppKit

extension PanelModel {
  /// NSAlert.runModal uses AppKit's modal-panel level, below our pop-up-menu panel.
  /// Keep the alert attached above its owner and temporarily lower only the owner;
  /// setting the alert's level before runModal is not enough because AppKit resets it.
  func runModalAlert(_ alert: NSAlert) -> NSApplication.ModalResponse {
    alert.layout()
    return runModal(attaching: alert.window) { alert.runModal() }
  }

  /// The folder picker sits at the same level as an alert and opened partly under the
  /// panel, its 选择 button included, on a 14-inch screen. It is not attached as a child
  /// (an open panel's window is AppKit's to manage); lowering the owner is enough.
  func runModalOpenPanel(_ panel: NSOpenPanel) -> NSApplication.ModalResponse {
    runModal(attaching: nil) { panel.runModal() }
  }

  /// Runs a modal window above the panel: the panel drops below the modal level for the
  /// duration and stays open (`modalActive`); afterwards level, key status and the flag
  /// are put back.
  private func runModal(attaching dialog: NSWindow?, _ run: () -> NSApplication.ModalResponse) -> NSApplication.ModalResponse {
    let parent = [dialogParentWindow, NSApp.keyWindow].compactMap { $0 }.first { $0.isVisible }
    let previousLevel = parent?.level
    let previousModalActive = modalActive
    modalActive = true
    if let parent {
      if parent.level.rawValue >= NSWindow.Level.modalPanel.rawValue {
        parent.level = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue - 1)
      }
      if let dialog {
        // Where a lone alert goes: centred, a little above the middle. Attaching orders the
        // window in at its unplaced origin, far to the left, and runModal does not move a
        // window that is already on screen. center() uses the screen the window is on, so
        // it goes onto the panel's screen first.
        if let area = parent.screen?.visibleFrame { dialog.setFrameOrigin(NSPoint(x: area.midX, y: area.midY)) }
        dialog.center()
        parent.addChildWindow(dialog, ordered: .above)
      }
    }
    defer {
      if let dialog {
        dialog.orderOut(nil)
        parent?.removeChildWindow(dialog)
      }
      if let parent, let previousLevel {
        parent.level = previousLevel
        if parent.isVisible { parent.makeKeyAndOrderFront(nil) }
      }
      modalActive = previousModalActive
    }
    NSApp.activate(ignoringOtherApps: true)
    return run()
  }
}
