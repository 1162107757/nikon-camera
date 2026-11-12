# Huevia 跨平台开发构建 206

源码：`1d69c6eeab6c5575a4b09b461329ff3082878589`。恢复原局部画笔、径向、渐变与取样修复工具，并修复边框弹窗配色、选择项高度和多层遮罩。原工程与旧包保留。

| 文件 | 平台 | 字节数 |
| --- | --- | ---: |
| `huevia-0.31.0-dev-206-android-arm64.apk` | 安卓 ARM64，最低 Android 8 / API 26，开发签名 | 50979878 |
| `huevia-0.31.0-dev-206-android-x64.apk` | 安卓 x86_64，模拟器实测 | 54285774 |
| `huevia-0.31.0-dev-206-ios-unsigned.ipa` | iPhoneOS ARM64，最低 iOS 16，未签名供自签 | 29381442 |

完整校验值、编译来源和原生库对齐结果见 [build-evidence.json](build-evidence.json)，IPA 独立核验见 [ios-build-evidence.json](ios-build-evidence.json)。二进制仅保存在本机，不纳入 Git。

Android 62 个界面场景、82 项原生媒体检查、原生图像流程和 JVM 446 项检查通过；Apple 137 项 Flutter、446 项共享、38 项原生头像和实际图像/RAW/导出流程通过。详见[冻结验证记录](../../docs/migration/validation/local-tools-border-206/README.md)。

完整迁移与所有样式组合尚未验收；原版导出设置等剩余内容正在 207 继续实现。荣耀 Magic 实机、用户 NEF 和 iPhone 自签安装仍需实测。
