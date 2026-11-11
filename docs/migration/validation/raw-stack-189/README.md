# 189 RAW 栈崩溃检查

原生 XCTest 捕获的 iOS 崩溃摘要保存在 `ios-crash-summary.json`。崩溃发生在栈内 LibRaw 大对象初始化，迁移桥接已改为堆分配；原 Android/iOS 工程与原 LibRaw 动态库保留。

`android-native.log` 是 Android 12 的 38 项原生检查，含请求 512 KiB 栈线程的真实 RAW 无缓存显影。`android-pipeline.log` 是同设备完整 Flutter/native 图像场景的实际结果；`android-widget.log` 是 16 个界面场景的实际结果。

`android-release-raw.png` 和 `android-release-share.png` 来自最终 x64 release 包的 DNG 编辑与完整 JPEG 导出实操。图像使用自制 DNG，未使用用户照片。

精确源码提交、包哈希及各证据文件哈希见 `../android12-raw-stack-189-20261111.json`。这是迁移开发版验证，不代表全部功能和样式已对齐，亦不代替荣耀 Magic 实机或未知型号 NEF 验证。
