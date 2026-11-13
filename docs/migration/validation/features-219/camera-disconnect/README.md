# 219 按会话范围显式断开

最终源码：`f3b6eeca671cd0336dd75f5862129d59364b1e76`。显式断开发送 `camera.disconnect` 与捕获的 `session`。核心在同一串行请求内核对当前模式的有效会话再关闭；旧照片 token 不能关闭新照片会话或当前槽位会话，旧槽位 token 也不能关闭还回后的照片会话或新的槽位。

| 请求 | 返回与行为 |
| --- | --- |
| 当前 photos / slots 的有效 token | 执行断开，完整状态为 `mode:none`、`connected:false`、`disconnected:true`、`stale:false`。 |
| 空、未知、过期 token | 不关闭任何当前通道，返回当前完整状态，附 `disconnected:false`、`stale:true`。 |

生产无范围调用只来自旧 Dart 相机入口，该入口已同步改为捕获会话并验证等待后的页面身份。因此没有保留空 payload 全局关闭；原生生命周期的直接 `closeTransport` / 内部 `disconnect` 仍保持其明确的全局停止语义。取消一个旧范围的断开请求也不会通过取消通道绕过会话守卫；已经开始的明确断开仍在原串行请求中完成。

[实际专项日志](target.log)与[退出码](target.exit)为 **167 项通过、exit 0**，其中包含前阶段会话检查与本轮 **57 项新增断言**。检查执行真实 PTP/IP 状态机和合成 socket，覆盖旧 / 新照片连接、照片至槽位模式转换、槽位还回、同一及新物理连接中的旧槽位 token、空 legacy 请求、当前 token 的正向断开，以及取消旧范围断开仍不关闭当前 owner。

[完整核心门禁](../core/core-check.log)为 **1623 项共享边界 + 6 项氛围 = 1629，exit 0**，167 项会话与 65 项连接检查均已包含其中。旧 [1572 项完整结果](../camera-watchdog/attempts/previous1572-core/result.json)作为历史独立保留，不冒充新增守卫已覆盖。Dart 侧 [15 项意图回归的增量归档](../flutter-camera/supplements/scoped-disconnect/result.json)由独立任务维护，不能与旧 71 项直接重复相加。

本轮执行前 Git 基线仍为 [execution-base.json](execution-base.json)记录的 `323a92a09049620f15d2a52f38ee63fdf7038af3`，包含当时尚未提交的 watchdog / 显式断开补丁。运行前后 239 个原始 Java 输入 SHA 完全一致；[分项结果](result.json)及[最终冻结源绑定](../core/final-source-binding.json)将其绑定到最终提交，未改写执行历史。这里只证明受控 JVM 行为，未宣称真实 Z6II / iPhone 现场连接或最终原生包验收已完成。
