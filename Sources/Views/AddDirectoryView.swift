import LuciControlCore
import SwiftUI

/// "添加目录": pick a folder, tick detected ones, choose how to share.
struct AddDirectoryView: View {
  @Environment(PanelModel.self) private var model

  private var listMaxHeight: CGFloat { model.maxPanelHeight - 56 - 60 }

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      BackHeader(title: "添加目录") { model.page = .home }
      FittingScrollView(maxHeight: listMaxHeight) {
        VStack(alignment: .leading, spacing: 20) {
          VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Agent")
            HStack(spacing: 6) {
              ForEach(model.agents) { agent in
                let active = agent == model.addAgent
                let supported = model.supportedAgents.contains(agent)
                Button { model.addAgent = agent } label: {
                  HStack(spacing: 5) {
                    AgentLogo(agent: agent, size: 13)
                    Text(agent.title).font(.ui(11)).foregroundStyle(DS.ink)
                  }
                  .padding(EdgeInsets(top: 5, leading: 9, bottom: 5, trailing: 9))
                  .background(active ? DS.accentFillStrong : DS.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                  .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(active ? DS.accent : .clear, lineWidth: 1.5))
                  .opacity(supported ? 1 : 0.4)
                }
                .buttonStyle(.plain)
                .disabled(!supported)
                .help(supported ? "" : "\(agent.title) 支持还在做")
              }
            }
          }

          VStack(alignment: .leading, spacing: 6) {
            SectionLabel(text: "路径").padding(.bottom, 2)
            HStack(spacing: 6) {
              TextField("~/dev/…", text: $model.addPath)
                .textFieldStyle(.plain).font(.mono(10.5)).foregroundStyle(DS.ink)
                .padding(.horizontal, 10).frame(height: 30)
                .background(DS.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .accessibilityIdentifier("add-path")
              Button { choose() } label: {
                Text("选择…").font(.ui(11)).foregroundStyle(DS.ink)
                  .padding(.horizontal, 12).frame(height: 30)
                  .background(DS.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
              }
              .buttonStyle(.plain)
            }
            Text("也可以把文件夹拖到菜单栏图标上").font(.ui(10)).foregroundStyle(DS.ink2)
          }

          if !model.addCandidates.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
              SectionLabel(text: "检测到的目录").padding(.bottom, 4)
              ForEach(model.addCandidates) { c in
                let on = model.addSelected.contains(c.path)
                Button { model.toggleCandidate(c.path) } label: {
                  HStack(spacing: 12) {
                    Checkbox(isOn: on)
                    VStack(alignment: .leading, spacing: 2) {
                      Text(Format.shortPath(c.path)).font(.mono(11)).foregroundStyle(DS.ink).lineLimit(1).truncationMode(.middle)
                      Text(candidateDetail(c)).font(.ui(10.5)).foregroundStyle(DS.ink2).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                  }
                  .padding(.vertical, 9)
                  .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
              }
            }
          }

          VStack(alignment: .leading, spacing: 0) {
            SectionLabel(text: "共享方式").padding(.bottom, 4)
            ToggleRow(title: "共享现有会话", detail: "添加后立即对手机可见", isOn: model.addShareExisting) { model.addShareExisting.toggle() }
            ToggleRow(title: "新会话自动共享", detail: "否则新会话默认私有，要在这里打开", isOn: model.addShareNew) { model.addShareNew.toggle() }
          }
        }
        .padding(EdgeInsets(top: 8, leading: DS.side, bottom: 8, trailing: DS.side))
      }
      HStack(spacing: 8) {
        SecondaryButton(title: "取消") { model.page = .home }.frame(maxWidth: 120)
        PrimaryButton(title: model.addCount > 0 ? "添加 \(model.addCount) 个目录" : "添加目录", enabled: model.addCount > 0) { model.commitAdd() }
      }
      .padding(EdgeInsets(top: 14, leading: DS.side, bottom: 16, trailing: DS.side))
      .overlay(alignment: .top) { Rectangle().fill(DS.line).frame(height: 0.5) }
    }
  }

  private func candidateDetail(_ c: DirectoryCandidate) -> String {
    let when = "最近在 \(c.agent.title) 中使用 · \(Format.relative(c.updatedAt, now: model.now))"
    return c.sessions > 0 ? "\(when) · \(c.sessions) 个会话" : "\(when) · 暂无会话"
  }

  private func choose() {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.prompt = "选择"
    panel.message = "选择要给手机访问的项目目录"
    if model.runModalOpenPanel(panel) == .OK, let url = panel.url {
      model.addPath = url.path
    }
  }
}
