# 原版安卓连接与相册诊断日志（193）

版本 `0.30.34-beta` / `193`。仅修改原版 Android 应用与对应验证，不修改跨端界面或在线后台。

用户反馈 191 后仍出现“相机已连接，但无法读取照片”。本次增加取证能力，不将合成测试结果解释为真实相机故障已经修复。

## 用户入口

1. 安装 `dist/upload193/huevia-0.30.34-beta-update.apk`，连接相机并重试读取照片。
2. 若照片暂不可用，点击下方“导出诊断”。连接页的错误详情中也有同名按钮。
3. 原有“帮助与设置 → 导出诊断报告”继续可用。
4. 选取文件保存位置，导出 JSON 文件。无需开启额外开关，不主动上传日志。

## 报告内容

- 命令 TCP、初始化确认、事件通道、读取设备信息和打开会话的阶段及耗时。
- 相册任务为何等待、相机信息解析、缺少的必需读取操作、存储卡和照片句柄读取阶段。
- 存储卡数量、照片句柄总数、数据长度、PTP 操作编号与返回码；格式回退和不可用存储卡有独立记录。
- 原有操作日志继续包含缩略图、照片元数据等读取时序；失败时补充 PTP 返回码。
- 当前 Wi-Fi / 相机会话 / 照片索引状态，手机厂商、型号、安卓版本和应用版本，以及基于已观察返回码生成的诊断摘要。

日志记录固定标记、数字及错误分类，不写入原始异常文本、Wi-Fi SSID、密码、照片内容、文件名或相机序列号。报告中的机型、地址和端口来自当前已建立的会话。现有预设报告字段保留，新增 `connectionDiagnostics`，原有 `connectionTrace` 保持兼容。

本地日志仍限制 256 条 / 64 KiB，异步写盘；最近的关键诊断优先保留，避免被普通保活事件立即挤掉。历史日志重新加载仍使用严格格式校验。外部应用文件目录不可用时改用应用内部目录。

## 验证

最终交付 APK 已校验原签名证书、v2/v3 签名、16 KiB 对齐，并在独立模拟器中安装验证。压缩包只移除 4 个 x86 库，其余 89 个载荷内容保持一致，保留 ARM64、ARMv7 和 x86_64。

真实安装包中的 MainActivity / Runtime / AlbumController / PtpIpClient 通过两个合成 Socket 运行，探针不打包生产实现：

- 相机忙 `0x2019`：相机会话仍打开，照片索引未就绪，界面显示导出入口，报告包含准确返回码及“读取照片索引时，相机返回忙碌”的摘要。
- 缺少 `GetObjectHandles (0x1007)`：报告记录缺少的具体操作，保留相机会话，允许导出诊断。
- 上述两类故障都通过原有文档结果回调写出真实 JSON 文件；导出未断开会话，没有额外连接或重复 `OpenSession`。
- 正常读取仍能自动加载照片列表。

三个设备场景共 53 项断言通过。主机验证：协议 5,435 项、日志 562 项、相册控制器 899 项、相机能力 33 项、网关 25 项、项目存储/目录 356/100 项、进度 23 项、Wi-Fi 保活/地址/网关/会话 519/27/37/604 项、运行时断网 29 项。

复测：

```powershell
pwsh -NoProfile -File tests/run-ptpip-download.ps1
& D:/dev/Java/jdk-17.0.19/bin/java.exe -cp tests/.build/ptpip-download cc.huevia.album.ConnectionTraceTest
pwsh -NoProfile -File tests/run-album.ps1 -JdkHome D:/dev/Java/jdk-17.0.19
pwsh -NoProfile -File tests/run-wifi-retention.ps1
pwsh -NoProfile -File tests/run-wifi-runtime.ps1
pwsh -NoProfile -File tests/wifi-album-device-probe/build.ps1
```

仅在独立 Android 模拟器安装目标 APK 与探针，传入实际 APK 的 SHA-256：

```text
adb -s SERIAL shell am instrument -w -r -e apkSha256 HASH -e failure busy cc.huevia.wifialbumqa/.WifiAlbumProbe
adb -s SERIAL shell am instrument -w -r -e apkSha256 HASH -e failure capability cc.huevia.wifialbumqa/.WifiAlbumProbe
```

省略 `-e failure ...` 验证正常读取；每次使用新的目标应用进程。安装包元数据、源码哈希及设备断言结果见 `evidence.json`。尚待用户使用真实手机/相机复现并导出报告，才能判断实际失败原因。本版本未发布到线上更新渠道。
