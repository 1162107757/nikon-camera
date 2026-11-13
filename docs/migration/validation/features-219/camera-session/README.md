# 219 相机会话与断线边界

代码审查确认三条独立问题：Wi-Fi 槽位适配器误用相册只读构造器，随后调用 Picture Control 专用方法，触发客户端模式守卫；进入槽位前主动关闭照片连接，使这一错误表现为断开；普通连接成功前还无条件扫描照片目录。另有已完成任务的取消和跨任务关闭竞争，可能结束后续工作所用的通道。没有现场相机 trace，本记录不把这些代码缺陷直接等同于用户 Z6II 的全部硬件故障原因。

本次保留原 `PtpIpClient` 的帧、端口、GUID 与权限守卫，复用原工程已有的会话移交 API：

- Wi-Fi 照片会话在短内存锁下移交给独立 Picture Control 客户端句柄，旧句柄永久退役，原有两条 TCP 通道与事务序列继续使用。网络读取和实际关闭都在该锁外执行。
- 槽位能力先验证，未声明能力时保留照片会话。健康只读槽位的正常关闭、相机忙或功能不支持响应可安全还回照片会话。实际错帧、失去 ACK 或无法验证读回时仍关闭，不为维持“已连接”而复用不确定状态。
- 已尝试写入后的还回，必须通过原有 verified import/deletion 移交守卫；既有一次写入预算、全槽位读回、持久化未知结果与禁止自动重放保持生效。
- USB 保留受控关闭与重新打开；它没有在此接口中取得可验证的同会话移交能力。原页面仍可明确重新只读扫描，未宣称 USB 零重连。
- `camera.connect` 只完成连接与设备能力读取，目录由明确的 `camera.page` 首次请求再加载。状态包含 `mode=photos/slots/none`、`photoConnected`、`slotsConnected`、`inventoryReady`；未读目录不被当成“已确认 0 张照片”。`session` 属于当前模式，已健康的槽位重复打开直接返回同一状态。
- 取消只认当前请求 token。取消时原子摘除旧客户端和精确槽位通道，再在锁外关闭；下一请求最多等待 5 秒关闭屏障，防止工厂复用同一个客户端对象时被旧关闭收尾影响。完成后的旧取消与纯状态查询取消不关闭通道。生命周期停止仍使尚未发布的本地通道失效并清理。

## 实际验证

当前产品源 `e55414ad38ab04291313ddc1244a7ec778da659f` 经[最终源码绑定](../final-source-binding.json)确认保留全部 239 个原核心输入，已包含 [连接 watchdog 原子终态](../camera-watchdog/README.md)和[按会话范围断开](../camera-disconnect/README.md)。完整 Java 17 门禁 **exit 0**，实际 **1623 项共享边界 + 6 项氛围 = 1629**，其中包含 **167 项会话所有权检查**和 **65 项连接检查**。[完整日志](../core/core-check.log)、[退出码](../core/core-check.exit)、[新 golden](../core/golden.json)、[结果与源指纹](../core/result.json)已保存。1629 是原 `323a…` 基线加当时工作树改动的真实编译执行结果，未复用 218 的 1423 项；后续源码绑定没有重跑该本地 JVM 门禁，渲染指纹经实际比较与前次一致。

当前 ARM full **`43482938724` 已成功**：[Apple 最终结果](../apple/ci-result.json)记录 **449 项 Flutter、5 项 UIKit、1 项 native pipeline**及设备 IPA 的本地独立验收通过。原平台失败/待验记录仍按历史保留；真实 Z6II 与 iPhone 连机未验证。

新增检查执行真实 `PtpIpClient` 状态机与合成 socket 字节，覆盖两通道 / 一次 OpenSession、连续事务、健康移交与还回、重复打开不发新命令、`0x2019` 忙 / `0x2005` 不支持响应、错事务必须关闭、活跃取消中断、迟到取消无效、verified 写入读回与丢 ACK / 拒绝写入不绕守卫。竞争检查使用 latch：旧关闭停在收尾阶段，新工厂将复用同一个 `PhotoCameraClient`，新请求必须等旧关闭完成；另验证尚未发布的本地槽位连接被生命周期取消后，两条 socket 均清理。[原独立 110 项日志](target.log)、[退出码](target.exit)保留该阶段记录；新增 57 项按会话范围断开断言后，[最新独立 167 项日志](../camera-disconnect/target.log)和完整核心门禁均已通过。[元数据](result.json)以最终完整运行绑定当前源，原 standalone 指纹作为历史保留。这没有宣称真实 Z6II、iPhone 或 219 原生包已完成现场验收。

前阶段[只读源码检查](source-check.log)为 945 个 UTF-8 / 配置文件、21 项只读细节渲染边界，exit 0；watchdog 修复后的[新检查](../camera-watchdog/source-check.log)为 969 个文件与同样 21 项边界，exit 0。[原工程清单](../camera-watchdog/inventory.log)仍确认 420 项保留、8 项批准修复、其余 412 项不变。未修改冻结原 Android 源码或已交付 218 安装包和文档。

## 历史尝试

首轮完整门禁暴露关闭后重新读取 USB 槽位的既有契约被破坏，返回“请先连接相机，再读取槽位”。已修生产分支：只有成功还回照片会话时才清除槽位重读身份，保留原显式只读重开；原断言未删除。[失败日志](attempts/core-check-usb-retry-before-fix.log)、[exit 1](attempts/core-check-usb-retry-before-fix.exit)保留。随后先取得的 [1505 项结果](attempts/core-check-before-cancel-barrier1505.log)与[80 项独立专项](attempts/target-before-cancel-barrier80.log)属于加入最后关闭屏障前的历史输入；[4f 候选 1535 项](attempts/4f-core1535/result.json)及[显式断开守卫前 1572 项](../camera-watchdog/attempts/previous1572-core/result.json)也均作为历史保留，不替代当前 1629 项，也不累加为额外通过数。
