# Huevia 跨端开发版 214 · 本地测试

**最终 `2bc9611` 的 Android 两份 APK 与 iOS 未签名 IPA 已通过本轮本地测试门禁。** Android 可安装测试；iOS 需用户自行签名后安装测试。

| 平台 | 实际附件 | 大小 |
| --- | --- | --- |
| Android ARM64 手机 | [214 ARM64 APK](huevia-0.31.0-dev-214-android-arm64.apk) | 52,510,514 字节 |
| Android x64 测试环境 | [214 x64 APK](huevia-0.31.0-dev-214-android-x64.apk) | 55,881,946 字节 |
| iPhone 自签测试 | [214 未签名 IPA](huevia-0.31.0-dev-214-ios-unsigned.ipa) | 64,774,297 字节 |

Android 版本为 `0.31.0-dev / 214`，iOS 为 `0.31.0 / 214`，包名均为 `cc.huevia.next`。三份实际文件大小与 SHA-256 已和 [ARTIFACTS.json](ARTIFACTS.json)核对，构建来源为 `2bc961163542d5189b0470a48df7c8300220722e`。Android 已接受本地测试，IPA 已接受本地自签测试。同包名的 214 会覆盖已有 next 版本；原 `cc.huevia` 应用、[213 对照包](../migration213/README.md)、194 与旧版导出 ZIP 均保留，不需要卸载旧应用。

本轮按原 Android 继续还原人像入口、更多菜单七项、选区刷、自然精修、自动祛痘候选、逐人全身肤色、二维光源、塑形范围和确认 / 取消 / 撤销。原四项需求及其余十一类功能继续保留；详细入口、测试步骤和设备条件见 [214 本地测试说明](../../docs/migration/local-testing-214.md)。

本轮 Android 已取得的证据：

- 两份 APK 验签通过，每 ABI 的 8 个 ELF 均通过 16 KiB 静态对齐检查：[签名与对齐记录](../../docs/migration/validation/features-214/android-signing-alignment.json)。
- 正式 R8 包实际运行 54 项通过，覆盖真实五官 / 皮肤分析、渲染、修补、取消和 RAW JNI 回调：[运行日志](../../docs/migration/validation/features-214/android/release-runtime.log)、[结果](../../docs/migration/validation/features-214/android/release-runtime.json)。运行环境为 API 31、4096 字节页的模拟器。
- 最终源码的原式界面 12 项、取消流程 5 项定向检查通过，记录见 [ARTIFACTS.json 的 androidUiGate](ARTIFACTS.json)。
- **4 KiB 页模拟器测试和 16 KiB 静态对齐不等于 16 KiB 实体设备实测。** ARM64 手机、实体相机、未知 NEF 机型与系统权限仍按指南继续测试。最终人像 / 塑形界面截图由主任务核对后补入，不以候选截图代替结果。

iOS 最终 CI `43388505094 / 2bc9611` 已通过 Flutter 319 项、共享核心 1359 项及跨端一致性检查、原生流水线 1 项和 PhotoKit XCTest。实际 IPA 已独立核对大小与摘要，SHA-256 为 `ec7d38f942bc073e9b43e95ad39fc073a73ca249c11072381fee792820157180`。它是 iOS 16.0 起的未签名设备包，需用户自行签名，不能直接安装；自签与 iPhone 实机检查仍需完成。

旧 Android 资料迁出继续使用同签名的 [194 维护包](../migration213/huevia-0.30.34-legacy-export-194.apk)。它保留原入口并新增“旧版资料迁出”；保存 ZIP 后，在新版“设置 → 旧版资料迁入”预检、核对并迁入，可撤回本次迁入。旧应用、ZIP 和 213 / 194 基线均保留，不清数据来绕过安装失败。

QQ Android 腾讯登记尚未核实保存生效；iOS Universal Link 仍未配置，真实 QQ 登录不标为已验收。实体相机、iPhone、自签安装与 16 KiB 设备仍需分别验证。

用户已明确“暂不发布，我先测试”：本轮仅本地交付，不执行生产数据库 / IAM / 函数部署，不上传草稿，不公开发布，也不继续上线前登录或远程会话核对。新版更新分发接口尚未上线。
