# Huevia 跨端开发版 217 · Android / iOS 本地测试

**217 Android 两份 APK 已可本地安装测试，未签名 iOS IPA 已可供本地自签测试。** 三份附件同源 `7e2b782d4cea9845fd632b409ab82905328a4a4c`，实际大小、摘要与分平台状态见 [ARTIFACTS.json](ARTIFACTS.json)。Mac 完整 CI `43423048624` 和 IPA 独立核验已通过；iPhone 自签安装与实机体验仍需用户验证。

| 平台 | 实际附件 | 当前状态 |
| --- | --- | --- |
| Android ARM64 手机 | [217 ARM64 APK](huevia-0.31.0-dev-217-android-arm64.apk)，52,657,970 字节 | 可本地安装测试 |
| Android x64 测试环境 | [217 x64 APK](huevia-0.31.0-dev-217-android-x64.apk)，56,094,938 字节 | 可本地测试，不替代 ARM64 或 16 KiB 实体设备 |
| iPhone 自签测试 | [217 未签名 IPA](huevia-0.31.0-dev-217-ios-unsigned.ipa)，64,865,047 字节 | iOS 16.0 起、真机 arm64，需自行签名后安装；尚无 iPhone 实机安装验收结论 |

Android 包名为 `cc.huevia.next`，版本 `0.31.0-dev / 217`。两 ABI 使用既有 next 开发证书，验签、ZIP 16 KiB 及每 ABI 8 个 ELF 静态对齐通过：[检查记录](../../docs/migration/validation/features-217/android-signing-alignment.json)。最终 x64 正式 R8 包实际运行 78 项通过：[运行结果](../../docs/migration/validation/features-217/android/release-runtime-result.json)；QQ 实装页面无验证码且未同意时不发起授权：[页面记录](../../docs/migration/validation/features-217/android/qq-ui.json)，没有进行真实 QQ 登录。

| 附件 | SHA-256 |
| --- | --- |
| ARM64 | `fd4e71c85defaab977956b7a747f6ad084d4979e768b1340cf54f24275e3bfad` |
| x64 | `bd387ea95a4388a9c66da7f21ab02aa8513bc4d35eae7e2c4f33fc79fdf2b0e3` |
| iOS 未签名 IPA | `59fdb115d37ceb75fdbf729806fc9ad6b5dc3a8b08007fb2ece110a6513826cb` |

Apple 同轮实际通过 **404 项 Flutter、golden 1423 项跨平台一致性、1 个原生流水线场景与 1 项 PhotoKit XCTest**：[CI 结果](../../docs/migration/validation/features-217/apple/ci-result.json)。prepare 完整日志另确认 34 项 Apple Wi-Fi 流及等待 / 取消检查通过：[短摘收据](../../docs/migration/validation/features-217/apple/prepare-wifi-result.json)。实际 IPA 已重新计算大小和摘要，并完成 arm64 iPhoneOS、版本、模型 / 字体及未签名状态的[独立核验](../../docs/migration/validation/features-217/apple/independent-verification.json)，不以模拟器结果替代 iPhone / 相机实测。

本轮重点为 **QQ 登录移除应用图片验证码**：同意后调用 QQ 原生 SDK，仍需腾讯身份校验及正常服务会话；取消、离页和账号变化保护保留，邮箱 / 账号密码注册验证码不变。

**用户对窄范围更新授权后，生产 QQ 接口免验证码补丁已部署并核验。** 只删除首次 QQ 建号的额外图片验证码消费；普通注册仍要验证码，无效 QQ 凭据不能登录，100 MiB 容量保留，见 [服务部署记录](../../docs/migration/qq217-server-review.md)。Android 腾讯新包登记尚未实测确认，iOS Universal Link 尚未配置；未用真实用户令牌测试，真实原生授权仍不标为已验收。客户端遇旧服务验证码要求时仍会显示服务尚未更新提示，不会假装成功。

累积功能继续测试：

- 216 自动祛痘照片编号 / 范围定位、逐项勾选、数量反馈、取消及确认一次撤销；关闭旁原版全局照片菜单与只读细节；17 个调节参数和六个独立工具图标。
- 215 原式人像直进，工具顺序「皮肤 / 面部 / 塑形 / 自然精修 / 修补」；第二指取消未提交整笔、残指锁定、滑条 / 照片跨区域抬指保护、圆环只预览及完整子事务确认 / 取消。
- iOS 相机连接阶段、等待秒数、75 秒核心预算、首授权 / USB 等待边界及主动取消。**用户型号为 Nikon Z6II（“Z62”），走相机 Wi-Fi；实体 iPhone 连接尚未验证成功。**

Z6II 复测入口为「连接至智能设备 → Wi-Fi 连接 → 建立 Wi-Fi 连接」，iPhone 连机身显示的 SSID 后回 Huevia，见 [Nikon 官方说明](https://onlinemanual.nikonimglib.com/z7II_z6II/en/09_menu_guide_06_28.html)。电脑 / WTU 是不同流程，不据此假定用户选错。反馈时保留 iPhone / iOS、机身入口、实际停留阶段 / 秒数、完整错误和本地网络授权情况。

完整步骤与已完成本地逻辑验证见 [217 本地测试指南](../../docs/migration/local-testing-217.md)。RAW / NEF 先显影再测细节；全尺寸细节只读，不应新建版本 / 草稿 / 系统相册文件；删除仅使用专门测试副本。4 KiB 模拟器及 16 KiB 静态对齐均不能代替 16 KiB 实机验证。

保留 [216](../migration216/README.md)、[215](../migration215/README.md)与 [214](../migration214/README.md)基线。同包名 `cc.huevia.next` 的 217 安装会覆盖既有 next 应用，先保留重要测试资料与旧版导出 ZIP，无需卸载原 `cc.huevia`。

安装包仍仅本地测试，不部署数据库 / IAM / 更新分发函数，不上传草稿、不公开发布。此次授权只覆盖已说明的 QQ 接口和测试包更新，包验收通过不自动取得其他发布权限。
