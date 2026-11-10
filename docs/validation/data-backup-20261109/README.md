# 2026-11-09 定时数据备份验收

已完成首份真实备份并启用云端每日任务。[最终状态](final-state.json)绑定独立函数`huevia-data-backup`／`lam-kkffj9wt`、独立角色和已开启`huevia-daily-backup`。计划北京时间03:00，每份保留30天，未来的计划执行尚未观测。

首次完成标记为`huevia-backups/daily/2026-11-09/2026-11-09T10-04-21-151Z-99851b0c-c57c-49ea-9255-4419ccdec4da/COMPLETE.json`。本次35张表与773文件的gzip／字节长度／SHA-256／实际COS回读全部成功，完成于北京时间18:06:07；没有以异步请求“受理成功”代替备份完成。

- [云端实际代码身份](cloud-code-proof.json)：与本地已测包SHA-256相同，280705bytes；[包清单](worker-package.json)不含环境配置、用户数据或APK，实际服务密钥逐文件扫描不存在。
- [专项测试日志](unit.log)：10项通过，包含失败不生成完成标记、SHA/大小、权限路径、保留期、北京时间日期、新旧context凭证刷新和内部调度认证。
- [临时表恢复验证](typed-restore-verification.json)：33张生产业务表在会话临时表按原类型／identity／检查及索引恢复，完整JSON值相同；未修改生产业务行，也不是全实例或真实文件灾难恢复演练。
- [只读快照RPC权限](private-rpc.json)：anon=false、authenticated=false、service_role=true。生产创建和权限撤销／授权在同一事务完成。
- [原服务保留](original-function-preserved.json)：原Web函数Active，运行时、角色、完整环境、日志绑定、资源配置、handler及修改时间均与开始前一致。

先前准备状态保留在`prepared-status.json`，由本最终状态覆盖。部署前CLI创建角色被IAM拒绝，用户另行明确授权且完成微信MFA后，通过已登录主账号控制台创建独立角色和策略。直接SCF创建CloudBase命名空间函数被Stamp拒绝，改用CloudBase创建；首轮凭证预检发现Node20把每次调用临时凭证放在序列化environment中，按官方SDK的context解析规则修正后，实际COS列举和完整备份通过。预检不是原Web函数的异常请求。

原始API响应（含私有配置）、首次本地快照和云端代码ZIP仅保存于已忽略目录；公开证据未包含密钥、调度令牌、用户信息、文件清单正文或签名下载地址。备份本体含业务敏感数据，保持私有并使用SSE-COS AES256。没有修改原限流／告警策略、发送微信或发布Android版本。

完整运行和恢复边界见[备份说明](../../data-backup.md)。
