# LibRaw RAW 显影依赖

固定官方版本 **LibRaw 0.22.3**，完整源码在 `LibRaw-0.22.3/`，原始发行 ZIP、SHA 和 URL 在 SOURCE.json。ZIP SHA-256 为 `114ca5cf9f774114cb99ce7acbb521af5f6895e76372098ea4bef5741bd089ac`。源码来自[官方发布页](https://www.libraw.org/download)，没有改写上游文件。

本项目选择 LGPL 2.1 分发 LibRaw，保留官方 LICENSE.LGPL、LICENSE.CDDL 和 COPYRIGHT。`libraw.so` 与应用 JNI 桥 `libhuevia_raw.so` 独立动态链接；完整官方源 ZIP、桥源码、RAW Java 适配器、设置模型、构建脚本和许可均随 APK 的 `assets/third-party/libraw/` 分发。LLVM runtime 的许可见同目录 LLVM-NOTICE.txt。

## 重建和替换

在项目根运行：

```powershell
pwsh -NoProfile -File scripts/build-raw-native.ps1 -NdkRoot D:/dev/android-sdk/ndk/28.2.13676358
```

输出为 `app/src/main/jniLibs/{arm64-v8a,armeabi-v7a,x86_64,x86}/{libraw.so,libhuevia_raw.so,libc++_shared.so}`，保留原纯 Java 包的 32／64 位安装范围。使用 NDK r28c、Android API 26；自建库及 64 位 ABI 依赖均为 16KiB 兼容 LOAD 对齐。官方 NDK 32 位 libc++ runtime 保留其 4KiB LOAD 对齐，对应传统 32 位 Android 进程，不把它误报为 16KiB 库。源 ZIP 与解压目录逐文件校验，BUILD-IDENTITY.json 逐库记录实际对齐、源指纹、工具链和摘要。原生实际运行验收使用 x86_64 模拟器，32 位和 arm64 编译成功不代替对应实体设备测试。

允许修改 LibRaw 源码；传入 `-AllowModifiedLibRaw` 时使用当前完整源文件的实际摘要，重新构建库及桥。相同 ABI 的库可单独替换；ABI 变化时用随包的桥源码重新链接。按 Android 的正常工具链重打包、签名、安装自建 APK。应用不限制为了调试所替换的 LGPL 库而进行的逆向工程。改变解码行为后应使用独立 LibRaw runtime 版本字符串或清除自己的 RAW 工作缓存，避免复用旧结果。原 RAW 文件不应改写。

默认构建未使用 OpenMP；进度／取消回调在发起显影的 worker 上运行。开启系统 zlib，未集成可选 RawSpeed、Adobe DNG SDK、外部 JPEG/JPEG2000 或专有解码插件。特定压缩模式是否可用，以实际 LibRaw 错误为准，不使用内嵌 JPEG 充当完整显影。

## 输出与范围

`open_file → unpack → dcraw_process → copy_mem_image` 从实际传感器数据处理有效全尺寸；`half_size=0`。LibRaw 内部使用 16bit 图像及 demosaic／相机颜色矩阵，输出指定 sRGB 曲线和 8bit。RGB 直接写入 Android Bitmap 的 stride，再倒向逐行扩为 RGBA，不额外分配整张 RGB／Java 数组。Java 将完整 Bitmap 编成 PNG，进入已有 8bit sRGB 编辑链。

自定白平衡将黑体光谱与 CIE XYZ 匹配函数近似积分，再用相机矩阵计算用户通道倍率；它不是对 JPEG 叠加冷暖色。CIE 解析近似参考 [Wyman、Sloan、Shirley 2013](https://jcgt.org/published/0002/02/01/)。没有可用相机矩阵时明确拒绝自定白平衡，仍可选择相机或自动模式。

曝光 UI 为 −5 至 +5 EV；官方 LibRaw 的 demosaic 前 `exp_shift` 支持 −2 至 +3 EV，范围外剩余增益由 LibRaw 16bit 输出的 `bright` 阶段处理，全部发生于 PNG 编码之前。高光恢复按 LibRaw 0–9 模式执行。此处不声称全线性 16bit Java 编辑或任意高光恢复能力。

当前完整显影上限为 6000 万有效像素、1GiB 源文件和 512MiB LibRaw RAW buffer 限额。该 buffer 限额不是 App 总内存上限；Bitmap、demosaic 和 PNG 编码另有内存开销。
