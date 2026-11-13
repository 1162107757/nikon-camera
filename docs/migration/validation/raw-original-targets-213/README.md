# A10 原始 NEF、配对与保存目标：开发验证

本记录属于 213 开发验证，不覆盖 212 或更早交付物。2026-11-13 文档复核基线为 `8d43086119fc88eb97e8157be44d76b6ac917c26`；独立源码检查、平台构建和实际安装包运行按各自证据记录，不合并声称接机通过。

## 实际接入

`CameraRawPairingPage` 从相机 JPEG 查看器进入。库存读取覆盖全部可读存储卡和最多 20000 个对象，独立于可见相册分页，浏览不下载原文件。唯一匹配复用原 `RawPhotoPairing`：可信相机身份、全局唯一同名 RAW、有效且相同的拍摄时间、同卡时父目录一致、可用时拍摄序列一致。缺卡、缺对象、未知身份或重名不自动猜测，展示卡、日期、序列与大小，要求用户明确选择。用户最终确认后，重新核对原始描述符，再复用 `CameraTransfer` 接收完整 NEF。

原始保存页明确选择应用原图库、系统相册或用户授权的 Files 文件夹。JPEG 既有默认原字节保存路径保留，并新增其他保存位置入口；NEF 直接进入原格式和目标页。共同暂存层支持 JPEG / NEF，保留既有 JPEG 保存标识及历史记录兼容；NEF 复用原结构校验，复制和发布均不显影、不改 EXIF、不应用编辑配方。

Android NEF 系统相册适配复用原 `RawPhotoStore` / `RawPhotoPublisher`、持久完成证据和实际系统资源 SHA/长度回读。用于适配旧发布器的额外物理暂存仅在成功核对后清理，应用 `originals/` 原文件继续保留。iOS 按真实 NEF UTI 添加 PhotoKit RAW 资源；系统相册路径要求可读取授权，并从实际 RAW 资源读取完整字节核对，不能以仅添加授权或 JPEG 显影结果冒充 RAW 回读。系统不提供 NEF 类型或读取授权时，用户可明确选择 Files。

Files 使用独立 `cc.huevia/file-publication` 通道选择目标；界面只获得私有映射的 `targetId` 和名称。Android 保存系统 SAF 持久读写授权，Apple 保存用户选择文件夹的 minimal bookmark 并重新取得安全范围访问。`files.publishOriginal` 使用稳定 `operationId`，在创建前记录意图，保存已创建资源的归属和状态，复制后重新读取目标文件核对 SHA-256 与完整长度。重试复用原资源；完成文件被删除或修改时不覆盖、不静默新建；仅对有自身记录且仍与原文件前缀一致的未完成文件执行明确重试。无法确认创建响应的外部不完整文件保持待核对，不猜测归属。

## A6 共用证据

接收后仅在应用 JPEG 的 `cameraSource.cameraId` 和完整 JPEG 描述符都与所选相机库存证据一致、且匹配唯一时，通过既有 `AppState.updatePhoto` 持久保存 `rawSource` / `rawSourceSha` 和显式选择证据。关联使用确认时冻结的来源快照，刷新列表不更换已接收 RAW 的证据。缺少来源的旧 JPEG 不按文件名自动绑定；NEF 仍作为独立原图保留。

相机行增加 `storage` 和完整 PTP ObjectInfo 的 SHA-256 `descriptor`；独立 `downloadCameraId` / `downloadTrusted` 使用可信 GUID 或真实有效的标准 DeviceInfo 序列号及厂商/型号，未知身份绑定当前会话，A1 原信任规则保持。

`camera.resolve` 优先核对原 handle，再按每次最多 128 个对象分段检索独立全卡库存。它只读元数据，跳过已经删除的对象，找到后才加入当前 `observed` 下载许可。相机下载前后已经接入共享队列的验证和持久原文件收据，边拍边传与手动队列标识不可混用。

## 本地实际验证

| 检查 | 已通过范围 |
| --- | --- |
| `CameraRawBoundaryTest` | 28 项：完整库存、重名、未知身份、缺卡、取消、描述符变化、明确选择、真实 TIFF/EP CFA 结构的测试 NEF、暂存/读回原字节和稳定收据 |
| 既有 `OriginalPublicationBoundaryTest` | 28 项 JPEG 回归，原画面/草稿/原文件不变，旧保存任务和清理约束保留 |
| `CameraResolveBoundaryTest` | 21 项：标准序列号稳定、A1 信任不变、128 对象分页、handle 迁移及找到后的原字节下载 |
| 相机、RAW 与 Files Flutter 专项 | 15 项：含原 6 项 OriginalSave、新 6 项 Files/配对/来源关联和 3 项遥控/槽位检查；目标/操作标识固定、文件 SHA 收据拒绝、取消不下载、没有 Photos 权限时仍可选择 Files；有证据才绑定 JPEG，同名旧图不猜测 |
| `SharedDownloadsBoundaryTest` | 53 项：账号/相机/会话/描述符校验、明确确认绑定、原生先持久收据、重启复用、已完成不倒退、目标/SHA/长度/操作标识绑定、损坏日志隔离 |
| Android 实际 SDK 36 + Flutter jar 独立编译 | NativeOriginalFiles、NativeGallery、SharedRawGalleryPublication、既有 JPEG 发布适配及相机 USB 类通过；本组独立验证没有占用共享 Gradle / ADB，主任务随后统一构建和运行 |

日志位于 `.tooling/agent-camera/`：`raw-compile.log`、`CameraRawBoundaryTest.log`、`CameraResolveBoundaryTest.log`、`raw-android-sdk-compile.log`、`flutter-raw-files.log`、`raw-dart-analyze.log`。

队列强化的编译/检查补充在 `downloads-compile.log` / `SharedDownloadsBoundaryTest.log`。原生 Gallery / Files 返回 `owner`、稳定 `operationId`、源 SHA、字节长度和目标证据，队列完成要求原文件收据与目标收据一致且 `verified=true`。显式队列系统发布使用 `verifyReadback=true`，Apple 必须从真实系统资源读回；旧手动 JPEG 的仅添加授权路径保持兼容。损坏队列记录保留在原处，并由 `downloads.list.issues` 单独报告，不阻断其余有效记录。

## 统一平台证据的边界

- A6 的完整页面已接最多 100 项、应用 / 系统 / 文件夹目标和明确继续；Queue / Protection 16 项受控检查验证后台到期暂停、前台继续不重复接收、显式通知停止以及目标回读请求，详见[编辑组状态](../../status-editing-lifecycle-213.md)。Remote / Slots / RAW 配对对 Live、持久队列和手动传输执行准入互斥。这里的受控响应不算真实 SAF 或 PhotoKit 发布。
- 主任务 [119 项 Android 原生检查](../features-213/android/native-119.json)在 API 31 / x86_64 / 4 KiB 页模拟器通过，记录的四个源码 SHA 与复核基线匹配；包含实际服务与引擎接管生命周期。它明确不覆盖完整 Flutter 接收流水线，更没有物理相机输入。
- [41 项 R8 release 检查](../features-213/android/release-runtime.json)来自 `3db73d2575fc93296e0995c5476c237397c2a1a7` 的真实 x64 优化 APK；实际模型 / 渲染 / 取消及新鲜 RAW JNI 缩略图回调通过。A7 的 Viewer 6 项另外覆盖导航与分页调度；RAW 缩略图不等于 NEF 原字节发布成功，渲染出的 JPEG 也不能替代 NEF 收据。
- Android 两 ABI 开发包的[签名、ZIP 16 KiB 与 ELF LOAD 对齐](../features-213/android-signing-alignment.json)有静态证据。运行证据仍为 4 KiB 模拟器，不能据此声称实体 arm64 / 16 KiB 页设备已运行或接机通过。

## 明确保留的验收

本专项尚未取得 213 Apple SDK / IPA 成功验收记录；ImageCaptureCore / PhotoKit / Files 必须由统一 Apple CI 编译并核对产物，不能将接口声明或 212 历史成功记录当作本轮 Apple 平台通过。仍缺实体相机、16 KiB Android 设备和 iPhone。真实 Nikon 双卡、RAW+JPEG 与未知 NEF，Android DocumentsProvider、授权撤销、iCloud / 第三方 Files、文件提供者离线或撤销、设备存储不足、实体 iPhone 的实际 RAW 资源回读，以及进程终止期间外部创建响应丢失均须分别验证。本轮共同目标发布支持 JPEG / NEF；其他 RAW 格式仍沿用原文件分享，未声称全面格式兼容或端到端实机通过。

平台依据：[Apple 文件夹授权与 minimal bookmark](https://developer.apple.com/documentation/uikit/providing-access-to-directories)、[文档选择器](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(foropeningcontenttypes:ascopy:))、[系统 RAW UTI](https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers)。
