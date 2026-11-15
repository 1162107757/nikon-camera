# 相机界面接入源码审查

审查日期：2026-11-14。基线：`a0ff5db`；对象为工作区尚未提交的相机界面改动。已完成初审及同日三项修正的定向源码复核；以下保留初审问题及其修复状态。

## 范围与结论

审查 `camera.dart`、`camera_connection_view.dart`、`camera_connection.dart`、`wired_camera.dart`、`sync_tools_dock.dart`、`camera_photo_sort.dart`、`camera_photo_toolbar.dart`、`camera_downloads.dart`、`camera_grid.dart`、`camera_remote.dart`、`camera_remote_preview.dart` 和 `tool/check_camera_photo_sort.dart` 的当前改动。未编辑产品代码。

初审发现 3 项 P2，定向复核结果为 **3 项已解决、0 项部分解决、0 项未解决**。本次定向复核没有新增阻塞项。排序比较器本身保留源列表、同值稳定顺序和无效时间置后；初审问题出现在会话与分页使用方。

## 修正复核结果

| 初审项 | 状态 | 当前源码证据 |
| --- | --- | --- |
| 新会话残留旧目录/游标 | 已解决 | `camera.dart:432–450` 在接受新会话后清除 `items`、`offset`、`hasMore`、`paginationError`、`warning`，随后 `previews.setSession()` 对变化的会话执行缓存和代际重置；选择继续清除。惰性读取不会再显示旧会话目录。 |
| 全屏退出提前恢复同步请求 | 已解决 | `camera.dart:135–169` 先等待 `MaterialPageRoute.completed`，再等待 `afterClose()`，最后才解除 `childOpen` 并恢复预览/状态请求。`:178–191` 收集 `CameraRemotePage.onClosing` 提供的关闭 Future；`camera_remote.dart:357–369` 将原有关闭实现的 Future 上报，系统返回后的 `dispose()` 也走此路径。 |
| 预览翻页破坏所选排序 | 已解决 | `CameraPhotoSort` 已从 `CameraPage` 传至网格和预览。`camera_grid.dart:220` 排序初始列表，`:261–269` 合并新页后排序完整目录，按当前 handle 恢复索引，再计算下一张位置，不再按批次追加展示。 |

全屏退出顺序还对照了项目本地 Flutter SDK 的源码：`routes.dart` 的 `TransitionRoute.completed` 在路由 dispose 时完成；`navigator.dart` 的普通路由 dispose 等待其 widget 子树卸载。因此本项目的正常返回路径会先执行遥控 `dispose()`、登记关闭 Future，再进入调用方 `afterClose()`。此为框架源码核对，未运行 Flutter。

## 初审问题记录（均已解决）

### 1. [P2，已解决] 新会话必须清除旧照片目录和分页游标

位置：`cross-platform/app/lib/camera.dart:262–266`、`:429–443`。

已经浏览相机 A 后发生物理断开，`status()` 会隐藏照片但保留 `items`、`offset`、`hasMore`。重新连接相机 B 时，新增的 `deferPhotoRead = true` 阻止原本会清空目录的 `page()`；`status()` 在会话变化时只清除选择。只要新会话进入 `photos` 模式，网格就会用新 `previews.session` 显示旧目录，即使 `inventoryReady` 为 false。用户可在点击“浏览相机照片”之前，对新会话发出携带旧 handle/文件名的预览或接收请求；旧分页游标也会残留。

修正：会话身份改变或断开时，一起清空目录、分页状态、选择和预览缓存；让新连接保持真正的未读取状态。验证应覆盖“先读取 A → 物理断开 → 连接 B → 未点浏览”的路径，断开路径不能只测 UI 的 `disconnect()`。

### 2. [P2，已解决] 全屏退出应等待遥控销毁和租约释放后再恢复同步页

位置：`cross-platform/app/lib/camera.dart:134–138`、`:153–158`；相关既有逻辑为 `camera_remote.dart:424–442`、`:472–490`。

新的全屏分支等待 `hueRootPage()`，其实现直接返回 `Navigator.push()` 的 Future；该 Future 在 pop 开始时完成。原来的 `showLegacyGlassSheet()` 还会等待 `route.completed`。Android 系统返回或 iOS 返回手势在 `busy == false` 时可以直接 pop，绕过会先关闭租约的 `finish()`。因此同步页会提前清除 `childOpen`、恢复缩略图并调用 `camera.status`，而退出动画中的遥控页仍然存活、可能轮询并持有租约；直到稍后的 `dispose()` 才发出异步关闭。

修正：全屏返回也应等待 route transition 完成，并显式等待该遥控页的关闭 Future；确认租约已关闭后再恢复同步页请求。保持已有 `pollCompletion` 串行等待与后台/账号变化保护。验证需包含系统返回、返回手势、轮询中返回以及立即重新打开工具，不能只测顶部返回按钮。

### 3. [P2，已解决] 预览翻页不能把重新排序的目录按旧追加协议合并

位置：`cross-platform/app/lib/camera.dart:198–200`；相关使用方为 `camera_grid.dart:252–260`。

`morePhotos()` 现在返回全部已加载照片的排序结果，但 `CameraPhotoViewer.move()` 仍然只把未见过的条目追加到现有列表。例：名称升序第一批为 `DSC_2, DSC_4`，新页合并后的正确顺序为 `DSC_1, DSC_2, DSC_3, DSC_4`；预览实际变成 `DSC_2, DSC_4, DSC_1, DSC_3`，与网格和用户选择的排序不一致。时间排序在新页应插入当前列表前部或中部时也会发生。

修正：把当前排序传给预览，在合并新页后重排完整预览目录，并按当前照片 handle 恢复索引，避免跳图。现有纯 Dart 检查只检查排序函数，没有覆盖预览的合并协议。

## 非阻塞收尾复核

- `SyncToolsDock.downloadLabel` 的旧参数和调用已删除。
- `CameraRemotePage` 的 `transport` 已仅在真实状态为 `usb` 或 `wifi` 时展示连接方式。
- RAW 开关的 `camera-raw-switch` key 已实际加到控件上。
- 375dp 下的标题、工具展开面板和双列网格具有源码上的宽度约束；短屏遥控存在滚动回退。但这些只能说明约束路径可读，不能证明 Flutter 实际排版、字体缩放、系统安全区或触控行为已通过。

## 已核对的保护与验证限制

与 `a0ff5db` 规范化换行后比较，遥控 `run()`、`request()`、`capture()`、`poll()` 主体仍未改动；350ms 轮询及 `pollCompletion` 等待仍在源码中。原 `closeLease()` 实现移至 `releaseLease()`，方法重命名之外的主体完全等值，外层 `closeLease()` 只登记并返回该 Future。`finish()` 和 `dispose()` 延续原有关闭调用。新增暂停和对焦入口继续进入既有 `request/run`。第 2 项的修正发生在关闭 Future 的交接与调用方恢复时序，没有重写快门或轮询业务。

本轮没有运行 Flutter、Gradle、Apple CI、原生构建、真机或真实相机验证，也没有提交、推送、发布、修改版本/原生代码或冻结 221 记录。没有把 HTML 原型或其截图作为原生产品验证。仅进行了源码/差异检查、业务方法等值比较、路由生命周期源码核对，以及预览追加协议的最小数据推演。协调方报告修正后 Dart analyzer 无问题、23 项纯 Dart 排序检查通过；审查者未独立重跑，新增 widget 测试也不视为已经执行。该记录不能支持“原生视觉验收完成”或“可发布”的结论。
