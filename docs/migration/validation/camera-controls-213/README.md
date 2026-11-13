# A3 / A5 开发验证与 A2 / A7 验收边界

本记录覆盖新增遥控和优化校准槽位代码，并补充已整合后台保护与查看器的证据边界。2026-11-13 文档复核基线为 `8d43086119fc88eb97e8157be44d76b6ac917c26`。各安装包、测试日志按各自源码记录核验，不替代 212 冻结证据或实体相机验收。

## 已接入

- `CameraRemotePage` 在既有相册连接上申请独立、可撤销的 Nikon 遥控权限，复用原 `NikonRemoteCamera` / `RemoteLiveFrame` / `RemoteProperty`。支持实际取景帧、暂停/恢复、自动对焦、具备可信几何信息时的点按对焦、单张快门及实际机身参数读取；原协议授权的参数为只读，页面要求在机身调整。离开页面释放遥控权限，恢复相册所有权。
- 快门前持久保存相机身份、库存基线与单次操作标识；响应丢失保留待核对状态，不重发快门。用户可读取相机新照片核对，或在相机手动核对后明确解除阻塞。应用退后台停止取景轮询并发出一次停止请求，失败不循环重试。
- `CameraSlotsPage` 展示真实 C1–C9 数据，支持受原转换器约束的 638 字节 NCP 兼容导入、机内槽位复制、明确覆盖及删除。NCP 适配参数和完整说明先展示，再进行单独的目标确认。
- 写入前重新读取身份、能力与全部槽位，并紧接写入前再次检查目标原字节；复制还检查来源没有变化。一次连接最多尝试一次写入或删除。操作前持久保存意图；执行后读取全部槽位，核对目标原字节或空槽，以及其他槽位未变化。活动槽位不删除。
- Wi-Fi 使用原 `PtpIpClient` 的独立 Picture Control 模式。Android 先关闭 OS MTP 会话，再独占双向 USB bulk 端点，复用原 PTP 编解码与严格验证。Apple 使用 `ImageCaptureCore` 实际系统会话和 `requestSendPTPCommand:outData:completion:`；逻辑会话操作映射到真实系统打开/关闭完成，不向系统持有的会话重复发送 PTP OpenSession。两端共用 `SharedSlotTransportGuard`。
- 响应丢失后，新的明确连接只读核对旧记录，不重放原命令。身份或字节无法唯一匹配时保持待核对，用户可在原相机手动检查后明确确认。设备序列号仅用于本地身份哈希，不写入操作记录。

Apple API 依据：[PTP command / outData](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:))、[PTP capability prerequisite](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:sendcommanddelegate:didsendcommand:contextinfo:))。

## 本地实际通过

| 检查 | 结果 | 证据 |
| --- | --- | --- |
| Java 11 共享源码编译及相机协议状态边界 | 76 项通过 | `.tooling/agent-camera/raw-compile.log`、`CameraControlsBoundaryTest.log`；`CameraControlsBoundaryTest` |
| Android USB 照片/槽位两个适配类对实际 Android SDK 36 与 Flutter jar 编译 | 通过，仅既有 API 弃用提示 | `.tooling/agent-camera/android-slots-compile.log` |
| Dart 两页与专用测试静态分析 | 零问题 | `.tooling/agent-camera/dart-analyze.log` |
| Flutter 遥控未知结果阻塞、能力禁用/断开恢复、槽位删除确认和取消 | 3 项通过 | `.tooling/agent-camera/flutter-controls.log` |

边界测试包括原 NCP 测试字节实际转换为 614 字节并精确回读、原 NCP 字节不变、取消不写、来源/目标中途变化拒绝、旧确认与重复执行拒绝、写入成功但响应丢失后跨会话只读恢复、删除不改其他槽位、活动槽拒绝、操作顺序、取消/关闭和 USB 首次打开失败后的明确重试。

## A2 / A7 集成复核

- Android 主任务的 [119 项原生检查记录](../features-213/android/native-119.json)及[实际日志](../features-213/android/android-native.log)已核对通过；记录的宿主、保护控制器、服务和 instrumentation 四个源码 SHA 与上述复核基线一致。运行环境为 API 31 / x86_64 / 4096 字节页模拟器。生命周期用例实际启动服务，并覆盖同主线程快速停止再启动、同 engine 接管、关闭和重开 Activity、通知停止后旧宿主迟到释放仍不关闭新宿主 backend。119 是媒体与生命周期总检查数，不是 119 项接机检查。
- 通知停止使用独立 `stopRevision`；Live / Queue 在前台也处理真正停止。Queue / Protection 的 16 项受控 Dart 检查和既有 Live 的 16 项回归由编辑组验证，详见[专项状态](../../status-editing-lifecycle-213.md)。这些检查不代替实体锁屏、厂商电池策略、断网或系统终止。
- iOS 到期取消链经只读复核：`camera.cancel` 不等待共享请求锁；Wi-Fi 关闭只唤醒阻塞读写并取消网络连接，USB 关闭异步请求系统会话结束，不在到期回调中等待 semaphore。重新连接时的等待在 worker 上。此结论是源码复核，不是实际 iOS 到期或 iPhone 运行证据。Apple 的[到期回调约定](https://developer.apple.com/documentation/uikit/uiapplication/beginbackgroundtask(expirationhandler:))要求主线程同步执行该回调。
- A7 的 `camera_viewer_test.dart` 6 项控件检查通过，覆盖相邻导航后的当前 DTO、只取缩略图、分页与回调竞态；RAW 解码由原生夹具另外核验。主任务 [41 项 R8 release 记录](../features-213/android/release-runtime.json)来自 `3db73d2575fc93296e0995c5476c237397c2a1a7` 的真实 x64 优化 APK，含新鲜 RAW JNI 缩略图，不代表所有机型文件或实际 PTP 缩略图通过。

## 仍待验证

主任务已产出 Android 开发 APK 并取得上述模拟器记录；[签名和 ZIP / ELF 16 KiB 对齐](../features-213/android-signing-alignment.json)通过不等于 16 KiB 设备运行通过。本专项尚未取得 213 Apple SDK / IPA 成功验收记录，须由统一 Apple CI 编译新增 J2ObjC / ImageCaptureCore 实现并独立核对产物，不能沿用 212 的成功记录。

仍缺实体相机、16 KiB Android 设备和 iPhone。实时画面与坐标、不同拍摄模式、USB 授权拒绝/拔插/占用、实际 NCP 写入/删除/掉线及存储卡回读、长时间后台和系统终止后的恢复均须分别验收。机身参数只读、Nikon Wi-Fi 遥控的实际能力范围保持不变，不认定整体迁移或端到端实机已通过。
