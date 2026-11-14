# 220 本地测试附件

**三包已接受本地测试交付，未公开发布。** 固定源码 `780376ec1017357fd152adbdd1b5bc71c39a6bf6`，Apple full `43529742646` 成功；不混入正在开发的 221。

| 平台 | 附件 | 字节数 |
| --- | --- | ---: |
| Android ARM64 | [ARM64 APK](huevia-0.31.0-dev-220-android-arm64.apk) | 52,854,578 |
| Android x64 | [x64 APK](huevia-0.31.0-dev-220-android-x64.apk) | 56,291,546 |
| iPhone 自签 | [未签名 IPA](huevia-0.31.0-dev-220-ios-unsigned.ipa) | 64,971,215 |

SHA-256：

- ARM64：`a6354ee004b66f72ebea4d7dfe74a718a3a5a5d43a69c0f7b0005117b1622b4c`
- x64：`96c0a18c8cfdde44282949465bb7d0d66010deae2f78d577d830e1fc09fce060`
- IPA：`0cc8b86b7d2a0b664e31f747db50882e3fc8078677cb3797475a79b8753113aa`

精确元数据见 [ARTIFACTS.json](ARTIFACTS.json)，步骤见 [220 指南](../../docs/migration/local-testing-220.md)，收据见 [验证索引](../../docs/migration/validation/features-220/README.md)。Android 两 ABI 验签、各 8 个 ELF 的 16KiB 静态对齐和 10 张模板图通过；精确 x64 APK 在 API31/4KiB 环境通过 78 项 R8 及本地安装界面复测。Apple 实际 488 Flutter、5 UIKit、native pipeline 1、核心一致性 1770 通过，IPA 独立验包 exit 0。

**已知新问题：遥控快门/就绪状态闪烁，以及返回可能退到桌面或退出，正在 221 中处理；220 未包含这些后续修复。** 这是本地测试基线，不表示全部问题已解决。

IPA 为 iPhoneOS/arm64、iOS16+，需自行签名，真实 iPhone 安装和 Z6II 连接仍待验证；亮屏 Wi-Fi/系统切网与 USB 需现场复测。QQ 保留腾讯身份校验，iOS Universal Link 未配置、Android 登记与真实授权未验证。4KiB 模拟器/16KiB 静态不等于 16KiB 设备实测；既有 RAW 原图删除限制保留。

保留 [219 基线](../migration219/README.md)；旧 [d554](../../docs/migration/validation/features-220/attempts/d554/result.json)、[8c19330](../../docs/migration/validation/features-220/attempts/8c19330/result.json)、[db6b172](../../docs/migration/validation/features-220/attempts/db6b172/result.json)仅属未交付历史。不发布商店、更新清单或草稿。
