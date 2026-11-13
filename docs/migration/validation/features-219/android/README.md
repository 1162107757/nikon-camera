# 219 Android e554精确包收据

最终平台源码`e55414ad38ab04291313ddc1244a7ec778da659f`。新两APK签名/各8 ELF与ZIP静态16KiB/十图、精确x64 R8 78与冷启动2·50·19全通过。ARM full`43482938724`的新5case/新增类型断言和完整pipeline已通过，IPA独立核验成功，三包已接受本地测试、publishedfalse。[收据](final-receipts.json)与[附件草稿](../../../../../dist/migration219/ARTIFACTS.json)均为e554。

| 包 | 字节 | SHA-256 |
| --- | ---: | --- |
| ARM64 | 52,723,506 | `33ea9ba00ce7888a4a6fbb51bfbc61d600d9210611a27e53e6a26b00641c1b20` |
| x64 | 56,226,010 | `a3d5100cbff3b5a939e44a39137fc130bc875a653fa3413a5904d45153649713` |

本次归档独立重算两包大小/SHA并核签名日志为既有next证书。[静态](../android-signing-alignment.json)、[十图](../preset-preview-assets.json)、[R8日志](release-runtime.log)/[结果](release-runtime-result.json)匹配新包；`accepted:true/exit0/code-1`只指运行门禁。[e554冷启动](final-e554-exact-apk-cold-launch.json)/[三事件](source-e554-cold-launch-events.json)真实2预设/50手机/19应用。

完整[18图功能UI](final-ui-result.json)/[事件](final-ui-events.json)保留a54旧SHA，按[Android限定等价](source-e554-android-ui-equivalence.json)引用：lib/Android/core/原app与a54/89/91相同；iOS原生和测试树确变，旧[91证明](source91-android-ui-equivalence.json)和[89证明](source-equivalent-ui-binding.json)均保持各自原字节，不冒称e554完整UI复跑。[91旧收据](../attempts/91/README.md)另归历史。

旧91 Intel449 Flutter和旧5UIKit通过后，native前台检查expectedtrue/actual1失败；旧ARM诊断5通过也同样失败，没有完成后续Retouch/RAW。数字1说明找到presenter，但JSON数字不满足严格布尔契约；新源改真布尔、同5case新增原值/JSON往返类型断言，strict Dart不放宽。旧91候选IPA只属旧源、未交付，不是e554。新5和完整pipeline必须实际跑完。

实装RAW用DNG，NEF仅有独立控件标签覆盖，无真实NEF/Z6II连接/槽位写入结论。4KiB模拟器/16KiB静态不代替ARM64手机/16KiB实体设备。RAW删除仍报“项目照片文件名无效”，[原错图](ui/final-own-dng-cleanup-fresh-scope.png)和`rawDeletionProductCheckPassed:false`保留；QA唯一DNG已[精确清理](cleanup-own-dng/README.md)及[Download SHA守卫](own-download-cleanup.json)，原19行/637文件SHA保留，不能当产品删除通过。

未签名IPA需自签，QQ真实授权/Android登记、iOS UniversalLink未配置、iPhone/Z6II/权限仍待现场验证。不部署、不公开发布。

最终Apple证据见[CI](../apple/ci-result.json)与[独立验包](../apple/independent-verification.json)。Foreground snapshot保留null、证据machine-test，不补造计数；iPhone/Z6II/QQ真实设备边界仍未验。
