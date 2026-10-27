# RAW 原生与实际界面探针

反射调用实际安装 APK 的 RawDeveloper 和 RawDevelopActivity，探针不编译或打包生产类。根任务独占模拟器，先单独安装最终主 APK，再运行：

```powershell
pwsh -NoProfile -File tests/raw-development-device-probe/build.ps1
pwsh -NoProfile -File tests/raw-development-device-probe/run.ps1 -CandidateApk <最终APK绝对路径> -ExpectedApkSha256 <SHA256> -Serial emulator-5586
```

不会安装、卸载或清空主应用。runner 核对已安装 APK 字节，临时设置普通字体和飞行模式，安装自己的 instrumentation，最后卸载自己的探针并恢复设置。所有 DNG、NEF 副本、显影缓存和 Activity 生成的文件都有本轮唯一命名或精确路径；不接触相机、MediaStore 或用户原 RAW。

SyntheticDng.java 生成 96×64、12bit 白点／16bit 容器、真实未压缩 RGGB Bayer DNG；没有嵌入 JPEG。检查完整尺寸、实际去马赛克、曝光和三种白平衡、缓存／账号隔离、输出损坏重建、方向、取消、源文件变化拒绝和原 RAW 摘要。

同一运行还启动真实 RAW Activity，验证实际控件、PNG 写出和全尺寸 JPEG 编辑副本交接，保留两张截图。UI 夹具是合成图案，仅用于布局及交互检查，不能当成照片审美评价。

默认额外读取 `.tooling/raw-native/samples/nikon-z6-lossless-14bit.NEF`，其来源与 CC0 许可在同目录 SAMPLE.json。固定 SHA 为 `c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31`，来自 raw.pixls.us Nikon Z6 14bit 无损压缩样本；实际处理完整有效尺寸，并确认原文件不变。没有提供 NEF 时明确记录 skipped，不把合成 DNG 成绩当成真实 NEF 成绩。

证据保存在 `docs/validation/photo-image-suite/raw-development/<APK前缀>/<runId>/`；输出明确是 8bit sRGB PNG，不能认证 16bit Java 编辑链、所有 RAW 压缩模式、实体手机速度或峰值内存。
