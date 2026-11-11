# Huevia 跨平台开发版 202

统一源码：`80739e3b5792024a34ce3355c76f969aa75d289e`。本批恢复原版边框面板和构图界面，加入分割对比、编码前/实际 JPEG 精确预览，并修正 EXIF 大图预览内存占用。整体迁移尚未完成。

| 包 | 大小（字节） | SHA-256 |
| --- | ---: | --- |
| [Android ARM64](huevia-0.31.0-dev-202-android-arm64.apk) | 50,504,742 | `71ee234b826d59690f10f2fc81913ae5be61202357bd4a4451a178d3ab136ec5` |
| [Android x64 模拟器](huevia-0.31.0-dev-202-android-x64.apk) | 53,876,174 | `8b95e0e5c1514beb9158c6c74423e303ed67d115e888320c49a5f0efead675ec` |
| [iPhoneOS ARM64 IPA](huevia-0.31.0-dev-202-ios-unsigned.ipa) | 29,146,712 | `196599191ade08689a7871c6edb7f6d9a623fa406f1162ff316b6f20d2af1b0e` |

Android 最低 8.0，使用开发签名，应用标识 `cc.huevia.next`。IPA 最低 iOS 16，未签名，供自行签名安装；尚无实体 iPhone 安装结果。

Android 36 个界面场景、51 项原生检查，以及 Mac 50 项 Flutter、218 项共享检查和 iOS 原生流程通过。Android 正式包另完成 2400 万像素 EXIF 旋转 JPEG 的精确预览与重复分享实操。荣耀 Magic 和未知型号 NEF 仍须实机/实样验证。

完整截图、测试范围与未完成项见 [202 验证记录](../../docs/migration/validation/editor-workspace-202/README.md)。原工程及旧安装包保留。
