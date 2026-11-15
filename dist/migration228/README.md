# Huevia 228 测试包

Android 和 iOS 均已通过本地测试验证，最终源码 `734aa3b0f6687dda815af9e13070f0f3c463873c`。后续已按用户要求上传至公开测试渠道（beta），见 [发布记录](PUBLICATION.json)。

- [Android 手机 ARM64](huevia-0.31.0-dev-228-android-arm64.apk)
- [Android 模拟器 x64](huevia-0.31.0-dev-228-android-x64.apk)
- [iOS 未签名 IPA](huevia-0.31.0-dev-228-ios-unsigned.ipa)，自行签名安装。

修复同步标签整体与照片无间距的问题：固定16dp留白、滚动顶部12dp渐隐。下载使用明确的56dp实心深色圆底/白图标，启用、禁用、明暗主题都保留，角标与下载动作不变。保留227停止传输保留连接等修复。

[测试指南](../../docs/migration/local-testing-228.md) / [字节与SHA清单](ARTIFACTS.json)。实体相机仍需复测；iOS QQ Universal Link/AASA尚未配置。

公开下载页：https://huevia.cc/preset-library/download/?channel=beta 。23条旧公开记录已下架，两个域名66个旧下载地址均404。主站首页与下载页均已取消原版/新版选择，Android仅开放当前228版下载；iOS同样提供当前228版。
