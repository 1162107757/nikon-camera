# 217 本地测试验证记录

冻结打包源码为 `7e2b782d4cea9845fd632b409ab82905328a4a4c`，Android 版本 `0.31.0-dev / 217`、iOS 版本 `0.31.0 / 217`，包名 / Bundle ID 均为 `cc.huevia.next`。Android 两份 APK 和同源 iOS 未签名 IPA 已接受用于本地测试 / 自签测试，`published:false`。Mac 完整运行 `43423048624` 和实际 IPA 独立验证均已成功。当前平台状态以 [附件清单](../../../../dist/migration217/ARTIFACTS.json)为准；[217 测试说明](../../local-testing-217.md)记录用户入口。216 及更早附件不覆盖，历史测试数量不继承为 217 结论。

## Android 附件、签名与实际运行

以下大小及 SHA-256 已从当前 217 文件重新计算，与 [签名 / 对齐记录](android-signing-alignment.json)和附件清单一致。

| 附件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| [ARM64 APK](../../../../dist/migration217/huevia-0.31.0-dev-217-android-arm64.apk) | 52,657,970 | `fd4e71c85defaab977956b7a747f6ad084d4979e768b1340cf54f24275e3bfad` |
| [x64 APK](../../../../dist/migration217/huevia-0.31.0-dev-217-android-x64.apk) | 56,094,938 | `bd387ea95a4388a9c66da7f21ab02aa8513bc4d35eae7e2c4f33fc79fdf2b0e3` |

两 ABI 验签、ZIP 16 KiB 对齐及每 ABI 8 个未压缩 ELF 的 LOAD 段静态对齐通过。签名证书与既有 next 开发包一致，SHA-256 为 `76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75`；原始验签日志：[ARM64](../../../../.tooling/next217/arm64-apksigner.bat-final.log)、[x64](../../../../.tooling/next217/x64-apksigner.bat-final.log)。未据静态检查认定 16 KiB 实体设备通过。

最终 **x64 APK** 已在 API 31、4096 字节页模拟器实际执行 **78 项 R8 运行检查**，`exit:0 / accepted:true`。见 [运行日志](android/release-runtime.log)、[结果 JSON](android/release-runtime-result.json)、[最终映射收据](android/release-runtime-mapping.json)及 [构建结果](android/android-release-result.json)。真实 mesh、语义皮肤、渲染、只读全尺寸细节、修补、取消与 RAW JNI 回调在本次运行通过；这些结果不扩写为 ARM64 手机、16 KiB 实机或实体相机通过。

## QQ 已安装界面与分批回归

[QQ 实装 QA](android/qq-ui.json)绑定上述 x64 摘要、`emulator-5584`、API 31 和 4096 字节页环境。主线程已看过 [初始页面](android/ui/qq-login-no-captcha.png)和 [未同意时的提示](android/ui/qq-consent-validation-no-captcha.png)：没有应用图片验证码、验证码输入或刷新入口；未同意说明时只显示明确提示，没有请求 QQ 授权或创建账号。该 QA 没有执行真实腾讯授权或真实用户登录。

QQ Flutter 的 8 个用例有分批逐项证据，**没有一份 Windows 单批 8/8 完整通过收据**：

- [首轮日志](../../../../.tooling/agent-account/qq217-flutter.log)：前 4 项报告通过，随后宿主中途退出，后 4 项 `did not complete`；该次整组不计通过。
- [剩余 4 项定向日志](../../../../.tooling/agent-account/qq217-flutter-remaining.log)：4 项 All tests passed，test package exit 0，覆盖授权期间账号变化、旧服务仍要求验证码、会话交换期间账号变化及离页丢弃迟到凭据。

原生 SDK 同意流程、凭据边界、取消、重复操作和旧服务兼容行为均有上述本地逻辑断言；腾讯真实身份校验、Android 包登记和 iOS Universal Link 仍需各自的外部配置 / 设备验证，不能由模拟授权测试代替。邮箱 / 账号密码注册原有验证码合同保留。

上述 Windows 分批事实继续保留；最终同源 Mac 全套 404 项已完整通过，收据见下节，不再仅依赖 Windows 分批结果作为最终 Flutter 门禁。

## 共享核心与服务端

[217 核心验证说明](core/README.md)、[运行收据](core/result.json)及 [执行日志](core/run.log)记录共享边界 **1417** 项、氛围回归 **6** 项通过，`golden.json.boundaryChecks` 为 **1423**。新增 QQ 桥接 **32** 项包含在共享回归中；原注册 **20** 项、资料及传输 **43** 项也随完整入口通过，不能再加到 1417 上重复计数。运行输入按 `cf8e62a...` 加当时未提交 QQ 补丁记录，实际编译源由 [逐文件指纹](core/source-fingerprints.json)与 [源清单](core/sources.json)绑定；不是将该检查时的 base commit 当作最终 APK commit。渲染指纹与 216 归档一致，见 [217 golden](core/golden.json)。

服务端完整本地回归为 **241 项：234 通过、0 失败、7 跳过**，42 个测试文件、进程退出 0，见 [完整日志](server-local/server-full.log)和 [运行收据](server-local/result.json)。7 项跳过依赖既有签名 APK 夹具，不计为已通过；没有把这份本地结果写成生产端到端成功。QQ 相关的 [48 项定向服务测试](../../../../.tooling/agent-account/qq217-server-tests.log)是全量中的相关覆盖，不另行累加。

[服务候选准备记录](server-local/prepared-candidate.json)描述准备阶段；用户授权后的 [生产部署收据](qq-server/result.json)确认主函数已 Active，读回 51 个成员内容和 Unix 权限与批准候选一致，仅 `server/app.mjs` 删除首次 QQ 建号的验证码消费。原 100 MiB 策略、函数配置及定时备份保留，没有数据库、IAM 或更新分发变更。

[最终六项 HTTP 探针](qq-server/http-verification.json)通过：普通注册无验证码仍返回 `428 CHALLENGE_REQUIRED`；QQ 空令牌返回 `400 qq_invalid_token`，专用无效令牌返回 `401 qq_verification_failed`；后台认证及两项静态容量检查通过。此前误用后台路径的失败探针保留在 [完整探针历史](qq-server/http-attempts.json)，不计为业务通过。没有使用真实用户令牌、创建账号或验证真实设备 QQ 授权成功。安装包仍只供本地测试，公开发布状态为 false。

## Mac 全量、IPA 与设备边界

217 完整 Apple 运行是 [43423048624](https://github.com/1162107757/nikon-camera/actions/runs/43423048624)，来源与 Android 相同，为 `7e2b782d4cea9845fd632b409ab82905328a4a4c`。实际通过 **404 项 Flutter、golden 1423 项 Objective-C / JVM 一致性、1 个原生流水线场景及 1 项 PhotoKit XCTest**，不是推测数量或沿用上一版本。见 [CI 结果](apple/ci-result.json)、[完整 Flutter 日志](apple/flutter-tests.log)、[核心一致性](apple/core-parity.json)、[原生流水线结果](apple/simulator-result.json)、[原生 / PhotoKit 执行日志](apple/simulator-tests.log)及 [Photos 初始访问记录](apple/simulator-initial-access.json)。

本次 prepare 的完整 `apple-app` job 日志另实际输出 **PASS 34 Apple Wi-Fi stream checks**，包含授权等待取消、连接前取消与真实回环流检查。`wifi.log` 未作为原工件上传，因此只读取得 job `131877524449` 的完整日志后归档 [34 项收据](apple/prepare-wifi-result.json)和 [原始行短摘](apple/prepare-wifi-excerpt.log)，记录本次 run、job、源 SHA、原始行号和完整日志摘要。没有重跑 Mac 或将其他 run 的计数移入本次；这些检查不代表实体 Z6II 连接成功。

| 实际附件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| [217 未签名 IPA](../../../../dist/migration217/huevia-0.31.0-dev-217-ios-unsigned.ipa) | 64,865,047 | `59fdb115d37ceb75fdbf729806fc9ad6b5dc3a8b08007fb2ece110a6513826cb` |

本机最终 IPA 已重新读取大小并计算上述摘要，与 [IPA 构建收据](apple/ipa-verification.json)及 [独立验证](apple/independent-verification.json)完全一致。后者确认 arm64 iPhoneOS、最低 iOS 16.0、版本 217、所需字体 / 人像模型、ImageCaptureCore / WebKit 链接和未签名状态；可供本地自签测试。尚未验证 iPhone 真机安装，包内 `fullParityComplete:false` 的范围标记保留，不将构建和流水线成功扩写为全设备 / 全功能实测完成。

历史 [216 Apple 归档](../features-216/apple-attempts/43416796573/summary.json)记录的是另一源码：Flutter 402 通过、PhotoKit 1 项通过，但新细节夹具在 `media.reviewPreview` 因旧数组长度失败，尚未进入 `detailRender`，216 IPA 未验收。217 已按真实参数 schema 修正夹具，并在上述同源完整原生流水线中实际通过；216 的 402 项不移作 217 数量，也不改写其失败档案。

实体 Nikon Z6II 的 iPhone Wi-Fi 连接、有线相机、遥控与槽位写入回读、16 KiB Android 设备、iPhone 自签安装与真实存储权限仍需现场验证。QQ 真授权未验收、iOS Universal Link 未配置。此次仅交付本地测试包，QQ 六项线上拒绝 / 容量探针已通过；没有公开发布包或更新清单，没有数据库、IAM 或更新分发部署。后续设备反馈按本版本来源另行补充。
