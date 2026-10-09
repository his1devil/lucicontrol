import LuciControlCore
import SwiftUI

/// "设备": the phones on the roster, each with a switch; removed ones can be restored.
struct DevicesView: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    VStack(spacing: 0) {
      BackHeader(title: "设备") { model.page = model.devicesReturnPage }
      VStack(alignment: .leading, spacing: 18) {
        if !model.macOnline {
          // The roster is only as fresh as this Mac's own link; say so instead of showing
          // whatever it was when the link went.
          Text(macOfflineNote).font(.ui(10.5)).foregroundStyle(DS.ink2).fixedSize(horizontal: false, vertical: true)
        }
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
                // Removed means blocked; one the daemon has not blocked yet is being re-blocked.
                if !d.blocked {
                  Text("正在禁用访问…").font(.ui(10.5)).foregroundStyle(DS.waitingText)
                }
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
    // Pushes only say what changed; the page asks for the whole roster when it opens.
    .task { model.refreshDevices() }
  }

  private var macOfflineNote: String {
    switch model.sharing {
    case .paused: "共享已暂停，手机现在连不上这台 Mac。恢复共享后这里才有它们的实际状态。"
    case .unpaired: "这台 Mac 还没连接手机。"
    default: "这台 Mac 还没连上中继（\(model.sharing.label)），连上后这里才有手机的实际状态。"
    }
  }
}

struct DeviceRow: View {
  @Environment(PanelModel.self) private var model
  var device: Device

  var body: some View {
    let on = !device.blocked
    let presence = DevicePresence(device, macOnline: model.macOnline)
    let online = presence == .connected || presence == .onlineElsewhere
    HStack(spacing: 12) {
      StatusBar(color: online ? DS.online : DS.offline)
      VStack(alignment: .leading, spacing: 3) {
        Text(device.label).font(.ui(12)).foregroundStyle(on ? DS.ink : DS.inkOff)
        Text(Format.deviceSubtitle(device, macOnline: model.macOnline)).font(.ui(10.5)).foregroundStyle(DS.ink2).lineLimit(1)
      }
      Spacer(minLength: 8)
      PillToggle(isOn: on) { model.toggleDeviceBlocked(device.id) }
    }
    .fixedSize(horizontal: false, vertical: true)
    .contentShape(Rectangle())
    // The relay pings phones every 25 s and gives up on one after 70 s of silence.
    .help(online ? "手机锁屏或断网后，最多约一分钟才会显示离线" : "")
    .contextMenu {
      Button("移除设备") { model.removeDevice(device.id) }
    }
  }
}
