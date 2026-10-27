# APK 容量升级本地实施记录

2026-10-27，已按根任务后续授权应用 017 并仅部署四个必要服务/后台文件。未上传真实安装包或修改线上发布策略、管理员密码及环境配置。此前限定授权的 8 个自有小云存储夹具均已精确清理。

## 范围

- `online-library/server/apk.mjs`：完整签名 APK 输入上限 32 MiB；保留 pinned signer、包名、v2/v3 全内容签名、ZIP 展开预算与 manifest 验证。
- `online-library/server/releases.mjs`：声明上限 32 MiB，512 KiB 分块索引扩展到 0–63；拒绝 64、负数和非规范前导零索引。超过 4 MiB 使用下文的私有签名重定向路径。
- `online-library/admin/releases.js`：文件选择限制与文案一致为 32 MiB。
- `online-library/database/017-app-release-capacity.sql`：扩展 releases/uploads 的 byte_length CHECK、chunks 的 chunk_index CHECK，以及 upload_budget、release_budget_atomic、upload_begin、upload_check 四个既有 RPC 的单次容量校验。既有私有 bucket 的对象限额从 4 MiB 同步至 32 MiB，public/允许 MIME 和其他 bucket 保持；版本物理存储键同时接受旧 `.apk` 和新 `.bin`。重复执行安全，不创建发布、改变已有强制策略或修订号。
- 原有预设、样片、头像上限未改；上传/下载次数、实际字节及声明字节预算未扩大。

## 验证

`node --test test/apk.test.mjs test/releases.test.mjs test/release-capacity.test.mjs`：11/11 通过、0 跳过，日志 `node-tests-first.log`。

新专项使用 `dist/huevia-0.22.1-beta-debug.apk`：9,478,052 字节，SHA-256 `852d17a89984f82f4af9d116c7bacb17b3243675299ce07de3bf237692b508c6`。本地内存对象存储真实写入全部分块及合并对象，服务端实际解析 manifest、验证两套签名与完整文件 SHA，草稿默认普通更新；没有使用网络上传或发布操作。修改受保护 APK 字节仍拒绝。

`node test/release-postgres.mjs`：隔离 PGlite 通过原有生命周期/权限/策略和新容量验收。017 实际执行两次，历史 published/mandatory=true/revision=7 行保持；32 MiB 声明、64 个分块完整 reserve/ready/claim/create、32 MiB+1 及第 64 块拒绝、原 64 MiB 实际写入预算与 80 MiB 每来源下载预算均验证。所有合成数据事务回滚，最终 releases/uploads/audit 为 0。日志 `postgres-first.log`。

聚焦 `git diff --check` 通过，仅有仓库既有 LF/CRLF 提示。本地阶段未操作 Android、构建版本或设备；后续限定的云存储验收与后台上线分别记录如下。

新增私有签名下载后，执行 `node --test test/apk.test.mjs test/releases.test.mjs test/release-capacity.test.mjs test/storage-signed-download.test.mjs test/release-redirect.test.mjs test/http.test.mjs`：17/17、0 跳过，日志 `redirect-tests-first.log`。覆盖既有小包/内联下载、真实签名大包上传、零 body 的 307、真实私有对象长度/SHA 校验、预算拒绝、读取中及签名中撤回、错误 URL、过期/超长 token、外部 host、公有对象、错误 bucket/path、重复 query、密钥 echo 和 provider 错误信息不泄露。

补齐私有 bucket 限额后再次执行隔离 PGlite，日志 `postgres-bucket-final.log`。夹具验证目标 bucket 为 private 且限额 32 MiB，不相关 bucket 可见性/容量保持；017 重复执行及容量/策略/预算验收通过。

真实存储对照后补齐 `.bin`/octet 兼容与严格 APK 文件名，最终 Node 18/18、0 跳过，日志 `bin-redirect-tests-final.log`。新增断言最终对象 MIME、SHA 物理键，以及严格文件名参数/注入拒绝。最终 PGlite 日志 `postgres-bin-confirm.log`，验证 32 MiB 新 `.bin` 行可创建，历史 `.apk` 行不改。之前 `postgres-bin-final.log` 保留了首次失败：006 的跨列 CHECK 实际命名为 `nikon_app_releases_check`；017 现明确替换这个旧约束和新的命名约束，复测通过。

## 大包传输约束与实现

当前服务是 `scf_bootstrap` 启动的 9000 端口 Web Function。腾讯官方[Web 函数概述](https://intl.cloud.tencent.com/zh/document/product/583/40688)和[配额限制](https://cloud.tencent.com/document/product/583/11637)列明同步/HTTP 响应体 6 MB 上限。`huevia.cc` 当前 Caddy 代理到该上游，代理本身不会扩大上游响应能力。

本地实现通过 [CloudBase PG Storage 的官方签名 API](https://docs.cloudbase.net/openapi/storage.v1.postgres.openapi.yaml)绕开函数 body 上限：`POST /v1/storages/object/sign/{bucketId}/{objectName}`，请求 `expiresIn=60`。大于 4 MiB 的公开 `/releases/:id/file` 始终读取并核验真正的私有对象，不使用 bundled 副本充当被签名对象的证据；检查预算与发布状态，核大小/SHA，签名前后复查发布状态，返回 `307`、`Content-Length: 0`、`no-store` 与 `Referrer-Policy: no-referrer`。小包的 inline/bundled 行为保持。

`CloudBaseStorage.signDownload` 仅允许所配置 Storage API 的精确 HTTPS origin，路径必须为 `/v1/storages/object/sign/<configured-bucket>/app-releases/<SHA>.bin`（保留旧 `.apk` 精确路径兼容），provider query 必须只有一个 JWT token。检查 provider token 的 exp 在请求的 60 秒内（允许 5 秒时钟误差），拒绝服务凭据 echo；服务凭据仅发送给固定签名 POST，`redirect:error`，不会用服务鉴权请求签名 URL。仅在验证后从不可变版本身份追加严格格式 `Huevia-<positive-code>-<beta|stable>.apk` 的 download 参数；任意额外 provider query 和文件名注入仍拒绝。无 COS 通配 host、公有 bucket、上传签名、外部 URL 或第三方凭据转发后备路径。未知 provider 形态返回通用 503，不能静默放宽。

短期签名是读取授权凭证；撤回会停止新的授权发放，但已发放 token 在短期有效窗口内仍可能可用。不得向用户声称已发签名立即失效。每次 API 签发前保留原下载预算和完整校验。

## 真实小夹具验收与后缀/MIME兼容

使用根任务授权的既存服务凭证，先精确核对 ENV_ID。仅在私有 bucket 写入 UUID 唯一内容、SHA 唯一路径的小夹具，不读写既有对象；未迁移数据库或发布安装包。所有回执只含 host/path、TTL、HTTP 状态、字节/SHA 和 cleanup，不含服务密钥、完整签名 URL 或 token。

- `LIVE-STORAGE-SIGNING.json`：PG 返回的 `fullSignedURL` 与 `signedURL` 均为预期 HTTPS API origin、exact 签名对象路径，真实 JWT TTL=60 秒，生产 URL allowlist 校验通过；但物理 `.apk` GET 403。
- `LIVE-STORAGE-SIGNING-DIAGNOSTIC.json`：明确错误是 `STORAGE_ACCESS_DENIED / cos get object denied (HTTP 403)`，不是缺客户端鉴权；不应通过向客户端发送 serviceKey 来修复。
- `LIVE-STORAGE-READ-CONTROLS.json` 与 `LIVE-STORAGE-EXTENSION-CONTROLS.json`：相同内容、相同 octet MIME 下 `.apk` 拒读、`.bin` 可读；`.bin` 配 APK MIME 也拒读。官方 authenticated、既有适配器 authenticated 及无鉴权 signed 读取对照一致，排除了签名 API 不存在和 app-releases 前缀不允许的猜测。
- `LIVE-STORAGE-BIN-APK-FILENAME.json`：真实私有 SHA `.bin`、octet、production signDownload、无鉴权 GET 200；精确字节/SHA 一致，响应 `Content-Disposition: attachment; filename=Huevia-111-beta.apk; filename*=UTF-8''Huevia-111-beta.apk`，符合浏览器 APK 文件名要求。fixture 精确 DELETE 后 HEAD404。

因此新完成对象使用 `.bin` + `application/octet-stream`，仍保存完整、原字节、完整签名 APK。逻辑 release manifest/版本/包名/签名/校验和保持，客户端目的文件和浏览器下载名仍是 `.apk`。

017 扩 bucket 容量已按下节记录完成。发布仍须将最终完整包真实写入私有 `.bin` 对象，验证公开入口 307 和最终 APK 字节/SHA/签名，以及 Android DownloadManager 实际跟随重定向。小夹具回执不能作为大包公网或设备下载成功的证明。

## 后台上线记录

根任务于本地验收后明确授权必要后台上线，范围为 017 与四文件 limited overlay，不含真实 APK 上传/发布、环境变量或管理员变更。重新通过 GetFunctionAddress 拉取当时最新生产 ZIP：30,327,599 字节、SHA `c0e5aaae27ac6249182d8a7a1d16a8fd8ce83b89fad38396064558df46647ff9`，与根任务基线一致；环境/运行时配置 SHA `da33acd719d9c43196919efe50eca2461873afc885c58d961705b1218f126768` 一致。见 `DEPLOYMENT-PREFLIGHT.json`。

`DATABASE-BEFORE.json` 保存受影响约束、4 个 RPC 定义/ACL、私有 bucket 元数据、17 条版本记录和 390 目录签名。执行最终 SHA `e0e82ee6435228ad4c285ab237522541e8b1443e6dff3a410bbea347a4d57178` 的 017 后，bucket 为 private/32 MiB，其余元数据保持；32 MiB/.bin/chunk63/RPC/原预算/ACL 核对通过，17 个旧版本逐字段及目录签名保持。首次 `MIGRATION-017.json` 的 rpcCapacity=false 是验收脚本错误要求 `p_index > 63` 空白，真实函数是正确的 `p_index>63`；没有重复执行 SQL，另以空白无关检查确认，`MIGRATION-017-CONFIRMED.json` 全部通过，完整回读在 `DATABASE-AFTER-MIGRATION.json`。

以该最新 ZIP 为基线，仅替换 `server/apk.mjs`、`server/cloudbase.mjs`、`server/releases.mjs` 和 `admin/releases.js`。准备包 SHA `43d05745749aabd8d5f1dd0b62e50acab59079df6a86f1ba8f83e156a65a26ca`，由 SCF UpdateFunctionCode 部署，未运行 setup 全流程。部署后 Active，原环境/运行时配置 SHA 不变，并比较全部非代码配置字段，未发现变化。见 `OVERLAY-PREPARED.json` 与 `DEPLOYMENT-RESULT.json`。

SCF 回读 ZIP 为 30,332,276 字节、SHA `8975da9434325ebd0f047f14a660736350616d810bf66d9aaeeb5038867b9395`。平台重打包使整个 ZIP 比准备包多 4 字节；逐成员检验 45 项内容、Unix 模式、清单与准备包完全一致，且相对原生产仅上述 4 文件变化，41 成员不变，8 个历史 bundled APK 保留。见 `DEPLOYED-ZIP-VERIFICATION.json`。

上线后双 Origin 的 `admin/releases.js` 均显示 32 MiB，目录均为 390；旧 108 仍返回 mandatory=true，完整下载 3,938,426 字节/SHA `995b33c82c9f2b72835ad6a2a194a2db8fae50caebfca860f8af2e8dc3a089f1` 匹配。部署后数据库 17 个旧版本逐字段与目录签名保持。见 `PUBLIC-BACKEND-VERIFICATION.json` 和 `DATABASE-POST-DEPLOY-PRESERVATION.json`，均通过。

根任务已接手最终包的 Chrome 后台上传/上架及真实大包、Android 验收。本子任务未创建或修改线上 release 行，也未将真实 APK 写入云存储；后台上线不能被记为最终 APK 发布成功。

旧 108 的 `AppUpdateManager.Release` 会拒绝超过 4 MiB 的元信息，下载和最终安装边界又精确核字节及 SHA；不能通过伪报长度、HTTP 压缩或只扩大服务上限修复。当前完整新包应明确提示旧版从下载页覆盖一次；未来新版客户端上限由根任务同步处理。
