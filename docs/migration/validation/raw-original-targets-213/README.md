# A10 原始 NEF、配对与保存目标：开发验证

本记录属于当前工作区开发验证，不冻结安装包，不覆盖 212 或更早交付物。

## 实际接入

`CameraRawPairingPage` 从相机 JPEG 查看器进入。库存读取覆盖全部可读存储卡和最多 20000 个对象，独立于可见相册分页，浏览不下载原文件。唯一匹配复用原 `RawPhotoPairing`：可信相机身份、全局唯一同名 RAW、有效且相同的拍摄时间、同卡时父目录一致、可用时拍摄序列一致。缺卡、缺对象、未知身份或重名不自动猜测，展示卡、日期、序列与大小，要求用户明确选择。用户最终确认后，重新核对原始描述符，再复用 `CameraTransfer` 接收完整 NEF。

原始保存页明确选择应用原图库、系统相册或用户授权的 Files 文件夹。JPEG 既有默认原字节保存路径保留，并新增其他保存位置入口；NEF 直接进入原格式和目标页。共同暂存层支持 JPEG / NEF，保留既有 JPEG 保存标识及历史记录兼容；NEF 复用原结构校验，复制和发布均不显影、不改 EXIF、不应用编辑配方。

Android NEF 系统相册适配复用原 `RawPhotoStore` / `RawPhotoPublisher`、持久完成证据和实际系统资源 SHA/长度回读。用于适配旧发布器的额外物理暂存仅在成功核对后清理，应用 `originals/` 原文件继续保留。iOS 按真实 NEF UTI 添加 PhotoKit RAW 资源；系统相册路径要求可读取授权，并从实际 RAW 资源读取完整字节核对，不能以仅添加授权或 JPEG 显影结果冒充 RAW 回读。系统不提供 NEF 类型或读取授权时，用户可明确选择 Files。

Files 使用独立 `cc.huevia/file-publication` 通道选择目标；界面只获得私有映射的 `targetId` 和名称。Android 保存系统 SAF 持久读写授权，Apple 保存用户选择文件夹的 minimal bookmark 并重新取得安全范围访问。`files.publishOriginal` 使用稳定 `operationId`，在创建前记录意图，保存已创建资源的归属和状态，复制后重新读取目标文件核对 SHA-256 与完整长度。重试复用原资源；完成文件被删除或修改时不覆盖、不静默新建；仅对有自身记录且仍与原文件前缀一致的未完成文件执行明确重试。无法确认创建响应的外部不完整文件保持待核对，不猜测归属。

## A6 共用证据

相机行增加 `storage` 和完整 PTP ObjectInfo 的 SHA-256 `descriptor`；独立 `downloadCameraId` / `downloadTrusted` 使用可信 GUID 或真实有效的标准 DeviceInfo 序列号及厂商/型号，未知身份绑定当前会话，A1 原信任规则保持。

`camera.resolve` 优先核对原 handle，再按每次最多 128 个对象分段检索独立全卡库存。它只读元数据，跳过已经删除的对象，找到后才加入当前 `observed` 下载许可。相机下载前后已经接入共享队列的验证和持久原文件收据，边拍边传与手动队列标识不可混用。

## 本地实际验证

| 检查 | 已通过范围 |
| --- | --- |
| `CameraRawBoundaryTest` | 28 项：完整库存、重名、未知身份、缺卡、取消、描述符变化、明确选择、真实 TIFF/EP CFA 结构的测试 NEF、暂存/读回原字节和稳定收据 |
| 既有 `OriginalPublicationBoundaryTest` | 28 项 JPEG 回归，原画面/草稿/原文件不变，旧保存任务和清理约束保留 |
| `CameraResolveBoundaryTest` | 21 项：标准序列号稳定、A1 信任不变、128 对象分页、handle 迁移及找到后的原字节下载 |
| 相机、RAW 与 Files Flutter 专项 | 13 项：含原 6 项 OriginalSave、新 4 项 Files/配对和 3 项遥控/槽位检查；目标/操作标识固定、文件 SHA 收据拒绝、取消不下载、没有 Photos 权限时仍可选择 Files |
| Android 实际 SDK 36 + Flutter jar 编译 | NativeOriginalFiles、NativeGallery、SharedRawGalleryPublication、既有 JPEG 发布适配及相机 USB 类通过；没有运行共享 Gradle / ADB |

日志位于 `.tooling/agent-camera/`：`raw-compile.log`、`CameraRawBoundaryTest.log`、`CameraResolveBoundaryTest.log`、`raw-android-sdk-compile.log`、`flutter-raw-files.log`、`raw-dart-analyze.log`。

## 明确保留的验收

Windows 未编译 Apple SDK，本轮 ImageCaptureCore / PhotoKit / Files 代码须由统一 Apple CI 编译，不能将接口声明当作 Apple 平台通过。真实 Nikon 双卡、RAW+JPEG 与未知 NEF，Android DocumentsProvider、授权撤销、iCloud / 第三方 Files、文件提供者离线或撤销、设备存储不足、实体 iPhone 的实际 RAW 资源回读，以及进程终止期间外部创建响应丢失仍须接机验证。本轮共同目标发布支持 JPEG / NEF；其他 RAW 格式仍沿用原文件分享，未声称全面格式兼容。

平台依据：[Apple 文件夹授权与 minimal bookmark](https://developer.apple.com/documentation/uikit/providing-access-to-directories)、[文档选择器](https://developer.apple.com/documentation/uikit/uidocumentpickerviewcontroller/init(foropeningcontenttypes:ascopy:))、[系统 RAW UTI](https://developer.apple.com/documentation/uniformtypeidentifiers/system-declared-uniform-type-identifiers)。
