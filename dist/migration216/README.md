# Huevia 跨端开发版 216 · Android 本地测试

**216 Android 两份 APK 已可本地安装测试；iOS 完整验收失败，不提供 216 IPA。** 附件来源为 `e8f78a766f839f27ca5e244fcfae404f6898f9b3`，实际大小、SHA-256 和平台状态见 [ARTIFACTS.json](ARTIFACTS.json)，不沿用 215 的摘要或测试总数。

| 平台 | 实际附件 | 当前状态 |
| --- | --- | --- |
| Android ARM64 手机 | [216 ARM64 APK](huevia-0.31.0-dev-216-android-arm64.apk)，52,657,970 字节 | 可本地安装测试 |
| Android x64 测试环境 | [216 x64 APK](huevia-0.31.0-dev-216-android-x64.apk)，56,160,474 字节 | 可本地测试，不替代 ARM64 手机或 16 KiB 实体设备 |
| iPhone 自签测试 | 尚无已验收附件 | `43416796573 / e8f78a7` 完整原生流水线未通过，无可交付 216 IPA |

Android 版本为 `0.31.0-dev / 216`，包名 `cc.huevia.next`。两 ABI 验签、既有 next 证书、ZIP 16 KiB 对齐和每 ABI 8 个 ELF 静态对齐通过：[签名与对齐记录](../../docs/migration/validation/features-216/android-signing-alignment.json)。最终 x64 R8 包在 API 31、4096 字节页模拟器实际运行 78 项通过，安装摘要与此 x64 附件一致：[运行结果](../../docs/migration/validation/features-216/android/release-runtime-result.json)。

最终安装包的原式菜单 13 项已实屏核对。其他早期界面证据来自生产代码相同的 `8ced1d6`，与最终 `e8f78a7` 仅差两处测试依赖修复，来源见 [屏幕记录](../../docs/migration/validation/features-216/android/release-ui.json)。内置样片未检出自动祛痘候选，候选标记的原生样片验证仍待有效样片；定向标记与勾选测试另有记录。

首轮 Apple `43412448770` 的 [失败记录](../../docs/migration/validation/features-216/apple-attempts/43412448770-result.json)保留：Flutter 390 通过、12 失败，未接受 IPA。两处测试依赖修复后原 12 项已定向通过，见 [本地结果](../../docs/migration/validation/features-216/flutter/local-results.json)。

第二轮 Apple `43416796573 / e8f78a7` 的 [归档结果](../../docs/migration/validation/features-216/apple-attempts/43416796573/summary.json)已核实：Flutter **402/402**、PhotoKit 授权 XCTest **1/1** 通过，设备与模拟器编译成功；完整 native pipeline 因新细节测试夹具仍发送旧长度数组，在 `media.reviewPreview` 被拒绝，**尚未进入 `detailRender`**，见 [失败原文](../../docs/migration/validation/features-216/apple-attempts/43416796573/native-failure.txt)。因此不验收、不交付 216 IPA。

该测试夹具已在后续 **217** 按当前参数 schema 修正，继续完整验证；**217 全量门禁仍待通过**，不能将修复本身记作验证成功。已交付的 216 Android APK 保持原文件、版本、大小和摘要，不为此重建或覆盖。完整证据索引见 [216 验证记录](../../docs/migration/validation/features-216/README.md)。

本轮重点：

- 「自动祛痘」候选在真实定位照片上显示编号和范围，支持逐项勾选、定位、数量反馈与取消；确认所选作为一次人像撤销。
- 编辑器关闭旁三点恢复原版全局照片菜单及样式，包含直方图、只读细节、照片版本、滤镜、配方、复制调色、重置与条件删除等入口。
- 调节中的 17 个参数与曲线、HSL、调色盘、去灰、局部、修补六个工具使用独立图标。
- iOS 相机连接显示阶段和等待秒数，可取消；核心握手与初始目录读取有 75 秒总预算，首授权、USB 等待和首屏读取另有明确边界。

入口与复测步骤见 [216 本地测试说明](../../docs/migration/local-testing-216.md)。RAW / NEF 先显影再测细节；全尺寸细节只读，不应新增版本、草稿或系统相册文件。删除菜单仅用专门测试副本验证。

215 的人像直进、双指取消整笔、残指锁定、画笔圆环预览及子页确认 / 取消继续保留。[215 测试包](../migration215/README.md)与 [214 基线](../migration214/README.md)均不覆盖；同包名新版安装会覆盖已有 next 应用，先保留重要测试资料与旧版导出 ZIP。

**已确认用户使用 Nikon Z6II（“Z62”）与相机 Wi-Fi；本轮尚未确认实体 iPhone 连接成功。** 复测时，Z6II 进入「连接至智能设备 → Wi-Fi 连接 → 建立 Wi-Fi 连接」，iPhone 连接机身显示的 SSID，再回 Huevia 连接，见 [官方智能设备说明](https://onlinemanual.nikonimglib.com/z7II_z6II/en/09_menu_guide_06_28.html)。「连接至电脑」是另有 WTU 配对要求的流程，见 [官方电脑连接说明](https://onlinemanual.nikonimglib.com/z7II_z6II/en/10_establishing_wireless_connections_02.html)；目前不据此认定用户选错模式。实际停留阶段仍待现场反馈，请记录所装版本、iPhone / iOS、机身入口、停留阶段 / 秒数、完整错误及授权情况。

4 KiB 模拟器或 16 KiB 静态对齐不代表 16 KiB 实机验证。原四项与十一类功能、实体相机 / iPhone、自签和权限边界继续按指南核对；QQ Android 登记未核实，iOS Universal Link 未配置。

本轮仅本地测试，未发布；不部署生产数据库 / IAM / 函数，不上传草稿，不公开发布。后续上线须有新的明确指示。
