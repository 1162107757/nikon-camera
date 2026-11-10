# 腾讯云 COS 更新包存储

2026-11-08 已完成线上切换。后台后续上传的 APK、上传分片和最终下载均使用腾讯云 COS；现有 23 条版本记录、上架/撤回状态、修订号与强制更新策略保持一致。当前公开测试版仍为 115 / 0.23.4-beta，本次未发布新的 App 安装包。

## 线上配置

- 桶：`huevia-updates-1252602548`，地域 `ap-shanghai`，单 AZ 标准存储、私有读写、SSE-COS AES256。
- APK：`huevia-updates/app-releases/`；上传分片：`huevia-updates/app-upload/`。数据库保留原来的逻辑路径，适配层添加独立前缀。
- 下载域名：`https://download.huevia.cc`，CNAME 直连 COS，强制 HTTPS。证书 `cBmyGXt7` 已绑定，公网证书链验证通过。**免费证书有效至北京时间 2027-02-05 21:59:59，需在到期前续期并重新部署；未开通付费自动续期。**
- 执行角色：`HueviaUpdatePackageRole`，ID `4611686018450225576`；仅 SCF 载体，关联 `HueviaUpdatePackageStorage`（ID `293055026`）。用户已确认授权并完成腾讯云本人核验。
- 策略仅允许上述两个指定前缀的 GetObject、PutObject，没有其他桶、删除、列举或账号管理权限。策略在 [cos-release-policy.json](../online-library/infra/cos-release-policy.json)。
- 线上选择 `APP_RELEASE_STORAGE=cos`；现有其他环境变量逐项保留。预设、摄影样片、头像和数据库继续使用原服务。

运行时通过 SCF 保留请求头读取每次请求的新临时凭证，用 AsyncLocalStorage 隔离并发请求；仅在 SCF 环境且请求来自本地代理时接受，不记录或返回凭证。没有创建或保存主账号长期密钥。

## 上传与下载行为

`server/cos-release-storage.mjs` 仅接受内容寻址的 APK 和上传分片路径。写入带 Content-MD5、禁止覆盖标志；遇到 COS 的 `FileAlreadyExists`（409）会重新读取并校验完整对象大小和 SHA-256，只有内容完全一致才复用。同一版本或同一安装包仍由既有数据库规则拒绝重复创建。

版本元数据中的 `/preset-library/releases/{id}/file` 不变。COS 模式包含历史小包，都在校验真实 COS 对象、下载预算及最新上架状态后返回零 body 的 307。链接限定 HTTPS 域名、Host、对象路径和下载文件名，最长有效 60 秒；不使用函数内置 APK 替代 COS 对象。撤回阻止新的签名发放，已发放的短时链接在原有效窗口内仍可能使用。

单包 32 MiB、512 KiB 分片、0–63 索引和既有流量预算保持不变。本次未更改 Android 客户端、预设编辑器或本地 154/155 安装包。

## 迁移与验收

原 CloudBase 私有对象中的 23 个历史包共 **116,371,212 字节**，先逐包检查大小、SHA-256、包名、版本和 APK 签名，再上传 COS。随后通过 COS 控制台选择自定义 HTTPS 域名逐包下载回读，23/23 完全一致。原对象保留。

- [来源校验](validation/cos-migration-20261107/source-integrity.json)与[目标回读校验](validation/cos-migration-20261107/target-integrity.json)。
- [公网 HTTPS](validation/cos-migration-20261107/public-https.json)：证书域名正确；未签名的当前 APK 对象 GET 返回 403。
- [线上 COS 验收](validation/cos-migration-20261107/live-cos.json)：首页、后台页、健康、预设目录、115 版元数据一致、完整 COS 下载字节与签名、已撤回版本携带 ETag 仍返回 404，7 项通过。
- [真实后台上传](validation/cos-migration-20261107/upload-verification.json)：19 个分片写入 COS、读取校验并合并完整包；同名文件精确复用，重复版本正确拒绝。23 条版本元数据不变；仅本次两项验收任务已主动设为过期，测试分片保留在私有目录。
- [官网实际下载](validation/cos-migration-20261107/browser-download.json)：从首页点击“下载 Android 安装包”，完整取得 9,531,300 字节的 115 版 APK，SHA-256 一致。
- 最终后台测试 188 项：181 通过、7 项已有条件跳过、0 失败。COS 专项 6 项全过，覆盖内容寻址/重试、大小限制、路径隔离、官方 SDK 精确签名、并发临时凭证隔离和历史小包的撤回门控。源码语法检查通过。

## 部署与回滚

原函数 ZIP、配置与版本清单备份在忽略目录 `online-library/.local/cos-migration/`。首次部署以真实线上 ZIP 为基础，仅覆盖 3 个服务文件并加入 COS 适配及 3 个官方 SDK 文件，共 7 个文件。真实上传验收发现同名对象返回码兼容问题后，仅修正适配文件；两次部署均逐文件验证其他内容及文件权限保留。

审计/准备入口：`audit-cos-migration.mjs`、`prepare-cos-apks.mjs`、`prepare-cos-deploy.py`；配置切换/恢复入口为 `deploy-cos-storage.mjs`。验收入口为 `verify-cos-readbacks.mjs`、`verify-cos-live.mjs --cos`、`verify-cos-upload.mjs`。后者包含仅针对本轮两项测试任务的过期清理，不应用于其他上传。

尚未产生 COS 独有的新版本时，可恢复原存储配置与原运行角色，兼容代码仍支持 CloudBase。切换后若有新上传，回滚前必须先复制这些新增对象并校验，避免数据库中的新版本在旧存储缺失。原历史对象与备份 ZIP 不删除。

官方 SDK 固定为 `cos-nodejs-sdk-v5@3.0.0`，通过隔离的 esbuild 工具打包，无运行时 npm 安装。重建入口为 `online-library/scripts/build-cos-sdk.mjs`；版本、来源、哈希和依赖许可保存在 `server/vendor/`。

## 官方依据

- [COS Node.js SDK 预签名 URL](https://cloud.tencent.com/document/product/436/36121)
- [新 COS 桶分发 APK 的域名限制](https://cloud.tencent.com/document/product/436/96243)
- [SCF Web 函数保留请求头](https://cloud.tencent.com/document/product/583/56124)
- [SCF 临时凭证更新机制](https://cloud.tencent.com/document/faq/583/9180)
- [COS 资源级权限格式](https://cloud.tencent.com/document/product/436/31923)
