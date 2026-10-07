import AppKit
import LuciControlCore
import SwiftUI

/// Flags for development and screenshots:
///   --demo               sample data instead of a daemon
///   --daemon <path>      the lucirund to run (default: the one in the app bundle)
///   --data-dir <dir>     LUCIRUND_DIR for the daemon (an isolated identity and config)
///   --relay <base>       relay to pair through (default: the daemon's)
///   --window             the panel in an ordinary window instead of under the icon
///   --page <name>        home | add | pair | devices | settings | codex-missing
///   --appearance dark    force dark (or light)
///   --pair-state <s>     waiting | code | claimed | done (with --page pair)
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  private var model: PanelModel!
  private var panel: PanelController!
  private var statusItem: StatusItemController?
  private var window: NSWindow?
  private var backend: DaemonBackend?
  private var updater: UpdateController?
  private var terminationPending = false

  static func main() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    // Unit-test hosts must not start a daemon or check the live update feed.
    if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
      model = PanelModel()
      return
    }
    let args = CommandLine.arguments
    func value(_ flag: String) -> String? {
      guard let i = args.firstIndex(of: flag), i + 1 < args.count else { return nil }
      return args[i + 1]
    }
    if let appearance = value("--appearance") {
      NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
    }
    if args.contains("--demo") {
      model = PanelModel.demo()
    } else {
      model = PanelModel()
      let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/MacOS/lucirund")
      let exe = value("--daemon").map { URL(fileURLWithPath: $0) } ?? bundled
      backend = DaemonBackend(model: model, executable: exe, dataDir: value("--data-dir"), relay: value("--relay"))
      backend?.testAutoConfirm = args.contains("--test-auto-confirm")
      backend?.takeOverAtStart = args.contains("--takeover")
      if let dir = value("--test-add-dir") { backend?.addDirectories([dir], shareExisting: true, shareNew: false) }
    }
    if let page = value("--page") {
      switch page {
      case "add": model.openAdd()
      case "pair":
        model.startPairing()
        switch value("--pair-state") {
        case "code": model.pairMode = 1
        case "claimed": model.simulateClaim()
        case "done": model.simulateClaim(); model.confirmPairing(accept: true)
        default: break
        }
      case "devices": model.page = .devices
      case "settings": model.page = .settings
      case "settings-latest": model.page = .settings; model.update = .latest(checkedAt: Date())
      case "settings-downloading": model.page = .settings; model.update = .downloading(version: "0.2.0", progress: 0.45)
      case "codex-missing": model.page = .codexMissing
      case "codex-login": model.codexProblem = .notLoggedIn; model.page = .codexMissing
      case "takeover": model.page = .takeover
      case "empty": model.directories = []
      case "claude": model.agent = .claudeCode
      default: break
      }
    }
    if args.contains("--window") { model.panelVisible = true }
    panel = PanelController(model: model)
    panel.profiling = args.contains("--profile")
    backend?.start()
    // Isolated daemon runs and UI fixtures never use the production update feed.
    if !model.isDemo, value("--data-dir") == nil,
       !args.contains("--login-item"), !args.contains("--icons") {
      updater = UpdateController(model: model)
    }
    if let dir = value("--icons") {
      Self.writeIcons(to: dir)
      exit(0)
    }
    if let what = value("--login-item") {
      // Development check of the launch-agent registration: on | off | status.
      if what == "on" { try? LoginItem.set(true) }
      if what == "off" { try? LoginItem.set(false) }
      print("login item: \(LoginItem.statusText) (plist in bundle: \(LoginItem.isAvailable))")
      exit(0)
    }
    if args.contains("--window") {
      showInWindow()
    } else {
      statusItem = StatusItemController(panel: panel, model: model)
      backend?.showPanel = { [weak self] in
        guard let self else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.panel.show(anchor: self.statusItem?.buttonFrameOnScreen) }
      }
      if args.contains("--open") {
        // Open the panel under the icon right away, for a look at the real panel window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
          panel.show(anchor: statusItem?.buttonFrameOnScreen)
          if args.contains("--profile") {
            // Walk through the pages and time each switch, layout included.
            let pages: [PanelPage] = [.settings, .add, .devices, .pair, .home, .settings, .home]
            for (i, page) in pages.enumerated() {
              DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + Double(i) * 0.5) { [self] in
                let t0 = CFAbsoluteTimeGetCurrent()
                if page == .pair { model.startPairing() } else { model.page = page }
                panel.contentViewForSnapshot?.layoutSubtreeIfNeeded()
                panel.contentViewForSnapshot?.displayIfNeeded()
                NSLog("profile: page %@ in %.1f ms", String(describing: page), (CFAbsoluteTimeGetCurrent() - t0) * 1000)
                if i == pages.count - 1 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exit(0) } }
              }
            }
          }
          if let then = value("--then") {
            // A second page after the first one, to check the panel re-sizes between pages.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
              switch then {
              case "devices": model.page = .devices
              case "settings": model.page = .settings
              case "home": model.page = .home
              case "add": model.openAdd()
              default: break
              }
            }
          }
          if let path = value("--snapshot") {
            let delay = Double(value("--snapshot-delay") ?? "") ?? 1.3
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
              if let view = panel.contentViewForSnapshot { Self.snapshot(view, to: path) }
              exit(0)
            }
          }
        }
      }
    }
  }

  /// Quitting switches sharing off, so it always asks first; with a phone connected or a
  /// phone-started turn running the message says what stops.
  func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if terminationPending { return .terminateLater }
    // Sparkle already asked to install. Active sessions still require explicit consent
    // when a quit happens outside its postponed-relaunch path.
    if updater?.isRestarting != true || model.hasActiveSessions {
      let alert = NSAlert()
      alert.messageText = "退出 LuciControl？"
      alert.informativeText = model.quitWarning
      alert.alertStyle = .warning
      alert.addButton(withTitle: "退出")
      alert.addButton(withTitle: "取消")
      NSApp.activate(ignoringOtherApps: true)
      guard alert.runModal() == .alertFirstButtonReturn else { return .terminateCancel }
    }
    guard let backend else { return .terminateNow }
    terminationPending = true
    // Let the daemon tell the phones and close down before we go.
    Task {
      await backend.stop()
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    return .terminateLater
  }

  /// The four menu bar icon states at 4x, light and dark, for a look at the drawing.
  private static func writeIcons(to dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    for (name, state) in [("off", MenuBarIcon.State.off), ("sharing", .sharing), ("waiting", .waiting), ("update", .update)] {
      for dark in [false, true] {
        let scale: CGFloat = 4
        let size = MenuBarIcon.size
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSAppearance(named: dark ? .darkAqua : .aqua)!.performAsCurrentDrawingAppearance {
          (dark ? NSColor(hex: "#1e1f22") : NSColor(hex: "#f2f2f4")).setFill()
          NSRect(origin: .zero, size: size).fill()
          MenuBarIcon.image(for: state).draw(in: NSRect(origin: .zero, size: size))
        }
        NSGraphicsContext.restoreGraphicsState()
        if let png = rep.representation(using: .png, properties: [:]) {
          try? png.write(to: URL(fileURLWithPath: dir).appendingPathComponent("icon-\(dark ? "dark" : "light")-\(name).png"))
        }
      }
    }
  }

  /// The same content in a plain window on the design canvas's grey, for screenshots and
  /// comparison with design/reference. `--snapshot <png>` writes the window and quits.
  private func showInWindow() {
    let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: DS.panelWidth + 48, height: 400), styleMask: [.titled, .closable], backing: .buffered, defer: false)
    let fitter = WindowFitter()
    let root = PanelRoot().environment(model).onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
      // The window follows the panel's natural height, like the panel under the icon does.
      fitter.fit()
    }
    let hosting = NSHostingView(rootView: AnyView(root))
    hosting.sizingOptions = [.intrinsicContentSize]
    hosting.wantsLayer = true
    hosting.layer?.cornerRadius = DS.panelRadius
    hosting.layer?.cornerCurve = .continuous
    hosting.layer?.masksToBounds = true
    let backdrop = BackdropView(frame: NSRect(x: 0, y: 0, width: DS.panelWidth + 48, height: 400))
    backdrop.addSubview(hosting)
    hosting.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      hosting.topAnchor.constraint(equalTo: backdrop.topAnchor, constant: 24),
      hosting.leadingAnchor.constraint(equalTo: backdrop.leadingAnchor, constant: 24),
      hosting.widthAnchor.constraint(equalToConstant: DS.panelWidth),
    ])
    fitter.window = w
    fitter.hosting = hosting
    w.title = "LuciControl"
    w.contentView = backdrop
    w.isReleasedWhenClosed = false
    w.center()
    w.makeKeyAndOrderFront(nil)
    fitter.fit()
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
    window = w
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
      let path = CommandLine.arguments[i + 1]
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        fitter.fit()
        Self.snapshot(backdrop, to: path)
        exit(0)
      }
    }
  }

  private static func snapshot(_ view: NSView, to path: String) {
    view.layoutSubtreeIfNeeded()
    guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
    view.cacheDisplay(in: view.bounds, to: rep)
    guard let data = rep.representation(using: .png, properties: [:]) else { return }
    try? data.write(to: URL(fileURLWithPath: path))
  }
}

/// Sizes the preview window to the hosting view's natural height, keeping its top edge put.
@MainActor
final class WindowFitter {
  weak var window: NSWindow?
  weak var hosting: NSHostingView<AnyView>?
  var lastHeight: CGFloat = 0

  func fit() {
    guard let window, let hosting else { return }
    hosting.layoutSubtreeIfNeeded()
    let natural = hosting.fittingSize.height
    guard natural > 0 else { return }
    let height = min(natural, DS.panelMaxHeight) + 48
    guard abs(height - lastHeight) > 0.5 else { return }
    lastHeight = height
    var frame = window.frameRect(forContentRect: NSRect(x: 0, y: 0, width: DS.panelWidth + 48, height: height))
    frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
    window.setFrame(frame, display: true)
  }
}

/// The design canvas's grey behind the panel, with the panel's shadow.
final class BackdropView: NSView {
  override init(frame: NSRect) {
    super.init(frame: frame)
    wantsLayer = true
  }

  required init?(coder: NSCoder) { fatalError() }

  override func updateLayer() {
    layer?.backgroundColor = (effectiveAppearance.isDark ? NSColor(hex: "#2a2d31") : NSColor(hex: "#dfe2e6")).cgColor
  }

  override var wantsUpdateLayer: Bool { true }
}
