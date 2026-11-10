# CloudBase 业务数据定时备份至 COS

状态：**已启用。** 用户明确授权并完成腾讯云微信本人验证后，已创建独立角色、部署独立函数，并在首次完整备份成功后开启每日定时器。2026-11-09北京时间18:06:07首次备份完成，35张表、773个文件全部回读校验通过。定时器已回读为开启，每天北京时间03:00执行，下一次计划为2026-11-10 03:00。未来每日执行尚未到时间，不能写成已观测连续成功。

## 已启用的具体方案

- 每天北京时间03:00，由云端SCF定时器执行；不依赖个人电脑开机。保留30天，仅在本次完整备份成功后清理本备份前缀的旧副本。
- 独立事件函数 `huevia-data-backup`，512MB／900秒，独立运行角色 `HueviaDataBackupRole`。
- 目标为现有私有桶 `huevia-updates-1252602548` 的 `huevia-backups/daily/`，每次运行使用独立目录；SSE-COS AES256、Content-MD5、禁止覆盖。
- 新角色只能读写／清理该备份前缀，读取原有 `huevia-updates/app-releases/` APK；列举权限限制到备份前缀。关联既有 `HueviaFunctionLogWrite` 写入现有日志主题，原更新角色不扩大权限。具体见[策略](../online-library/infra/cos-backup-policy.json)和[部署计划](../online-library/backup/deployment-plan.json)。
- 仅在独立函数私有环境中复用现有 `CLOUDBASE_SERVICE_KEY`；COS使用每次调用context的新临时角色凭证，不保存主账号长期密钥。另生成只供定时器／运维调用的随机调度令牌，阻止伪造Timer消息发起备份，令牌不打包、不写日志、不交付明文。

## 数据与完整性

只读的 `nikon_backup_snapshot()` STABLE RPC，在单次PostgreSQL语句快照下导出全部public.nikon_*表、storage.buckets/objects元数据及实际列／约束／索引／函数／触发器／权限资料。仅service_role可执行。当前预检为33张业务表加2张文件元数据表，约4MB JSON；745个CloudBase对象和28个COS版本文件合计773项、471,890,089bytes。对象数量随业务增长，不能把本轮统计当作固定上限。

原始JSON直接gzip，不经JavaScript数值重写，保留bigint精度。每个源文件备份到独立路径，验证长度及SHA-256，并从COS实际回读比对；APK额外比对数据库中原有SHA-256。数据库gzip与恢复材料也回读。全部成功后才写`COMPLETE.json`；中途缺文件、哈希失败或权限失败均不标记有效备份。

失败记录只含阶段／通用代码／计数，不输出用户资料、密码哈希、会话或服务凭据。备份对象包含业务敏感数据，继续保持私有。当前代码不创建额外邮件／短信告警订阅。

## 恢复边界与验证

[恢复说明](../online-library/backup/RECOVERY.md)随每个备份上传，包含版本化迁移SQL和实际数据库结构资料。该备份是应用逻辑数据与文件副本，不是整个腾讯云账号／PostgreSQL物理实例镜像。平台auth/storage内部迁移、COS未完成上传分片和云账号配置不在恢复承诺中；临时上传／会话等状态灾后应失效，不能直接复活。原存储对象不删除。

- 10项Node专项测试通过：真实字节回读、bigint原文、失败无完成标记、APK哈希、路径／桶限制、30天清理范围、北京时间日期、临时凭证刷新（含CloudBase新版context.environment JSON与旧版environ）、固定CloudBase来源、调度认证、COS加密与禁止覆盖等。
- 真实CloudBase控制面以会话临时函数取快照，在会话临时表中按原列类型／identity／约束／索引恢复全部33张业务表，完整JSON值比较通过；未改生产业务行，也未留下公开RPC。此验证不包含真实COS上传或文件恢复。
- 首次真实任务完成35张表与773项源文件备份，包含CloudBase预设／样片／头像／个人文件及COS全部28项版本对象；每项真实COS回读／哈希通过后才生成完成标记。有效目录：`huevia-backups/daily/2026-11-09/2026-11-09T10-04-21-151Z-99851b0c-c57c-49ea-9255-4419ccdec4da/`。
- 独立函数包为280705bytes，SHA-256 `1831ff635c5fa4b79137c8d9e32a2e60952b8c97a1bdc790365a5f7233a112ba`，从云端实际下载后与本地逐字节相同。包含运行模块、恢复材料和现有固定版COS SDK；ZIP CRC通过，逐文件扫描确认不存在现有服务密钥，不含环境变量、用户数据或APK。
- 原Web函数仍Active；运行时、角色、内存、超时、handler、完整环境变量、日志集／主题和修改时间逐项与开始前一致。

本地数据库快照及原始云API响应仅在已忽略的 `.tooling/data-backup/`；不提交Git。脱敏验证记录在[本轮目录](validation/data-backup-20261109/)。

## 部署与后续运维

1. 授权创建独立角色，绑定限定COS策略和既有日志策略。
2. `python online-library/scripts/package-data-backup.py`；核对输出清单后，按用户授权运行 `deploy-data-backup.mjs --deploy --allow-existing-service-credential`，经CloudBase创建函数（直接SCF创建此环境函数会因Stamp被拒绝）。此时先不注入数据库密钥，函数Active后以`--configure --allow-existing-service-credential`原子设置独立角色与私有配置。
3. 新函数Active后运行 `--run-once`；增加service_role-only快照RPC时使用同一事务完成创建／REVOKE／GRANT，避免公开可调用窗口，并异步执行完整备份；用`--status`查询已回读的完成标记。`--diagnose`只返回context字段名，不返回凭据值；新版CloudBase临时凭证从每次调用的environment JSON解析，不使用冷启动process.env凭证兜底。
4. 首次成功后才运行 `--enable-timer`，回读定时器、时区及函数配置，验证原Web函数代码／配置／角色／日志未变。没有成功的完整备份时，脚本拒绝启用定时器。

腾讯云官方依据：[定时触发器](https://cloud.tencent.com/document/product/583/9708)、[SCF备份到COS示例](https://cloud.tencent.com/document/product/583/18254)、[每次调用context临时凭证](https://cloud.tencent.com/document/faq/583/9180)、[COS权限指引](https://intl.cloud.tencent.com/zh/document/product/436/30580)。
