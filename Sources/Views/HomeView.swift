import LuciControlCore
import SwiftUI

/// Tabs per agent, then the shared directories with their sessions.
struct HomeView: View {
  @Environment(PanelModel.self) private var model

  private var listMaxHeight: CGFloat { model.maxPanelHeight - 47 - 50 }

  var body: some View {
    VStack(spacing: 0) {
      TabBar()
      let dirs = model.directories(for: model.agent)
      if !model.supportedAgents.contains(model.agent) {
        EmptyState(title: "\(model.agent.title) 支持还在做", detail: "先用 Codex。等 LuciControl 学会跟 \(model.agent.title) 说话，它的会话会出现在这里。")
      } else if dirs.isEmpty {
        EmptyState(title: "还没有共享的目录", detail: "点左下角「+ 添加目录」，选择要给手机访问的项目")
      } else {
        FittingScrollView(maxHeight: listMaxHeight) {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(dirs) { dir in
              DirectorySection(directory: dir)
            }
          }
          .padding(.horizontal, DS.side)
          .padding(.bottom, 12)
        }
      }
    }
  }
}

struct TabBar: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    HStack(spacing: 2) {
      ForEach(model.agents) { agent in
        let active = agent == model.agent
        Button { model.agent = agent } label: {
          HStack(spacing: 5) {
            AgentLogo(agent: agent, size: 14, color: active ? DS.accentText : DS.ink2)
            Text(agent.shortTitle).font(.ui(11, active ? .medium : .regular))
              .foregroundStyle(active ? DS.accentText : DS.ink2).lineLimit(1)
          }
          .padding(EdgeInsets(top: 10, leading: 4, bottom: 11, trailing: 4))
          .frame(maxWidth: .infinity)
          .background(active ? DS.accentFillStrong : .clear, in: UnevenRoundedRectangle(topLeadingRadius: 6, topTrailingRadius: 6))
          .overlay(alignment: .bottom) { Rectangle().fill(active ? DS.accent : .clear).frame(height: 2) }
          .overlay(alignment: .topTrailing) {
            if model.hasWaiting(agent) {
              Circle().fill(DS.badgeWaiting).frame(width: 5, height: 5).padding(5)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tab-\(agent.rawValue)")
      }
    }
    .padding(.top, 12).padding(.horizontal, 12)
    .overlay(alignment: .bottom) { Rectangle().fill(DS.line).frame(height: 0.5) }
  }
}

/// One shared directory: its uppercase name, the count, and its sessions.
struct DirectorySection: View {
  @Environment(PanelModel.self) private var model
  var directory: SharedDirectory

  var body: some View {
    let all = model.sessions(in: directory)
    let (shown, folded) = Grouping.split(all)
    let expanded = model.expanded.contains(directory.id)
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        // Two folders can share a name; the full path tells them apart.
        SectionLabel(text: directory.name, color: DS.ink).help(Format.shortPath(directory.path))
        Text("\(all.filter(\.shared).count)/\(all.count) 会话").font(.ui(10)).foregroundStyle(DS.ink3).lineLimit(1)
        Spacer()
        RemoveButton(label: "移除共享目录 \(directory.name)", enabled: model.canRemove(directory),
                     help: model.canRemove(directory) ? "移除共享目录，保留磁盘文件" : "有会话正在运行或等待响应，结束后可移除") {
          model.requestDirectoryRemoval(directory)
        }
        .accessibilityIdentifier("remove-directory-\(directory.id)")
      }
      .padding(.bottom, 8)
      .contentShape(Rectangle())
      .contextMenu {
        Button("移除共享目录…") { model.requestDirectoryRemoval(directory) }
          .disabled(!model.canRemove(directory))
        Toggle("新会话自动共享", isOn: Binding(get: { directory.sharesNewSessions }, set: { model.setNewSessionsShared(directory, $0) }))
        Divider()
        Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: directory.path)]) }
      }
      ForEach(shown) { s in SessionRow(session: s) }
      if !folded.isEmpty {
        if expanded {
          ForEach(folded) { s in SessionRow(session: s) }
        }
        Button { model.toggleExpanded(directory) } label: {
          Text(expanded ? "收起" : "更早的 \(folded.count) 个会话").font(.ui(10)).foregroundStyle(DS.accentText)
            .padding(.leading, 16).padding(.vertical, 8)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.top, 18)
  }
}

struct SessionRow: View {
  @Environment(PanelModel.self) private var model
  var session: Session

  var body: some View {
    let on = session.shared
    HStack(spacing: 12) {
      StatusBar(color: barColor)
      VStack(alignment: .leading, spacing: 3) {
        Text(session.title).font(.ui(12)).foregroundStyle(on ? DS.ink : DS.inkOff).lineLimit(1)
        Text(Format.sessionSubtitle(session, now: model.now)).font(.ui(10.5)).foregroundStyle(subtitleColor).lineLimit(1)
      }
      Spacer(minLength: 8)
      HStack(spacing: 6) {
        PillToggle(isOn: on, enabled: !model.isRemoving) { model.toggleSession(session.id) }
        RemoveButton(label: "移除会话 \(session.title)", enabled: model.canRemove(session),
                     help: model.canRemove(session) ? "移除共享会话，保留 Codex 聊天记录" : "会话正在运行或等待响应，结束后可移除") {
          model.requestSessionRemoval(session)
        }
        .accessibilityIdentifier("remove-session-\(session.id)")
      }
    }
    .fixedSize(horizontal: false, vertical: true)
    .padding(.vertical, 9)
    .accessibilityIdentifier("session-\(session.id)")
  }

  private var barColor: Color {
    guard session.shared else { return DS.barOff }
    switch session.state {
    case .waiting: return DS.waiting
    case .running: return DS.running
    case .idle: return DS.idle
    }
  }

  private var subtitleColor: Color {
    session.shared && session.state == .waiting ? DS.waitingText : DS.ink2
  }
}

/// "还没有共享的目录" and the like, under the tab bar.
struct EmptyState: View {
  var title: String
  var detail: String
  var body: some View {
    HStack(alignment: .center, spacing: 14) {
      RoundedRectangle(cornerRadius: 2).fill(DS.barOff).frame(width: 4, height: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.ui(12)).foregroundStyle(DS.ink)
        Text(detail).font(.ui(10.5)).foregroundStyle(DS.ink2).fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .padding(EdgeInsets(top: 22, leading: DS.side, bottom: 26, trailing: DS.side))
  }
}
