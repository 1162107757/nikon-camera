# 219 验证夹具适配

本次只修验证夹具，未恢复生产 `HueviaTask.cancelled` 可写属性，也未降低原 R8 78 项检查。

- Apple：`avatar_apple.mm` 使用真实 `cancelIfActive`；`avatar_apple.sh` 链接输入新增生产 `HueviaTaskCancellation.m`。`bash -n` 和差异检查实际通过。Windows 未执行 Apple SDK 编译，须由新 Mac 全门禁验证。
- Android：精确 mapping 指明生产取消状态类 `NativeTaskCancellation → ir`。旧夹具把普通 `AtomicBoolean` 塞进 R8 的擦除 `Object` capture，虽然原反射 probe 能通过，生产内联调用仍会转换成 `ir` 而失败。新夹具从 mapping 参数反射真实生产 flag，保留 false/true/reset probe、正常及运行中取消断言。
- 修正后测试 APK [实际编译成功](test-apk-build.log)，在 `emulator-5584` 对持有的4f x64 APK [实际通过全部78项](release-runtime.log)，`INSTRUMENTATION_CODE: -1`、runner exit 0。来源 APK、mapping、测试 APK 和夹具 SHA 见 [result.json](result.json)。

此处验证的产品源是持有的 `4f9f1dc6d32d41f7b0179dac7436addc35ff6699`，**不是最终219交付验收**。后续 watchdog/会话断开修复形成新源后，必须重建产品 APK 并用对应新 mapping 再跑78项。

[原 ClassCastException 失败](old-r8-cast-failure.log)保留。重建测试 APK 时曾漏私有 runner override，导致 [instrumentation 未注册](omitted-runner-attempt.log)；该次不计通过。后已加入既有 `release-test-runner.gradle`，并同步 `.tooling/setup219.py` 的 runner 复制及生产 taskClass 映射参数，避免重生私有脚本时丢失。

私有 Apple verifier 后续补了实际 `simulator-pipeline*.log` 前台 marker 核验，只接受明确的 bool/count 字段；缺失、类型错误或非活跃窗口不通过。其 [10项正反例](foreground-verifier-checks.json)实际通过，仅属 verifier 解析检查，不能算作 UIKit 测试或 iPhone 实连。原78项运行时的源指纹和日志保持原样，后续私有 verifier 的新 SHA 另列于收据。
