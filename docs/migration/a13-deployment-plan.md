# A13 云端分发待审计划

状态：仅离线准备。没有执行数据库迁移、IAM 修改、函数部署、上传或公开发布。实际 213 APK/IPA 尚待统一构建；本计划不填写未取得的产物摘要、版本文件 URL 或发布 ID。

## 审批对象与执行顺序

离线包由 `python online-library/scripts/package-mobile-release-review.py` 生成，含可部署的主 Web 函数 ZIP、备份 worker ZIP、022 SQL、两份精确 IAM 策略、回退说明及逐文件 SHA-256 清单。运行打包命令不会连接云端，不读取 `.local` 或环境凭据。源代码改变后须重新生成并核对清单。

审批分为同一份计划中的三个明确范围，均待主任务拿到实际产物后一次提交复核：

1. 应用 022、增加指定 COS 前缀权限、更新两个既有函数代码，保留原环境变量、函数身份、超时、内存、触发器与域名配置。
2. 将逐个验过身份、平台、签名、ABI 与摘要的实际 213 安装包上传为私有 draft。实际文件清单由脚本检查输出附入，不用开发夹具代替。
3. 复核 draft 的实际版本、SHA-256、更新说明与渠道后，使用精确 `PUBLISH versionCode sha256` 确认发布，并匿名回读下载文件核对全部字节。上传 draft 不等于批准公开发布。

## 数据库 022 的作用范围

`022-mobile-releases.sql` 只新增独立的 `nikon_mobile_releases`、`nikon_mobile_uploads`、`nikon_mobile_upload_chunks`、`nikon_mobile_release_audit`、`nikon_mobile_release_budgets` 五张表、对应序列/索引、不可变触发器和两个服务 RPC。每次应用在事务内；重复执行不新增版本或重新发布。

RLS 开启；PUBLIC、anon、authenticated 无表或 RPC 权限，仅 service_role 具备明确授权。管理员仍须通过既有登录、有效账号复核、Origin 与 CSRF 检查。分块按管理员、上传 ID、平台、序号、声明字节、摘要、准备状态绑定。相同分块可重试，冲突内容拒绝；最多 256 个 512 KiB 分块、128 MiB 文件，组装验证时仅允许一个处理任务。上传及下载预算与旧版分开，不扩大旧版额度。

不改既有 `nikon_app_*` 表、旧发布历史、旧会话/QQ/预设资料或原 SQL 迁移，不自动建立发布数据。发布后的字节/身份/渠道/说明不可覆盖；撤回保留高水位，不以旧版本替代。

## 平台信任规则

| 安装身份 | 验包入口与大小 | 签名/平台 |
| --- | --- | --- |
| `cc.huevia`、`com.nikonpreset.usbprobe` | 原接口；默认 `inspectApk` 提前限制 32 MiB | 原证书 SHA-256 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`；原签名校验与不支持的签名方案/轮换拒绝规则保留 |
| Android `cc.huevia.next` | 仅显式指定 next 的独立 mobile 上传；128 MiB | 固定证书 SHA-256 `76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75`；完整内容签名、版本、包名、ABI；不允许旧证书替代。实际 213 仍须再次验签 |
| iOS `cc.huevia.next` | 独立 unsigned-ipa 上传；128 MiB | ZIP/CRC、binary 或 XML Info.plist、版本、最低 iOS、ARM64 Mach-O iPhoneOS platform=2；拒绝模拟器及带 `_CodeSignature`/provisioning 的分发包 |

next 的 ABI 从 APK 实际 native libraries 解析；自动更新查询携带当前 ABI，arm64 文件不会提示给 x64 安装。现有唯一版本约束按平台/包名/版本，不会把相同版本的两个 ABI 文件当作同一个可覆盖文件；如需同时公开多个 ABI，须另行制定多资产目录，不能将第二个文件覆盖第一个版本。

Android 安装前再次核对字节、SHA-256、包名、版本、当前与发布证书。iOS 下载后再次核对摘要、Bundle ID、版本、最低系统和真机平台，再导出供用户自行签名；没有 App Store、TestFlight 或应用内直接安装的承诺。

## COS 与备份权限

桶固定 `huevia-updates-1252602548`，上海 `ap-shanghai`，保持私有；沿用现有角色，不新增用户密钥。

- Web 函数只在原 `huevia-updates/app-releases/*` 与 `huevia-updates/app-upload/*` 外，增加 `huevia-updates/mobile-releases/*`、`huevia-updates/mobile-upload/*` 的 GetObject/PutObject。源码进一步限制为 `mobile-releases/{ios|android}/{sha256}.bin` 与 `mobile-upload/{uuid}/{0..255}-{sha256}.part`，不允许其他对象或上传分块签名下载。
- 下载仍使用真实既有域 `https://download.huevia.cc`，对正确对象及 ASCII 安装包文件名签名，最长 60 秒；回读校验后签名，并在返回响应前重新检查撤回状态。签名 URL 不落入 App 长期配置或发布清单。
- 备份角色仅增加 `huevia-updates/mobile-releases/*` 的 GetObject。原 `huevia-backups/daily/*` 写入/30 天清理范围不变；不增加源文件删除或源目录列举权限。新已验证版本的真实字节与新表数据进入备份；未完成 mobile-upload 分块明确排除在持久文件恢复合同外。

## 实际接口地址

共同 BASE 为 `https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library`。以下是源码路由，部署前不当作已经在线可用的服务。

| 用途 | BASE 后路径 |
| --- | --- |
| 旧两包版本/下载 | 原 `/releases/latest` 与 `/releases/{releaseId}/file`，行为保留 |
| next 版本查询 | `/releases/latest?packageName=cc.huevia.next&channel=beta&versionCode=<本机版本>&sdk=<系统API>&abi=<本机ABI>` |
| next 管理 | `/api/next/releases`、`/uploads`、`/uploads/{uploadId}/chunks/{index}`、`/uploads/{uploadId}/complete`、`/{releaseId}/publish`、`/{releaseId}/withdraw` |
| next 文件 | `/next/releases/{releaseId}/file` |
| iOS 版本清单 | `/ios/releases/latest?bundleId=cc.huevia.next&channel=beta` |
| iOS 管理 | `/api/ios/releases` 及相同 uploads/publish/withdraw 子路径 |
| iOS 文件 | `/ios/releases/{releaseId}/file` |

实际 releaseId/file URL 必须采用服务对真实产物验完后返回的结果。iOS `HueviaIosReleaseManifest` 可指向上述稳定清单地址；未部署、无发布或已撤回时明确报告不可用，不伪造现有版本。

## 实际产物就绪后的本地检查与 draft

从 `online-library` 工作目录运行 `node scripts/prepare-mobile-release.mjs <实际.apk或.ipa路径> --notes-file <已复核说明文件>`，默认只做本地检查，不读管理员会话、不连接云端。输出实际摘要与精确发布确认文字。

取得本次批准并完成服务准备后，`--upload-draft` 才通过既有管理员会话及 CSRF 上传；脚本不输出 Cookie、CSRF 或云凭据。`--publish --confirm "PUBLISH <真实版本号> <真实SHA256>"` 是独立明确的公开发布动作。`--verify-public` 只回读已经发布的实际文件并核对完整摘要。

## 回退

审批前/部署前由主任务只读归档当前 Active 主函数与备份 worker 的代码包、校验其 SHA-256，并记录当前两份 IAM 策略版本。离线计划中相应项保持“待抓取”，不把本地 Git 基线冒充生产镜像。

发生异常时，先用有效管理员会话撤回本轮实际新版本，确认 `WITHDRAW <真实版本号> <真实SHA256>` 与 expectedRevision，阻断新下载。恢复刚归档的两个代码包及原策略版本；保留环境变量、QQ AppID、原服务账号、域名、触发器与历史旧包发布状态。原两包接口与资料无需回退数据。

022 是追加结构，回退时保留其表、文件、审计与版本高水位，不执行 DROP/DELETE 或复活撤回版本。需要停用新管理入口时可使用包内 `disable-mobile-release-management.sql` 仅撤销新管理 RPC 的 service_role 执行权；恢复需复核后再次应用 022。已经安装的新 App 继续使用本机资料与既有业务功能，更新服务会明确不可用，不强迫降级或清空数据。

## 明确待办

实际 213 APK、IPA、各自摘要与最终说明尚待主任务提供；当前生产代码/IAM 回退快照待批准前只读归档；云端所有改动与公开发布尚未执行。用户明确 QQ iOS Universal Link“还未配置”，Team ID/Associated Domains/AASA 与真实 QQ 授权属于独立外部验收条件，不在本部署中伪造或代填。
