import LuciControlCore
import SwiftUI

/// "设置": devices, updates, general, this Mac, quit.
struct SettingsView: View {
  @Environment(PanelModel.self) private var model

  private var listMaxHeight: CGFloat { model.maxPanelHeight - 56 - 50 }

  var body: some View {
    VStack(spacing: 0) {
      BackHeader(title: "设置") { model.page = .home }
      FittingScrollView(maxHeight: listMaxHeight) {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "设备")
            Button { model.page = .devices } label: {
              HStack(spacing: 10) {
                Image(systemName: "iphone").font(.system(size: 12, weight: .regular)).foregroundStyle(DS.ink)
                Text("已配对设备").font(.ui(11.5)).foregroundStyle(DS.ink)
                Spacer()
                Text("\(model.visibleDevices.count) 台设备").font(.ui(10.5)).foregroundStyle(DS.ink2)
                Text("›").font(.ui(13)).foregroundStyle(DS.ink2)
              }
              .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
              .background(DS.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
          }

          VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "更新")
            UpdateCard().padding(.top, 2)
            ToggleRow(title: "自动检查更新", detail: "每天检查一次，并在启动时检查", isOn: model.autoCheckUpdates) { model.autoCheckUpdates.toggle() }
            ToggleRow(title: "自动下载并安装", detail: "在后台下载，下次重启 LuciControl 时生效", isOn: model.autoInstallUpdates, enabled: model.autoCheckUpdates) { model.autoInstallUpdates.toggle() }
          }

          VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "通用")
            ToggleRow(title: "开机时启动 LuciControl", detail: "登录 macOS 后自动在菜单栏运行；不开着就没有共享", isOn: model.launchAtLogin) { model.launchAtLogin.toggle() }
            ToggleRow(title: "更新可用时提示", detail: "在菜单栏图标和面板底部显示提示", isOn: model.updateHints) { model.updateHints.toggle() }
          }

          if let m = model.machine {
            VStack(alignment: .leading, spacing: 6) {
              SectionLabel(text: "本机")
              VStack(alignment: .leading, spacing: 4) {
                infoRow("机器名", m.label)
                infoRow("账号", m.owner)
                infoRow("Codex", m.agentVersion)
                if let exp = m.tokenExpiresAt {
                  infoRow("令牌", "\(shortDate(exp)) 到期，自动续期")
                }
              }
              .padding(12)
              .background(DS.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              HStack(spacing: 14) {
                linkButton("体检") {}
                linkButton("打开日志") {}
                linkButton("重新配对") { model.startPairing() }
              }
              .padding(.top, 2)
            }
          }

          Button { NSApp.terminate(nil) } label: {
            HStack(spacing: 12) {
              VStack(alignment: .leading, spacing: 2) {
                Text("退出 LuciControl").font(.ui(11.5)).foregroundStyle(DS.ink)
                Text("退出后手机连不上这台 Mac").font(.ui(10.5)).foregroundStyle(DS.ink2)
              }
              Spacer()
              Text("⌘Q").font(.ui(10)).foregroundStyle(DS.ink3)
            }
            .padding(.vertical, 9)
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityIdentifier("settings-quit")
        }
        .padding(EdgeInsets(top: 8, leading: DS.side, bottom: 16, trailing: DS.side))
      }
    }
  }

  private func infoRow(_ k: String, _ v: String) -> some View {
    HStack(spacing: 10) {
      Text(k).font(.ui(10.5)).foregroundStyle(DS.ink2).frame(width: 44, alignment: .leading)
      Text(v).font(.ui(10.5)).foregroundStyle(DS.ink).lineLimit(1)
    }
  }

  private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action).buttonStyle(.plain).font(.ui(11)).foregroundStyle(DS.accentText)
  }

  private func shortDate(_ d: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    return f.string(from: d)
  }
}

/// Version, state, the one button, the progress bar and the release notes.
struct UpdateCard: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    let (status, dot, button, action, busy) = describe()
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text("LuciControl \(model.machine?.appVersion ?? "")").font(.ui(12)).foregroundStyle(DS.ink)
          HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 6, height: 6)
            Text(status).font(.ui(10.5)).foregroundStyle(DS.ink2)
          }
        }
        Spacer(minLength: 8)
        PrimaryButton(title: button, compact: true, enabled: !busy, action: action)
      }
      if case .downloading(_, let p) = model.update {
        GeometryReader { g in
          ZStack(alignment: .leading) {
            Capsule().fill(DS.progressTrack)
            Capsule().fill(DS.progressFill).frame(width: g.size.width * p)
          }
        }
        .frame(height: 3)
      }
      let notes: [String]? = {
        switch model.update {
        case .available(_, let n), .ready(_, let n): n
        default: nil
        }
      }()
      if let notes, let v = model.update.pendingVersion {
        VStack(alignment: .leading, spacing: 2) {
          Text("\(v) 新内容").font(.ui(10.5)).foregroundStyle(DS.ink).padding(.bottom, 2)
          ForEach(notes, id: \.self) { n in Text("· \(n)").font(.ui(10.5)).lineSpacing(3).foregroundStyle(DS.ink2) }
        }
        .padding(.top, 9)
        .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 0.5) }
      }
    }
    .padding(12)
    .background(DS.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
  }

  private func describe() -> (String, Color, String, () -> Void, Bool) {
    switch model.update {
    case .latest(let at):
      return ("已是最新版本 · \(Format.relative(at, now: model.now))检查", DS.running, "检查更新", { model.checkForUpdates() }, false)
    case .checking:
      return ("正在检查更新…", DS.ink3, "检查中…", {}, true)
    case .available(let v, _):
      return ("发现新版本 \(v)", DS.accent, "下载并安装", { model.downloadUpdate() }, false)
    case .downloading(let v, let p):
      return ("正在下载 \(v) · \(Int(p * 100))%", DS.ink3, "下载中…", {}, true)
    case .ready(let v, _):
      return ("\(v) 已下载，可以安装", DS.accent, "安装更新", { model.installUpdate() }, false)
    case .installing:
      return ("正在安装…", DS.ink3, "安装中…", {}, true)
    }
  }
}
