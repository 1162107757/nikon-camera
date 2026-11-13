# e554 ARM完整运行：原生证据

源为 `e55414ad38ab04291313ddc1244a7ec778da659f`，完整运行 `43482938724`。根代理独立验证器已实际exit0，[公开CI](../../../apple/ci-result.json)与[包验证](../../../apple/independent-verification.json)收据保留；仅接受本地测试、未发布。

- [取消状态 JVM](native-task-tests.log)：本轮实际309项通过，含100轮竞争；原4f执行保留，未改写成此次执行。
- [UIKit](simulator-tests.log)：实际5项通过、0失败，14.001秒，包含e554新加的公开布尔/计数类型及JSON往返断言。
- [完整 native机器结果](simulator-result.json)：唯一用例成功、源匹配e554，fresh runId与ready记录一致。

Flutter测试拦截了调试日志，未观察到前台快照，故 **`snapshot:null`、`evidence:machine-test`**，不编造计数。结论来自经审计的确切两个Dart Git blob：在实际iOS模拟器中，唯一用例无条件等待前台断言，无吞错/跳过；完整成功结果只能在这些断言通过后生成。实际iOS runtime/SDK、fresh nonce、来源和测试图片SHA均严格核对。旧91同一Dart路径真实失败，作为负对照保留。

私有采集器仍优先使用有效marker；缺marker才用上述严格证据，错误marker不会被fallback掩盖。[17项采集器正反例](collector-regressions.json)实际符合预期，拒绝错误源、失败/跳过用例、缺少调用、非iOS、错误SDK/nonce/图片等；不计入App测试数量，也没有重跑产品测试。可审计的[采集器附件](foreground-evidence-collector.py.txt)和指纹见 [result.json](result.json)。产品源码及原expect未因采集适配修改。
