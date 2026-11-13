# 91源 ARM 原生诊断

GitHub实际执行 head 为 `91ae4b6b7352eba4c6d116cd4afee2334ffd742c`，运行 `43479234183` 的结论为 **failure**。artifact API记录、原始日志及 SHA 见 [result.json](result.json)。实际模拟器架构为 arm64。

- 模拟器 SDK 编译通过；[5项 UIKit全部实际通过](simulator-tests.log)，`Executed 5 tests, with 0 failures`，用例合计13.195秒。包含3项 presenter、任务取消token和真实 PhotoKit授权。
- [native pipeline失败](simulator-result.json)位于 `camera_foreground_fixture.dart:18`：`presenterAvailable` 期望布尔 `true`，实际为数字 `1`。这是生产快照 JSON 类型错误，不是测试名称中的 codecs/RAW 错误。前面的活跃场景/窗口及布尔检查已通过，失败发生在前台 marker 打印前，下游人像/RAW检查未完成。
- 诊断不含 IPA，不作完整门禁或交付验收。

后续最小修复把两个比较表达式派生字段明确封装为 `@YES/@NO`，保留严格 Dart布尔断言；现有 UIKit同一用例补5个公开布尔字段的 CoreFoundation类型及 JSON往返检查，2个计数字段保持数值，总用例数仍为5。修复后的两个源指纹记录在收据中，实际 SDK执行须等待新冻结源完整门禁；不能把旧91的5项通过算作新增断言已经运行。

后续修复的 `e55414ad38ab04291313ddc1244a7ec778da659f` / 主 ARM full `43482938724` 已实际5项/0失败14.001秒（含新JSON类型断言）及完整native通过，[公开CI](../../../apple/ci-result.json)与[独立验证](../../../apple/independent-verification.json)已获根代理exit0，仅本地测试、未发布。前台snapshot为null、证据machine-test。此目录原91的5项13.195秒通过与后续pipeline失败保持原样，未改写为e554执行。
