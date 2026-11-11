# 原版 Android Wi-Fi 连接与照片列表修复（191）

版本：`0.30.33-beta`，`versionCode=191`，包名 `cc.huevia`。工作目录为 `D:/dev/ai-project/nikon-camera`。

## 修改

- 同步页正在等待连接/导入任务释放连接时，首次照片列表准备可能被推迟。旧版仅在连接 UI 状态改变时重建页面，最后一个任务释放后状态未变，未重新消费照片浏览需求。因此会停留在“相机已连接，照片暂不可用”，且下方只有默认说明。现在运行时通知到达时先检查可见同步页的照片浏览需求，再决定是否重建页面。
- PTP/IP 初始化确认虽然使用 30 秒预算，底层每次读取只允许 15 秒，导致等待相机确认时提前超时。命令和事件通道的初始化确认分别使用一个覆盖包头与包体的 30 秒期限。普通控制读取、原图下载预算及 TCP 建连的 5 秒限制保持原策略。
- 建连超时区分 Wi-Fi TCP 通道、等待相机确认、事件通道、读取相机信息和打开会话。保留原始超时异常，并释放已经创建的通道。
- 不新增协议重试、相机内容写入或网络路由回退。连接观察事件不会无条件重建界面，避免重置正在显示的照片、进度及滚动位置。

## 验证

`evidence.json` 记录安装包元数据、生产源码及测试源码 SHA-256、主机测试摘要，以及绑定安装包 SHA-256 的设备回归结果。

- 旧版 186 安装包：在独立 Android 模拟器运行真正的 `MainActivity`、`CameraConnectionRuntime`、`AlbumController` 和 `PtpIpClient`，通过两个合成 PTP/IP Socket 注入已连接会话。复现默认“照片暂不可用”说明；连接任务释放后仍无 `GetStorageIDs`，验证旧版缺陷。
- 最终 191 交付包：同一场景自动读取存储和照片句柄，得到 1 张合成照片并清除不可用状态。全程两个通道、一次 `OpenSession`，未手动点击重试。设备探针仅加载目标安装包的生产类，不打包生产实现。
- PTP/IP：5,435 项断言，包含超过 15 秒确认等待的合成复现、6 个阶段的超时清理、普通读取超时仍终止、原图传输预算及一次性连接移交。
- 相册：899 项；相机能力 33 项；网关连接 25 项；项目存储/目录 356/100 项；进度 23 项。
- Wi-Fi 保活/目标地址/网关/会话：519/27/37/604 项；真实运行时断网测试 29 项。

复测命令（PowerShell，项目根目录）：

```powershell
pwsh -NoProfile -File tests/run-ptpip-download.ps1
pwsh -NoProfile -File tests/run-album.ps1 -JdkHome D:/dev/Java/jdk-17.0.19
pwsh -NoProfile -File tests/run-wifi-retention.ps1
pwsh -NoProfile -File tests/run-wifi-runtime.ps1
pwsh -NoProfile -File tests/wifi-album-device-probe/build.ps1
```

探针仅允许 Android 模拟器。安装目标 APK 和探针后，将实际 APK 的 SHA-256 传给 `am instrument -w -r -e apkSha256 HASH cc.huevia.wifialbumqa/.WifiAlbumProbe`。旧版复现另传 `-e expectBlocked true`。请使用独立测试设备，探针会启动原版应用并注入合成连接状态。

## 安装包

交付文件：`dist/upload191/huevia-0.30.33-beta-update.apk`。保留原签名证书，APK v2/v3 和 16 KiB 对齐校验通过。包压缩过程中只去除 4 个 x86 库，其余 89 个载荷逐项保持解压后内容一致；保留 ARM64、ARMv7 和 x86_64。最终交付包已在独立模拟器覆盖安装并运行上述回归。未发布到线上更新渠道。

## 尚待实机验证

验证时没有连接用户手机或真实相机。合成协议与模拟器结果不能证明用户 Z30 的实际 Wi-Fi 路由、相机确认及待机条件均已解决。需要使用本版本在实际手机/相机上复测；若仍失败，可依据新的阶段提示和连接报告继续定位。
