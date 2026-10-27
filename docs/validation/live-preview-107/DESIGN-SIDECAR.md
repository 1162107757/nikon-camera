# Huevia 107 native design sidecar

此 Markdown 是本目录 DESIGN.md 的原生实现与证据扩展，不是根 `.impeccable/design.json` 的替换。记录时间为 2026-10-27（Asia/Shanghai）；只记录已构建状态，没有新增网页标本、栅格资产或设计方向。

## Binding

| 项目 | 本次绑定 |
|---|---|
| App | `cc.huevia` · `0.21.8-beta` · versionCode 107 |
| APK | [huevia-0.21.8-beta-debug.apk](../../../dist/huevia-0.21.8-beta-debug.apk) · 3,991,674 bytes |
| APK SHA-256 | `b05fc8e8bbe786b5f41f1bc1998c4bf6649ee329b3413f8ab800c73d6ab3d347` |
| 来源清单 | [SOURCE-IDENTITY.json](SOURCE-IDENTITY.json)：221 个固定生产输入；本次重新计算全部输入与 APK 的 SHA-256，均匹配。 |
| 图片清单 | [SCREENSHOTS.json](SCREENSHOTS.json)：18 张最终 framebuffer PNG；本次重新计算全部图片 SHA-256，均匹配。 |
| 完成复核 | [FINISH-REVIEW.md](FINISH-REVIEW.md)：限定四项修正的 **ship**，没有材料性发现；不是用户视觉接受或发布证明。 |

八个 changed 输入为 `app/build.gradle`、`PhotoFilterEditor.java`、`PhotoColorDialog.java`、`PhotoBorderPanel.java`、`LocalAlbumPanel.java`、`AppIcon.java`、`LatestPreviewQueue.java`、`PhotoVersionBadge.java`；完整路径和各自哈希以来源清单为准。根 PRODUCT.md 和 DESIGN.md 仅作为既有产品/视觉证据读取，未改写。

## Source map

| 实现事实 | 原生权威来源 |
|---|---|
| 内容自适应徽标面、48dp 最小命中区、数字字号增长与描述 | [PhotoVersionBadge.java](../../../app/src/main/java/cc/huevia/ui/PhotoVersionBadge.java)，13–17 行 |
| 缩略图右下 6dp 定位、条件显示、现有版本选择器 | [LocalAlbumPanel.java](../../../app/src/main/java/cc/huevia/ui/LocalAlbumPanel.java)，454–478 行 |
| 灰色高级入口与基本参数共用结构、首基线与 selected 处理 | [PhotoFilterEditor.java](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java)，214–224、286–303 行 |
| HSL 点/按钮/内缩面、布局方向、暂存 Apply/Cancel、最新普通帧启用应用 | [PhotoColorDialog.java](../../../app/src/main/java/cc/huevia/ui/PhotoColorDialog.java)，17、38–82、103–105 行 |
| Material 暗主题；排版辅助只处理 AlertDialog，不会改写 PhotoColorDialog 的 Button 基线 | [styles.xml](../../../app/src/main/res/values/styles.xml)，15–24 行；[PhotoEditorTypography.java](../../../app/src/main/java/cc/huevia/ui/PhotoEditorTypography.java)，15–39 行 |
| 480px 交互源、1280px 解码、相同 profile/geometry/border 渲染链 | [PhotoFilterEditor.java](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java)，156、324–328、484–506、651–656 行 |
| 一个在途/一个最新待办、交互帧发布条件、epoch 丢弃 | [LatestPreviewQueue.java](../../../app/src/main/java/cc/huevia/ui/LatestPreviewQueue.java)，24–39 行 |
| 边框手势合并、身份边界 | [PhotoFilterEditor.java](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java)，235–242 行；[PhotoBorderPanel.java](../../../app/src/main/java/cc/huevia/ui/PhotoBorderPanel.java)，129–155 行 |
| 裁剪角度直接使 Canvas 失效并重绘 | [PhotoCropDialog.java](../../../app/src/main/java/cc/huevia/ui/PhotoCropDialog.java)，34、48–53 行 |

渲染调度没有 200ms 预览防抖；源码的 200ms 属于草稿保存合并。队列 reset 不强行终止已开始的计算，结果完成后按 epoch 丢弃。调色“应用”还校验打开时的编辑状态没有变化；没有将撤销或账号边界交给预览队列代管。

## Viewport evidence

三组最终记录都来自 `emulator-5588` / ranchu，每组 87 条原生断言通过、failure 为 null；每组包含调节、HSL、曲线、边框外观、相册徽标与版本选择器六个已载入状态。报告和 provenance 同时绑定上述 APK 与各自截图哈希。

| 模式 | PNG 物理尺寸 / 实际 fontScale | 最终运行与绑定 |
|---|---|---|
| portrait phone | 1080×2424 / 1.0 | [报告](b05fc8e8/20261027-000713-phone-f58a58/20261027-000713-phone-f58a58/report.json) · [provenance](b05fc8e8/20261027-000713-phone-f58a58/provenance.json) |
| font1.3 portrait | 1080×2424 / 1.2999999523162842 | [报告](b05fc8e8/20261027-000934-font1.3-39f3cb/20261027-000934-font1.3-39f3cb/report.json) · [provenance](b05fc8e8/20261027-000934-font1.3-39f3cb/provenance.json) |
| landscape | 2424×1080 / 1.0 | [报告](b05fc8e8/20261027-001022-landscape-9fcfd8/20261027-001022-landscape-9fcfd8/report.json) · [provenance](b05fc8e8/20261027-001022-landscape-9fcfd8/provenance.json) |

本次文档核对实际打开了 [phone 调节](b05fc8e8/20261027-000713-phone-f58a58/20261027-000713-phone-f58a58/01-editor-adjustment.png)、[phone 相册徽标](b05fc8e8/20261027-000713-phone-f58a58/20261027-000713-phone-f58a58/05-album-version.png)、[font1.3 HSL](b05fc8e8/20261027-000934-font1.3-39f3cb/20261027-000934-font1.3-39f3cb/02-hsl.png)、[landscape 曲线](b05fc8e8/20261027-001022-landscape-9fcfd8/20261027-001022-landscape-9fcfd8/03-curves.png)。全部 18 张逐图完成复核的范围见 FINISH-REVIEW；本记录不冒称重新打开全部图片。

原生探针比较高级入口与基本参数的屏幕基线（容差 1px）和图标 y 坐标，并验证运行时 HSL top padding ≥8dp。徽标探针验证命中区至少 48×48dp、该双版本夹具可见面高不超过 26dp且宽小于 60dp、点击打开原有选择器；这些界限不是任意版本数/字号的固定面宽保证。实际照片为随包 `preset_template` 生成的自有 QA 文件；分组包含原图、真实渲染效果文件和来源关联。调节图的高曝光是测试终态，不是目标影调。

## Live-render and verification limits

每项手势发出 90 个原生 MOVE。下表为报告记录的 pointer-up 前照片像素签名改变次数，仅说明这组模拟器手势中出现多次真实照片变化，不能换算为 FPS。

| 控件 | phone | font1.3 | landscape |
|---|---:|---:|---:|
| 基本调节 | 38 | 36 | 33 |
| HSL 色相 / 饱和度 / 明亮度 | 24 / 22 / 23 | 20 / 13 / 14 | 17 / 16 / 19 |
| 曲线 | 29 | 18 | 20 |
| 滤镜强度 | 21 | 12 | 23 |
| 边框外观 | 25 | 19 | 17 |
| 裁剪角度（Canvas 路径） | 90 | 90 | 90 |

现有证据另覆盖普通预览恢复原预览源宽度、基本/强度/边框单手势一次撤销、曲线应用一次撤销、HSL 取消不改父状态、原始夹具字节不变及版本选择器。REVIEW-PACKET 记录的 15 项 host 调度断言与每配置 87 项原生断言分别计数；三配置重复不等于 261 个独立场景。本次文档阶段未重放手势或新增构建测试。

这里的 full1280 是普通预览输入，既有原图与导出路径的边界继续保留；本轮不能据此宣称完整导出重测。无实体手机/相机、FPS、吞吐、色彩标定、TalkBack、平板或生产发布认证。原生 Android 组件没有 HTML/CSS 检测适用面。
