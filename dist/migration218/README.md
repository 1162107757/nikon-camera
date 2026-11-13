# Huevia 跨端开发版 218 · Android / iOS 本地测试

**218 两份 Android APK 和未签名 iOS IPA 已接受用于本地测试 / 自签测试。** 三份同源 `a86b4f6d4facd3cb2be9876f9e47961fdaf19433`，完整 Mac 运行 `43431433303` 已成功，实际 IPA 独立核验与十图门禁均通过。Android 版本 `0.31.0-dev / 218`，iOS 版本 `0.31.0 / 218`，包名 / Bundle ID 均为 `cc.huevia.next`。此前 `27bfc5b2c4ab9769181b664e2277033a26202506` 候选保持隔离、未交付，旧运行 `43427475083` 不替代最终验收。所有已交附件保持不变，完整元数据见 [ARTIFACTS.json](ARTIFACTS.json)。

**本版仍有两项已知问题，正由 219 处理，未包含在 218：** Android 从相册打开 JPEG 时，编辑器格式标签可能误显示 NEF；iOS 217 已报告真实前台相机连接在 2–6ms 内被旧前台窗口检查拒绝，218 沿用同段未修代码。**相机连接请等 219 专项 IPA，不建议使用 218 重复测试该问题。** 这不影响本轮对预设菜单、模板设置及包完整性的验收范围。

| 平台 | 当前状态 |
| --- | --- |
| Android ARM64 手机 | [218 ARM64 APK](huevia-0.31.0-dev-218-android-arm64.apk)，52,723,506 字节，已接受用于本地测试 |
| Android x64 测试环境 | [218 x64 APK](huevia-0.31.0-dev-218-android-x64.apk)，56,160,474 字节，已接受用于本地测试，不代替 ARM64 或 16 KiB 实体设备 |
| iPhone 自签测试 | [218 未签名 IPA](huevia-0.31.0-dev-218-ios-unsigned.ipa)，64,868,359 字节；iOS 16.0 起、真机 arm64，需自行签名安装；尚无 iPhone 实机安装验收结论 |

| 附件 | SHA-256 |
| --- | --- |
| ARM64 | `6d42627b6f754decd7d98f4e56a72ab8a57b715e7c81050618a374d16ebd2287` |
| x64 | `f61f23e4dc96be57e886b2d4c3aa2ed6ffea3a8c84a557dcc2ff202ab0fd75d6` |
| iOS 未签名 IPA | `e53ca64f5f7fbbf8f5b035875558a9b9f30a6cf28eebbf5c01f88a1eb44b6b7f` |

两 ABI 验签、ZIP 16 KiB 对齐及每 ABI 8 个 ELF 静态对齐通过：[检查记录](../../docs/migration/validation/features-218/android-signing-alignment.json)。最终 x64 APK 在 API 31、4 KiB 模拟器实际重跑 78 项 R8 检查，退出 0：[运行结果](../../docs/migration/validation/features-218/android/release-runtime-result.json)。既有 instrumentation harness 未改动，实际运行的是本次精确的新 APK。

Apple 同源完整运行实际通过 **421 项 Flutter、golden 1423 项跨平台一致性、1 个原生流水线场景和 1 项 PhotoKit XCTest**：[CI 结果](../../docs/migration/validation/features-218/apple/ci-result.json)。prepare 日志另确认 [34 项 Apple Wi-Fi 流 / 等待检查](../../docs/migration/validation/features-218/apple/prepare-wifi-result.json)通过；这不覆盖上述 UIKit 前台窗口选择问题。实际 IPA 的摘要与 [独立核验](../../docs/migration/validation/features-218/apple/independent-verification.json)一致，10 张独立图片及其两套打包副本均与仓内和 217 一致，见 [跨端图片记录](../../docs/migration/validation/features-218/preset-preview-assets.json)。

[实装 QA](../../docs/migration/validation/features-218/android/release-ui.json)及 [操作 / 截图记录](../../docs/migration/validation/features-218/android/ui-events.json)绑定最终 x64 摘要：浅色 / 深色与中文标题菜单、多置顶冷重启保留、取消一款仍保留另一款、删除确认 / 取消均已核对。模板设置仅状态 / 说明及两动作，两按钮完整位于系统导航上方；普通 JPEG 自选 / 恢复及预设卡片照片模拟已实装核对，[内置 10 图](../../docs/migration/validation/features-218/preset-preview-assets.json)与 217 逐字节一致。仅清理自建 QA 副本，原有预设状态和跟随系统外观已恢复；这些模拟器证据不扩大为实体设备验收。

本轮重点：

- 「我的预设」长按改为紧凑圆角菜单。置顶 / 取消置顶直接执行，无二次确认；可同时置顶多款，状态继续持久保留。删除仍走原「移除预设？」确认及原有保护。
- 「设置 → 预览模板」只保留模板状态说明、「从手机选择模板图」和「恢复内置摄影样片」，不再独立展示大样片、摄影署名或样片浏览入口。10 张内置图片全部保留，继续用于预设卡片手机模拟；取消选图保留原模板，两项操作不能被系统底部导航栏遮住。
- 217 的 QQ 免应用图片验证码流程、216 的原式照片菜单 / 只读细节 / 自动祛痘、215 的人像直进 / 多指取消 / 圆环 / 完整子事务继续保留。

具体入口、长名 / 两主题、多置顶 / 重开应用、删除取消及模板两项操作的步骤见 [218 本地测试指南](../../docs/migration/local-testing-218.md)。超长名 / 大字号另有组件覆盖，不用组件测试代替实体设备结果；最终源码的 Mac `43431433303` 已完整通过，旧候选的结论仍独立保留。

QQ 首次建号的额外应用图片验证码服务补丁已按用户授权上线并核验，见 [部署收据](../../docs/migration/validation/features-217/qq-server/result.json)；普通注册原验证码和腾讯身份校验仍保留。未使用真实 QQ 令牌或创建账号，真实腾讯设备授权仍未验收；Android 腾讯登记尚未实测确认，iOS Universal Link 未配置。用户的 Nikon Z6II（“Z62”）通过相机 Wi-Fi，实体 iPhone 连接成功仍未验证；218 的已知前台窗口问题由 219 另行修复与验收。

已验收 [217 基线](../migration217/README.md)的 404 项 Flutter、native pipeline 1 项、PhotoKit 1 项及 IPA 只对应 217，不继承为 218 结论。[216](../migration216/README.md)、[215](../migration215/README.md)和 [214](../migration214/README.md)附件保持不变。新版 next 安装会覆盖已有同包应用，先保留重要资料和旧版导出 ZIP；无需卸载原 `cc.huevia`。

本轮面向跨端 Android / iOS 本地测试，iOS 仍按设备用未签名 IPA 自签安装交付；不公开发布、不上传发布草稿，不扩大 QQ 窄范围更新为其他生产部署。16 KiB 静态对齐或 4 KiB 模拟器结果均不能替代 16 KiB 实体设备验证。
