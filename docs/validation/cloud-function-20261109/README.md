# 2026-11-09 云函数告警排查与日志接入

对象：上海 `nikon-d8girdjsr252fd90e` 环境的 `nikon-preset-library`（`lam-c5mc40h5`）。用户报告 15:04 告警，随后明确授权开通日志、确认日志付费模式，并授权给现有 `HueviaUpdatePackageRole` 增加当前环境的日志配置查询与日志写入能力。

## 已完成

- 环境请求日志已开启；新日志中可看到目录、社区及数据库请求记录。
- 云函数运行日志绑定到主账号自有主题 `huevia-api-runtime`，日志集 `huevia-runtime-diagnostics`，上海区，保留 7 天，初始 1 个分区、最大 2 个；匿名上传未开启。
- 日志主题 `b542b8c6-ab56-40fa-a14d-c81cd050fb18`，日志集 `ae4d30f6-aad2-44c7-aa52-fca7d7ebe513`。函数状态 `Active` / `Available`，运行日志配置可回读。
- `HueviaFunctionLogWrite`（293251244）当前版本 4，仅允许上海日志主题元信息查询、当前日志集元信息查询以及向当前主题写入。查询父日志集是部署校验，不读取日志正文。运行角色、既有 COS 策略保持；未授予日志内容读取、删除、其他主题写入或账号管理权限。具体动作和资源见 [实际策略](log-policy-applied.json)。
- 正常 `/health` 请求返回 200，请求 ID `c6a7509f-7504-4a8b-afa4-d21063e059a7` 与 CLS 中同一函数的结束记录 `status_code:200` 对应，已确认实际采集，不仅检查开关。开始记录 `202` 属于运行中状态。[可见日志证据](runtime-log-proof.json)、[日志截图](runtime-logs-active.jpg)。
- `/health` 与 `/catalog.json` 验证均 200，目录 391 条。函数代码包 SHA-256 仍为 `c658d22bf91b9693c5a5b1b1a2e01d72460c33ea4c08989d355bb5cba0079ab9`；环境变量及运行时、256 MB 内存、60 秒超时、角色均未变，没有部署代码或更改限流／告警策略。

绑定过程先出现缺少 `cls:DescribeTopics`，补齐配置查询后，代管主题仍返回 `ClsLogSetId & ClsTopicId not matched`。CloudBase API 代理创建的主题也归 TCB 代管；最终在已登录主账号 CLS 控制台开通服务并创建自有主题，成功绑定。此前新建但未绑定、未索引的空代管主题及其空日志集已清理，原有环境请求主题和其他环境保留。没有将函数角色换成拥有全服务权限的预置角色。

## 历史告警结论及边界

可回读的分钟监控显示，15:01–15:06 出现 43 次 Error，15:04 为 11 次，与邮件一致；同段 Http4xx 为 79。系统错误、433 超时、434 内存不足和限流指标均为 0。15:10 至 16:27 请求范围内，接口返回的 62 个可用分钟采样中 Error、Http4xx 均为 0；未返回的分钟不能算作已观测零值。逐项数字与时间见 [summary.json](summary.json)。

SCF 的 4xx 指标也可能包括 430 执行错误、439 进程退出，不能直接当作网站的普通 401／404。保留的认证／风险聚合记录未提供集中登录或风控拒绝证据，但这些不是完整历史请求记录。其他任务确认对应时段没有进行线上异常请求测试。

**目前无法确定 15:04 的具体错误，也不能认定或排除攻击。** 当时请求／运行日志未启用，现在开通不能补回历史日志。新请求已能记录实际错误及请求 ID，后续若再次出现可据日志定位。本次未创建持续盯守或自动修复任务。

## 证据与参考

[最终函数配置](function-logging-config.json)、[日志主题](runtime-topic.json)、[完整脱敏摘要](summary.json)。原始 API 返回、SQL 聚合、实时源包与日志明文仅保留在忽略目录 `.tooling/cloud176`，未复制环境变量、凭证、个人资料或请求 IP 到交付记录。

腾讯云官方：[SCF 监控指标](https://cloud.tencent.com/document/product/248/45130)、[运行状态码](https://cloud.tencent.com/document/product/248/87507)、[CloudBase 资源与日志角色配置](https://docs.cloudbase.net/solutions/cloudbase-for-platforms/manage-resources)、[SCF 日志结构](https://cloud.tencent.com/document/product/583/60336)。
