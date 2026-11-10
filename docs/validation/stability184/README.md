# 184 / 0.30.30-beta：导出错误与 Android 12 稳定性

最终本地候选：`dist/upload184/huevia-0.30.30-beta-update.apk`，31,419,670 字节。

- SHA-256：`2ab445a72700385b5ba95fb51d8ee130f2df751c59e4723e1d2572ac7cf72776`
- 完整构建 SHA-256：`306de70ed640c16461b0d8b01a30a163b2a0c0ca9827a1fd8ae465726ed05988`
- 包名 `cc.huevia`，versionCode 184，versionName `0.30.30-beta`。
- 签名证书 SHA-256：`04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`；v2/v3 校验通过，16 KiB ZIP 对齐检查通过。
- 仅在本地准备安装包，未提交、推送或上传发布。旧版 178–183 安装包和冻结记录未修改。

## 已证实的问题

### 1. 导出提示「效果模型无效」

183 在真实 Android 12 / API 31 上使用局部调整、裁剪、边框组合进行原尺寸导出，会生成合法的 322 字符效果标识。`PhotoPresetSources.rememberModel` 原先仅允许 256 字符，另两处限制却是 512 字符，导致渲染后的提交失败。简单组合 235 字符能够成功，分享导出使用 79 字符摘要标识也能够成功。这是标识存储校验不一致，与模型下载无关。

184 将源关联、结果恢复和批处理键统一使用 1024 字符校验，仍拒绝空白、控制字符及超长内容；恢复日志按 modified UTF 的最坏字节数限制读取，同时检查 EOF。批量请求先校验，避免无效请求先耗费完整渲染。没有截断标识或改变哈希算法。

在同一 API 31 环境中，原来成功的简单原尺寸导出和复杂分享导出，183 与最终 184 的输出 JPEG SHA-256 完全相同；此前失败的 322 字符组合现在完整导出并能从原关联记录复用。[结果与逐项证据](final-results.json) 包含精确标识和输出哈希。

### 2. 真实 Android 12 闪退：效果缩略图复制

第一版 184 候选 `75c34c18…` 在 RAW 编辑回归中发生了未捕获的 `IllegalAccessError`：

```text
PresetPreviewProfile.render:28
PhotoFilterEditor.render / renderColour
PhotoBorderPanel.lambda$requestThumbnails$9
java.lang.Object.clone() is inaccessible
```

183 也在同一 API 31 环境复现了相同异常，独立于 RAW 解码器。该调用位于接口默认方法内，源代码中的数组 `clone()` 在此运行环境解析到了不可访问的 `Object.clone()`。改用 `Arrays.copyOf(argb, argb.length)`，保留相同的独立像素副本，未改变色彩运算、空间滤镜或效果标识。

证据：[原始崩溃缓冲](raw-api31-crash.txt)、[新记录器实际保存的异常栈](raw-api31-local-crash.txt)、[修改前 DEX](preview-profile-dex-before.txt)、[修改后 DEX](preview-profile-dex-after.txt)。183 的专项报告保存在 `device/6a50a4be/phone-20261110-072113-a5a6ac20/`，其中 `baselinePreviewCrash` 是实际异常栈。修复后相同默认方法的原图、曝光和强度包装调用在 API 31/36 均通过，RAW 全流程也不再触发这条崩溃。

这确认了一处 Android 12 崩溃点。当前没有荣耀 Magic 真机日志，不能据此断言用户手机上的所有闪退均由它导致。

### 3. 文件选择器及系统设置交接

183 的诊断报告入口在系统缺少文件应用、或系统拒绝启动时会抛出未处理的 `ActivityNotFoundException` / `SecurityException`。实际 Android ActivityMonitor 故障注入已复现；这类注入是错误路径验证，不是荣耀真机崩溃的归因。

184 将相关模板、样片、预设、照片选择及报告导出交接收敛到 `SystemActivityLauncher`。缺少 OPEN_DOCUMENT 时可退回 GET_CONTENT，并移除不适用于该回退的持久授权标记；拒绝或无可用入口时给出提示。创建文档不能用文件选择代替，因此失败时保留在应用内。相关系统设置交接也处理首选与回退均被拒绝的情况。相册仅修改这两类交接，[与冻结 183 的精确差异](local-album-vs183.patch) 未涉及排序或删除逻辑。

## 诊断能力

应用启动时安装本地有界记录器，保留原默认未捕获异常处理器，写入失败仍将原始 Throwable 原样交给原处理器一次。最近一次 Java 崩溃记录包含版本、系统/机型、线程、堆占用和异常栈；使用原子替换，文件最多 64 KiB。没有吞掉崩溃或自动上传记录。

在「设置 → 使用帮助 → 导出诊断报告」中，无需先连接相机就能导出 JSON。后台工作线程追加 `appStability`，包括本地异常和 Android 11+ 的系统退出原因，区分 Java/native crash、ANR、低内存等。最多保留 4 条异常退出，最多读取一条 64 KiB trace；native tombstone 以 Base64 保存二进制前缀。报告收集失败保留原报告。

如荣耀 Magic 升级后仍闪退，重新打开应用并导出该报告，可继续依据真实栈和系统退出原因定位。

## 最终验证

[final-results.json](final-results.json) 指向每次实际安装包 SHA、报告及清理记录；以下 8 次选定回归合计 615 项检查全部通过，清理和设置恢复均核实。

| 环境与范围 | 检查数 |
| --- | ---: |
| Android 12 手机：启动、四个根页面反复切换、预设来源/筛选、选择器故障、效果默认方法、三种真实 JPEG 导出、诊断 | 77 |
| Android 12 大字体、深色、关闭模糊 | 77 |
| Android 12 平板尺寸 | 77 |
| Android 16 手机 | 77 |
| Android 16 横屏、深色 | 77 |
| Android 12：LibRaw、合成 DNG、RAW Activity、全尺寸 Nikon Z6 NEF、色彩与原件保留 | 160 |
| Android 12：真实 NEF 编辑 | 15 |
| Android 12：导出预览、原尺寸细节、缩放平移、方向、裁剪边框、取消及线程清理 | 55 |

主机回归：688 项照片批处理、95 项源关联恢复；11 项崩溃记录边界、原子写入与处理器链；NP3/单色既有回归通过，完整外部预设语料缺失的检查按原脚本明确 SKIP，未下载或虚构覆盖。

手工独立 Lint 描述符显式列出全部 Java 源码，以 minSdk 26 / compileSdk 35 扫描 API、权限、线程、资源、回收和 receiver flags。成功运行后的结果为原有 33 项：18 NewApi、12 InlinedApi、2 receiver flags、1 ResourceType，详见 [审计说明](source-review.md)。本次新增代码没有新增这些警告。此前缺 package 导致 manifest merger 失败的尝试不算审计完成；最终 XML/TXT 是修正描述符后的真实结果。Lint 结果未宣称为零问题，也没有为了消除警告而改写已由 D8 回移的 String API。

API 31/36 模拟器均为隔离的本任务 AVD；运行时页面大小为 4096。16 KiB 是安装包对齐检查，未宣称已在 16 KiB 运行环境验证。没有荣耀真机、物理相机传输、长时间内存压力或整机厂商后台策略认证。

## 保留的失败与中间证据

- `rejected-candidate-75c34c18/` 是抓到实际缩略图闪退后废弃的候选，不能作为交付包。其签名候选仍在本地按完整构建 SHA 分目录保存。
- 最终 SHA 下 `phone-20261110-072321-5289d28d` 是测试工具发全局返回键时被其他窗口抢焦点导致 INJECT_EVENTS 拒绝，未作为通过证据。工具改为关闭本应用的提示后重跑成功，没有修改生产包。
- RAW `20261110-072511-phone-bcafdbae55` 已通过前面的 UI/解码检查，随后因临时 root ADB 推入的 NEF 文件权限而在测试文件归属检查失败。恢复非 root ADB、使用全新测试目录后完整 160 项成功，失败记录没有删除。
- 构建早期一次外层 PowerShell 将 javac 警告 stderr 误判为失败；完整成功构建为 `build-array-fix.log`。原始日志仍保留在 `.tooling/stability184/`，未当作产品故障。

## 源码与包对应

[source-manifest.json](source-manifest.json) 冻结本次 18 个生产/测试文件的哈希，副本位于 `.tooling/stability184/final-source/`；[preservation.json](preservation.json) 核对 183 的 11 个保留源文件及相册两处交接以外的全文一致性。最终 APK 与 183 的有效载荷差异仅为 `classes.dex` 和 `AndroidManifest.xml`，签名元数据随重签变化，资源、模型、全部保留 ABI 的 native 库逐字节一致。

交付包从完整构建中仅剔除 4 个 x86 库；89 个保留条目与完整构建逐项一致，详见 [payload-provenance.json](payload-provenance.json)。签名、元数据及哈希分别见 [apk-signature.txt](apk-signature.txt)、[package-candidate.json](package-candidate.json)、[SHA256SUMS.txt](SHA256SUMS.txt)。
