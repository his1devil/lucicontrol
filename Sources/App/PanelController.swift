import AppKit
import LuciControlCore
import SwiftUI

/// The floating panel under the menu bar icon: a borderless, non-activating panel with a
/// blurred, rounded background and the SwiftUI pages inside. It sizes itself to the content
/// (up to 590 pt) and goes away on an outside click, Esc, or when another app comes forward.
@MainActor
final class PanelController: NSObject, NSWindowDelegate {
  private let model: PanelModel
  private var window: PanelWindow?
  private var anchor: NSRect?
  private var clickMonitor: Any?
  private var keyMonitor: Any?

  init(model: PanelModel) {
    self.model = model
    super.init()
    // Build the window now, so the first click does not pay for the first layout.
    let w = makeWindow()
    window = w
    w.contentView?.layoutSubtreeIfNeeded()
  }

  var isVisible: Bool { window?.isVisible ?? false }
  var contentViewForSnapshot: NSView? { window?.contentView }

  func toggle(anchor: NSRect?) {
    trace("toggle: visible=\(isVisible)")
    if isVisible { hide() } else { show(anchor: anchor) }
  }

  private func trace(_ msg: String) {
    if ProcessInfo.processInfo.arguments.contains("--trace") { NSLog("panel: %@", msg) }
  }

  func show(anchor: NSRect?) {
    let t0 = CFAbsoluteTimeGetCurrent()
    self.anchor = anchor
    let window = window ?? makeWindow()
    self.window = window
    // The cap follows the screen the icon is on: the design's height and a half, unless the
    // screen has less room under the menu bar than that.
    if let anchor, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main {
      model.maxPanelHeight = min(DS.panelMaxHeight, screen.visibleFrame.height - 6 - 8)
    }
    model.panelVisible = true
    model.now = Date()
    place(window)
    window.makeKeyAndOrderFront(nil)
    installMonitors()
    if profiling { NSLog("panel: shown in %.1f ms", (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
  }

  func hide() {
    trace("hide (visible=\(isVisible))")
    window?.orderOut(nil)
    model.panelVisible = false
    removeMonitors()
  }

  /// `--profile` logs how long showing and resizing take.
  var profiling = false

  /// Where the menu bar button is right now. A click there while the panel is open makes
  /// the panel resign key before the button's action runs; that click must close the
  /// panel, not close and reopen it.
  var anchorFrame: (() -> NSRect?)?

  private var workspaceObserver: Any?

  private func makeWindow() -> PanelWindow {
    let window = PanelWindow(contentRect: NSRect(x: 0, y: 0, width: DS.panelWidth, height: 200),
                             styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
    window.delegate = self
    window.isFloatingPanel = true
    window.level = .popUpMenu
    window.hidesOnDeactivate = false
    window.isOpaque = false
    window.backgroundColor = .clear
    window.hasShadow = true
    window.isMovableByWindowBackground = false
    window.animationBehavior = .none
    window.collectionBehavior = [.canJoinAllSpaces, .transient, .ignoresCycle]

    let container = PanelBackgroundView(frame: window.contentRect(forFrameRect: window.frame))
    container.autoresizingMask = [.width, .height]
    // The page sits at the top of the window; the window then takes the page's height.
    let root = ZStack(alignment: .top) {
      PanelRoot().environment(model).onGeometryChange(for: CGSize.self) { $0.size } action: { [weak self, weak window] size in
        guard let window else { return }
        if ProcessInfo.processInfo.arguments.contains("--trace") { NSLog("root: size %.0f x %.0f", size.width, size.height) }
        self?.resize(window, to: size)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    let hosting = NSHostingView(rootView: root)
    hosting.sizingOptions = []
    hosting.frame = container.bounds
    hosting.autoresizingMask = [.width, .height]
    hosting.layer?.masksToBounds = true
    container.addSubview(hosting)
    window.contentView = container
    return window
  }

  /// Keeps the top edge where it is while the content grows or shrinks.
  private func resize(_ window: NSWindow, to size: CGSize) {
    guard size.height > 0 else { return }
    let height = min(size.height, model.maxPanelHeight)
    var frame = window.frame
    let top = frame.maxY
    frame.size = NSSize(width: DS.panelWidth, height: height)
    frame.origin.y = top - height
    if frame.size != window.frame.size {
      // No animation: NSWindow's animated setFrame blocks the main thread for its whole
      // duration, which is what made every page change feel slow.
      let t0 = CFAbsoluteTimeGetCurrent()
      window.setFrame(frame, display: true, animate: false)
      if profiling { NSLog("panel: resized to %.0f in %.1f ms", height, (CFAbsoluteTimeGetCurrent() - t0) * 1000) }
    }
  }

  /// Centred under the icon, kept inside the screen with an 8 pt margin.
  private func place(_ window: NSWindow) {
    guard let anchor, let screen = NSScreen.screens.first(where: { $0.frame.intersects(anchor) }) ?? NSScreen.main else { return }
    let visible = screen.visibleFrame
    var x = anchor.midX - window.frame.width / 2
    x = min(max(x, visible.minX + 8), visible.maxX - window.frame.width - 8)
    let y = anchor.minY - 6 - window.frame.height
    window.setFrameOrigin(NSPoint(x: x, y: y))
  }

  private func installMonitors() {
    removeMonitors()
    // Switching to another app (⌘-Tab, a click the global monitor sees, Spotlight) closes the panel.
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
      let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
      let ours = app?.processIdentifier == ProcessInfo.processInfo.processIdentifier
      Task { @MainActor in
        guard let self, !ours, !self.model.modalActive else { return }
        self.hide()
      }
    }
    clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
      // A click on the menu bar icon arrives here too; the icon's own action toggles the
      // panel, so it must not be closed first (that made the icon re-open it).
      let location = NSEvent.mouseLocation
      Task { @MainActor in
        guard let self, !self.model.modalActive else { return }
        if let frame = self.anchorFrame?(), frame.contains(location) { return }
        self.trace("global click")
        self.hide()
      }
    }
    keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
      if event.keyCode == 53 { // Esc
        self?.hide()
        return nil
      }
      return event
    }
  }

  private func removeMonitors() {
    if let workspaceObserver { NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver) }
    workspaceObserver = nil
    if let clickMonitor { NSEvent.removeMonitor(clickMonitor) }
    if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    clickMonitor = nil
    keyMonitor = nil
  }

  func windowDidResignKey(_ notification: Notification) {
    trace("resign key; mouse over icon=\(anchorFrame?().map { $0.contains(NSEvent.mouseLocation) } ?? false)")
    if model.modalActive { return }
    if let frame = anchorFrame?(), frame.contains(NSEvent.mouseLocation) { return }
    hide()
  }
}

/// A panel that can take the keyboard (the path field) without activating the app.
final class PanelWindow: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

/// Blur behind the window, rounded to the design's 14 pt, with a hairline edge.
final class PanelBackgroundView: NSVisualEffectView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    material = .popover
    blendingMode = .behindWindow
    state = .active
    wantsLayer = true
    layer?.cornerRadius = DS.panelRadius
    layer?.cornerCurve = .continuous
    layer?.masksToBounds = true
    layer?.borderWidth = 0.5
    layer?.borderColor = NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.12) }.cgColor
  }

  required init?(coder: NSCoder) { fatalError() }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    layer?.borderColor = NSColor(name: nil) { $0.isDark ? NSColor.white.withAlphaComponent(0.1) : NSColor.black.withAlphaComponent(0.12) }.cgColor
  }
}
