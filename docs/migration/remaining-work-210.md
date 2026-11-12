# 210 迁移剩余工作与下一轮分工

审计日期：2026-11-12。源码快照：`c33c4546120e5225cf95f4841639f22b1e7f8d84`。

本清单对照原 Android 的实际入口与当前 Flutter、共享核心及两端宿主接线。源码链接固定到上述提交；当前整体构建、安装和设备结果以主任务的最终验证记录为准。本文件不把构建中状态写成通过，也不修改既有冻结证据。

整体迁移尚未完成。判断依据是操作是否从页面进入实际平台能力，并能保存、恢复和核对结果；仅保留 Java 类、资源、按钮或后端接口不算完成。

## 一、真正还缺迁移接线的功能

| 编号 | 尚缺的范围与当前判据 | 可核对入口及下一步完成条件 |
| --- | --- | --- |
| A1 | **相机自动边拍边传。** 当前“边拍边传”标签打开本机拍摄项目页，支持手动加入已保存 JPEG；没有接入相机新对象事件、自动收片和自动入项目的生产者。 | 原 [AlbumController][original-album-controller] 的 PhotoLive 流程与 [AlbumPanel][original-album] 的项目开拍入口；现 [camera.dart][camera] → `ProjectPresetsPage`、[SharedCamera][shared-camera]。下一步连接新片发现、去重接收和项目入库，以连续拍摄、重复事件、断线重连后不漏片/不重复入库结束验收。 |
| A2 | **后台连接保护、平台生命周期和持久任务恢复。** 主页标签切换保活已补齐；设置中的“后台连接保护”仍仅提示保持前台，没有原 Android 前台服务、电池策略、连接移交及恢复接线。iOS 也未实现对应暂停/恢复策略。 | 原 [CameraConnectionService][connection-service]、[PhotoLiveContinuation][live-continuation]；现 [settings.dart][settings]、Android [MainActivity][android-host]、iOS Runner 宿主。下一步完成平台任务生命周期，验证锁屏、退后台、系统终止和重开后，原片、已完成成品与任务状态一致。 |
| A3 | **遥控拍摄、实时取景、对焦及相机参数。** 当前“遥控拍摄”行打开连接页；`SharedCamera` 没有对应遥控请求。 | 原 [RemoteCaptureActivity][remote-activity]、[NikonRemoteCamera][remote-camera]；现 [camera.dart][camera] 的 `openConnection` 和 [SharedCamera][shared-camera]。下一步补相册/遥控会话移交及实际控制页，验证开始、停止、返回相册、拍摄失败后的状态恢复。Fuji 能力继续按原有已确认范围处理。 |
| A4 | **USB 相机平台接入。** 当前设置明确显示“此安装包暂不支持 USB 相机连接”，并未完成设备发现、授权、拔插及 PTP 通道适配。 | 原 `app/src/main/java/cc/huevia/usb/`；现 [settings.dart][settings] 的 USB 行。下一步分别补 Android USB Host 与可用的 Apple 相机通道，再按具体机型验证只读发现、授权拒绝、拔插和会话释放。 |
| A5 | **Wi-Fi / USB 预设槽位读写闭环。** 纯协议保护已保留，当前跨端桥没有完整槽位展示、确认写入、删除及回读页面。 | 原 `picturecontrol/`、`usb/WirelessPictureControl` 和 `DiagnosticsActivity`；现 [SharedCamera][shared-camera] 只暴露连接、目录、缩略图、原片下载等请求。下一步接原能力判断、目标槽位确认、执行及回读核对，保留响应丢失时的不确定状态，不能自动重复写入。 |
| A6 | **相机多选、批量接收、保存目标与下载队列恢复。** 当前 `CameraTransfer` 是一次一张的前台接收，已显示真实字节进度；没有原版相机批选、跨重开下载队列、目标位置和恢复入口。 | 原 [AlbumPanel][original-album] 的 `beginDownloadBatch`、下载恢复及 `PhotoSaveChoice`；现 [CameraTransfer][camera-transfer]、[CameraPhotoGrid][camera-grid]。下一步补队列和持久完成收据，验证停止、掉线、重开后只重试未完成项。任务恢复与协议是否支持字节级续传应分别核对。 |
| A7 | **完整照片查看器与应用内 RAW 缩略图。** 当前相机查看器能放大预览和接收单张原片，尚无原版 `moveDetail` 的相邻照片切换和预取；应用本机网格对 RAW 仍使用文件图标。 | 原 [AlbumPanel][original-album] 的 `moveDetail`、`updateDetailNavigation`；现 [CameraPhotoViewer][camera-grid]、[PhotoMasonry][photo-grid]。下一步补相邻查看、会话变化时退出/刷新，以及有界 RAW 预览接线；浏览预览不能触发原片下载。 |
| A8 | **人像精修和平台推理闭环。** 当前编辑器有“人像”标签，但内容仍只有“人像精修”文字；自动选脸、肤色范围、磨皮/祛痘、脸部及身体定位没有可操作的对应页面和分析请求。 | 原 [PhotoPortraitDialog][portrait-dialog]、[PhotoBodyDialog][body-dialog]、`PhotoPortraitDetection` / `PhotoBodyAnalysis`；现 [legacy_editor.dart][legacy-editor] 的 `tab == 8` 分支。下一步先补分析结果与参数 DTO、两端推理，再接原工具页、取消/应用与草稿；以不同人像、无人脸、大图和取消场景验证。模型文件随包存在不代表推理已接入。 |
| A9 | **涂抹自动修补。** 画笔、径向/渐变和取样克隆已有独立流程，但没有原版“涂抹后松手自动消除”的修补分析、应用及重试闭环。共享模型能保留既有 patch，不能据此认定已能创建新修补。 | 原 [PhotoPatchDialog][patch-dialog]、`PhotoPatchSampler` / `PhotoPatchRenderer`；现 [SharedLocalEdits][local-edits]、`legacy_local_workspace.dart`。下一步接修补计算和编辑事务，核对源坐标、EXIF、局部区域、撤销和停止后原图不变。 |
| A10 | **RAW 原始格式的完整保存目标与相机配对流程。** 本轮手动 JPEG 色彩参考已接入，但这是显影参考，不等于原版相机 JPEG→NEF 库存配对或 NEF 原字节发布。当前直接系统保存原文件的闭环限定 JPEG；RAW 可分享原文件，原版独立格式/位置选择仍未对齐。 | 原 [RawPhotoPairing][raw-pairing]、[RawPhotoPublisher][raw-publisher]、`RawPhotoPanel`；现 [SharedRawReference][raw-reference-core]、[SharedOriginalPublication][original-publication] 和 [export_settings.dart][export-settings]。下一步补明确格式和目标、配对不确定时显式选 RAW、发布收据及读回字节核对。 |
| A11 | **完整多图编辑、批量系统发布和删除范围。** 已有最多 100 张顺序导出、取消/继续及分享，也有单张照片的多版本系统保存；尚缺原版完整批量编辑入口、多照片系统发布的统一任务，以及应用原图/成品/系统相册的删除范围选择。当前 `version.delete` 只处理保存版本。 | 原 [AlbumPanel][original-album] 的批量导出/删除、`PhotoAlbumDeletion`；现 [album_batch.dart][album-batch]、[ExportSave][export-save]、[versions.dart][versions] 及两端 `NativeGallery` / `HueviaGallery`。下一步统一范围和持久操作标识，验证部分失败、授权变更、重试去重及保留未选中原图。 |
| A12 | **QQ 原生授权。** `account.qq` 后端调用存在，当前 QQ 按钮仍提示安装包不支持授权。 | 原 [QqLoginController][qq-controller] / `QqAuthorizationGate`；现 [legacy_account.dart][legacy-account]。下一步补双方 SDK、回调、取消和账号接线，再使用真实测试账号完成授权验收。 |
| A13 | **更新流程与旧安装资料迁入。** “检查更新”目前只展示当前版本；资料恢复覆盖当前共享版的索引/相对路径及局部旧草稿，不是原 Android 包或原 iOS 安装的完整资料迁入。 | 原 [AppUpdateManager][update-manager] / `UpdatePanel`、原预设/相片/草稿存储；现 [settings.dart][settings]、[AppState.initialize / restorePhoto][domain]。下一步分别确定两端更新分发方式并接版本/包校验；为旧预设、原片、草稿、项目和账号资料设计可核对的迁入入口及失败回滚。 |

## 二、代码闭环已补齐，仍需实体、账号或系统场景验收

这些条目不应继续标为“完全没有实现”，也不能仅凭核心测试或模拟器结果标记全部完成。

| 范围 | 当前已具备的闭环 | 仍须完成的验收与源码入口 |
| --- | --- | --- |
| 本轮 JPEG/NEF 浏览及下载 | JPEG 专用库存查询与回退、NEF 独立筛选、相机生成的预览、串行有界缓存、真实接收/校验/入相册阶段；网格浏览先预览再下载。 | 实体 Z 6_2 / iPhone 的独立 JPEG、RAW+JPEG、双卡/不可读卡、对象删除、断网和停止接收。用户已确认 209 的 RAW 缩略图正常，该反馈不替代本轮新版全部 JPEG 场景。[SharedCamera][shared-camera]、[CameraPreviews][camera-previews]、[CameraTransfer][camera-transfer]。 |
| iOS 连接与主页保活 | 首次连接的本地网络说明、打开设置入口、Wi-Fi 限定 Socket；四个主页保留状态，切换标签页不再销毁目录读取/下载页面。 | 授权拒绝→设置开启→返回、相机 Wi-Fi 无公网同时使用蜂窝网络、其他相机客户端占用、切标签/进入系统照片选择器。用户确认开启本地网络后可连接，仍需新版实体回归。[HueviaCorePlugin][ios-core]、[HueviaWifiSocket][wifi-socket]、[main.dart][main]。 |
| 首页及编辑器预设 | 无远程预览 URL 时由已校验配方和内置样片生成效果；编辑器在线/我的来源、实际照片滤镜缩略图、只读配方准备和账号隔离已接入。 | 新装零本机预设、接相机 Wi-Fi 时公网不可用、已有缓存离线使用、服务返回空目录/失败、账号切换与预设移除后重开。在线编辑不能暗中加入“我的预设”。[PresetImage][widgets]、[EditorPresets][editor-presets]、`SharedRuntime` 的 `editor.catalog` / `editor.prepare`。 |
| 本轮拍摄项目 | 新建/重命名、手动加入 1–100 张已保存 JPEG、默认预设快照、前台处理、持久队列/失败记录、停止/重试、查看原图和已保存成品已具备。配置和处理记录有账号保护，处理不会覆盖照片当前草稿。 | 普通安装包实际重开、处理过程中结束应用、原图变化/移除、预设移除与账号切换、成品已生成但任务回执未写完。项目当前处理 JPEG，自动新片入项目、后台处理和原版保存目标属于 A1/A2/A6/A10。[ProjectPresetsPage][projects-ui]、[ProjectPresetsModel][projects-model]、[SharedProjects][projects-core]、`ProjectBoundaryTest` / `project_presets_test.dart`。 |
| 本轮 RAW 外部 JPEG 参考 | 显式选取并确认同次拍摄，绑定 RAW/JPEG SHA，保存相对路径，可恢复内嵌参考；两端复用画面对齐、色彩拟合及高光拒绝规则，未通过时保留中性色彩。 | 用户未知型号 NEF 的白色高光偏粉实样、真实同次拍摄 JPEG、错配/裁切/不同 EXIF 方向、16MB 边界及长时间显影的内存表现。用户确认和 SHA 绑定不替代画面匹配检查，也不是相机库存自动配对。[RawDevelopPage][raw-develop]、[RawJpegReference][raw-reference-ui]、[SharedRawReference][raw-reference-core]、`NativeRawReference`、两端 `NativeMedia` / `HueviaMedia`。 |
| 本轮稳定性诊断 | Flutter 异常处理链保持原行为，保存有界本地记录；Android 复用原 Java/系统退出采集；iOS 接 NSException 和系统实际投递的 MetricKit 崩溃/内存/watchdog 摘要。导出保留 schema 1，并以白名单剔除消息、个人路径、地址和二进制原始轨迹。 | 受控开发包中记录→重启→导出链路、Android 12 的真实低内存/ANR/原生异常、iPhone 的实际 MetricKit 投递。记录窗口和跨版本标记须保留；没有系统记录不能证明没有崩溃。Windows `flutter_tester` 退出不归为荣耀 Magic 应用闪退。[AppStability][app-stability]、[NativeStability][native-stability]、[HueviaStability][ios-stability]、[diagnosticSnapshot][help]。 |
| 荣耀 Magic Android 12 / RAW 大图 | 已有内存边界、RAW 显影、原片校验和各任务取消路径。 | 仍需用户对应型号设备、当前包和原始 NEF 实样复测；模拟器、合成 DNG 或桌面宿主异常都不能替代这项结果。优先取得新版脱敏诊断，并关联操作步骤及同一构建号。 |
| 账户、个人同步与社区 | 密码登录/注册、人机验证、头像选择复核、恢复/退出隔离、同步冲突处理、讨论/投稿/消息页面与持久重试均已接线。 | 真实测试账号、令牌过期、两个账号切换、冲突两种选择、上传/提交响应丢失及审核通知。仅本地接口替身或游客浏览不足以完成真实写入验收。[profile.dart][profile]、`account_profile.dart`、`personal_sync.dart`、`community_state.dart` / `submission_editor.dart`。 |
| 系统图库及成品保存 | Android MediaStore、iOS PhotoKit 的授权/分页/缩略图/原字节导入，单图多版本发布和 JPEG 原字节直接保存已有闭环与收据。 | iOS 有限照片、仅添加授权、iCloud 原片、用户在系统中撤销/删除资源；Android 26–28 的写入权限与新系统的部分授权；发布中途取消、重开、重复响应和外部改动。完整 RAW 目标保存与多图删除/发布仍属于 A10/A11。[ExportSave][export-save]、[OriginalSave][original-save]、两端 `NativeGallery` / `HueviaGallery` / `HueviaPublication`。 |

## 三、功能已有接线，仅样式或交互细节还需对照验收

| 范围 | 当前对照点与剩余检查 | 可复核源码 |
| --- | --- | --- |
| 相机网格及查看器 | 本轮按原版最少三列自适应方格、8dp 间距、14dp 圆角和角标恢复展示，移除列表中的尺寸/大小详情。还需同设备对照列宽取整、屏幕边距、RAW/JPEG 标识、缩略图裁切、选中/不可用态，以及横屏和大字体。完整多选/相邻查看功能归 A6/A7。 | 原 `AlbumPanel.PhotoAdapter` / `ThumbTile` 与 [CameraPhotoGrid][camera-grid]。 |
| 编辑器、边框及导出预览 | 原边框模板和参数面板已有接线；继续核对中文字体回退、字面宽度、文字位置、模板像素取整、滚动/拖动手感及不同构图/边框组合。既有验证保留的约 1–3px 差异不能因新包编译通过而自动关闭。 | [legacy_editor.dart][legacy-editor]、`border_panel.dart`、`crop_workspace.dart`、[export_settings.dart][export-settings] 及原 `PhotoFilterEditor` / `PhotoBorder`。 |
| 本轮在线滤镜、项目、RAW 参考和权限页面 | 检查加载、空、离线、失败/重试、进行中、取消和账号变化后的布局；缩略图必须显示真实帧，长名称、进度和固定操作区不能溢出或被底栏遮挡。项目完整原版自动开拍流程尚未迁移，不能只做外观验收。 | [EditorPresets][editor-presets]、[拍摄项目页面][projects-ui]、[RawDevelopPage][raw-develop]、[camera.dart][camera]。 |
| 首页、相册和二级弹层 | 四主页状态保留后，重查筛选/排序/选择页返回、滚动位置、主题切换、日期/来源标签、根导航遮挡、键盘与系统安全区；逐一对照注册、资料、社区及帮助/诊断的错误状态。 | [main.dart][main]、`legacy_sheets.dart`、[PhotoMasonry][photo-grid]、`legacy_photos.dart`、[settings.dart][settings]。 |

## 下一轮并行分工建议

1. **相机任务组：A1、A2、A6。** 先接自动新片生产者和持久收片队列，再做后台/恢复；共享同一会话所有权模型。遥控 A3 和槽位写入 A5 各自保留独立状态机，避免与相册传输并发争用通道。
2. **图像工具组：A8、A9。** 先完成两端分析/推理结果和可取消计算，再接人像、身体和自动修补页面，最后验证草稿/撤销和大图内存。基础调节、局部蒙版和取样克隆保持现有结果。
3. **图库与平台组：A4、A10、A11。** 将 USB 发现、RAW 发布和照片删除/批量发布拆为独立小任务；每项都包含真实资源回读与失败恢复，不能只接页面。
4. **账户/分发/资料组：A12、A13。** QQ、更新和旧安装迁入分别处理；用独立测试账号与资料副本完成验证。
5. **由主任务统一验收和构建。** 宿主桥、路由、共享 DTO 的修改先协调文件范围。每个子任务交付“页面入口→原生能力→持久结果→取消/失败/重开验证”及明确未验证范围；实体设备和账号验收单独排期。运行中的冻结构建不混入新源码。

[camera]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/camera.dart
[shared-camera]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/core/java/cc/huevia/shared/SharedCamera.java
[camera-grid]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/camera_grid.dart
[camera-previews]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/camera_previews.dart
[camera-transfer]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/camera_transfer.dart
[original-album]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/ui/AlbumPanel.java
[original-album-controller]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/album/AlbumController.java
[connection-service]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/connection/CameraConnectionService.java
[live-continuation]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/connection/PhotoLiveContinuation.java
[remote-activity]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/RemoteCaptureActivity.java
[remote-camera]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/remote/NikonRemoteCamera.java
[settings]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/settings.dart
[android-host]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/android/app/src/main/java/cc/huevia/sharedapp/MainActivity.java
[main]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/main.dart
[legacy-editor]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/legacy_editor.dart
[portrait-dialog]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/ui/PhotoPortraitDialog.java
[body-dialog]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/ui/PhotoBodyDialog.java
[patch-dialog]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/ui/PhotoPatchDialog.java
[local-edits]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/core/java/cc/huevia/shared/SharedLocalEdits.java
[projects-ui]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/project_presets.dart
[projects-model]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/project_presets_model.dart
[projects-core]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/core/java/cc/huevia/shared/SharedProjects.java
[raw-develop]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/raw_develop.dart
[raw-reference-ui]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/raw_reference.dart
[raw-reference-core]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/core/java/cc/huevia/shared/SharedRawReference.java
[raw-pairing]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/album/RawPhotoPairing.java
[raw-publisher]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/album/RawPhotoPublisher.java
[original-publication]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/core/java/cc/huevia/shared/SharedOriginalPublication.java
[export-settings]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/export_settings.dart
[export-save]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/export_save.dart
[original-save]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/original_save.dart
[album-batch]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/album_batch.dart
[versions]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/versions.dart
[photo-grid]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/photo_grid.dart
[legacy-account]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/legacy_account.dart
[qq-controller]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/account/QqLoginController.java
[update-manager]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/app/src/main/java/cc/huevia/updates/AppUpdateManager.java
[domain]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/domain.dart
[widgets]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/widgets.dart
[editor-presets]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/editor_presets.dart
[profile]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/profile.dart
[ios-core]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/native/ios/Classes/HueviaCorePlugin.m
[wifi-socket]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/native/ios/Classes/HueviaWifiSocket.m
[app-stability]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/app_stability.dart
[native-stability]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/android/app/src/main/java/cc/huevia/sharedapp/NativeStability.java
[ios-stability]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/native/ios/Classes/HueviaStability.m
[help]: https://github.com/1162107757/nikon-camera/blob/c33c4546120e5225cf95f4841639f22b1e7f8d84/cross-platform/app/lib/help.dart
