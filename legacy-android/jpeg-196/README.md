# 旧 Android JPEG 修复维护包 196

本目录独立于已冻结的 195，修复由本目录 `patch_sources.py` 应用到生成的旧版 Java 源码。原 `app/`、194 overlay、195 源文件/安装包和新版 213 产物均不改写。

构建先加载 194 overlay 以保留兼容依赖及资料迁出代码，再加载 196 overlay：复制原 Java 树到 `app/build/generated/legacy-jpeg196/java`，调用 `patch_sources.py --source <生成树>`，使用生成树、原 194 的 `src`、共享核心及本目录 `src`。版本固定为 `cc.huevia` / `0.30.36-beta-jpeg-fix` / `196`，保留四 ABI，供同签名覆盖安装 193/194/195。

196 从 194 的生成 manifest 另存独立副本到 `app/build/generated/legacy-jpeg196/AndroidManifest.xml`。原 Huevia 主入口保留；`LegacyExportActivity` 的 MAIN/LAUNCHER intent-filter 被移除，且设为 `exported=false`。因此 196 只暴露正常 Huevia 桌面入口，不再增加“旧版资料迁出”图标；资料迁出代码仍在包内。

由主任务取得构建和设备使用权、准备好补丁后，在唯一项目根目录执行：

```powershell
python legacy-android/jpeg-196/build.py
```

默认离线使用现有 Gradle 8.11.1、JDK 17.0.19、Android SDK/build-tools 36.1.0；`--online` 允许补齐依赖，沿用现有 Maven init，不自动启动或改写代理。可用 `--gradle`、`--java`、`--sdk` 和 `--build-tools` 指定路径。

构建前确认原 `.tooling/debug.keystore` 的真实证书 SHA-256 为 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`；完成后核对 v2/v3 签名、16KiB ZIP 对齐、版本、四 ABI、唯一 Huevia launcher 及 helper 的非 exported 状态。桌面入口检查同时读取 `aapt2 dump badging` 和编译后的 `aapt2 dump xmltree`。

输出为 `dist/legacy-jpeg196/` 下 APK、`receipt.json`、`SHA256SUMS.txt` 及 `build-evidence/`。195 和 213 包不覆盖；四 ABI 包按手动附件交付，不改变旧更新渠道 32MiB 规则。

本构建脚本的静态校验不替代 JPEG 列表、缩略图、下载、升级后的资料保留和桌面图标的实际设备验收。

## 相对 195 的状态修复

共享 Controller 已有照片索引时，原 AlbumPanel 仍可能因丢失单监听回调而保留空连接快照。此时主界面显示已连接、诊断显示索引就绪，但照片页面停在“照片暂不可用”；Runtime 的重试直接返回已就绪，不触发分页。

196 在页面进入、前台恢复、共享状态刷新及显式重试时幂等同步真实快照，恢复分页并重新接管前台监听器。同一快照不清空现有照片或重置已推进的分页。主动连接、下载、导出、恢复任务及本地编辑页保留各自所有权。漏掉断线通知后，前台清理失效的远程条目和过期忙碌状态，下载文件仍保留。

保留 195 的空 JPEG 筛选回退、通用类型独立 JPEG 识别及不可读卡提示。新增诊断仅记录页面是否接入、分页开始/结果和类型计数，不记录照片文件名或内容。原 `app/` 文件始终不改写。

设备回归入口为 `tests/build_probe.py`：构建同签名的独立 Instrumentation APK，加载已安装的真实生产类，通过只读受控 PTP/IP 相机复现第二 Panel 接管并关闭监听器后的陈旧页面，覆盖前台、进入、重试、幂等、忙碌/所有权和漏通知断线清理。测试只允许运行在专用模拟器和显式指定的安装包 SHA 上。

真实 Z 6_2 验证与跨平台新版移植仍按用户要求分步完成：先交付旧版并等待真机反馈，通过后再移植新版。
