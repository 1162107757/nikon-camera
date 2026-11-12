# Huevia 跨平台开发版 205

生产源码：`494f1d74cc5bfa154962c820f650c727622962d5`。保留原项目，使用独立应用标识 `cc.huevia.next`。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| `huevia-0.31.0-dev-205-android-arm64.apk` | 50,848,806 | `fb21c9c7cda3b4f9a0f538e5aad5337c5dc8d7d52b7a303d8c46269c7facf7d0` |
| `huevia-0.31.0-dev-205-android-x64.apk` | 54,220,238 | `98c75205ebe2cb069d8a74b98242f2a1093c78352617029c51138480e95ece9d` |
| `huevia-0.31.0-dev-205-ios-unsigned.ipa` | 29,358,788 | `8bcb1354df362128210b1a5a91e8f72e0b62781236fe529c1426d74468593164` |

Android 最低 26、目标 35，使用现有开发签名；x64 为模拟器包，ARM64 为手机包。IPA 是最低 iOS 16 的未签名设备包，供自行签名使用。包保存在本机，未强制加入 Git。

本轮恢复原版选区和区域调节，修复临时预览覆盖草稿，并复查边框与导出。Android 58 个界面场景、82 项媒体检查、Apple 120 项 Flutter、436 项共享检查及实际原生图像流程通过。整体迁移、完整像素对齐和实体设备验收仍在继续，详见[验证范围](../../docs/migration/validation/local-selection-205/README.md)及 [build-evidence.json](build-evidence.json)。
