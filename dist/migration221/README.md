# 221 本地测试附件

**三包已接受本地测试交付，未公开发布。** 固定源码 `d22ec09eb7b10eb1e2e8812ff9b04e30c87dbd2d`，Apple full `43535636225` success、IPA 独立验包 exit 0。

| 平台 | 附件 | 字节数 |
| --- | --- | ---: |
| Android ARM64 | [ARM64 APK](huevia-0.31.0-dev-221-android-arm64.apk) | 52,854,578 |
| Android x64 | [x64 APK](huevia-0.31.0-dev-221-android-x64.apk) | 56,291,546 |
| iPhone 自签 | [未签名 IPA](huevia-0.31.0-dev-221-ios-unsigned.ipa) | 64,974,803 |

SHA-256：

- ARM64：`f5347fe00125629779a1c3446d75b55690453156116dd4a668d832d63299ddda`
- x64：`61235dfd69bdf891f6bae098672ab5d710f1526d763e3ac98108f712f051fa4b`
- IPA：`945b49d3b0f1203d7b74ad787c1bf73f01fa3c296d8b1532cc03555604a5c897`

[ARTIFACTS.json](ARTIFACTS.json)记录精确收据，[测试步骤](../../docs/migration/local-testing-221.md)与 [验证索引](../../docs/migration/validation/features-221/README.md)说明范围。Android 两 ABI 验签/各8ELF16KiB静态/10图通过；精确 x64 在 API31/4KiB 环境实际通过 78 R8、四根标签和两内层返回共6例。Apple 实际 494 Flutter、5 UIKit、native pipeline 1、核心一致性1770通过；本地核心 golden 仍是220参考，未冒称本地221重跑。

本轮仅修复遥控静默刷新/拍照安全串行及 Android 根返回退后台、保留 Activity/页面，内层返回按原路由。**新设计在独立会话审核，未接入221。** 保留 [220 三包基线](../migration220/README.md)，不覆盖旧附件。

IPA 为 iPhoneOS/arm64、iOS16+ 未签名设备包，需自行签名；真实 iPhone 安装、Z6II Wi-Fi、USB、QQ 授权及16KiB实体设备仍待验证。iOS QQ Universal Link 未配置，既有 RAW 原图删除限制保留。仅本地测试，不发布商店、更新清单或草稿。
