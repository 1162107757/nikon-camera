# iOS 自签名首包 · 2026-11-08

用户明确要求先生成 IPA，由其自行签名，并确认没有 Mac。此交付使用现有私有 GitHub 仓库的独立 `codex/ios-unsigned-*` 分支和 macOS Actions；未提交到默认分支，未改安卓安装包、线上网站、更新后台或下载预算。

交付文件为 `dist/Huevia-0.1.0-ios-unsigned.ipa`。版本 **0.1.0 / build 4**，最低 iOS 16，设备架构 arm64。无 Mach-O 签名、无描述文件，需要使用者自行签名后安装。最终字节数、SHA-256、精确源代码提交、编译回执及验证范围见 [summary.json](summary.json) 和 [final/ipa-verification.json](final/ipa-verification.json)。

这是独立的精简 iPhone 原生首包，提供真实在线预设库、摘要校验下载、本地 NCP／NP3 添加/保存/分享，以及针对 Z6II 的 Wi-Fi 槽位读取和严格 NCP 0100 子集的兼容导入。NP3 结构解析和 NP3 相机写入、照片调色、RAW、USB 不在此包范围。相机写入须用户选择槽位并确认；覆盖前两次核对原数据，写入后精确读回，不确定结果不自动重试。

最终验证：

- 云端纯 Swift 核心 7 项测试通过：数据边界、格式转换、相机范围、槽位变化拒绝、读回核对和不确定写入拒绝重试。测试相机是脚本夹具。
- 真正 `iphoneos` 设备包编译成功，Windows 端再次校验 ZIP CRC、ARM64 Mach-O、iOS 平台、Info.plist、照片资源及无签名/描述文件；不是模拟器 App 改扩展名。
- 真正 iPhone 模拟器执行五个页面启动和截图，包含浅色、深色/大字体、预设详情、相机和设置；10 张摄影资源逐一通过 iOS UIImage 解码检查。截图与审阅结论单独保存。
- 当前线上预设文件实际 HTTP 200、638 字节、SHA-256 与目录一致；不据此声称相机导入实测通过。
- 用户自行签名、实体 iPhone 安装及实体相机 Wi-Fi 导入尚未验证，留待安装后复测。

历史构建 1/2/3 及其截图保留，未作为最终交付：先后发现图片资源查找失败、暗色强调色与字段标识问题，以及图片加载后触发的网格宽度回归。最终使用标准 iOS imageset 编译资源和受列宽约束的图片布局；旧报告 `review.md`、`verdict.md`、`verdict-final.md` 按历史保留，最终交付判定另存。

构建入口：[ios/README.md](../../../ios/README.md)。原生设计事实限定记录在 `ios/DESIGN.md`，不覆盖现有 Android 设计规范。本包没有加入 TestFlight、App Store 或官网公开下载。
