import LuciControlCore
import SwiftUI

/// The 40 × 18 ON / OFF pill on the right of every row.
struct PillToggle: View {
  var isOn: Bool
  var enabled: Bool = true
  var action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 0) {
        if isOn {
          label("ON", color: DS.knobOn)
          knob(DS.knobOn)
        } else {
          knob(DS.knobOff)
          label("OFF", color: DS.toggleOffText)
        }
      }
      .padding(2)
      .frame(width: 40, height: 18)
      .background(isOn ? DS.toggleOn : DS.toggleOff, in: Capsule())
      .opacity(enabled ? 1 : 0.4)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
    .animation(.easeOut(duration: 0.15), value: isOn)
    .accessibilityLabel(isOn ? "开" : "关")
  }

  private func label(_ text: String, color: Color) -> some View {
    Text(text).font(.ui(8, .medium)).tracking(0.4).foregroundStyle(color).frame(maxWidth: .infinity)
  }

  private func knob(_ color: Color) -> some View {
    Circle().fill(color).frame(width: 14, height: 14)
  }
}

/// The 4 pt colour bar on the left of a row, as tall as the row. A shape takes every point
/// of height it is offered, so the row that holds it sets `fixedSize(vertical:)`.
struct StatusBar: View {
  var color: Color
  var body: some View {
    RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 4)
  }
}

/// A section's small uppercase label.
struct SectionLabel: View {
  var text: String
  var color: Color = DS.ink3
  var body: some View {
    Text(text).font(.ui(10, .medium)).tracking(0.8).textCase(.uppercase).foregroundStyle(color)
  }
}

/// "‹ Title" at the top of a sub page.
struct BackHeader: View {
  var title: String
  var back: () -> Void
  var body: some View {
    HStack(spacing: 10) {
      Button(action: back) {
        Text("‹").font(.ui(17)).foregroundStyle(DS.ink2)
          .frame(width: 26, height: 26)
          .background(DS.fill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
      }
      .buttonStyle(.plain)
      .accessibilityLabel("返回")
      Text(title).font(.ui(14, .medium)).tracking(-0.2).foregroundStyle(DS.ink)
      Spacer()
    }
    .padding(EdgeInsets(top: 20, leading: DS.side, bottom: 10, trailing: DS.side))
  }
}

/// A row with a title, a one-line description and a pill.
struct ToggleRow: View {
  var title: String
  var detail: String
  var isOn: Bool
  var enabled: Bool = true
  var action: () -> Void

  var body: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.ui(11.5)).foregroundStyle(DS.ink)
        Text(detail).font(.ui(10.5)).foregroundStyle(DS.ink2)
      }
      Spacer(minLength: 8)
      PillToggle(isOn: isOn, enabled: enabled, action: action)
    }
    .padding(.vertical, 9)
    .opacity(enabled ? 1 : 0.4)
  }
}

/// The blue button: "完成", "添加 N 个目录", "下载并安装".
struct PrimaryButton: View {
  var title: String
  var compact = false
  var enabled = true
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.ui(compact ? 10.5 : 11.5))
        .foregroundStyle(.white)
        .padding(.horizontal, compact ? 11 : 22)
        .frame(height: compact ? 26 : 30)
        .frame(maxWidth: compact ? nil : .infinity)
        .background(DS.accent, in: RoundedRectangle(cornerRadius: compact ? 6 : 7, style: .continuous))
        .opacity(enabled ? 1 : 0.5)
    }
    .buttonStyle(.plain)
    .disabled(!enabled)
  }
}

/// The grey button next to a primary one: "取消", "选择…".
struct SecondaryButton: View {
  var title: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Text(title).font(.ui(11.5)).foregroundStyle(DS.ink)
        .frame(height: 30).frame(maxWidth: .infinity)
        .background(DS.fill, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
    .buttonStyle(.plain)
  }
}

/// Two-way segmented control, as on the pairing page.
struct Segmented: View {
  var options: [String]
  @Binding var selection: Int
  var body: some View {
    HStack(spacing: 0) {
      ForEach(options.indices, id: \.self) { i in
        let on = i == selection
        Button { withAnimation(.easeOut(duration: 0.15)) { selection = i } } label: {
          Text(options[i]).font(.ui(11)).foregroundStyle(DS.ink)
            .frame(maxWidth: .infinity).frame(height: 22)
            .background(on ? DS.segmentOn : .clear, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
            .shadow(color: on ? .black.opacity(0.15) : .clear, radius: 1, y: 1)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(2)
    .background(DS.segment, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
  }
}

/// The 16 pt checkbox on the add page.
struct Checkbox: View {
  var isOn: Bool
  var body: some View {
    ZStack {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .fill(isOn ? DS.accent : .clear)
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .stroke(isOn ? DS.accent : DS.checkOff, lineWidth: 1.5)
      if isOn {
        Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
      }
    }
    .frame(width: 16, height: 16)
  }
}

/// An agent's mark: Codex is a template drawn in the text colour, Claude keeps its orange.
struct AgentLogo: View {
  var agent: AgentKind
  var size: CGFloat
  var color: Color = DS.ink
  var body: some View {
    switch agent {
    case .codex:
      Image("CodexLogo").renderingMode(.template).resizable().scaledToFit().foregroundStyle(color).frame(width: size, height: size)
    case .claudeCode:
      Image("ClaudeLogo").renderingMode(.original).resizable().scaledToFit().frame(width: size, height: size)
    }
  }
}

/// A small icon button in the footer.
struct FooterIcon: View {
  var symbol: String
  var size: CGFloat = 14
  var color: Color = DS.ink
  var help: String
  var action: () -> Void
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: size, weight: .medium)).foregroundStyle(color)
        .frame(width: 22, height: 22).contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .help(help)
    .accessibilityLabel(help)
  }
}

/// The dot that pulses next to "等待连接".
struct PulsingDot: View {
  var color: Color
  @State private var dim = false
  var body: some View {
    Circle().fill(color).frame(width: 6, height: 6).opacity(dim ? 0.35 : 1)
      .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) { dim = true } }
  }
}

/// A scroll view that is as tall as its content until the cap, then scrolls. The panel is
/// content-sized (the design's `max-height: 590px; overflow: hidden`), and a plain
/// ScrollView inside a self-sizing hosting view has no height of its own. Until the content
/// has been measured it takes whatever height is proposed (the window's current height), so
/// a page switch never collapses the panel first.
struct FittingScrollView<Content: View>: View {
  var maxHeight: CGFloat
  @ViewBuilder var content: Content
  @State private var contentHeight: CGFloat?

  var body: some View {
    let scroll = ScrollView(.vertical) {
      content
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { h in
          if ProcessInfo.processInfo.arguments.contains("--trace") { NSLog("fitting: content %.0f (max %.0f)", h, maxHeight) }
          contentHeight = h
        }
    }
    .scrollIndicators(.automatic)
    // A `maxHeight` frame is flexible and would swallow whatever height the window has, so
    // it is only used until the content has been measured.
    if let contentHeight {
      scroll.frame(height: min(contentHeight, maxHeight))
    } else {
      scroll.frame(maxHeight: maxHeight)
    }
  }
}
