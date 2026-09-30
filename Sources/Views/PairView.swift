import CoreImage.CIFilterBuiltins
import LuciControlCore
import SwiftUI

/// "连接手机": the QR code or the short code, the claim confirmation, and the done page.
struct PairView: View {
  @Environment(PanelModel.self) private var model

  var body: some View {
    @Bindable var model = model
    VStack(spacing: 0) {
      BackHeader(title: "连接手机") { model.pairing = .idle; model.page = .home }
      switch model.pairing {
      case .waiting(let code, let payload, let expiresAt):
        VStack(spacing: 18) {
          Segmented(options: ["扫描二维码", "输入短码"], selection: $model.pairMode)
          if model.pairMode == 0 {
            QRCodeView(payload: payload).frame(width: 150, height: 150).padding(10)
              .background(DS.qrBackground, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            instructions("在 iPhone 上打开 Luci Run，进入 Agent →「我的设备」\n→「连接一台电脑」，对准二维码扫描")
          } else {
            HStack(spacing: 6) {
              ForEach(Array(code.enumerated()), id: \.offset) { i, ch in
                if i == 3 { Spacer().frame(width: 6) }
                Text(String(ch)).font(.mono(21)).foregroundStyle(DS.ink)
                  .frame(width: 36, height: 44)
                  .background(DS.fill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
              }
            }
            .padding(.top, 18).padding(.bottom, 6)
            instructions("在 iPhone 上打开 Luci Run，进入 Agent →「我的设备」\n→「连接一台电脑」，输入上面的 6 位短码")
          }
          HStack(spacing: 6) {
            PulsingDot(color: DS.accent)
            Text("等待连接 · \(Format.countdown(until: expiresAt, now: model.now)) 后过期 · ").font(.ui(10.5)).foregroundStyle(DS.ink2)
              + Text("刷新").font(.ui(10.5)).foregroundStyle(DS.accentText)
          }
          .onTapGesture { model.startPairing() }
          if model.isDemo {
            Button("（演示：模拟手机已连接）") { model.simulateClaim() }
              .buttonStyle(.plain).font(.ui(10)).foregroundStyle(DS.ink2).opacity(0.7).underline()
          }
        }
        .padding(EdgeInsets(top: 10, leading: DS.side, bottom: 20, trailing: DS.side))
      case .claimed(_, let user, let device):
        VStack(spacing: 12) {
          Image(systemName: "person.badge.shield.checkmark").font(.system(size: 22, weight: .medium)).foregroundStyle(DS.accentText)
            .frame(width: 44, height: 44).background(DS.accentFill, in: Circle())
          VStack(spacing: 4) {
            Text("\(user) 的手机要连接这台 Mac").font(.ui(12)).foregroundStyle(DS.ink)
            Text("\(device) · 之后它能看到并操作共享目录里的会话。是你吗？").font(.ui(10.5)).foregroundStyle(DS.ink2)
              .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
          }
          HStack(spacing: 8) {
            SecondaryButton(title: "不是我") { model.confirmPairing(accept: false) }.frame(width: 100)
            PrimaryButton(title: "确认连接") { model.confirmPairing(accept: true) }.frame(width: 140)
          }
          .padding(.top, 4)
        }
        .padding(EdgeInsets(top: 28, leading: DS.side, bottom: 24, trailing: DS.side))
        .frame(maxWidth: .infinity)
      case .done(let user, let device):
        VStack(spacing: 12) {
          Image(systemName: "checkmark").font(.system(size: 18, weight: .semibold)).foregroundStyle(DS.accentText)
            .frame(width: 44, height: 44).background(DS.accentFill, in: Circle())
          VStack(spacing: 4) {
            Text("已连接 \(user) 的 \(device)").font(.ui(12)).foregroundStyle(DS.ink)
            Text("经中继转发 · 端到端加密").font(.ui(10.5)).foregroundStyle(DS.ink2)
          }
          PrimaryButton(title: "完成") { model.finishPairing() }.frame(width: 96).padding(.top, 4)
        }
        .padding(EdgeInsets(top: 28, leading: DS.side, bottom: 24, trailing: DS.side))
        .frame(maxWidth: .infinity)
      case .failed(let msg):
        VStack(spacing: 12) {
          Text(msg).font(.ui(10.5)).foregroundStyle(DS.ink2).multilineTextAlignment(.center)
          PrimaryButton(title: "重试") { model.startPairing() }.frame(width: 96)
        }
        .padding(EdgeInsets(top: 28, leading: DS.side, bottom: 24, trailing: DS.side))
      case .idle:
        VStack(spacing: 12) {
          Text("正在准备连接码…").font(.ui(10.5)).foregroundStyle(DS.ink2)
        }
        .padding(24)
        .onAppear { model.startPairing() }
      }
    }
  }

  private func instructions(_ text: String) -> some View {
    Text(text).font(.ui(10.5)).lineSpacing(4).foregroundStyle(DS.ink2).multilineTextAlignment(.center)
  }
}

/// The pairing payload as a QR code, drawn crisp at any size.
struct QRCodeView: View {
  var payload: String
  var body: some View {
    if let image = Self.render(payload) {
      Image(nsImage: image).resizable().interpolation(.none).scaledToFit()
    } else {
      Color.gray
    }
  }

  static func render(_ text: String) -> NSImage? {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = "M"
    guard let ci = filter.outputImage else { return nil }
    let scaled = ci.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
    let rep = NSCIImageRep(ciImage: scaled)
    let image = NSImage(size: rep.size)
    image.addRepresentation(rep)
    return image
  }
}
