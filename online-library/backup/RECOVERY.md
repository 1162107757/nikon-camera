# Huevia COS 数据备份恢复说明

仅接受包含 `COMPLETE.json` 的目录。先验证其中 database、files、recovery 所列的长度与 SHA-256，再解压 database.json.gz，核对解压后 SHA-256。没有 COMPLETE 的目录是未验收的中途结果。

数据库包含33张或更多 public.nikon_* 业务表、storage.buckets/objects 元数据，以及实际列类型、默认值、identity、约束、索引、函数、触发器与权限/RLS资料。原始 JSON 文本直接压缩，未通过 JavaScript 数值重新序列化，保留 bigint 精度。恢复时同样避免以普通JavaScript Number重写数据。

1. 在隔离的 CloudBase PostgreSQL 环境准备恢复，先保留故障环境。不要直接在正在服务的生产数据库运行覆盖或清空。
2. 按 schema-migrations.sql 的编号顺序创建应用结构；CloudBase 的 auth/storage 平台结构由平台初始化，不以业务备份覆盖其内部迁移。
3. 根据 database.json 中的实际 columns/constraints/indexes/functions/triggers/tableSecurity/policies 与目标结构核对；数据库可能在打包后新增迁移，实际快照的结构资料优先。涉及未匹配的新列、类型或约束时停止，不静默丢列。
4. 将 public.nikon_* 数据按外键依赖顺序、在一个维护事务内恢复；identity显式值使用 OVERRIDING SYSTEM VALUE，并按恢复后的最大ID校正identity/sequence。先在临时表按原类型导入并比较完整JSON值；仓库 verify-restore.sql 提供此验证，不能把它当作生产恢复命令。
5. 根据 files 中 provider/path/key 将实际对象恢复到原私有桶和原对象路径，恢复 CloudBase 存储元数据须使用平台支持的上传流程，不直接覆盖 storage.objects。COS APK恢复到 huevia-updates/ 下的原始路径；逐项再验SHA-256和长度。
6. 未完成上传分片、会话、验证码和风控窗口属于临时状态。灾后不要复活旧登录或继续中断上传，恢复时清除对应临时表并要求重新登录；稳定业务内容、版本、身份和密码哈希保留。
7. 核对目录、预设原件、样片、头像、个人预设、用户与版本发布/撤回策略。检查私有对象匿名请求仍被拒绝，再切回业务流量。

云服务密钥、腾讯云账号权限、CloudBase平台内部auth/storage迁移、COS中断上传分片不属于此备份包。需要在恢复环境重新配置服务密钥和运行角色。此备份是应用级逻辑数据与文件副本，不是整个云账号或PostgreSQL实例的物理镜像。

每日任务只在备份对象全部回读成功后写COMPLETE；成功后才清理本备份前缀中超过30天的旧对象。业务数据、原照片/预设文件及原APK均不删除。
