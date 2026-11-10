# 官网下载 JSON 修复 · 2026-11-08

用户反馈点下载得到 JSON。复现为 HTTP 429 `RELEASE_BUDGET`：单来源小时字节额度为 80 MiB，29.84 MiB 的 156 包第三次请求就会超过额度。网页链接的 `download` 属性让浏览器把 JSON 错误响应保存成文件。

修正：

1. 018 迁移将单来源小时字节额度改为 256 MiB，可容纳八次当前完整包请求；每小时 20 次请求、全局每天 1,000 次／2 GiB、32 MiB 单包上限、上传额度及历史使用量保留。线上只替换预算函数中的一个字节常量，没有清零或删除记录，见 [budget-applied.json](budget-applied.json)。
2. 两个网页链接去掉强制 `download` 属性，成功下载由服务器 APK 附件响应决定文件名。浏览器文件导航错误返回可读 HTML 和返回下载页入口；App、`application/json` 和 `*/*` 客户端保留原 JSON 错误语义。
3. COS 的 ASCII 文件名改用无需引号的合法 token，避免响应链路中的引号反斜线转义。对象路径、短时签名、有效期、Host 校验与私有权限保留。

生产包先备份再最小覆盖：第一阶段仅变更 `server/app.mjs`、新增 `server/release-download-error.mjs`、更新 `download/index.html`；第二阶段仅变更 COS 响应文件名。其余负载与模式、环境变量和执行角色不变。最终函数 Active／COS，ZIP SHA-256 `c8802c9546809a97a11bbe0bae050af9ca395e6d5cf55fbc5e3cbbf840b69290`。见 [function-deployment.json](function-deployment.json)、[filename-deployment.json](filename-deployment.json)。

官网当前目录 `/var/www/huevia-home/releases/20261108-download-13140639`，`current` 原子切换到该目录；旧目录保留，可回退。Caddy 配置未改，其他 14 份网页资产保留。

验证：

- 后端完整回归 191 项：184 通过，7 个原有条件跳过，0 失败。下载错误、COS、重定向、网页及真实隔离 PostgreSQL 配额的 19 项全部通过；验证旧额度第三个包失败、新额度八个包成功、历史使用不清零、次数和全局额度仍受限。可选隔离 PG 测试在本机实际运行通过。
- 线上不存在的版本，HTML 导航返回 404 可读页面且无附件头；JSON 客户端保留 404 JSON。Android 156 上架状态与普通更新策略保留。
- Chrome 真实从官网下载，取得 **`Huevia-156-beta (1).apk`**（本机已有同名文件），31,292,511 字节，完整 SHA-256 `9223d32f9db99cec28282c3af007acff9cf1fb36a724c14b2525ad7ccef4fc95`。生产解析器确认包名 `cc.huevia`、versionCode 156、最低 API 26、原证书 V2／V3。详见 [download-result.json](download-result.json)。完整文件保存在忽略目录 `.tooling/download-json-fix/website-download.apk`。

首屏、下载区和完整下载页的 iOS“正在准备中”同时保留。用户刷新页面后重新下载即可。
