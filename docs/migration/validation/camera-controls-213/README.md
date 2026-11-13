# A3 / A5 开发验证（未冻结安装包）

本记录只覆盖当前工作区新增的遥控和优化校准槽位代码，不替代 212 的安装包、冻结源码、验证记录或实体相机验收。

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

## 仍待验证

Windows 未进行 Apple SDK 编译。统一 Apple CI 必须编译新增 J2ObjC 接口和 ImageCaptureCore 实现，再独立核对 IPA。实体 Nikon / iPhone / Android 的实时画面与坐标、不同拍摄模式、USB 授权拒绝/拔插/占用、实际 NCP 写入/删除/掉线及存储卡回读仍需接机验收。尚未产出或认证本轮 APK / IPA，也不认定整体迁移完成。
