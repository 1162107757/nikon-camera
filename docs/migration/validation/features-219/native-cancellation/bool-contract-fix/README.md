# 原生前台快照布尔契约修复

绑定源 `e55414ad38ab04291313ddc1244a7ec778da659f`，主 ARM full `43482938724`。本轮已有[实际5项UIKit及完整pipeline通过](../executions/43482938724/README.md)的独立原始证据，包含新的类型断言；资料整理未重新执行产品测试。

5项/0失败实际14.001秒，包含5个BOOL和2个count的原值及JSON往返公开CFType断言。[公开CI](../../apple/ci-result.json)与[独立验证](../../apple/independent-verification.json)已由根代理实际exit0验收，仅本地测试、未发布；snapshot为null，machine-test证明已执行断言，不伪造日志或计数。

生产快照中的 `registeredPresenterAttached`、`presenterAvailable` 两个比较表达式改为明确返回布尔对象，不改变其真值或场景选择策略。原 UIKit同一用例新增公开类型检查：5个布尔字段在序列化前及 JSON往返后均须为 `CFBooleanGetTypeID`，两个计数字段须为 `CFNumberGetTypeID`。不依赖私有类名，也不要求 UI-test runner 自身有活跃场景。总用例数仍5，严格 Dart布尔断言保持。

[旧91诊断](../diagnostics/43479234183/README.md)的5项通过、13.195秒及后续前台字段数字1故障均保留。该旧通过不包含新类型断言，不能用于接受新源 IPA。

精确2个新输入及其原始指纹见 [result.json](result.json)。原309项 JVM实际 Java输入字节未变；原16项上下文中14项未变、这2项变化，原执行记录不被重写。
