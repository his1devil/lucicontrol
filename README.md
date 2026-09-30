# LuciControl

lucirund 的 macOS 菜单栏 App：决定哪些目录和 Codex 会话对手机（Luci Run）可见，显示会话状态，
完成配对、设备管理和更新。

- 方案：[docs/PLAN.md](docs/PLAN.md)
- 设计稿：`design/LuciControl.dc.html`，渲染图在 `design/reference/`
- 重新渲染设计稿：`python3 design/tools/render.py`（需要 node 和 Google Chrome）
- `design/logos/`：Codex 和 Claude 是设计项目里的正式标志（去掉了内容凭证元数据），另外三个是渲染用的占位图形

相关仓库：`../lucirund`（守护进程和中继）、`../yptd-mobile-app`（手机端和 RemoteWire 包）、`../yptd-serve`（签发设备令牌）。

## 开发

```sh
xcodegen generate                                   # 生成 LuciControl.xcodeproj（不入库）
xcodebuild -project LuciControl.xcodeproj -scheme LuciControl -configuration Debug \
  -derivedDataPath DerivedData build CODE_SIGN_IDENTITY=-
open DerivedData/Build/Products/Debug/LuciControl.app --args --demo   # 菜单栏里跑，用示例数据（试手感用 Release：把 -configuration 换成 Release）
swift test                                          # LuciControlCore 的单测
scripts/snapshots.sh <目录>                          # 各页截图（浅色、深色），用来和 design/reference 对比
scripts/make-icons.sh                               # 从设计稿的 SVG 重新生成 App 图标
```

调试参数：`--demo` 示例数据；`--window` 面板放进普通窗口；`--page home|empty|claude|add|pair|devices|settings|codex-missing`；
`--pair-state code|claimed|done`；`--appearance light|dark`；`--snapshot <png>`；`--open` 启动就打开面板；`--open --profile` 打印打开面板和切换页面的耗时；`--icons <目录>` 输出菜单栏图标的四种状态。

测试参数（接真实守护进程时）：`--test-auto-confirm` 手机认领后自动确认；`--test-add-dir <路径>` 启动后共享这个目录；`--login-item on|off|status` 登记 / 注销 / 查看开机启动；`--snapshot-delay <秒>` 推迟截图。

真实模式下（不带 `--demo`）App 会在自己的包里启动 lucirund。这台 Mac 上如果还装着命令行版的服务，面板会先显示接管页；开发时用 `--data-dir` 指一个隔离目录就不受它影响。
