# Huevia 跨端开发版 215 · Android 本地测试

**215 Android 两份 APK 与未签名 iOS IPA 已完成本轮构建验收，可用于本地测试。** 实际文件、大小、SHA-256 和源码记录见 [ARTIFACTS.json](ARTIFACTS.json)，三份文件均来源于 `950926c408f81d27db7fa46fb6335579d0459c4c`。随后提出的候选瑕疵定位、完整三点菜单及调节图标另以 216 交付，215 文件保留。

本轮重点为人像中的修补操作：照片编辑器点击「人像」直接进入原式工作区，工具顺序为「皮肤 / 面部 / 塑形 / 自然精修 / 修补」；单指只绘当前笔，第二指立即取消整条未提交路径并转为双指缩放 / 移动。剩下一指不能补画或提交，所有手指抬起后的新手势才可继续。

「画笔大小」调节显示与当前照片共用坐标、缩放比例的圆环，结束调节后收起；预览不产生修补。修补子页确认后保留已有肤色、人脸与其他编辑，并作为一次父人像撤销；取消不改进入前的状态。具体入口、双指与旋转回归、大小预览、确认 / 取消和平台条件见 [215 本地测试说明](../../docs/migration/local-testing-215.md)。

| 平台 | 实际附件 | 当前状态 |
| --- | --- | --- |
| Android ARM64 手机 | [215 ARM64 APK](huevia-0.31.0-dev-215-android-arm64.apk)，52,444,978 字节 | 可本地安装测试 |
| Android x64 测试环境 | [215 x64 APK](huevia-0.31.0-dev-215-android-x64.apk)，55,881,946 字节 | 可本地测试；不替代 ARM64 手机或 16 KiB 设备实测 |
| iPhone 自签分发 | [215 未签名 IPA](huevia-0.31.0-dev-215-ios-unsigned.ipa)，64,765,153 字节 | iOS 16 起，安装时自行签名；尚未作 iPhone 实机安装验收 |

Android 版本为 `0.31.0-dev / 215`，包名 `cc.huevia.next`，签名与既有 next 版本一致。两 ABI 均验签通过，每 ABI 的 8 个 ELF 均通过 16 KiB 静态对齐：[签名与对齐记录](../../docs/migration/validation/features-215/android-signing-alignment.json)。安装会覆盖已有 next 版本，请先保留重要测试资料；原应用与 214 对照包继续保留。

最终 x64 R8 包在 API 31、4096 字节页模拟器实际运行 54 项通过，已安装 APK 摘要等于此处附件。实际屏幕核对了人像直进、同排修补、大小调节圆环显示 / 收起、只调大小后照片区域全部像素不变、单笔修补 / 撤销 / 重做、子页和父页取消，测试原图摘要保持不变：[运行结果](../../docs/migration/validation/features-215/android/release-runtime-result.json)、[屏幕检查记录](../../docs/migration/validation/features-215/android/release-ui.json)。双指及跨控件残指行为已有定向指针测试，尚未作实体设备多点触控验收。

本轮定向组件 / 入口测试的实际结果见 [本地记录](../../docs/migration/validation/features-215/flutter/local-results.json)。Windows 完整 25 项工作区测试因宿主访问冲突未完成，未记为通过；随后同源 Mac 全量 350 项通过，实际 iOS 原生综合场景及 PhotoKit XCTest 通过，见 [CI 收据](../../docs/migration/validation/features-215/apple/ci-result.json)。[IPA 独立核验](../../docs/migration/validation/features-215/apple/independent-verification.json)确认 arm64、215 构建号、无应用签名或 provisioning profile、原模型/字体与原生框架完整。

214 源码记录、二进制与旧基线保留，现有可用状态见 [214 目录](../migration214/README.md)；原四项需求与十一类功能继续回归。实体相机、iPhone、USB / Wi-Fi、相机槽位与遥控能力、未知 NEF、存储权限仍需实际设备核对。4 KiB 模拟器通过或 16 KiB 静态对齐不等于 16 KiB 实机通过。

QQ Android 登记尚未核实保存生效；iOS Universal Link 尚未配置，真实 QQ 登录不标为已验收。本轮仅本地测试，生产部署、草稿上传及公开发布继续暂缓，后续须有新的明确指示。
