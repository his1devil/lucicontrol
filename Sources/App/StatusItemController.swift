import AppKit
import LuciControlCore

/// The menu bar item: left click opens the panel, right click shows the small menu, a
/// folder dropped on it opens the add page with the path filled in.
@MainActor
final class StatusItemController: NSObject {
  private let item: NSStatusItem
  private let panel: PanelController
  private let model: PanelModel
  private var dropTarget: DropTargetView?
  private var observation: Task<Void, Never>?
  /// What the icon shows now; every status push re-runs `refreshIcon`, most change nothing.
  private var iconState: MenuBarIcon.State?

  init(panel: PanelController, model: PanelModel) {
    self.panel = panel
    self.model = model
    item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()
    guard let button = item.button else { return }
    panel.anchorFrame = { [weak self] in self?.buttonFrameOnScreen }
    button.image = MenuBarIcon.image(for: .sharing)
    button.imagePosition = .imageOnly
    button.target = self
    button.action = #selector(clicked(_:))
    // Menus open on the press, not the release; the panel does the same.
    button.sendAction(on: [.leftMouseDown, .rightMouseDown])
    button.setAccessibilityLabel("LuciControl")
    if ProcessInfo.processInfo.arguments.contains("--trace") {
      // The item gets its place in the bar a moment after launch; log its centre in CG
      // (top-left origin) coordinates for a synthetic click.
      DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
        guard let f = self?.buttonFrameOnScreen, let screen = NSScreen.screens.first else { return }
        NSLog("icon: centre-cg %.0f %.0f", f.midX, screen.frame.height - f.midY)
      }
    }
    let drop = DropTargetView(frame: button.bounds)
    drop.autoresizingMask = [.width, .height]
    drop.onDrop = { [weak self] path in self?.dropped(path) }
    button.addSubview(drop)
    dropTarget = drop
    observation = Task { [weak self] in
      // Re-draw the icon whenever the state it depends on changes.
      while let self, !Task.isCancelled {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
          withObservationTracking {
            self.refreshIcon()
          } onChange: {
            c.resume()
          }
        }
      }
    }
  }

  deinit {
    observation?.cancel()
  }

  var buttonWindow: NSWindow? { item.button?.window }
  var buttonFrameOnScreen: NSRect? {
    guard let button = item.button, let window = button.window else { return nil }
    return window.convertToScreen(button.convert(button.bounds, to: nil))
  }

  private func refreshIcon() {
    let state: MenuBarIcon.State
    if model.waitingCount > 0, model.sharing == .sharing {
      state = .waiting
    } else if model.update.pendingVersion != nil, model.updateHints {
      state = .update
    } else if model.sharing == .sharing {
      state = .sharing
    } else {
      state = .off
    }
    // Everything above is read on every pass (observation tracking needs it); the image
    // and the status bar's re-layout only when the state is new.
    guard state != iconState else { return }
    iconState = state
    item.button?.image = MenuBarIcon.image(for: state)
  }

  @objc private func clicked(_ sender: Any?) {
    if ProcessInfo.processInfo.arguments.contains("--trace") { NSLog("icon: clicked, event=%@", String(describing: NSApp.currentEvent?.type.rawValue)) }
    if NSApp.currentEvent?.type == .rightMouseDown {
      showMenu()
    } else {
      panel.toggle(anchor: buttonFrameOnScreen)
    }
  }

  private func showMenu() {
    let menu = NSMenu()
    // Otherwise NSMenu enables every item whose target answers, and ignores isEnabled below.
    menu.autoenablesItems = false
    menu.addItem(withTitle: "打开面板", action: #selector(openPanel), keyEquivalent: "").target = self
    let pause = NSMenuItem(title: model.sharing == .paused ? "恢复共享" : "暂停共享", action: #selector(togglePause), keyEquivalent: "")
    pause.target = self
    pause.isEnabled = [.sharing, .connecting, .paused].contains(model.sharing)
    menu.addItem(pause)
    menu.addItem(withTitle: "设置…", action: #selector(openSettings), keyEquivalent: "").target = self
    menu.addItem(.separator())
    menu.addItem(withTitle: "退出 LuciControl", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    item.menu = menu
    item.button?.performClick(nil)
    item.menu = nil
  }

  @objc private func openPanel() { panel.show(anchor: buttonFrameOnScreen) }
  @objc private func togglePause() { model.togglePause() }
  @objc private func openSettings() {
    model.page = .settings
    panel.show(anchor: buttonFrameOnScreen)
  }

  private func dropped(_ path: String) {
    model.openAdd(path: path)
    panel.show(anchor: buttonFrameOnScreen)
  }
}

/// Sits over the status bar button, takes folder drops, and hands clicks to the button.
final class DropTargetView: NSView {
  var onDrop: ((String) -> Void)?

  override init(frame: NSRect) {
    super.init(frame: frame)
    registerForDraggedTypes([.fileURL])
  }

  required init?(coder: NSCoder) { fatalError() }

  override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
    folder(in: sender) == nil ? [] : .copy
  }

  override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
    guard let path = folder(in: sender) else { return false }
    onDrop?(path)
    return true
  }

  private func folder(in info: any NSDraggingInfo) -> String? {
    let urls = info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    guard let url = urls.first else { return nil }
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
    return url.path
  }

  // Clicks belong to the button underneath.
  override func mouseDown(with event: NSEvent) { superview?.mouseDown(with: event) }
  override func mouseUp(with event: NSEvent) { superview?.mouseUp(with: event) }
  override func rightMouseDown(with event: NSEvent) { superview?.rightMouseDown(with: event) }
  override func rightMouseUp(with event: NSEvent) { superview?.rightMouseUp(with: event) }
}
