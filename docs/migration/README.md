# 整体跨平台迁移

用户已确认：整体迁移、全部功能对齐安卓、由开发方选择适合的技术路线、iOS 输出供自签的 IPA。现有 Android 和 iOS 原生工程及安装包均保留。

迁移基线：`master` 的 `6fb5003d8be85fcbb0fa3b4d99aef63cc1751f3c`，Android 186 / 0.30.32-beta。工作分支 `codex/cross-platform-migration`，新增工程在 `cross-platform/`。

先验证关键链路，然后逐项迁移和验收。当前状态为进行中；不把界面外壳、未实现入口或脚本相机当作全功能交付。

最新完整验证构建为 [206](../../dist/migration206/README.md)：接入原画笔、径向、渐变与取样修复，修复边框深色弹窗、48dp 选项和上层窗口统一遮罩。三个包对应同一源码；Android 62 个界面场景、82 项原生检查、JVM 446 项，以及 Apple 137 项 Flutter 与实际原生流程通过。[验证记录](validation/local-tools-border-206/README.md)明确列出物理像素取整、真机和其余功能的未验收范围。207 正在继续恢复原快速/完整导出设置和预览返回流程。

候选方案为 Flutter 共享界面，尽量直接复用现有 Java/C++ 核心，平台适配放在边界。现有 NCP 包 46 个类没有 Android API 依赖；能否通过 J2ObjC 在 iOS 使用，以实际构建和像素/格式回归为准。

技术依据：

- [Flutter 原生互操作](https://docs.flutter.dev/interop)：共享界面可调用 Android Java、Apple 系统 API 和 C/C++。
- [J2ObjC](https://developers.google.com/j2objc/)：可将非 UI Java 源码编译为供 iOS 使用的 Objective-C，仍需针对当前核心实际验证。
- [Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore)：提供连接相机的发现、读取及 PTP 命令接口；不据此声称所有相机/iPhone/签名环境均可写入预设。

后续状态、原工程保护清单和验证记录在本目录维护。
