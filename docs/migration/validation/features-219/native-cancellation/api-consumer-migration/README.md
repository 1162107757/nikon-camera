# 219 原生取消 API 调用点补齐

89c 的 Mac `43464094785` 在设备编译时报 [只读取消属性写入错误](failure-excerpt.log)。这次补齐两份生产调用方，不恢复可写属性：

本补丁现绑定 `e55414ad38ab04291313ddc1244a7ec778da659f` / ARM full `43482938724`。两份消费者和两个检查工具的4个原始输入 SHA 均未变，并与新 Git 内容按 LF 规范化一致。57份源检查和历史回放的实际基线仍为 HEAD89c 加当时未提交补丁；随后本轮[实际5项UIKit及完整native pipeline通过](../executions/43482938724/README.md)单列，不计入原309项执行。

最终[公开CI](../../apple/ci-result.json)及[独立验证](../../apple/independent-verification.json)已由根代理实际exit0验收，仅本地测试、未发布。当前新309/100轮竞争、5项/0失败14.001秒及schema1唯一whole native case成功单列；前台证据为machine-test，快照null。

- `HueviaOriginalFiles.mm`：取消原文件保存时调用 `cancelIfActive`；成功或失败投递 UI 前 `finish`，清理时只移除同一任务。
- `HueviaImportPicker.m`：4处选择器/后台到期写入改为 `cancelIfActive`；完成或清理时退役该 token。保留 generation、加载取消、原数据清理和现有错误结果约束，旧头像到期回调不能覆盖已完成结果。
- `source_check.py` 接入公开取消 API 兼容性边界：确认只读属性及现有取消/完成方法，对全部57份仓库 Apple 源码检查旧 setter。独立 `HueviaCameraCancellationFlag` 的可写 Wi-Fi 测试状态经声明类型核对后保留。

[源检查实际通过](source-check.log)。[历史回放](historical-replay.json)分别使用 Git89c 两份真实旧生产文件，均能被新边界拒绝；当前调用方与独立 mock 被接受。此处只检查源兼容性，不冒称 Apple SDK 编译或 UIKit 通过。

本次API迁移时，原309项 JVM两个实际 Java输入、核心树及原Java源未变，未重跑这些未变检查；精确历史证明见 [result.json](result.json)。随后e554已完成新的完整源编译和pipeline，不能沿用旧候选代替。完整pipeline通过也不宣称每个选择器/Files取消分支均被单独自动化运行。
