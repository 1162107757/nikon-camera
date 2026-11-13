# 219 连接 watchdog 终态竞争

复审确认旧候选存在一个独立窗口：watchdog 已通过循环头的 `finished` 判断并进入时钟读取，此时连接成功结束；若旧线程随后恢复并看到超时值，仍会直接关闭它保存的客户端。线程中断只有进入等待时才生效，不能代替“成功完成”和“超时关闭”之间的原子所有权判定。

本次让 `ACTIVE → SUCCESS / TIMED_OUT / CANCELLED / RETIRED` 在同一短所有权锁内只取得一次终态。成功返回前必须赢得完成权；完成路径也在锁外读取单调时钟，超过 75 秒就拒绝发布成功。超时取得终态时，原子摘除它确切拥有的对象并登记关闭屏障，再到锁外执行关闭。下一请求即使会复用同一个客户端对象，也必须等旧关闭结束，不能被旧 timer 的尾部关闭影响。锁内不读取时钟、不执行实际 close，也不发送 PTP 命令。

Java 17 独立连接专项 **65 项实际通过，exit 0**：[原始日志](target.log)、[退出码](target.exit)。新增真实 clock supplier 与 latch 检查包括：

- watchdog 暂停在时钟读取中，连接先成功退休；恢复后返回 75 秒过期值，不能再关闭成功连接。
- watchdog 仍暂停，但工作线程完成时已达 75 秒；必须报告超时，不能发布连接成功。
- timer 已赢得超时，实际关闭暂停在收尾阶段；工作线程失败后，下一工厂复用同一个客户端对象，仍必须等待旧关闭完成。旧 timer 结束后新连接保持有效。

既有有效 75 秒超时、活跃取消、过期任务取消及握手阶段检查继续执行。watchdog 阶段的[完整核心门禁](attempts/previous1572-core/core-check.log)实际为 **1566 项共享边界 + 6 项氛围 = 1572，exit 0**。加入[按会话范围断开](../camera-disconnect/README.md)后，最终 [完整门禁](../core/core-check.log)为 **1623 + 6 = 1629，exit 0**，包含 65 项连接和 167 项会话检查；这些子集不额外相加。[当前 golden 与运行输入](../core/result.json)保留最终运行的原始工作树指纹；原独立 65 项日志和原指纹仍作为前阶段记录保存。

旧 `4f9f1dc` 候选的 [1535 项核心记录](../camera-session/attempts/4f-core1535/result.json)及其原 `ae856…` 执行基线完整保留，仅作历史，不替代修复后的新源验收。运行开始前实际 Git 基线由 [execution-base.json](execution-base.json)捕获；最终源码已通过[当前绑定证明](../final-source-binding.json)另行绑定 **`e55414ad38ab04291313ddc1244a7ec778da659f`**，没有改写 `323a…` 执行基线。原核心修复未修改 Dart、原生包装层、冻结原 Android 源码、PTP 帧 / 端口 / GUID 或已交付 218 包。

[旧绑定与待平台验收记录](source-binding-pending.json)保留此前候选及其阶段摘要，不改写原日志或历史 SHA。当前产品源为 **`e55414ad38ab04291313ddc1244a7ec778da659f`**，ARM full **`43482938724` 已成功**：[最终 Apple 结果](../apple/ci-result.json)确认 **449 项 Flutter、5 项 UIKit、1 项 native pipeline**及设备 IPA 的本地独立验收通过，[最终源码绑定](../final-source-binding.json)保留原 `323a…` 核心执行基线；这不是重跑本地 1629 的声明。真实 Nikon Z6II 与 iPhone 连机仍未验证。这里只保存白名单阶段摘要，没有拷贝用户原始诊断报告。

初次编译的[重复测试入口错误](attempts/compile-duplicate-main.log)，以及测试 fixture 首次关闭 claim 位于唤醒 worker 之后导致的[竞争失败](attempts/target-timeout-fixture-claim-before-unblock.log)和[exit 1](attempts/target-timeout-fixture-claim-before-unblock.exit)均保留。fixture 已改为先取得首次 close，再唤醒 worker，原安全断言没有删除。这里证明受控 JVM 竞争顺序，不宣称真实 Z6II 或 iPhone 现场验证完成。
