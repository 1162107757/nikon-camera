# 221 验证索引

固定源码 `d22ec09eb7b10eb1e2e8812ff9b04e30c87dbd2d`。**三包已接受本地测试交付，`published=false`。** Apple [full 43535636225](https://github.com/1162107757/nikon-camera/actions/runs/43535636225) success，IPA 独立验收 exit 0。范围限遥控静默刷新/拍照安全串行和 Android 返回修复；界面沿用220，新设计在独立会话审核、未接入221。

| 范围 | 实际证据 |
| --- | --- |
| 遥控本地回归 | [remote-result.json](local/remote-result.json)：新6项+旧迟到打开1项实际 exit 0；[source-binding.json](local/source-binding.json)绑定4个最终Git输入，原903df基线/未提交补丁事实和raw SHA保留，未声称整个Windows套件执行通过 |
| Android 两 ABI | [android/result.json](android/result.json)：构建/验签/各8ELF16KiB静态对齐/10图通过；精确x64在API31/4KiB环境R8 78项通过 |
| Android 返回 | [back-navigation-result.json](android/back-navigation-result.json)：四根tab退后台/恢复同Activity、同PID、原页；连接页和队列返回同步，两内层例通过，共6例、exit 0；[220复现](android/back220-baseline.json)保留 |
| 本地静态 | [local/result.json](local/result.json)及 [analyze.log](local/analyze.log)、[source-check.log](local/source-check.log)、[inventory-verify.log](local/inventory-verify.log)：全应用分析0、source check1239/21/57、inventory420/8/412实际 exit 0 |
| 核心参考/绑定 | [reference.json](core/reference.json)、[golden.json](core/golden.json)：沿用220真实golden，243个Java输入未变且已绑最终221；`freshRunClaimed=false`，不声称本地221 JVM重跑 |
| Apple 新全套 | [ci-result.json](apple/ci-result.json)：494 Flutter、5 UIKit（含PhotoKit）、完整native pipeline1通过；[core-parity.json](apple/core-parity.json)实际重新核对1770项一致 |
| IPA 独立核对 | [independent-verification.json](apple/independent-verification.json)、[ipa-verification.json](apple/ipa-verification.json)：同源iPhoneOS/arm64、build221、iOS16+、未签名，10图原字节保留；[simulator-result.json](apple/simulator-result.json)唯一完整场景success |

[source.json](source.json)汇总最终绑定，[ARTIFACTS.json](../../../../dist/migration221/ARTIFACTS.json)记录三包实际字节/SHA及本地交付状态，[指南](../../local-testing-221.md)列出复测步骤。前台fixture实际通过，证据为machine-test、snapshot=null，不捏造独立快照或额外运行次数。

实体相机、iPhone安装/连接、QQ授权及16KiB设备仍未验证；iOS QQ Universal Link未配置，既有RAW原图删除限制保留。原始 `fullParityComplete=false` 不改成全部设备/功能已验收。保留 [220收据](../features-220/README.md)，不改旧包，不接入未审核设计，不部署服务或公开发布客户端。
