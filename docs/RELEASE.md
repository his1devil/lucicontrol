# LuciControl 发布与更新

更新时间：2026-10-07。当前公开分发版本 0.1.1 (3)，macOS 14+，Universal（arm64 / x86_64）。

## 本机修复候选版 0.1.2 (5)

2026-10-09 准备的本机候选进一步修复了确认框被主面板遮挡的问题，包含面板透明圆角修复，以及会话/共享目录的可见移除按钮。具体说明见 `docs/releases/0.1.2.html`，验证记录见 `docs/TESTING.md`。App 与 DMG 已通过 Developer ID 签名、Apple 公证、staple 和 Gatekeeper；7 个 Mach-O 均含两种架构，更新 ZIP 的 Ed25519 签名独立验证通过。产物与 `validation.json` 在 `build/releases/0.1.2-5/`，来源记录如实保留未提交工作树标记。本轮尚未发布到下载服务器、GitHub 或正式 appcast，也未替换正在运行的 `/Applications/LuciControl.app`；上述 0.1.1 仍为公开版本。

## 分发边界

LuciControl.app 包含 lucirund，Sparkle 2.10.0 升级整个 App。手机配对、身份、共享目录保存在 `~/Library/Application Support/lucirund`，安装脚本和更新器不删除该目录。旧 CLI LaunchAgent 需要经过 App 的接管流程，不能同时运行两套 daemon。

主更新源固定为 `https://im.zhanghuanyang.com/lucirund/dist/appcast.xml`。版本文件先部署到同一下载站，再原子替换 appcast。正式下载站已发布 0.1.1 (3)，公开 DMG 与 ZIP 完整下载后的 SHA256 与本机一致；线上 appcast 返回 200、`application/xml` 与 `no-cache, max-age=0, must-revalidate`，版本、大小和 Ed25519 签名核对通过。维护者已授权公开源码与版本标签；[GitHub Release v0.1.1](https://github.com/his1devil/lucicontrol/releases/tag/v0.1.1) 已发布，使用与主下载站完全相同的签名包，匿名完整下载后的 SHA256 核对通过。客户端没有自动切换镜像；国内、海外网络质量仍需分别实测。

首次安装用 DMG，将 App 拖入 Applications。安装窗口参考 `yptd-desktop`：白底、600 × 380 点窗口、左右 120 点图标，紫色弧形箭头像笑脸并指向 Applications；顶部提供中英双语拖拽提示。Applications 是指向系统应用目录的真实快捷入口，背景包含 1x / 2x 分辨率。已经安装的 0.1.0 没有 Sparkle，需要先手动安装一次新版本，后续才能收到自动更新。手机继续使用 Luci Run 内部 TestFlight；这份 Mac 包不走 TestFlight。

## 已实现行为

- Sparkle 负责检查、下载、验证更新签名、替换、重启；设置与 Sparkle 持久化选项同步。
- 默认每天检查，自动下载默认关闭。用户打开自动下载后，下载完成等待退出安装，不主动结束会话。
- 手动安装时，daemon 尚未就绪、会话运行中、或等待批准/答复，暂缓重启；结束会话后在设置中重试安装。
- 更新重启与普通退出共用等待 daemon 停止的流程，避免新旧 daemon 并存；正常更新无需重复确认退出。
- 检查失败显示错误，未检查时不显示“已是最新版本”。下载进度由 Sparkle 窗口显示，面板不再伪造 45%。
- Codex 未安装或未登录的首次启动，完成安装/登录后继续手机配对；取消配对后不会被重复强制打开。
- `--demo`、`--data-dir` 和单元测试宿主不连接正式更新源。

## 本机签名材料

- Developer ID Application: Antai Feng (M7ZSWL69E9)
- notarytool Keychain profile: `lucicontrol-notary`（已验证成功）
- Sparkle Keychain account: `com.his1devil.lucicontrol`
- 客户端公钥：`Xv/Qaiz9k+0HaC2Lv5kL4QOMZiz8hpubsN9cIWIupvU=`

私钥只保存在钥匙串，未导出、未写入仓库或发布服务器。应由维护者通过受控渠道备份；不要重新生成来替换丢失的现有更新密钥。首次 `generate_appcast` / `sign_update` 使用可能需要本人在系统钥匙串对话框授权，密码不进入聊天或脚本。

## 准备候选包

安装 Xcode、XcodeGen、Go 和 Python 3.10+（DMG 依赖要求），保留相邻 `../lucirund` 源码。从 [Sparkle 官方 2.10.0 发布](https://github.com/sparkle-project/Sparkle/releases/tag/2.10.0) 下载发布工具，指定 `bin` 路径。

DMG 布局使用独立 Python 虚拟环境，依赖版本固定在 `scripts/dmg/requirements.txt`；AppKit、CoreServices、`tiffutil` 和 `hdiutil` 使用 macOS 自带工具链。先准备打包依赖：

```sh
python3 -m venv build/dmg-venv
build/dmg-venv/bin/python -m pip install -r scripts/dmg/requirements.txt
export DMG_PYTHON="$PWD/build/dmg-venv/bin/python"
```

随后验证并构建：

```sh
swift test
xcodegen generate
xcodebuild -project LuciControl.xcodeproj -scheme LuciControl -configuration Debug \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath DerivedData \
  CODE_SIGN_IDENTITY=- ONLY_ACTIVE_ARCH=YES test
SPARKLE_TOOLS=/path/to/Sparkle/bin scripts/release.sh
```

正式发布默认要求 App 和 daemon 工作树干净。本地候选验证可显式设置 `ALLOW_DIRTY=1`，产物 `source.json` 会标记 dirty，不能将其描述为已经打 tag 的提交产物。每次构建使用唯一且递增的 `RELEASE_BUILD`，脚本拒绝覆盖已有输出目录。`RELEASE_VERSION`、`RELEASE_BUILD` 必须与准备发布的版本一致；默认值为 0.1.2 / 5。

脚本执行 Archive / Developer ID Export，检查包内每个 Mach-O 的两种架构、签名、Hardened Runtime 和时间戳，提交 Apple 公证，staple App 和 DMG，验证 Gatekeeper，生成携带更新包 Ed25519 签名的清单。构建过程保留公证结果 JSON、日志和来源记录。签名失败立即终止。

`scripts/build-dmg.sh` 自动绘制背景、创建 Applications 链接并写入卷内 Finder 布局；背景引用由 macOS 原生 alias/bookmark API 生成，不需要控制 Finder，也不需要 AppleScript 自动化授权。参考实现为相邻 `yptd-desktop/scripts/make-dmg-background.py` 与 `electron-builder.yml` 的 DMG 配置。必须先完成布局和压缩，再依次签名、公证、staple、验证；签名后不能重新编辑镜像内容。

输出在 `build/releases/<version>-<build>/`：

- `downloads/LuciControl-<version>-<build>-universal.dmg`：首次安装。
- `updates/LuciControl-<version>-<build>.zip`：Sparkle 更新包，包含 stapled App。
- `updates/appcast.xml`：更新清单。
- `SHA256SUMS`：两种下载文件的校验值；它不能替代 Ed25519 签名。
- `export/LuciControl.app`：最终 App。

脚本只准备本机产物，并向 Apple 提交公证；不上传服务器或 GitHub。

## 公开下载（2026-10-07）

- [安装包：LuciControl 0.1.1 (3) Universal DMG](https://im.zhanghuanyang.com/lucirund/dist/LuciControl-0.1.1-3-universal.dmg)
- [更新包 ZIP](https://im.zhanghuanyang.com/lucirund/dist/LuciControl-0.1.1-3.zip)
- [GitHub 备用下载](https://github.com/his1devil/lucicontrol/releases/download/v0.1.1/LuciControl-0.1.1-3-universal.dmg)
- [SHA256 校验文件](https://im.zhanghuanyang.com/lucirund/dist/LuciControl-0.1.1-3.sha256)
- [自动更新清单](https://im.zhanghuanyang.com/lucirund/dist/appcast.xml)

已按维护者的公开分发指令发布现有签名候选包，尚未完成的设备验收见下文。`build/releases/0.1.1-3/publication.json` 保留公开下载校验记录；原 `source.json` 仍如实标记工作树构建；源码随后随 `v0.1.1` 标签归档，安装包不因此重新构建。

服务器先将 DMG/ZIP/版本化 `.sha256` 发布为不可变文件，再原子启用 appcast；现有 CLI 的 `SHA256SUMS` 与二进制未改动。nginx 为 appcast 增加精确路由，修正 XML 类型并要求重新验证缓存，仅做平滑重载；中继 PID 未变化，健康检查通过。配置备份：`/etc/nginx/conf.d/im.zhanghuanyang.com.conf.bak-lucicontrol-20261007-234517`。

## 本轮验证结果

正式候选包 0.1.1 (3) 的 App / DMG 均已通过公证、staple 和 Gatekeeper；7 个 Mach-O 都包含 arm64 与 x86_64。归档签名用 App 内公钥独立验证通过，修改字节后的签名验证失败。13 项 Core 测试、6 项 App 测试通过。Apple 芯片实际启动通过；本机 x86_64 启动返回 Bad CPU type，因此 Intel 运行仍未验收。

本次只修订首次安装 DMG 外壳，保留 0.1.1 (3) 的 App 与 Sparkle ZIP。已实际通过 Finder 打开验证双语提示、图标、笑脸箭头和 Applications 入口；包内 App 签名与公证票据仍有效，App/daemon 可执行文件和 CodeResources 与原候选包一致。新 DMG 重新通过 Developer ID 签名、Apple 公证、staple 与 Gatekeeper。旧的纯白安装镜像及校验记录保存在候选目录的 `previous-installer/plain/`，不用于分发。

当前 DMG SHA256：`8a3487a5ceb1fd5f5d7c554d844ddc845137127fecb2bad412198f53206fd8c1`。ZIP SHA256 仍为 `4ef7cda20684f20cca53f1a485036e4f5d4b9f8f4976b6a07ad676fdf204f1b0`。

另用独立 bundle ID `com.his1devil.lucicontrol.updatevalidation` 制作了两个 Developer ID 签名并公证的测试副本，复用正式 App 的可执行代码和 Sparkle，仅替换测试 Info.plist、模拟 daemon 与本机更新地址。实际通过 Sparkle UI 验证：

- 被修改的归档遭安装器拒绝，提示 improperly signed，旧版本仍运行。
- 正确包可下载、解压；会话运行中点击安装和重试都保持旧版本，无 daemon shutdown。
- 会话空闲后重试，旧 daemon 收到 shutdown，然后安装目录版本由 1 变 2，新 daemon 自动启动，替换后签名与 Gatekeeper 仍通过。
- 新版本检查显示“已是最新版本”；更新源停止后显示失败和重试，旧 App 保持可用。
- 自动检查、自动下载、更新提示开关在正常退出和重新启动后保留。

详细证据在 `build/releases/0.1.1-3/validation.json` 与 `update-validation/`。这证明隔离环境中的安装链路，不能替代真实 lucirund、手机重连、全新用户配对和 Intel 真机验收。正式下载源现已上线；GitHub Release 及源码标签现已公开。本轮没有替换 `/Applications/LuciControl.app`。

## 后续发布顺序与尚待验收

1. 完成全新用户配对、Intel 真机测试，以及两个正式签名公证版本 N → N+1 的下载、退出、替换、重启、手机重连测试。本机 Rosetta 启动不能替代 Intel 真机。
2. 验证坏签名/损坏包/断网时旧版本可用，登录启动设置与配对身份在更新后保留。签名校验通过并不意味着业务健康检查和自动回滚已实现；目前没有业务级自动回滚。
3. 在服务器先上传不可变版本 ZIP/DMG，回读核对 SHA256，再以同目录临时文件 + rename 原子替换 appcast。XML 用 `application/xml`，feed 不缓存过期版本；不要覆盖旧版本归档。
4. GitHub Releases 上传同一份 DMG/ZIP/校验值作备用。避免把本机日志、凭证、用户配置或私钥包含进去。
5. 分别从中国与海外网络检查证书、清单和完整下载。版本号与 feed 指向必须匹配。

撤回时从 feed 移除有问题版本并保留上一版包。Sparkle 默认不会用较小 build 自动降级；需要修复后发布更大的 build，或指导用户手动恢复已签名旧版本。涉及配置迁移时先验证数据向后兼容。

官方参考：[Apple 公证](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)、[Sparkle 集成](https://sparkle-project.org/documentation/programmatic-setup/)、[发布更新](https://sparkle-project.org/documentation/publishing/)、[菜单栏更新提示](https://sparkle-project.org/documentation/gentle-reminders/)。
