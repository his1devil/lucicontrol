import LuciControlCore
import SwiftUI

/// The panel: one page at a time above a footer, at most 590 pt tall.
struct PanelRoot: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      switch model.page {
      case .home: HomeView()
      case .add: AddDirectoryView()
      case .pair: PairView()
      case .devices: DevicesView()
      case .settings: SettingsView()
      case .codexMissing: CodexMissingView()
      }
      if model.page != .add {
        FooterBar()
      }
    }
    .frame(width: DS.panelWidth)
    .background(DS.panel)
    .task {
      // Relative times and the pairing countdown tick once a second, while the panel shows.
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        if model.panelVisible { model.now = Date() }
      }
    }
  }

}

/// "+ 添加目录 · ● 共享中 · icons" under every page but the add page.
struct FooterBar: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    HStack(spacing: 8) {
      Button { model.openAdd() } label: {
        HStack(spacing: 4) {
          Text("+").font(.ui(13)).foregroundStyle(DS.accentText)
          Text("添加目录").font(.ui(10.5)).foregroundStyle(DS.accentText)
        }
        .padding(.leading, 8).padding(.trailing, 10).frame(height: 24)
        .background(DS.accentFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
      .buttonStyle(.plain)
      .padding(.trailing, 4)
      .accessibilityIdentifier("footer-add")

      Button { model.togglePause() } label: {
        HStack(spacing: 8) {
          Circle().fill(dotColor).frame(width: 6, height: 6)
          Text(model.sharing.label).font(.ui(10)).foregroundStyle(DS.ink2).lineLimit(1)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(pauseHelp)
      .accessibilityIdentifier("footer-status")

      Spacer(minLength: 4)

      if model.update.pendingVersion != nil {
        FooterIcon(symbol: "arrow.down.to.line", size: 13, color: DS.accentText, help: "有新版本") { model.page = .settings }
      }
      FooterIcon(symbol: "iphone", size: 13, help: model.sharing == .unpaired ? "连接手机" : "设备") {
        if model.sharing == .unpaired { model.startPairing() } else { model.page = .devices }
      }
      FooterIcon(symbol: "gearshape", size: 13, help: "设置") { model.page = .settings }
      FooterIcon(symbol: "power", size: 13, help: "退出 LuciControl") { NSApp.terminate(nil) }
    }
    .padding(EdgeInsets(top: 12, leading: 14, bottom: 14, trailing: DS.side))
    .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 0.5) }
  }

  private var dotColor: Color {
    switch model.sharing {
    case .sharing: DS.running
    case .connecting, .starting: DS.waiting
    case .error: DS.waiting
    case .paused, .unpaired: DS.pausedDot
    }
  }

  private var pauseHelp: String {
    switch model.sharing {
    case .sharing, .connecting: "点击暂停共享"
    case .paused: "点击恢复共享"
    default: ""
    }
  }
}

/// Shown when neither Codex CLI nor the desktop app can be found.
struct CodexMissingView: View {
  @Environment(PanelModel.self) private var model
  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("先安装 Codex").font(.ui(14, .medium)).tracking(-0.2).foregroundStyle(DS.ink)
      Text("LuciControl 让手机看到并操作这台 Mac 上的 Codex 会话。这台 Mac 上还没有 Codex：装好桌面版（ChatGPT.app）或命令行版并登录，再回到这里。")
        .font(.ui(11)).lineSpacing(4).foregroundStyle(DS.ink2).fixedSize(horizontal: false, vertical: true)
      HStack(spacing: 8) {
        PrimaryButton(title: "重新检查", compact: true) { model.page = .home }
        Link("下载 Codex", destination: URL(string: "https://openai.com/codex")!).font(.ui(11)).foregroundStyle(DS.accentText)
      }
    }
    .padding(EdgeInsets(top: 22, leading: DS.side, bottom: 22, trailing: DS.side))
  }
}
