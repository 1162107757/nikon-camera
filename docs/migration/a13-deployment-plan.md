# A13 云端分发待审计划

状态：仅离线准备与已授权的生产只读捕获。没有执行数据库迁移、IAM 修改、函数部署、上传或公开发布。实际 213 Android 两份 APK、两个 Active 生产回退代码包、两份实际 IAM 旧策略、DB 只读前置证据及最终更新说明已取得并绑定；仅 213 IPA 尚待取得，当前审阅包仍明确未完备。不能以 212 IPA 代替缺项，不填写未取得的摘要、版本文件 URL 或发布 ID。

## 本次已取得的实际产物

Android 构建源由主任务明确为 `3db73d2`，与后续仅含 iOS/收尾变动的当前 HEAD 分开记录。打包脚本把该提交展开为完整 revision，同时声明这不是可复现构建证明或生产部署证明。

| 本地文件（`dist/migration213/`） | 字节数 | SHA-256 |
| --- | ---: | --- |
| `huevia-0.31.0-dev-213-android-arm64.apk` | 52,117,298 | `fc3abd1668e31bc40e58aefdfcbde123e3cc8873012c6cb4fc038ee5f85ff6f3` |
| `huevia-0.31.0-dev-213-android-x64.apk` | 55,554,266 | `9fae5f4883a82c38bf53b478d199452ba8c2a36b567918ecf3e19eef6fb687bc` |
| 213 iOS unsigned IPA | 尚未取得 | 不填摘要 |

原生验签/ZIP 与 ELF 16 KiB 对齐证据为 `docs/migration/validation/features-213/android-signing-alignment.json`，记录绑定上述实际文件摘要。打包时再次对实际 APK 执行服务端同源完整内容签名/证书/包名/版本/ABI 校验，核对证据摘要和全部通过标志，再把真实 APK 字节与证据收入审阅 ZIP。文件换掉、证据不匹配或版本不是 213 均中止；文件不存在则保留对应缺项，不生成假记录。

## 审批对象与执行顺序

离线包由 `python online-library/scripts/package-mobile-release-review.py` 生成，含可部署的主 Web 函数 ZIP、备份 worker ZIP、实际已校验产物、原生证据、022 SQL、两份精确 IAM 策略、回退说明及逐文件 SHA-256 清单。运行打包命令不会连接云端，不读取 `.local` 或环境凭据。源代码、实际文件或审阅输入改变后须重新生成并核对清单。

`ARTIFACTS.json` 绑定真实产物，`REVIEW-STATUS.md` 与 `MANIFEST.json.readiness` 明确区分 `artifactsComplete`、`productionRollbackComplete`、`releaseNotesBound`。任一缺项使 `approvalReady=false`；即使输入齐备，`authorizedToDeploy`、`authorizedToPublish` 仍为 false，必须另获实际内容批准。此处不把进程 exit 0 当作完整发布输入已齐备。releaseId 和 publishedDownloadUrl 在真实服务返回前始终 null。

当前重打包命令为：`python online-library/scripts/package-mobile-release-review.py --production-capture dist/migration213/deployment-review/production-capture --release-notes dist/migration213/RELEASE-NOTES.txt`。`--production-capture` 只收入白名单的脱敏证据和显式验证的代码 ZIP，不递归收集该目录；包含环境变量或凭据字段的配置不能收入包。最终说明为 1,007 字节，SHA-256 `2448ce33ce1d6a8c337e51647a8543eaf428637e9cc28fa598f457dcf3044e43`。

## 已只读捕获的生产回退基线

2026-11-13 02:51 UTC 使用现有 CloudBase CLI 身份读取两个函数。实际下载 ZIP 的 SHA 与 `GetFunctionAddress.CodeSha256` 一致，ZIP CRC 全通过；读取前后 Status、修改时间及完整环境配置在内存比较一致，但不保存环境值或临时下载 URL。

| 生产函数 | Active 配置 | 真实代码 ZIP 字节 / SHA-256 |
| --- | --- | --- |
| `nikon-preset-library` | Nodejs20.19；HTTP；256 MiB；60 秒；`HueviaUpdatePackageRole` | 30,587,326 / `cbc721270e45a21f3ed7ed1a396178e034c7d28e9931b2660451ca2302e4f041` |
| `huevia-data-backup` | Nodejs20.19；Event；512 MiB；900 秒；`index.main_handler`；`HueviaDataBackupRole` | 280,705 / `1831ff635c5fa4b79137c8d9e32a2e60952b8c97a1bdc790365a5f7233a112ba` |

同日 02:52 UTC 仅执行一条 SELECT 读取数据库对象元数据：`nikon_mobile_*` 表不存在，mobile manage/budget RPC 不存在；`nikon_app_admin_allowed(text)`、`gen_random_uuid()`、旧 release 表、备份快照 RPC，以及 anon/authenticated/service_role 三角色均存在。022 尚未应用，前置满足。审阅包绑定该结果；部署前还应再次只读确认未发生漂移。

CAM 的现有 CLI 委托身份对两个 `GetRole`、两个已知 `GetPolicy` 实际返回 `AuthFailure.UnauthorizedOperation`，没有通过添加权限绕过。用户后来授权协助取得 CAM 只读能力并登录控制台，主任务于 2026-11-13 03:11 UTC 直接只读取得两个当前默认 version 1 的完整策略、真实角色 ARN、关联关系与修改时间。快照 `production-capture/iam-before.json` 为 SHA-256 `dceebce9f0b47c95b00623c82870c80208714beca220bb8eaf31b891decce0df`；已绑定到包内 `rollback/iam-before.json`。没有给 CLI 角色新增权限，也没有修改生产策略。[最小可选策略与身份说明](cam-readonly-setup.md)仅保留为未执行备选，不是本次部署必需步骤；只读配置授权不构成生产分发部署批准。

更新存储策略 `293055026` 当前 version 1，控制台修改时间 `2026-11-07 23:03:03`；备份存储策略 `293266107` 当前 version 1，修改时间 `2026-11-09 17:47:04`。将候选文档新增的 mobile 前缀移除后，两份 JSON 与实际生产旧文档逐项完全相同：更新仅拟增 mobile-releases/mobile-upload，备份仅拟增 mobile-releases 只读。备份原 GetBucket 的 `string_equal` / `cos:prefix=["huevia-backups%2Fdaily%2F"]` 条件完整保留，没有扩大其他列举、删除或日志权限。

打包时必须重新执行上述比较并生成 `evidence/production/iam-semantic-diff.json`，记录 before 快照及候选策略摘要、逐项新增权限、空删除列表与完整旧 JSON 保留结果；任何非约定差异都会拒绝出包。另对实际生产备份 ZIP 与候选源码比较完整 `pruneOldBackups`、30 天上海日历计算、daily 前缀、列举/删除守卫和成功备份后清理调用，要求相同，并记录函数摘要。IAM 本身只限制可删除的对象范围；30 天门限由保持不变的 worker 实现，不能仅凭策略 schema 断言该门限。

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
| Android `cc.huevia.next` | 仅显式指定 next 的独立 mobile 上传；128 MiB | 固定证书 SHA-256 `76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75`；完整内容签名、版本、包名、ABI；不允许旧证书替代。打包及服务上传均对真实字节再验签 |
| iOS `cc.huevia.next` | 独立 unsigned-ipa 上传；128 MiB | ZIP/CRC、binary 或 XML Info.plist、版本、最低 iOS、ARM64 Mach-O iPhoneOS platform=2；拒绝模拟器及带 `_CodeSignature`/provisioning 的分发包 |

next 的 ABI 从 APK 实际 native libraries 解析；自动更新查询携带当前 ABI，arm64 文件不会提示给 x64 安装。现有唯一版本约束按平台/包名/版本，不会把相同版本的两个 ABI 文件当作同一个可覆盖文件。本次移动更新候选为 arm64；x64 作为明确的单独交付附件，不以相同版本再上传覆盖 arm64。如需同版双 ABI 自动更新，须另行制定多资产目录。

原版迁出维护包 `huevia-0.30.34-legacy-export-194.apk` 为 35,368,260 字节，超过原两包 32 MiB 规则，属于另行审阅的迁出工具交付附件，不上传旧更新接口。主任务已实际执行旧 186 同签名维护升级到 194、导出、新版迁入与撤回；保留原 launcher 和“旧版资料迁出”两个入口。该实测不构成允许全局放宽旧包预算、卸载清数据或公开发布维护包的授权。

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

上线可执行性只读预检已确认：现有 CloudBase CLI 可读取 SQL 元数据与两个 Active 函数；当前数据库会话不是只读，具备 public schema CREATE 权限。没有执行任何 SQL 写入或函数更新来试权限，SCF 写权限仍须在已批准动作时由实际返回值确认；若委托 CLI 被拒绝，应使用已登录主账号控制台完成同一已批准代码更新，不扩大 CLI 长期权限。

现成工具入口为 `scripts/cloud-tools.mjs` / `scripts/tcb-api.mjs`：022 只选择本次单独 SQL，经既有 `ExecutePGSql` 入口按迁移传输方式原子应用，并通知 PostgREST reload schema；不能直接运行 `setup-cloud.mjs --migrate` 重放全部历史迁移。两函数只使用 `scf.UpdateFunctionCode` 和各自已经审阅的 ZIP，保留原配置，随后核对 Active、代码 SHA 与配置前后一致。现存 `deploy-code-only.mjs` 固定主函数及旧 build 路径，`deploy-data-backup.mjs` 的 deploy/configure 模式涉及创建或配置，不应直接当作本次两函数更新入口。候选两个函数 ZIP 均小于官方 Code ZipFile 50 MB 上限；参见 [UpdateFunctionCode](https://cloud.tencent.com/document/api/583/18581)。IAM 写入由主任务已登录的主账号控制台完成，两策略只有语义 diff 中约定的前缀变更。

App 管理员是独立登录条件：旧 CLI 会话已失效，旧本地凭据不能用于刷新，未尝试旧密码。已准备 [安全交互 CLI](release-admin-login.md)，让用户本人在本机终端不回显输入当前凭据，正常登录并只保存验证后的会话。当前 Web 管理 UI 只有旧 APK 路由，不能承担 next/IPA 上传；新 mobile 发布使用既有 `prepare-mobile-release.mjs`。登录准备已授权，生产部署、draft 上传与公开发布仍未执行或获准。

默认打包命令会绑定当前两个固定路径的 213 APK，并查找 `dist/migration213/huevia-0.31.0-dev-213-ios-unsigned.ipa`。IPA 实际路径不同可用 `--ios-ipa <实际路径>`；缺失时可生成未完备审阅快照，不会偷偷回退至 212。

最终重打包可继续使用已绑定的 `--production-capture` 与 `--release-notes`；单独输入也支持 `--rollback-main`、`--rollback-backup`、`--rollback-iam`、`--database-precheck`。回退材料必须来自部署前只读捕获，不是当前待部署 ZIP 的副本。IAM 快照 schema 为 1，`capturedAt` 记录实际捕获时间，`release`、`backup` 各包含真实 `roleArn`、`policyId`、`version`、`document`（完整策略 JSON，含 statement）；没有凭据、私钥或环境变量。脚本验证格式并绑定文件摘要，生产来源真实性仍由主任务在独立审批前核对。

从 `online-library` 工作目录运行 `node scripts/prepare-mobile-release.mjs <实际.apk或.ipa路径> --notes-file <已复核说明文件>`，默认只做本地检查，不读管理员会话、不连接云端。输出实际摘要与精确发布确认文字。

取得本次批准并完成服务准备后，`--upload-draft` 才通过既有管理员会话及 CSRF 上传；脚本不输出 Cookie、CSRF 或云凭据。`--publish --confirm "PUBLISH <真实版本号> <真实SHA256>"` 是独立明确的公开发布动作。`--verify-public` 只回读已经发布的实际文件并核对完整摘要。

## 回退

当前两个 Active 主函数/worker 生产代码包已只读归档并核对 SHA，两份实际 IAM version 1 旧策略也已从控制台只读捕获，摘要如上。部署前核对捕获时间、版本/修改时间与当前生产无漂移；漂移则重新捕获并重新审批，不把本地 Git 基线冒充生产镜像。

发生异常时，先用有效管理员会话撤回本轮实际新版本，确认 `WITHDRAW <真实版本号> <真实SHA256>` 与 expectedRevision，阻断新下载。恢复刚归档的两个代码包及原策略版本；保留环境变量、QQ AppID、原服务账号、域名、触发器与历史旧包发布状态。原两包接口与资料无需回退数据。

022 是追加结构，回退时保留其表、文件、审计与版本高水位，不执行 DROP/DELETE 或复活撤回版本。需要停用新管理入口时可使用包内 `disable-mobile-release-management.sql` 仅撤销新管理 RPC 的 service_role 执行权；恢复需复核后再次应用 022。已经安装的新 App 继续使用本机资料与既有业务功能，更新服务会明确不可用，不强迫降级或清空数据。

## 明确待办

实际 213 IPA 仍待绑定；云端所有改动与公开发布尚未执行。Android 腾讯登记仅有用户答复“能”，没有实际保存生效或真实 QQ 成功证据；用户明确 QQ iOS Universal Link“还未配置”。Team ID/Associated Domains/AASA 与真实 QQ 授权属于独立外部验收条件，不在本部署中伪造、代填或标为已验收。
