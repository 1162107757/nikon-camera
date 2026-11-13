# A12 / A13 跨端账户与交付开发记录

这是开发与本地检查记录，不改写 211 冻结清单或 212 已有验收。不构成真实 QQ 授权、生产更新发布、实体安装迁入或 Apple 新包验收。

## QQ 原生授权

- Android 使用现有官方 SDK 3.5.19、原 `QqLoginController` / `QqAuthorizationGate`，新增 Activity adapter；授权同意、验证码、取消、迟到结果、页面关闭与 `account.qq` 服务端会话接线已补齐。
- iOS 使用[官方 SDK 下载页](https://wiki.connect.qq.com/sdk下载/)的 3.6.22.459 xcframework。`prepare_qq_ios.py` 固定官方归档 SHA-256 `38a2fb7f26d8de683b942e16c5c1e46aeb054810d193bab0292686f8e5c74ae1`，逐个 Mach-O 检查真机 49 个对象 platform=2、模拟器 98 个对象 platform=7，架构分别 arm64 与 arm64/x86_64，最低 iOS 15.0。没有把模拟器切片当作真机。
- SDK 在用户同意后才初始化，原生临时 token 仅用于立即换取 Huevia 会话；清除腾讯缓存，不携带 AppKey。iOS 同时处理 AppDelegate 与当前 Flutter 的 [UIScene 回调](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate)。
- AppID `1105984855` 已存在。新版 Android 包名 `cc.huevia.next`，实际 212 证书 SHA-256 `76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75`、MD5 `84c2cfda7312206ad9967803c1018021`，仍须在 QQ 互联实际保存并生效。
- 用户明确 iOS Universal Link 尚未配置。`HueviaQqUniversalLink` 保持空值，原生返回明确配置错误。`qq_universal_link.py` 仅从真实 Team ID、Bundle ID 与 HTTPS URL 生成 AASA、Associated Domains 与 Info.plist；不部署、不会把模板当成已授权。
- [腾讯官方文档](https://wiki.connect.qq.com/universal-links适配faq/)要求匹配通用链接与 AASA。当前服务路由位于 `/preset-library`，AASA 的 `/.well-known/apple-app-site-association` 在该前缀之外；需要另设网关固定路由或自有 HTTPS 域根文件。使用者自行签名时，Team ID、Bundle ID、Associated Domains entitlement 与 AASA 必须一致，个人签名工具可能无法授予该 entitlement；此时账号密码登录仍可用。

## 更新分发

- 原 Android 包继续使用原发布表、32 MiB 限制及证书 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`；新版包独立使用 `NextAppUpdateManager` 和 128 MiB 限制，安装前复核 SHA-256、字节数、包名、版本、当前签名与发布签名。原源码没有修改。
- 新版 Android 查询仍为 `/releases/latest?packageName=cc.huevia.next`，实际文件为 `/next/releases/{id}/file`；独立命名空间避免旧下载依赖新发布表。`/api/next/releases` 管理新版 APK，`/api/ios/releases` 管理未签名 IPA，`/ios/releases/latest` 与 `/ios/releases/{id}/file` 提供 iOS 清单和下载。
- 所有路由使用现有真实 BASE `https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library`。`022-mobile-releases.sql` 新建独立表、事务 RPC、RLS、分块所有权/准备状态、预算、发布摘要确认、不可覆盖版本与撤回高水位。仅 service_role 可读写；普通用户会话没有管理权。
- 私有 COS 对象限于 `mobile-upload/{uuid}/{index}-{sha}.part` 与 `mobile-releases/{ios|android}/{sha}.bin`。发布前和下载前回读摘要，最多 60 秒签名，文件响应前重新核对撤回状态。原 `app-releases` / `app-upload` 路径规则保留。
- iOS IPA 上传时验证 ZIP、CRC、Info.plist（binary/XML）、Bundle ID、版本、未签名材料状态、ARM64 与 Mach-O 的 iPhoneOS platform=2；本机下载后再核对身份、版本和平台。它交付未签名 IPA，由用户自行签名，应用不承诺直接安装或迁移签名权限。
- `prepare-mobile-release.mjs` 默认只检查实际 APK/IPA。`--upload-draft` 通过既有管理员会话和 CSRF 上传私有草稿；`--publish --confirm "PUBLISH code sha256"` 才发布；`--verify-public` 独立回读实际字节。会话只读取已忽略的原有私有文件，不打印、提交或创建凭据。
- 生产部署顺序：先审阅并应用 022；为既有角色增加精确的两个 mobile COS 前缀；部署服务；把真实 iOS 清单 URL 写入 `HueviaIosReleaseManifest` 后构建；对实际新产物做默认检查与私有草稿；最终发布由主任务独立处理。本记录未部署数据库、IAM、服务或公开版本。

## 旧资料迁入与迁出

- 规范 ZIP 含版本化 `huevia-migration.json` 和内容寻址 payload；每项记录字节和 SHA-256。Android 导出包括可见预设、外部/内部相册与 RAW 原片、可读当前账号草稿、项目分类及默认预设。旧下载队列与系统相册许可不迁移。
- 原数据读取器可能执行恢复，所以迁出器先制作暂存副本，恢复仅在副本上运行。账号只导出 id/provider/username/nickname；密码、旧会话、QQ token、密钥不导出。账号专属草稿与项目默认需在新版重新登录同一账号后明确关联。
- Android 的不同包名不能读取原 sandbox。`cross-platform/legacy-android` 提供同包维护 overlay：原 `cc.huevia` 的下一版本号 194，通过系统文档选择器导出 ZIP；不改原 `app/` 源文件。必须匹配原安装证书；不能通过卸载清数据绕过签名。
- 实际原 193 APK 已由 apksigner 验证证书 SHA-256 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`、MD5 `945aa44a13dd8c10155ad0078edf698e`。本机既有 `.tooling/debug.keystore` 的证书摘要相符；维护包仍须由主任务实际签名和验证后交付。
- 原 iOS `Info.plist` 已启用文件共享，`AppModel.swift` 实际资料为 Documents/Presets 的 NCP/NP3；显示名在旧 UserDefaults。新版允许用户通过 Files 选择导出的 Presets 目录，保持预设字节，旧显示名取不到时退回文件名。原 iOS 源码不存在 Android 完整账户/照片/草稿/项目存储，不声称读取其他 sandbox 或 Keychain。
- 导入先严格拒绝路径穿越、未知/重复 ZIP 路径、超限与摘要损坏，再用原预设/草稿模型校验并逐张原生解码。提交保留已有预设名和草稿，用独立项目 ID 合并分类；照片索引与默认配置保存 before 副本，新增文件有磁盘 journal，失败/中断可撤回。成功后若受管资料发生编辑或新增，自动撤回在删除前停止。

## 本地检查证据

- 独立 JVM `LegacyMigrationBoundaryTest` 37 项通过；覆盖原资料不变、脱敏、预检/提交/撤回、冲突保留、取消回滚、编辑后撤回拒绝、路径/摘要损坏与旧 iOS 范围。
- 新增 Dart QQ/IPA 元数据 8 项通过；覆盖同意、取消/迟到结果、单次授权、账号变化、验证码过期、签名渠道与下载域约束。原生授权成功仍需真实 QQ 账号/设备。
- 新 Node 3 项通过，包含实际旧 APK 与 212 APK 正反向签名隔离、实际 SQL/PGlite+HTTP 的上传/草稿/发布/清单/撤回/CSRF/RLS；与原 APK/release/COS 定向回归共 18 项，13 通过、5 因旧 53 本地夹具缺失跳过。
- 真实 212 APK 已完整验签，`51,309,171` 字节、SHA-256 `1666b4850f1c1d76626c5e3b3fefa2fd3c6ba145730ca4c4dce2c9f0f68f18fe`。真实 212 未签名 IPA 的 Bundle ID、`0.31.0/212`、真机平台与结构检查通过，`29,667,421` 字节、SHA-256 `ffea0784ed576e2fb13a9136193d9cb9e0fab180549c826db0c3d22e4a873175`。这些是 212 输入验证，不冒充本轮新包验证。
