# 218 隔离候选的 Apple 成功记录

**本次完整 CI 成功，但候选已在交付前隔离，未验收、未交付 IPA。** 这是旧源码 `27bfc5b2c4ab9769181b664e2277033a26202506` 的历史记录，不是最终 218 的验收。

运行：[43427475083](https://github.com/1162107757/nikon-camera/actions/runs/43427475083)。完整工件已由既有 watcher 校验 API digest 后解包；工件信息和来源见 [artifact-api.json](artifact-api.json)。原 ZIP 未保留，本次归档没有声称重新计算过该 ZIP 的摘要；复制文件本身的 SHA-256 由 [summary.json](summary.json)绑定。

| 实际门禁 | 结果与证据 |
| --- | --- |
| Flutter 全套 | **420 项通过**；[完整日志](flutter-tests.log)末行实际为 `03:02 +420: All tests passed!` |
| 共享核心一致性 | 通过，golden **1423** 项；[core-parity.json](core-parity.json) |
| 原生流水线 | **1 个场景成功**；[simulator-result.json](simulator-result.json) |
| PhotoKit XCTest | **1 项通过，0 失败**；[结果](photokit-result.json)、[执行日志](simulator-tests.log)与 [初始授权记录](simulator-initial-access.json) |
| 静态分析与设备构建 | 本轮原始 [analyze.log](analyze.log)及 [device-build.log](device-build.log)保留；构建成功不等于候选交付验收 |

PhotoKit 日志包含同一测试的多层 suite 汇总，只计一次 `testPhotoLibraryConsent`，不将三行 `Executed 1 test` 累加。

主任务在运行完成前设置了 [交付冻结标记](delivery-hold.txt)：原生 UI QA 发现「恢复内置摄影样片」控件被 Android 系统导航栏遮挡。用户随后明确移除独立样片浏览，同时保留十张内置图供预设卡片使用。这些交付条件没有因旧源码的自动门禁成功而消失。

watcher 已退出 0，但只作诊断，其 [末尾短摘](watcher-excerpt.log)明确为 `Diagnostic run only; no accepted IPA is copied to delivery`。本目录仅保存 [候选 IPA 构建元数据](candidate-ipa-build-metadata.json)，**不含 IPA、不提供安装链接、`acceptedForDelivery:false`、`acceptedIpa:false`、`published:false`**。

后续源码为 `a86b4f6d4facd3cb2be9876f9e47961fdaf19433`，新完整运行 `43431433303` 必须独立验收。此处 420 项、原生场景和其余通过结果只属于旧源码，不继承为新源码结论。本次不修改最终指南、交付清单或任何二进制，也未重新运行测试。
