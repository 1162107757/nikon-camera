# Huevia 跨平台开发包 204

开发包 `cc.huevia.next`，保留原版安装。原账号资料页、复核后上传头像和边框缩略图任务竞争修复已接入。

| 文件 | SHA-256 |
| --- | --- |
| [Android ARM64](huevia-0.31.0-dev-204-android-arm64.apk) | `69a72381651b9b79f26457addb4b34c34fbdf43a0b08722beb5a4a5c53cadc4e` |
| [Android x64 模拟器](huevia-0.31.0-dev-204-android-x64.apk) | `c28cf2490de8dbf3629507e80d1722d30eeaba4a17412f94797672238b410b95` |
| [iOS 未签名 IPA](huevia-0.31.0-dev-204-ios-unsigned.ipa) | `94a1496d0418cbaa4b0ddcd7a9113a19d550254202bff3a6c06025399d30807f` |

Android 源码 `6d84ab3`，51 个界面场景、82 项原生检查和实际图片流程通过，APK 签名及 ABI 已验证。Apple 源码 `0b2fd3a` 补齐原生回调协议默认方法，Android 输入未变；80 项 Flutter、38 项原生检查及完整应用流程通过。IPA 已独立核验为 iPhoneOS ARM64、最低 iOS 16，需用户自签，尚未在实体 iPhone 安装。

安装包保存在本机此目录；仓库按既有规则只提交说明及验证记录。

完整迁移尚未完成，真实账号写入、荣耀 Magic Android 12、未知型号 NEF 和实体 iPhone 尚未验收。准确范围和失败保留见 [204 验证记录](../../docs/migration/validation/account-profile-204/README.md)。
