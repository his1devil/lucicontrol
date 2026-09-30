import LuciControlCore
import SwiftUI

/// "设备": the phones on the roster, each with a switch; removed ones can be restored.
struct DevicesView: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      BackHeader(title: "设备") { model.page = .settings }
      VStack(alignment: .leading, spacing: 18) {
        ForEach(model.visibleDevices) { d in
          DeviceRow(device: d)
        }
        Text("用同一个 Luci Run 账号登录的手机会自动出现在这里。").font(.ui(10.5)).foregroundStyle(DS.ink2)
        if !model.removedDevices.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            SectionLabel(text: "已移除的设备")
            ForEach(model.removedDevices) { d in
              HStack(spacing: 8) {
                Text(d.label).font(.ui(11.5)).foregroundStyle(DS.inkOff)
                Spacer()
                Button("恢复") { model.restoreDevice(d.id) }.buttonStyle(.plain).font(.ui(11)).foregroundStyle(DS.accentText)
              }
            }
          }
          .padding(.top, 4)
        }
      }
      .padding(EdgeInsets(top: 6, leading: DS.side, bottom: 22, trailing: DS.side))
    }
  }
}

struct DeviceRow: View {
  @Environment(PanelModel.self) private var model
  var device: Device

  var body: some View {
    let on = !device.blocked
    HStack(spacing: 12) {
      StatusBar(color: device.online ? DS.online : DS.offline)
      VStack(alignment: .leading, spacing: 3) {
        Text(device.label).font(.ui(12)).foregroundStyle(on ? DS.ink : DS.inkOff)
        Text(subtitle).font(.ui(10.5)).foregroundStyle(DS.ink2).lineLimit(1)
      }
      Spacer(minLength: 8)
      PillToggle(isOn: on) { model.toggleDeviceBlocked(device.id) }
    }
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(Rectangle())
    .contextMenu {
      Button("移除设备") { model.removeDevice(device.id) }
    }
  }

  private var subtitle: String {
    var parts: [String] = []
    parts.append(device.online ? "在线" : "离线")
    if !device.isOwner { parts.append("共享给 \(device.user)") }
    if device.blocked {
      parts.append("已禁用访问")
    } else if device.online, device.watching > 0 {
      parts.append("正在看 \(device.watching) 个会话")
    }
    return parts.joined(separator: " · ")
  }
}
