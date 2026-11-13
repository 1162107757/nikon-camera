# 214 本地测试版集成记录

214 Android 与 iOS 均已完成本轮构建验收，可用于本地测试；未部署、上传草稿或公开发布。最终源码为 `2bc961163542d5189b0470a48df7c8300220722e`，文件与摘要见 [安装包记录](../../../../dist/migration214/ARTIFACTS.json)。最新的人像入口合并与修补手势另以 215 交付，214 二进制保留作对照。

## 已完成的核心验证

- [JVM 实际执行日志](core/jvm.log)：1359 项共享边界、6 项氛围检查通过；原 NCP、本地调节和 RAW 兼容检查同次通过，详见日志。
- [同次核心结果](core/golden.json)：供 Apple 端同源结果逐项比对。
- [原生综合场景静态分析](core/fixture-analyze.log)：无问题。
- 核心实现提交：`a4fc43a`、`841165d`、`26023e4`、`85fc39a`。包含肤色 RGB 与强度、多人和全图范围迁移、每人身体皮肤蒙版、原补选擦除笔触、区域人像事务、自动祛痘候选及确认应用、个人色卡持久化、原蒙版与点按选脸、独立背景保护。
- `beforeBody` 仅返回用于定位的暂存预览副本；不保存草稿。
- 原项目冻结校验仍为 420 项：8 项已批准修复，412 项原文件保持不变。
- [Android 实际 Flutter／原生综合场景](android/native-pipeline.log)通过 1 个完整场景；[首轮色卡断言问题](android/native-pipeline-first-failure.log)保留。最终两份 APK 已核对包名、214 版本号、原签名、单 ABI、ZIP 16 KiB 与各 8 个 ELF LOAD 对齐，见 [验签与对齐](android-signing-alignment.json)。
- 最终 x64 混淆 Release 实际通过 [54 项运行检查](android/release-runtime.log)，混淆字段从该包同次 mapping 提取，并核验原始 instrumentation 成功码。[页面操作与原文件保护](android/release-ui.json)保留各次真实源版本，不把早期截图改写为最终 APK 截图。
- [最终完整 Apple CI](https://github.com/1162107757/nikon-camera/actions/runs/43388505094) / `2bc9611` 成功，源码与最终两份 Android APK 一致；[319 项 Flutter 测试](apple/flutter-tests.log)、[CI 记录](apple/ci-result.json)、[核心逐项对比](apple/core-parity.json)均通过。
- [实际 iOS 原生综合场景](apple/simulator-result.json)通过，覆盖真实人像模型与 RAW / JPEG；同次头像 38 项、无线协议 24 项及 PhotoKit XCTest 通过。最终 [未签名设备 IPA 独立核验](apple/independent-verification.json)通过：arm64、最低 iOS 16、214 构建号、原字体与模型、原生框架、无应用签名或 provisioning profile。
- [Mac 全量首次记录](apple-attempts/43382906163-flutter-tests.log)为 311 通过、3 失败；[更早 iOS 原生记录](apple-attempts/43378774156-simulator-result.json)在 RAW 内嵌 JPEG EXIF 方向检查失败。历史失败保留，修复后保持原断言，由最终完整 CI 证明通过；早期隔离候选 IPA 不作为最终交付。

## 仍需对应设备或外部配置

- 最新的人像入口合并、修补双指导航及画笔大小预览以 215 单独构建验收，不覆盖本轮二进制。
- 相机、iPhone、16 KiB Android 实体设备仍需实际测试；模拟器和静态对齐不能替代这些验证。
- QQ 新包登记尚未核实，iOS Universal Link 用户明确尚未配置，不能认定真实 QQ 登录已通过。

诊断失败、未完成的 Windows 测试及候选 IPA 不作为交付验收通过记录。原始 213 记录继续保留，不改写为 214 结果。
