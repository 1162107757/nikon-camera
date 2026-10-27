# App 普通更新与强制更新

2026-10-25 实现并随100版上线。扩展现有版本发布体系，不新增版本表或下载入口。

## 大安装包容量与签名下载（017，2026-10-27 已部署）

APK 校验、后台选择文件、数据库版本/上传行和上传 RPC 的单包上限改为 32 MiB；512 KiB 分块保持，索引扩展为 0–63。升级生产数据库应应用 `database/017-app-release-capacity.sql`，不能只替换服务文件。该迁移也把既有私有 `nikon-presets` bucket 的对象容量同步至 32 MiB，不改变 public/允许 MIME 配置。迁移可重复执行，不改变已有版本内容、发布状态、修订号或强制策略。预设、样片和头像应用接口的限制不受影响。

现有预算继续保持：上传 256 次变更请求/15 分钟、64 MiB 实际写入/日（分块和最终对象双计）、64 MiB 声明上传/日、4 个同时上传任务；下载每来源 20 次及 80 MiB/小时，全局 1000 次及 2 GiB/日。提高单包容量没有扩大流量预算。签名、包名、精确字节、SHA-256、修订和独立发布确认继续校验。

容量校验不等于传输能力。当前 `scf_bootstrap` 监听 9000 的 Web Function 经网关响应，腾讯官方列明[Web 函数响应 body 不超过 6 MB](https://intl.cloud.tencent.com/zh/document/product/583/40688)。本地新增大包路径：`/releases/:id/file` 对超过 4 MiB 的包先校验真实私有存储对象的精确字节与 SHA、发布状态和下载预算，再通过 [PG Storage 签名 API](https://docs.cloudbase.net/storage/pg/serving)签发 60 秒 URL，并再次检查发布状态后返回零 body 的 307。URL 只允许配置的 Storage API 同源、同 bucket、同 SHA 对象签名路径和单一有界 JWT token；仅由不可变版本身份追加严格的 `download=Huevia-<code>-<channel>.apk` 文件名，不接收任意 query；不把服务密钥交给客户端。小包保留原字节响应。撤回停止新签名发放，已经发放的 token 在短期有效窗口内仍可能可用。

自有小夹具的真实云端对照发现 `.apk` 后缀或 APK MIME 对象会被底层 COS 拒读；因此新完成对象使用同 SHA 的物理 `.bin` 键和 `application/octet-stream`，精确字节、APK 签名/manifest 和逻辑下载文件名均保持 APK。017 同时接受历史 `.apk` 与新 `.bin` 键，不改已有记录。真实 `.bin` 小夹具经生产签名方法无鉴权 GET 200，字节/SHA 和 `attachment; filename=Huevia-111-beta.apk` 均验证，夹具已清理。上线前仍须验证真实大包公网回读 SHA 和 Android DownloadManager 跟随 307。旧 108 客户端仍有 4 MiB 本地限制，需要从下载页覆盖安装一次；服务端不能通过伪报大小消除旧客户端限制。

本地聚焦 Node 18 项（无跳过）和隔离 PGlite 验收通过，包括真实 9,478,052 字节签名 APK 跨第 8 块上传、精确 SHA/签名、32 MiB / chunk 63 边界、越界拒绝、旧强制策略保留、原预算及签名 URL allowlist/生命周期/撤回门控/严格 APK 文件名。见 `../docs/validation/release-capacity-110/`。本地测试范围不代表真实大包或设备下载验收，后台上线回执如下。

2026-10-27 后台上线已完成：先备份约束、4 个 RPC、私有 bucket 元数据、17 条版本及 390 条目录签名，再应用 017；旧版本逐字段与目录签名保持。代码基于当时最新生产 ZIP 仅覆盖 `server/apk.mjs`、`server/cloudbase.mjs`、`server/releases.mjs`、`admin/releases.js`。拉回部署 ZIP 的 45 个成员逐内容及 Unix 模式核对，只有这 4 个文件变化，8 份历史 bundled APK 保留；函数 Active，环境/运行时及其他非代码配置保持。生产回读 ZIP SHA 为 `8975da9434325ebd0f047f14a660736350616d810bf66d9aaeeb5038867b9395`。双 Origin 的 32 MiB 后台脚本、390 份目录和旧 108 完整字节/SHA/强制策略均核对通过。此处只记录后台上线，最终 APK 上传、上架和设备大包下载由发布任务单独记录。

## 100版上线状态

用户明确授权“完成后上传测试强制更新”后，已应用014、仅替换服务端/后台两处发布模块并加入经过主任务三配置复验的100安装包。线上 `cc.huevia / beta` 已发布0.21.1-beta（100），release ID `a7a5ad8b-db8a-4de6-b951-adf0a71ff02c`，`mandatory=true`、`revision=3`（导入草稿1、策略2、发布3）。

采用此前76–83版的服务角色及bundled签名制品导入流程，导入审计明确记录该方式和 `privateObjectUploaded=false`，随后通过同一有管理员校验、修订及制品确认的策略/发布RPC完成。没有重置管理员密码，也未更改旧发布记录或其策略。代码部署后的44项内容与Unix模式全部核对，六份旧随包APK、云环境变量及Nodejs20.19运行时保持。

两个公开Origin（`https://huevia.cc` 和既有CloudBase Origin）分别验证完整3,901,562字节APK、SHA256 `4ebc35f9fc5930080ba994a6bffe7538feec5bc8679066c698d8f3001b9e37f0`、原证书v2/v3；99返回强制更新，100当前版、101更新客户端及sdk25不兼容场景均不强制。stable及旧包名查询保持原语义；14条旧release逐字段核对不变，只有迁移新增默认false。此次发布端未操作ADB或设备，实际99客户端提示/安装由主任务单独记录。

## 配置

后台“App 版本 → 查看版本”增加更新方式。默认普通更新；管理员可对草稿或已上架版本选择强制更新，保存前需勾选确认。上架仍使用原有独立确认流程，APK 内容、版本号、签名、渠道和包名不可覆盖。

强制更新适用于同包名、同渠道、系统兼容且版本较旧的客户端。当前版本、更新的客户端、不兼容系统、未上架及已撤回版本均不会收到 `updateRequired=true`。本轮不提供最低强制版本区间。

已上架版本可保存回普通更新；版本 `revision` 增加，客户端下次成功检查后解除要求。撤回同样取消更新要求，并阻止新下载；不自动退回更旧发布。网络失败不等同于服务端撤销，客户端按其本地交互策略处理。

## 公共契约

`GET /preset-library/releases/latest?channel=beta&packageName=cc.huevia&versionCode=98&sdk=35`

沿用 `schemaVersion: 1` 和所有原字段，增量示例：

```json
{
  "schemaVersion": 1,
  "channel": "beta",
  "updateAvailable": true,
  "updateRequired": true,
  "reason": "available",
  "release": {
    "id": "原版本 UUID",
    "versionCode": 99,
    "mandatory": true,
    "revision": 4
  }
}
```

示例省略了现有包名、版本名、SHA-256、签名、最低 SDK、大小、说明和下载地址。字段 `mandatory` 表示版本设置；顶层 `updateRequired` 表示本次请求是否必须更新，计算式为 `reason === 'available' && release.mandatory === true`。缺省策略字段视为普通更新。响应继续 `Cache-Control: no-store`；旧客户端能继续解析原字段，但不能补强其旧代码中的更新行为。

## 管理 API

`PUT /preset-library/api/releases/:id/policy` 复用现有管理员登录、CSRF、变更请求预算。

```json
{
  "expectedRevision": 3,
  "mandatory": true,
  "confirmation": "REQUIRE 99 <该版本完整 sha256>"
}
```

改回普通更新传 `mandatory: false` 和 `OPTIONAL 99 <sha256>`。布尔值必须是真正的 JSON 布尔值；字符串和数字拒绝。函数 `nikon_app_release_policy` 与发布/撤回共用事务锁并检查修订号；旧窗口写入返回冲突。重复保存同一策略不增加修订或审计。已撤回版本拒绝策略修改。

数据库列 `nikon_app_releases.mandatory boolean NOT NULL DEFAULT false`，审计 action 为 `policy`，details 保留 `previousMandatory`、`mandatory`、`versionCode`、`sha256`、`channel`、`revision`。匿名及普通用户没有此函数权限；仅服务角色可在服务端验证管理员后执行。

## 部署与发布脚本

先审阅并应用 `database/014-app-update-policy.sql`（前置 006，通常按序到 013 后），再部署对应服务器和后台。迁移可重复执行；历史草稿、上架或撤回行均默认普通更新，不自动发布或开启强制更新。数据库迁移不会被服务 ZIP 自动执行。

原发布命令保持兼容，默认新上传为普通更新：

```powershell
node scripts/publish-app-release.mjs <signed.apk> --publish --notes-file <notes.txt>
```

显式 `--mandatory` 设置强制，`--optional` 设置普通；二者互斥。带策略参数会先通过同一管理员 API 保存策略，再发布草稿；已上架版本则只显式调整其策略。**无策略参数时保留已复核的现有设置，不会把强制版悄悄改成普通版。** 脚本继续验证已发布 APK 字节、包名、SHA-256 和公开更新元数据；显式策略必须与公开 `mandatory/updateRequired` 一致才报告成功。

发布脚本会真实上传/修改/上架，不属于本地验收命令。99本地实现阶段未执行远程变更；100已按用户后续明确授权完成上述上线与强制策略配置。本次没有执行这个普通上传脚本，采用的是已有bundled导入、策略及发布RPC流程；不得将随云函数分发的APK记为私有对象存储上传成功。

## 本地验证

```powershell
node --experimental-vm-modules --test test/releases.test.mjs test/publish-app-release.test.mjs
node test/release-postgres.mjs
node scripts/check.mjs
```

聚焦 Node 测试 13 项通过，包括可用/不兼容/撤回/缺省契约、同版本解除强制、管理员/CSRF/类型/修订/确认校验、无重复审计、发布脚本兼容及显式策略。脚本测试完全拦截文件与网络，只使用合成安装包元数据；HTTP 测试使用本机服务及内存库，其中原有签名与下载校验仍使用已有本地历史 APK。

隔离 PGlite 通过原发布生命周期验收及新增策略权限/审计/撤销断言，实际应用迁移两次并验证历史上架行仍普通；合成数据事务最终回滚。64 个 JavaScript 模块语法检查通过。测试日志在 `.tooling/app-update-policy/`。这些是99实现阶段的本地检查；100发布新增的真实云端权限、44项代码/模式、双Origin下载及更新边界证据在 `.tooling/app-update-rollout-prep/`，包括 `public-verification-100.json`、`migration-014-applied.json`、`deployment-100.json` 和 `cloud-zip-independent-verification.json`。没有浏览器视觉验收；Android行为与安装包由主任务独立验收。
