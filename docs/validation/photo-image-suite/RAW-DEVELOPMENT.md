# RAW 显影实施与验证范围

底层使用官方 LibRaw 0.22.3：实际 `open_file → unpack → dcraw_process → copy_mem_image`，`half_size=0`，从有效全尺寸传感器数据生成 8bit sRGB PNG 工作图。原始 RAW 保持不变；Java 编辑链仍为 8bit sRGB，不把工作 PNG 宣传为可逆线性 16bit RAW。

## 实现

- `RawDevelopmentSettings`：相机／自动／自定白平衡、色温和色调、曝光、高光模式及线性／AHD 去马赛克。参数不可变且全部进入版本化身份。
- `RawDeveloper.inspect/develop`：同步 worker API，原 RAW 和输出 SHA、账号目录隔离、严格文件边界、原子 PNG／记录提交、缓存完整性校验、损坏输出重建和取消。原 RAW 在处理前后核对；缓存返回前也再次核对原图。
- JNI：直接将处理后的 RGB8 写入 Bitmap stride，再逐行倒向扩为 RGBA。没有额外完整 RGB 缓冲和巨型 Java 数组。LibRaw callbacks 关联取消／进度，JNI 异常及 Bitmap lock／recycle 路径均处理。
- 自定白平衡使用相机 XYZ 矩阵；DNG 只保留 `rgb_cam/pre_mul` 时，通过其逆／伪逆恢复相机响应。没有有效矩阵时明确报错，不退回 JPEG 色温。
- 官方源、四 ABI 库、完整源 ZIP／许可证／可替换重建说明随 APK 提供，参见 third-party/libraw/README.md 和 RAW-MODULE-IDENTITY.json。

## 已完成的主机／构建检查

281 项设置序列化、范围及真实未压缩 DNG 夹具结构检查通过。独立反射探针已构建签名；不编译或打包生产类。合成 DNG 没有内嵌 JPEG；另固定一张 CC0 Nikon Z6 14bit 无损压缩 NEF，完整来源和摘要见 `.tooling/raw-native/samples/SAMPLE.json`。

四 ABI 中 64 位库满足 16KiB LOAD 要求；NDK 官方 32 位 libc++ runtime 保留 4KiB 对齐，逐库如实记录。编译／ELF 不代替实体设备运行。

## 首批 Android 观察与修正

首候选 APK `9c61236e…` 原生证据保留于 `raw-development/9c61236e/20261027-182720-e9af33993b/`。前 20 项已通过，包括完整 DNG、原图保护、相机白平衡、±1EV、PNG SHA、缓存及账号隔离；随后在 DNG 自定白平衡报错。该记录仍为 **失败**，未把部分通过项计成整轮成功。

原因是 LibRaw 的 DNG 路径将颜色矩阵处理至 `rgb_cam/pre_mul`，没有保留 `cam_xyz`。JNI 已补充真实相机 RGB 矩阵逆／伪逆路径并重编。runner 的 finally 又因纯 Java 历史包不是 debuggable 而使 run-as 清理失败、掩盖了业务首错；已改为同签名 instrumentation 在 App UID 下只清本轮生成的私有夹具／独有 probe-owner 缓存，移除 run-as，清理错误单独记录并保留业务原错。

确认候选的完整 Android 结果须由根任务在最终同包报告中填写，未运行前不记 PASS。该子任务没有操作 ADB、安装主包或发布。

## 实际限制

6000 万有效像素、1GiB 输入、512MiB LibRaw RAW buffer 限额；不是 App 总内存保证。−5 至 +5 EV 的范围外增益按官方 LibRaw `exp_shift` 的 −2 至 +3 EV 能力与 16bit 输出 `bright` 阶段组合。支持范围以本构建的实际 LibRaw decoder 为准，未集成可选专有插件，不宣称所有 RAW 格式和压缩模式均可用。尚未据此认证实体手机峰值内存、速度或全部相机型号。
