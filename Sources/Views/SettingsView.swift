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
            Button { model.openDevices() } label: {
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
            ToggleRow(title: "自动检查更新", detail: "每天检查一次，启动后安排检查", isOn: model.autoCheckUpdates) { model.setAutoCheckUpdates(!model.autoCheckUpdates) }
            ToggleRow(title: "自动下载并安装", detail: "在后台下载，下次重启 LuciControl 时生效", isOn: model.autoInstallUpdates, enabled: model.autoCheckUpdates) { model.setAutoInstallUpdates(!model.autoInstallUpdates) }
          }

          VStack(alignment: .leading, spacing: 4) {
            SectionLabel(text: "通用")
            ToggleRow(title: "开机时启动 LuciControl", detail: "登录 macOS 后自动在菜单栏运行；不开着就没有共享", isOn: model.launchAtLogin) { model.setLaunchAtLogin(!model.launchAtLogin) }
            ToggleRow(title: "更新可用时提示", detail: "在菜单栏图标和面板底部显示提示", isOn: model.updateHints) { model.setUpdateHints(!model.updateHints) }
          }

          if let m = model.machine {
            VStack(alignment: .leading, spacing: 4) {
              SectionLabel(text: "Claude Code")
              if let join = m.claudeJoin {
                ToggleRow(title: "接入 Claude Code", detail: joinDetail(m, on: join),
                          isOn: join, enabled: m.claudeFound) { model.setClaudeJoin(!join) }
              }
              ToggleRow(title: "会话改东西前一律先问", detail: "只对手机上正开着的会话：Bash、Write、Edit 这类工具每次都弹确认，手机才能收到授权卡；本机装了自动放行的 hook 时需要开",
                        isOn: m.claudeForceAsk, enabled: m.claudeFound) { model.setClaudeForceAsk(!m.claudeForceAsk) }
            }
          }

          if let m = model.machine {
            VStack(alignment: .leading, spacing: 6) {
              SectionLabel(text: "本机")
              VStack(alignment: .leading, spacing: 4) {
                infoRow("机器名", m.label)
                infoRow("账号", m.owner)
                if m.agentError.isEmpty {
                  infoRow("Codex", m.agentVersion)
                } else {
                  infoRow("Codex", "连不上：\(m.agentError)", attention: true)
                }
                if m.claudeFound {
                  infoRow("Claude Code", m.claudeVersion.isEmpty ? "已安装" : m.claudeVersion)
                } else {
                  infoRow("Claude Code", "没找到 claude", attention: true)
                }
                if !m.linkError.isEmpty {
                  infoRow("中继", "连不上：\(m.linkError)", attention: true)
                }
                if let exp = m.tokenExpiresAt {
                  let token = Format.token(expires: exp, renews: m.tokenRenews, renewError: m.tokenRenewError, now: model.now)
                  infoRow("令牌", token.text, attention: token.attention)
                }
              }
              .padding(12)
              .background(DS.fill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
              HStack(spacing: 14) {
                linkButton("体检") { model.runDoctor() }
                linkButton("打开日志") { model.openLogs() }
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

  /// One fact; a long one is cut at the end and shown whole on hover.
  /// What joining every Claude session does, or why it is not in place yet.
  private func joinDetail(_ m: MachineInfo, on: Bool) -> String {
    if on, !m.claudeJoinProblem.isEmpty { return m.claudeJoinProblem }
    if on { return m.claudeJoinHelpers > 0 ? "已接入：\(m.claudeJoinHelpers) 个会话手机可以发消息。新开的 claude 都会接入" : "已接入：在任何终端里照常运行 claude，会话就会出现在这里和手机上" }
    return "在任何终端里照常运行 claude，会话就出现在这里和手机上，手机能发消息、批授权。会往 Claude Code 的设置里加 hooks 和一个不联网的会话助手，关掉即删除"
  }

  private func infoRow(_ k: String, _ v: String, attention: Bool = false) -> some View {
    HStack(spacing: 10) {
      Text(k).font(.ui(10.5)).foregroundStyle(DS.ink2).frame(width: 44, alignment: .leading)
      Text(v).font(.ui(10.5)).foregroundStyle(attention ? DS.waitingText : DS.ink).lineLimit(1).help(v)
    }
  }

  private func linkButton(_ title: String, action: @escaping () -> Void) -> some View {
    Button(title, action: action).buttonStyle(.plain).font(.ui(11)).foregroundStyle(DS.accentText)
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
      if case .downloading(_, let progress) = model.update, let p = progress {
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
    case .unchecked:
      return ("尚未检查更新", DS.ink3, "检查更新", { model.checkForUpdates() }, false)
    case .failed(let message):
      return (message, DS.waiting, "重试", { model.checkForUpdates() }, false)
    case .deferred(let v):
      return ("\(v) 待安装 · 等待服务就绪或会话结束", DS.waiting, "重试安装", { model.installUpdate() }, false)
    case .latest(let at):
      return ("已是最新版本 · \(Format.relative(at, now: model.now))检查", DS.running, "检查更新", { model.checkForUpdates() }, false)
    case .checking:
      return ("正在检查更新…", DS.ink3, "检查中…", {}, true)
    case .available(let v, _):
      return ("发现新版本 \(v)", DS.accent, "下载并安装", { model.downloadUpdate() }, false)
    case .downloading(let v, let p):
      return ("正在下载 \(v)" + (p.map { " · \(Int($0 * 100))%" } ?? ""), DS.ink3, "查看", { model.checkForUpdates() }, false)
    case .ready(let v, _):
      return ("\(v) 已下载，可以安装", DS.accent, "安装更新", { model.installUpdate() }, false)
    case .installing:
      return ("正在安装…", DS.ink3, "安装中…", {}, true)
    }
  }
}
