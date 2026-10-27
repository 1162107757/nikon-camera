# 下一轮局部蒙版：最小交付范围与接入边界

日期：2026-10-27。状态：**只读预研，尚未实现**。本文件是 108 完成后的下一轮准备，不属于 108 功能、性能结果或发布承诺。本次只新增本文档，没有修改生产代码、构建、运行测试或操作 ADB。以下行号对应预研时工作区源码。

## 推荐的最小交付

先完成一个照片专属的**椭圆渐变蒙版**：创建、移动、调整宽高、羽化、反选、启用/停用和删除；局部参数先限制为曝光、色温、饱和度。三项沿用现有点调色含义，不把清晰度、锐化等邻域算法放进首版局部处理。

交付需同时包括区域提示、实时预览、撤销/重做、草稿恢复、真实细节及现有 JPEG 导出；只显示选区或只处理缩略图不算完成。

首版暂不含画笔、多蒙版叠加、AI 选区、局部邻域处理、跨照片复制蒙版。具体交互和数学模型留给下一轮规格；本文件仅为范围建议及代码接入预研。

## 现有事实与不能跳过的接入点

| 实际文件 / 入口 | 现有事实 | 下一轮必须接入 |
| --- | --- | --- |
| [PhotoAdjustments.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ncp/PhotoAdjustments.java:42) | 不可变全局参数、曲线、HSL，已参与配方和跨照片复制。 | 蒙版用独立不可变模型挂在 Draft，局部参数可复用受限的点调色值；不要把照片空间位置默认传播给全局调节复制。 |
| [PhotoEditStore.java / Draft](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoEditStore.java:23) | 草稿含原图 SHA、预设字节、强度、全局调节、构图、边框、exported；`hasEffect/identity/profile` 决定渲染与身份。 | 加入蒙版、深复制/不可变约束、完整相等性、模型版本与有效效果身份；无蒙版保持旧身份和旧像素路径。所有重建 Draft 的入口必须保留蒙版。 |
| [PhotoEditStore.java / read、save](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoEditStore.java:74) | 当前 PED5，旧格式兼容；未知尾部数据拒绝。按账号与 sourceSha 存储，摘要校验，sync 后原子替换。 | 新格式版本，旧 PED1–PED5 读为空蒙版；校验类型、有限坐标、尺寸、参数、数量及总字节上限。不能直接在 PED5 末尾追加数据。沿用校验、隔离与原子提交。 |
| [PhotoFilterEditor.java / EditState、history](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java:167) | `snapshot/same/remember/restoreHistory/finishDrag` 管理完整快照与手势合并。 | 主状态、快照、相等判断、恢复、reset、bind 均覆盖蒙版；应用一轮蒙版编辑清空 redo，取消不写入。不能共享可变点/控制柄数组。 |
| [PhotoFilterEditor.java / save、freeze](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java:507) | 200ms 延迟保存，串行 IO，保存屏障；导出冻结 Draft；`matches/refreshExportStatus` 保护状态。 | 保存与 freeze 捕获同一不可变蒙版；已导出标记只对应同一冻结身份，导出期间的新蒙版编辑不得被标为已导出。 |
| [PhotoFilterEditor.java / currentProfile](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java:528) | Editor 和 Draft 各自组装 profile，目前是预设强度 → 全局调节 → 构图载体 → 边框载体。 | 两处组装一致地加入局部阶段。`schedulePreview`、滤镜缩略图 `request`、`draftThumbnail` 也必须保留蒙版快照与版本，不能只更新主图。 |
| [PresetPreviewProfile.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ncp/PresetPreviewProfile.java:12)、[AdjustedPreviewProfile.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ncp/AdjustedPreviewProfile.java:70) | `applyArgb` 只有颜色没有坐标；`renderPixels` 提供带宽高的行读写，全局预设/空间处理在此运行。 | 局部阶段必须按像素坐标和蒙版权重运行，不能只包装 `applyArgb(int)`。建议新增局部模型与 profile/行处理器，继续有界行缓冲、取消、进度和 alpha 保留。 |
| [PhotoGeometry.java / Plan](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ncp/PhotoGeometry.java:26)、[PhotoComposition.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoComposition.java) | 构图有明确的边缘坐标仿射映射及 inverse，含 EXIF、90°旋转、拉直和裁剪。 | 用同一变换把工作区触点映回原图坐标；裁剪/拉直后蒙版仍绑定原物体，不随当前显示宽高重解释。 |
| [PhotoFilterEditor.java / decode、render](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java:653) | 主预览先做 EXIF 方向归一，再缩小、调色、应用 geometry(exif=1)。 | 显式提供“已方向归一”的渲染坐标上下文；不能默认为原始 JPEG 存储坐标。 |
| [PhotoPresetRenderer.java / render、renderDetail](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoPresetRenderer.java:73) | 完整导出和真实细节先在原始存储方向调色，再应用 EXIF/构图；细节为无边框、无导出缩放 PNG。 | 向局部阶段提供真实 EXIF/原始尺寸坐标上下文，保证与主预览同一区域。局部效果发生在边框、导出缩小、JPEG 编码之前；保留原图不可覆盖和完整尺寸失败不降级规则。 |
| [PhotoDetailSource.java / preparePreview](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoDetailSource.java:145)、[PhotoFilterEditor.java / showDetails](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java:546) | 细节预览也先 raw 方向调色后构图；真实 tile 来自冻结 surface；当前中性时与 before 共用原图。 | provisional、full surface 同一蒙版与坐标上下文；`unchanged` 必须考虑有效蒙版，非空局部效果不能误走中性共享。冻结 identity 与 `starting.same(snapshot())` 一并覆盖蒙版。 |
| [GeometryPreviewProfile.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ncp/GeometryPreviewProfile.java:19)、[BorderPreviewProfile.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ncp/BorderPreviewProfile.java:11) | 几何提取只识别当前已知包装层，边框也只识别外层。 | 局部 profile 放在 Geometry 的内部或统一明确解包协议；不要套新外层后让构图/边框被误读为 NONE。 |
| [PhotoPresetBatch.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoPresetBatch.java:342)、[PhotoPresetRenderer.java / modelVersion](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoPresetRenderer.java:34) | 导出复用键包括源 SHA、效果预设 SHA、profile/model、实际导出规格；成功后按冻结 Draft 标记 exported。 | 蒙版参数及模型版本经 profile 进入此身份；相同原图与全局参数、不同蒙版必须生成不同效果身份。空蒙版不得使全部旧成品失去复用。 |
| [PhotoAdjustmentCopy.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoAdjustmentCopy.java:31)、[PhotoRecipeStore.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/album/PhotoRecipeStore.java:22) | 复制 basic/curves/HSL；配方不含照片构图。复制/撤销有完整草稿 compare-and-replace。 | 首版不复制或保存蒙版到配方，但应用配方、复制全局调节必须保留目标照片既有蒙版；比较与回滚不能覆盖后来的蒙版编辑。 |
| [AlbumPanel.java / ensureFilterEditor](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/AlbumPanel.java:3576)、[PhotoImageView.java](D:/dev/ai-project/nikon/app/src/main/java/cc/huevia/ui/PhotoImageView.java:169) | 宿主消费编辑结果、刷新缩略图；PhotoImageView 自有缩放和平移/翻页手势，`visiblePhotoBounds()` 返回裁切到视口的矩形。 | 首版优先独立工作区隔离选区手势；若复用主图，需要真实的图像到屏幕逆变换，不能用已裁切 visible bounds 反推坐标，否则放大后选区漂移。 |

## 三个必要契约

1. **非破坏保存与历史**：原 JPEG 不改写；不可变蒙版进入版本化 Draft 与完整快照，沿用 32 步会话历史和连续手势合并。若采用现有曲线/构图临时工作区模式，取消不写草稿、应用作为一个主历史步骤。导出过程中后来编辑的蒙版不能被标成已导出。
2. **坐标与共用渲染**：建议蒙版保存于 EXIF 归一、用户构图之前的完整原图归一化坐标。主预览已归一，full/detail 仍在 raw 坐标调色，三条入口必须显式传映射。建议全局效果后做局部点调色，再构图/边框/导出缩小；下一轮冻结羽化、混合空间、舍入模型，不能 UI 与导出各写近似算法。
3. **验证口径**：缩小预览仍是近似预览，要求区域映射一致；真实细节与完整输出编码前对照。提示叠色不进直方图/成品；禁用、零参数、无蒙版保持旧像素和身份；完整尺寸失败不降采样。

## 下一轮可复用验证入口（本次未执行）

- `tests/run-photo-editor.ps1`：扩展蒙版模型、旧草稿兼容、身份、历史与复制保留用例。
- `tests/editor-java/cc/huevia/album/PhotoCompositionTest.java`、`tests/run-photo-detail-viewport.ps1`：补 EXIF 1–8、奇数尺寸、旋转/拉直/裁剪与缩放映射。
- `tests/photo-color-device-probe/run.ps1`、`tests/photo-editor-device-probe/run.ps1`：补区域手势、取消/应用、undo/redo、切图恢复与过期回调。
- `tests/photo-export-device-probe/run.ps1`、`tests/run-image-performance.ps1`：补不同蒙版导出身份、真实细节对照、无蒙版回归和 24MP 内存/取消。

下一轮先验证坐标和不可变模型，再接草稿/共享渲染与 UI。局部蒙版、降噪、真实导出成品预览仍未实现；此预研不计为 108 已完成功能。
