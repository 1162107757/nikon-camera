# 213 图像工具、批量图库与相机生命周期状态

记录日期：2026-11-13。开发快照：`d3124a4b54192505f0ad7ac8a0a4f6cbaaf2b907`。本记录对应 A8 / A9 / A11，以及本组追加的 A2 / A6 / A7 控制器和控件检查；它不是本轮 APK / IPA 的冻结验收结论。统一构建、平台执行和最终验收由主任务继续收口。

本组工作只在 `D:\dev\ai-project\nikon-camera` 进行，未修改原 `app/` 源码、原 iOS 工程或 211 / 212 冻结包与验证记录。211 前台边拍边传和 212 的预设固定、RAW、账户、USB 能力继续保留。相机协议、槽位、RAW 配对与原格式目标的并行工作见 [相机组状态](status-camera-213.md) 和 [RAW / 保存目标记录](validation/raw-original-targets-213/README.md)。

## 已接入的操作链

| 类别 | 页面到实际能力 | 保存、失败与取消边界 |
| --- | --- | --- |
| A8 人像与身体 | 编辑器“人像”进入独立工作页；可自动选脸、选择人物、手动添加和调整脸部范围，调节提亮、磨皮、纹理、光源、眼神、眼白、牙齿、肤色目标与强度；可分析全身皮肤、多人物身体位置、瘦身 / 瘦腿 / 拉长范围、单腿与背景保护。点按祛痘复用原取样规则。 | Android 调用原 `PhotoPortraitDetection`、`PhotoFaceLandmarks`、`PhotoFaceSkinMask`、`PhotoPersonAnalysis` 和 `PhotoBodyAnalysis`。iOS 以 Vision 的真实眼位提供候选，再执行相同网格及语义模型。结果写回原二进制 `localData`；工具页只生成临时预览，按“应用”才交给编辑器保存草稿。取消、计算失败、账号变化和旧结果均不能代替当前编辑提交；撤销 / 重做保留完整前态。没有可靠皮肤范围时禁止制造有效皮肤效果。 |
| A9 涂抹自动修补 | “人像”页和调节栏均有修补入口。按源图坐标涂抹，松手后执行原 `PhotoPatchSampler` 的真实纹理搜索，冻结取样位移，以原 `PhotoPatchRenderer` 渲染；也可用位置控制与点按替代拖动。 | 使用 EXIF 定向、未裁切且未身体变形的坐标系，有界分析图最长边 384。选区过大、背景不足和取消会保留当前配方；重试、移除最后一个修补、撤销 / 重做均可操作。没有以新增按钮或已有 patch 的可读性代替新修补计算。 |
| A11 多图编辑与发布 | 选择 1–100 张后，可逐张进入完整编辑器；统一预设 / 强度、尺寸和应用成品 / 同时保存手机相册目标。开始后先冻结所有配方，再顺序生成和发布。 | 每个成员在本地任务日志中持久保存发布 `operationId`、配方、已生成版本和平台收据。重新打开相同选择可继续未完成项；已有成品不重新编码，已有发布不另造操作 ID。显式“新建一次批量任务”才创建新的发布意图。系统发布继续复用两端已有的原生校验与去重事务。 |
| A11 删除范围 | 多选页可进入“删除范围”，分别选择应用原图、应用成品和有保存记录的系统相册副本；手机相册来源则只作用于所选系统资源。提交前显示所选范围，Android / iOS 仍按系统要求确认。 | 先冻结源 SHA、版本集合、系统资源集合与操作 ID；每张按系统副本、成品、原图执行，前一步失败就保留其后范围。发布副本先按保存记录核对实际字节 / SHA；Android 使用 MediaStore 删除请求或对应系统授权，iOS 使用 PhotoKit 事务和回读。应用原图先移除原项目引用再 unlink。原生删除日志允许丢失响应后重试，不删除后续新版本或未选中原图。 |
| A2 连接保护与停止 | Android 前台服务 / iOS 有限后台时段由原生状态驱动。Dart 维护活动参与者，处理生命周期、原生期限和独立的通知 `stopRevision`。 | 新通知停止代次无论前台还是后台都实际调用 Live / Queue 的停止路径；普通关闭后台开关不等同于停止前台任务。过期事件不会被较早的原生调用响应覆盖；乱序响应和畸形状态不能恢复已经失效的后台许可。 |
| A6 下载队列控制器 | 读取原生持久队列及逐项接收收据；应用原图、系统相册和持久文件夹目标均有对应请求。恢复成员已有原生收据时，只做校验、入库及目标发布。 | 不从一次临时 transport reply 推导完成。系统 / 文件夹发布请求明确要求 `verifyReadback: true`，沿用原成员操作 ID；原生负责 owner、源 SHA、字节和目标绑定。账号变化停止并清除旧列表，迟到 restore / create 结果不展示到新账号。损坏日志通过 `issues` 单独提示，其他有效任务仍可继续。Queue、Live 和跨页面手动接收互斥。 |
| A7 相邻查看器 | 相邻导航、分页按 handle 去重、当前项接收、仅相邻缩略图预取；保留 JPEG 对应 NEF 的核对 / 接收入口及其预览暂停 / 恢复。 | 查看器冻结 session 与 generation；同名 session 的新代次也会失效。下载回调开始到共享传输状态发布之间有本地锁；分页返回时再次检查 busy；读取下一页期间不能接收或切上一张。预览 Future 按 session / generation / handle 隔离，防止新标题暂时显示旧图。空闲页面也会调度会话失效的实际刷新。 |

## 同模型推理的分发与边界

Android 复用工程已存在的 LiteRT 1.4.1 Java / native 运行库，没有为本组新增 Android 推理 `.so`。iOS 使用官方 `TensorFlowLiteC 2.17.0` CPU C API，并对原模型文件做固定字节长度与 SHA 校验：

| 资源 | 字节 | SHA-256 |
| --- | ---: | --- |
| `portrait/face_landmarks_detector.tflite` | 2,553,590 | `c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5` |
| `portrait/face_skin_multiclass.shuffle4.zlib` | 13,881,786 | `9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0` |
| 解包后的六类语义模型 | 16,371,837 | `c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0` |

iOS 的 crop、RGB 归一化、presence logit、468 点坐标、语义 softmax、人物连通区域和背景边缘保护在 `SharedPortraitInference` 中实现，来自原算法规则；不会用插值补出 468 点。多人面部皮肤按独立连通区域与其他人脸范围隔离。分析图片最长边 1280，自动修补最长边 384；模型后处理复用逐像素工作数组，iOS 每个人脸另设 autorelease pool。iOS CPU invoke 开启可取消选项并响应任务停止；停止后不提交计算结果。

已实际下载 [官方 CocoaPods 分发规范](https://github.com/CocoaPods/Specs/blob/master/Specs/1/6/0/TensorFlowLiteC/2.17.0/TensorFlowLiteC.podspec.json) 指向的 Google 运行库，核对其 xcframework 含真机 `ios-arm64` 和模拟器 `ios-arm64_x86_64-simulator`。下载包为 80,242,958 字节，SHA-256 为 `9667b476015f136e5b332ce040e12822c4ac6d5c58947882ddc809cdff0fb99e`。切片存在与 C API 头可读不等于 Apple SDK 编译、安装或推理已经通过。

保留的显式 `engine: system` 路径会标注 `Vision` 与取样肤色范围，不能当作原语义模型或 468 点推理通过；正常请求默认使用原模型。自动分析无人脸时返回空集合，允许手动选区，不生成假检测。

## 实际执行记录

| 检查 | 已观察结果 | 不能据此推导的范围 |
| --- | --- | --- |
| 人像 / 修补 / 删除共享边界 | 本组独立 `RetouchBoundaryTest` 40 项通过，覆盖原模型 DTO、真实取样搜索、祛痘、肤色互斥、取消、配方前态、版本范围和未选文件保护。主任务随后补 Mac 路径别名回归，并报告统一 JVM 1179 项通过。 | 合成 logits 的后处理检查不是一次真实模型执行；共享文件事务检查不是系统图库提供者执行。各次检查数量不相加为独立平台能力。 |
| Android 新适配编译 | `NativeRetouch`、`NativeAlbumOperations`、图库删除辅助和 Gallery 接线对真实 Android SDK 36 独立 javac 编译通过。 | 不代表系统确认、授权变更和实际外部资源删除全部通过。 |
| Android 实际执行 | 主任务已经执行实际 LiteRT 模型、皮肤蒙版、人像渲染、祛痘 / 自动修补和取消环节；运行日志可见 native runtime 初始化及对应操作完成。主任务当前原生检查结果为 119 项 PASS，包含其 FGS / Activity 复用与代次补强。 | 这不是本组自行签发的整个综合场景 PASS。后续 RAW 夹具缺 SHA 的失败已由负责组补齐，统一场景重跑与最终结果由主任务确认；仍不能覆盖所有真实人像、极端大图和实体相机。 |
| Queue / Protection 新专项 | `camera_downloads_test.dart` 与 `connection_protection_test.dart` 共 16 项，exit 0 / All tests passed。覆盖收据恢复不调 `camera.download`、系统 / 文件夹回读请求、临时响应不算收据、owner 切换、损坏日志隔离、手动 / Queue / Live 准入互斥、期限失效、前台恢复竞态及前台通知停止。 | 使用受控 core / 原生状态响应检验 Dart 协议与调度；不是一次真实 PhotoKit、SAF 或后台期限实测。 |
| 既有 Live 回归 | `camera_live_test.dart` 完整 16 项通过，包含窄屏大字 Live 卡控件、211 的断连 / 重连、重复去重、迟到收据、账号变化、停止补偿和前后台发现。 | 未使用实体相机替代原协议受控夹具。 |
| Viewer 控件 | `camera_viewer_test.dart` 6 项全部通过，检查相邻后接收当前不可变 DTO、仅缩略图预取、旧 session / 新 generation、初始和分页去重、busy 竞态、旧下载闭包保护和分页失败重试。 | 缩略图使用受控失败响应，测试的是控件 / 回调 / 调度，不是实际 PTP 缩略图或 RAW 解码。RAW 原生夹具由另一组接统一入口。 |
| 批量状态 / 发布恢复 | 既有 BatchExport 的 6 项状态检查独立通过；新增 `batch_album_publish_test.dart` 1 项通过，检查重开后沿用操作 ID、保留已发布收据、不重新生成已完成 JPEG，以及显式新任务换 ID。 | 测试中的发布响应是受控响应，不能称为真实系统相册发布通过。 |
| 分析检查 | 本组图像 / 批量文件、Viewer，以及三生命周期控制器和新增测试的定向 `dart analyze` 均为 No issues found。 | 静态分析不代替页面视觉检查或原生执行。 |

本地开发日志位于 `.tooling/retouch-migration/`，包括 `retouch-boundary.log`、`android-javac.log`、`dart-analyze.log`、`flutter-camera-lifecycle.log`、`flutter-live-regression.log`、`flutter-camera-viewer-skia.log`、`flutter-batch-state-tests.log` 和 `flutter-publication-test.log`。主任务的 Android 实际执行记录位于 `.tooling/next213/android-native.log`、`android-integration-logcat.txt` 等当前工作日志；这些是开发证据，尚未作为本记录的冻结分发附件。

## 未完成的执行与验收

- Windows 默认渲染后端运行部分控件时出现 `flutter_tester` exit 79 / native access violation。Viewer 和 Live 控件使用 `--no-enable-impeller` 后已完成上述检查；不能把此参数视为全部宿主问题的修复。
- `batch_export_test.dart` 的三项 PhotoMasonry / 批量页面布局检查在 Windows 375×812、文字倍率 1 / 2，以及 812×375、倍率 2 下未完成。即使切换 Skia，进程仍中途终止。这三项没有计入通过，等待 Apple 执行；不能从已通过的六项状态检查推导整份文件通过。
- A8 / A9 的唯一原生综合入口已经接入 `verifyRetouchPipeline(core)`：两张真实内置人像、原网格与语义模型、眼牙参数、真实预览、祛痘、自动修补、撤销、原图 SHA / 草稿不变、分析取消及无人脸风景。iOS 明确断言 CPU 同模型引擎和真实 468 点；当前 Apple 新快照执行中，尚不能写为通过。
- Apple 首轮准备阶段发现删除重试把原入参 `/var/...` 与持久 canonical `/private/var/...` 直接比较。主任务已修复生产路径守卫和删除后幂等重试，并添加路径别名回归；旧失败记录保留，新的完整 Apple 构建、控件与原生结果仍待主任务确认。
- A11 两端真实系统相册多图发布 / 删除、部分授权、系统确认取消、资源外部编辑 / 删除、iCloud / 第三方文件提供者、进程终止后的部分完成恢复，仍需完整平台事务验收。删除范围的代码和本地持久边界已接通，不能据此将这些场景标为实测完成。
- 人像 / 修补工具页的小屏、横屏、大字、TalkBack / VoiceOver、真实人物效果及长期内存表现，Android 电池策略 / 长时间锁屏，以及 iOS 实际后台期限和系统终止后的恢复，继续保留实机验收项。

本记录不改变 [213 统一剩余清单](remaining-work-213.md) 中由主任务掌管的最终平台结论。后续成功结果应追加对应运行、源码快照和证据，不覆盖本记录所列未完成执行或旧失败。

## 后续执行补记：批量控件测试

Apple 运行 `43348397039` 完成 257 项、失败 3 项；失败项正是上述三个批量控件视口，均在点击“开始批量导出”后等待 `pumpAndSettle` 超时。批量任务的真实文件日志需要系统事件循环处理磁盘 I/O，已有 Future 链和控件通知也需要测试 zone 推进微任务，单独在 `runAsync` 中等待任务不能完成两者。

`afed203` 后续测试修正保持三个视口和全部选择、固定动作、完成数量、分享断言，改为真实点击后交替推进真实事件循环与控件帧，设置 15 秒真实计时上限，并在每项结束时卸载页面、释放测试拥有的 `AppState`。同步断言当前完成文案“已保存成品 2/2 张”。Windows 使用 `--no-enable-impeller` 完整运行 `batch_export_test.dart`，同一进程 **9/9 全部通过**，包括此前未完成的三个控件项；单文件 `dart analyze` 为 `No issues found`。证据为 `.tooling/retouch-migration/flutter-batch-widget-complete.log` 和 `dart-analyze-batch-widget.log`。未跳过测试，未改生产缩略队列或 APK；对应 Apple 后续执行仍由主任务确认。
