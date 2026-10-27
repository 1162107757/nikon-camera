# 降噪、颗粒、暗角与透视模块

本模块由图片综合任务并行实现；它不是独立安装包或发布完成记录。主编辑器、草稿格式及原生验收由根任务集成。

## 实现与接入契约

- `PhotoAdjustments.Parameter` 在旧 13 项之后追加 `LUMA_DENOISE`、`COLOR_DENOISE`、`GRAIN`、`VIGNETTE`，范围均为 0–100。构造器接受旧 13 项与新 17 项；新增项全为 0 时，旧身份与旧渲染分支保持。`LEGACY_PARAMETER_COUNT=13` 用于旧格式读取；写入格式仍由新草稿/配方版本负责。
- `AdjustedPreviewProfile.renderPixels` 将降噪放在手动颜色之后、手动锐化之前，颗粒和暗角位于细节处理之后。所有入口共用该路径；`applyArgb` 仍只做点颜色。默认设置保留 108 的处理路径。
- `PhotoDetailEffects.denoise` 是自定义 encoded-sRGB 双边亮度/色差降噪：原图值提供空间及颜色差异权重，透明邻居按 alpha 加权，原 alpha 保留。每轴最多 5 个采样位置；整数权重/累加消除方向遍历差异。不是神经网络模型，也不是 Nikon 官方降噪的复刻。
- 行缓冲与图像高度无关，最大半径 12，工作量每像素最多 25 个邻居；6000×4000 输入仅保留行环和输出行。仅表示算法工作内存有界，不代表 Android 整体峰值内存。
- 颗粒是固定种子的连续噪声场，锚定 EXIF 归一后的完整原图坐标；暗角同样在构图之前。`SpatialPreviewFilter.Pixels.exifOrientation()` 默认为 1，根任务需在 raw 方向处理的完整导出/细节/临时预览入口返回原图 EXIF。已归一的主预览继续默认 1。
- `PhotoGeometry` 保留旧 6 参数构造器，增加尾部 `horizontalPerspective`、`verticalPerspective` 两个整数，范围 −100–100。`perspective(h,v)` 保留已有裁剪/拉直。旧零透视身份保持；非零透视采用 `photo-composition-projective-v2` 身份。
- `Plan` 提供完整 3×3 投影矩阵、`map` 和 `inverse`；透视采用正分母投影及填充缩放。实际 `PhotoComposition` 已使用 `Plan.matrix()`，因此直接消费投影矩阵，不需要另建近似像素路径。
- `PhotoCropDialog` 复用原滑杆，左侧下拉选择拉直、水平透视或垂直透视；数值单行，面板高度保持。取消不调用提交，应用只提交最终不可变几何对象。

算法基础参考：[Tomasi 与 Manduchi 的双边滤波原始论文](https://users.cs.duke.edu/~tomasi/papers/tomasi/tomasiIccv98.pdf)。此处的量化、采样、分量和参数映射是项目自定义模型，并非原论文实现的逐字移植。

## 已运行的验证

- `tests/run-photo-detail-effects.ps1`：39,904 项检查通过。包括噪点方差下降、亮度偏差、边缘反差、彩色降噪保留亮度、透明邻居隔离、单像素/单行、确定性颗粒、暗角中心/四角、EXIF 1–8 精确像素等价、极值透视与 EXIF/旋转/拉直/裁剪反变换、无空角、取消与进度。
- 同一测试用 64MiB Java 堆完成真实 24MP（6000×4000）流式降噪，桌面 JDK17 观察约 11.34 秒。未分配整张输入数组；这不是手机耗时或峰值内存承诺。
- `tests/run-image-performance.ps1`：冻结旧渲染对照通过，10,209,032 个像素精确一致，12,400,382 项检查。仅针对原有无新增效果的路径，不把这一结果当成新降噪的外部视觉认证。
- 现有测试中硬编码基础参数数量的断言改为枚举长度；旧 PED2/3 夹具继续明确写 13 项，避免拿新数据冒充旧格式。

日志在 `.tooling/photo-image-suite/detail-effects-host.log` 和 `legacy-render-regression.log`。本子任务未构建主 APK、未操作 ADB、未发布或部署服务。原生尺寸/交互/取消和真实照片审看仍需根任务在最终同包完成。
