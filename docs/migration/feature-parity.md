# 跨平台完整对齐清单

验收基准：Android 186 / `6fb5003d8be85fcbb0fa3b4d99aef63cc1751f3c`。
用户要求整体迁移、全部功能对齐安卓，原工程保留，交付可自签 IPA。
本清单记录开发状态，未验证的功能不能作为完成或缩减范围处理。

| 能力 | 现有实现依据 | 共享逻辑 | 共享界面 / 平台接入 | 验收状态 |
| --- | --- | --- | --- | --- |
| NCP / NP3 校验、单色与彩色预设解析 | `library/PresetFile`, `ncp/*PreviewProfile` | 直接复用 | 本地导入已接线 | 核心 JVM / Apple 原测试通过；应用待验证 |
| 本地预设、分类、样片、删除、文件分享 | `library/PresetLibrary` | 直接复用 | 首批页面已接线；样片编辑待迁移 | 待应用验证 |
| 在线预设、分页、搜索、分类、缓存、下载 | `OnlinePresetRepository`, `OnlinePresetSearch` | 原逻辑已纳入 | 分页/下载、完整目录搜索、缓存提示已接线，搜索合并在途请求 | 应用联网验收待完成 |
| 账户登录、注册、人机验证、QQ、头像、退出隔离 | `account/*` | Repository 直接复用 | 登录/退出/注册/图形验证已接线；QQ、头像待迁移 | 待完成 |
| 个人预设同步、云端移除、冲突处理 | `PersonalPresetSync`, `PersonalPresetApi` | 原逻辑复用并补充任务取消和作者校验 | 同步范围选择、两种冲突处理、删除及会话可见性已接线 | 31 项事务/权限检查通过；真实账号联网验收待完成 |
| 社区详情、评论回复、赞、收藏、投稿、举报 | `community/*`, `ui/CommunityPanel` | 原逻辑已纳入 | 待迁移全部页面 | 待完成 |
| 本地/系统照片导入、原图身份、分组、星标、筛选 | `LocalPhotoRepository`, `PhotoLibraryCatalog` | 部分原模型已纳入 | 私有原图导入与索引已接线；系统图库待接入 | 待完成 |
| 17 项基础调节、预设强度 | `PhotoAdjustments`, `StrengthPreviewProfile` | 直接复用 | 首批编辑器已接线 | 核心 JVM / Apple 指纹一致；应用待验证 |
| 曲线、HSL、调色盘、自动去灰 | `PhotoCurves`, `PhotoHsl`, `PhotoCleanup` | 直接复用 | 四通道控制点曲线、八色 HSL、调色盘已接线；自动去灰分析待迁移 | 待完成 |
| 裁剪、旋转、翻转、拉直、透视 | `PhotoGeometry`, `PhotoComposition` | 计划与模型直接复用 | 旋转/翻转/拉直/透视、百分比裁剪已接线；交互裁剪框待完善 | 待应用像素验收 |
| 局部蒙版、克隆、修复、调整区域 | `PhotoLocalEdits`, `PhotoPatch` | 原模型与滤镜直接复用 | 待迁移编辑交互及原生表面 | 核心 JVM / Apple 原测试通过；应用待完成 |
| 人像、肤色、瑕疵、身体与脸部模型 | `PhotoPortrait*`, `PhotoFace*`, `PhotoBodyAnalysis` | 纯 Java 部分已纳入 | iOS 模型推理及双方界面待迁移 | 待完成 |
| 边框、自动拍摄信息、标识、排版 | `PhotoBorder`, `PhotoBorderRenderer` | 模型直接复用 | Android 原渲染器、iOS 三种排版/原素材字体已接线 | 安卓三种边框集成通过；iOS 待应用验证 |
| 草稿、撤销重做、项目预设、调整复制 | `PhotoEditStore`, `PhotoRecipeStore`, `PhotoAdjustmentCopy` | 原模型已纳入 | 原格式草稿、撤销重做、账户配方保存/管理/应用已接线；批量调整复制待迁移 | JVM 配方及快照恢复验证通过；Apple 与旧安装资料迁移待验证 |
| RAW / NEF 信息、显影、白平衡、高光、JPEG 色彩匹配 | `RawDeveloper`, LibRaw C++, `RawJpegColorMatch` | 色彩与安全规则直接复用 | 两端 LibRaw 适配和共享显影控制已接线；外部 JPEG 参考配对待迁移 | 安卓 12 合成 Bayer RAW 全链路通过；iOS 同场景待验证，未知型号 NEF 待实样复测 |
| 完整尺寸/分享/自定义导出、成品与编码前预览 | `PhotoPresetRenderer`, `PhotoExportPreview`, `PhotoExportSpec` | 导出规格与滤镜直接复用 | 两端编解码/安全元数据及完整/分享/自定义导出已接线；成品管理待迁移 | 安卓集成通过；iOS 文件接口异常待修复 |
| 批量处理、取消、重试、作品/原图、系统图库发布及删除范围 | `PhotoPresetBatch`, `PhotoLiveGallery`, `PhotoEffectGallery` | 部分模型已纳入 | 待迁移 | 待完成 |
| Nikon Wi-Fi、Fuji X-T20、网络切换与连接保护 | `PtpIpClient`, `FujifilmPhotoClient`, `CameraWifiSession` | 原协议直接复用 | Wi-Fi 手动连接已接线；平台网络/生命周期待迁移 | 待完成，不扩大 Fuji 已验证能力 |
| 相机相册、缩略图、JPEG/NEF 原文件下载 | `AlbumController`, `PhotoCameraClient` | 原协议与解析直接复用 | 初始会话分页/接收已接线；完整库存策略与恢复待迁移 | 待完成 |
| 边拍边传、项目、续传、前后台任务及持久收据 | `PhotoLive*`, `CameraConnectionService` | 部分原模型已纳入 | Android 服务与 iOS 后台生命周期待接入 | 待完成；须验证系统暂停后的恢复 |
| USB 相机发现、权限、PTP 传输、槽位读写删除 | `usb/*`, `picturecontrol/*` | 验证/保护部分已纳入 | Android USB 与 iOS ImageCaptureCore 待接入 | 待完成，不能只凭 API 存在宣称机型支持 |
| Wi-Fi 预设槽位读写删除及会话移交 | `PictureControl*Session`, `PtpIpClient` | 原协议保护保留 | 待迁移完整确认/回读流程 | 待完成，不允许不确定写入自动重试 |
| 遥控、实时取景、对焦、拍摄、相机参数 | `remote/*`, `RemoteCaptureActivity` | 纯 Java 协议已纳入 | 待迁移 | 待完成 |
| 设置、主题、权限、诊断、更新、旧数据迁移 | 原 Activity、`updates/*`, `AppCrashDiagnostics` | 部分模型已纳入 | 主题已建立；其余平台适配待完成 | 待完成 |

## 已取得的证据

- 原工程 420 个已跟踪文件内容保留，`inventory.py --verify` 通过。
- 共享核心 Java 11 编译与原测试：2168 项 NCP、43230 项局部编辑、15575 项 RAW/JPEG 色彩、243 项 RAW 高光检查通过。
- Apple Objective-C 翻译运行同一套原测试，6 组图像 SHA-256 与 JVM 完全一致。
- 首次 Apple 成功记录：提交 `9a285bfe2e1726bdc34042bba596054b479d6546`，Actions run `42787370999`。
- 此证据仅证明共享核心。完整 Android APK、iOS 应用和 IPA 仍需构建与应用级验证。

### 首次应用构建与后续检查（开发记录）

- `060c5147d270717872202bf3b64ce004a7360c87` 的 iPhoneOS ARM64 应用构建成功，Actions `42807885872`；生成未签名 IPA `24,848,665` 字节，SHA-256 `2cacbf061580b07e25cd1897dd89082d6da3f1e69d7064975dbc37e6e0abd654`。最低 iOS 16，开发标识 `cc.huevia.next`，完整功能对齐仍未完成。
- 同一提交新增的 31 项共享边界检查已在 JVM 和 Apple 通过，覆盖离线账户、完整草稿、预设删除后的编辑、账户隔离和旧导出快照保护。
- Android x86_64 开发 APK 已构建，在隔离 Android 12 / API 31 模拟器冷启动并显示预设库；这不代表荣耀 Magic 实机稳定性已验证。
- 后续共享界面 9 项测试通过，含离线四页导航、注册失败保留输入、完整在线搜索，以及编辑器在横竖屏/大字体下恢复已移除预设的草稿、曲线和 HSL 操作。
- 后续 16 项 Android 12 原生媒体检查通过：真实 PNG/JPEG 编解码、原渲染器、EXIF 方向、旋转裁剪、边框、原草稿格式、取消及临时文件清理、原文件 SHA 不变、LibRaw 0.22.3 加载。
- 同一 Flutter/native 集成场景在 Android 12 通过：用自行生成的 Bayer DNG 实际显影，验证完整尺寸、白色饱和高光无明显偏粉、自定义白平衡/色彩参数、原始字节不变。合成 DNG 不能代替用户未知型号 NEF 实样。
- 共享界面及文件状态测试已增至 11 项并通过；新增照片并发导入串行提交、索引写入失败回滚与重试。Windows 本地测试需与模拟器分时运行，曾观察到宿主 `flutter_tester.exe` 退出，停止独立模拟器后串行测试通过。
- 当前 JVM 共享边界检查为 69 项，含 31 项个人同步事务检查；本地界面/状态测试为 14 项，新增旧相机会话响应隔离、同步范围作者固定、应用容器路径变化后的照片与 RAW 关联恢复。
- Android 12 已复跑 16 项原生媒体检查及 Flutter/native 集成场景，均通过；后者增加梯度图旋转裁剪的实际像素位置、三种 Nikon 边框素材及真实 DNG 显影。
- 为 Android 12L 及以下启用 Flutter 官方允许的兼容渲染器；Android 13+ 仍使用默认引擎配置。此选项已在固定 Flutter 3.47.9 源码核对、API 31 运行验证；后续升级 Flutter 时须检查其弃用状态。[官方文档](https://docs.flutter.dev/perf/impeller)
- 原项目 420 个已跟踪 Android/iOS 文件仍通过内容保留校验。上述 API 31 证据不能代替荣耀 Magic 的实机闪退复测。
- iOS 设备应用已成功编译至 RAW 控制版本；模拟器初始化已通过，首次图片导出在 `Files.isSymbolicLink` 的 JRE 路径触发空指针，正在修复运行库接入。完整 iOS 应用级验收和新版 IPA 交付仍未完成。
- `2524f4355ad6ce2ea581826a72c4f268154d7bd7` 的 Apple 共享核心验证通过（Actions `42823580601`），包含 69 项共享边界与原有全部图像指纹；`77230cb3ec080485fb7d983697a0b38e82de6e2d` 的 Apple 应用分析、14 项界面测试和 iPhoneOS 编译通过（Actions `42825950954`），应用集成仍被上述文件接口异常阻塞。
- 新增账户配方保存/列表/重命名/删除/跨照片应用，直接使用原 `PhotoRecipeStore` 格式。应用配方保留目标照片的构图、边框与局部编辑；原生侧按照片和账户保存校验后的预设快照，确保从无滤镜撤销回已移除的预设。JVM 共享边界检查增至 89 项并通过；新增 2 项大字体横竖屏配方界面测试通过。Windows 全套测试仍偶发宿主 `flutter_tester.exe` 访问异常，单独运行导航文件通过，Apple 全套复测待完成。

## 保留和交付规则

原 `app/`、`ios/`、既有安装包和冻结验证记录不覆盖；迁移代码位于 `cross-platform/`。
开发期间 Android 使用独立的 `cc.huevia.next`，避免测试构建覆盖用户现有安装与数据。
正式替换旧安装前，须完成原资料格式迁移、账户隔离与回滚验证。
最终 IPA 必须来自 iPhoneOS ARM64 构建，不能使用模拟器应用冒充；同时保存构建提交、哈希及检查记录。
