# 99 · 实施与验证入口

## 客户端

`AppUpdateManager` 接收严格布尔 `release.mandatory` 及修订号，缺字段按普通更新。`mandatory()` 同时检查已安装版本；保存可信版本元数据用于进程恢复，成功的服务端响应可以取消／撤回，离线失败不会伪造取消。下载／校验期间仍可排队重查策略；同一APK只变策略时保留进度，制品身份变化则清理旧候选。安装前再核版本、包名、URL、字节、SHA、签名和SDK。

`UpdatePanel` 显示紧凑普通弹窗和不可跳过的强制弹窗，进度原位更新。普通提示8小时去重，检查／下载／校验中不额外弹普通提示；强制提示保留重新检查和退出。前后台暂停恢复、系统安装来源授权及原有installEpoch守卫保留。`MainActivity` 仅新增强制提示安全时点Host接线；98诊断及照片功能保持。

## 后台

`014-app-update-policy.sql` 增加默认false的策略及带生命周期锁、revision、制品确认与审计的RPC；管理员会话、CSRF及权限检查沿用现有路由。管理页可调整草稿／上架版本；撤回优先，撤回版本不可重设策略。公开schemaVersion仍为1，release增加mandatory/revision，顶层updateRequired只针对更高、兼容且已发布版本。

发布脚本支持显式 `--mandatory`／`--optional`；未指定时保留已有策略，新上传默认普通。部署顺序和使用说明见[APP-UPDATES.md](../../../online-library/APP-UPDATES.md)。本轮未执行任何远程SQL、服务部署、上传或版本上架。

## 验证

- [客户端核心复核](CORE-REVIEW.md)：最终策略66项、实际生产manager的离线host状态37项及SDK35定向编译。host使用Android／JSON夹具，不能替代系统DownloadManager／安装器测试。早期62／32保留为历史，不合算最终独立场景。
- 后台13项聚焦Node测试、隔离PostgreSQL迁移／权限／撤销／审计验收、64模块语法检查；日志分别保存为backend-tests.txt、database.txt、syntax.txt。后端独立只读复核未发现本轮阻断问题。
- [最终身份](FINAL-IDENTITY.json)固定214项原生输入和4项后台输入，安装包为99／0.21.0-beta；构建与v2/v3签名通过。
- Android组件探针验证实际UpdatePanel、Release及manager状态读取，测试Activity跳过MainActivity初始化，GuardExecutor禁止一切后台网络任务。注入状态只证明原生界面／生命周期，不代表真实网络下载、系统文档选择器、安装器或实体手机验证。

最终原生结果、截图复核、清理和交付边界见[完成复核](FINISH-REVIEW.md)。
