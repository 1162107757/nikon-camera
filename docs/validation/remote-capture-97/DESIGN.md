---
name: Huevia 97 — 遥控工具状态
description: 现有原生摄影界面中可用、选中与禁用的局部区分
colors:
  capture-bg: "#121313"
  capture-panel: "#272625"
  capture-text: "#F6F1EB"
  capture-secondary: "#BEB9B2"
  photo-accent: "#F3B493"
typography:
  settings-title:
    fontFamily: "sans-serif-medium"
    fontSize: "17sp"
    fontWeight: 500
  setting-label:
    fontFamily: "sans-serif"
    fontSize: "13sp"
    fontWeight: 400
  setting-note:
    fontFamily: "sans-serif"
    fontSize: "11sp"
    fontWeight: 400
rounded:
  capture-tool: "12dp"
  capture-panel: "24dp"
spacing:
  touch-target: "48dp"
  tool-inset: "13dp"
components:
  capture-tool-available:
    textColor: "{colors.capture-text}"
    rounded: "{rounded.capture-tool}"
    width: "{spacing.touch-target}"
    height: "{spacing.touch-target}"
    padding: "13dp"
  capture-tool-selected:
    textColor: "{colors.photo-accent}"
    rounded: "{rounded.capture-tool}"
    width: "{spacing.touch-target}"
    height: "{spacing.touch-target}"
    padding: "13dp"
  capture-settings-panel:
    backgroundColor: "{colors.capture-panel}"
    textColor: "{colors.capture-text}"
    rounded: "{rounded.capture-panel}"
    padding: "14dp 20dp 20dp"
---

# Design System: Huevia 97 局部实现

## Overview

**Creative North Star: "橙光进入照片"**

沿用根 [DESIGN.md](../../../DESIGN.md)、[PRODUCT.md](../../../PRODUCT.md) 与 [96 局部设计](../remote-capture-96/DESIGN.md) 的原生 Android Java / Views 世界：深色取景工具、暖白操作与杏色选择态。97 是 Operate 局部修正，范围以 [BRIEF.md](BRIEF.md) 为准；保留照片优先的原型、图标族、几何、文案与保存语义。

当前版本为 97 / 0.20.2-beta，绑定 APK SHA-256 `de07855886b72077852faa07a0e45c70363af89a686c5e702a6200ed01f4418f`。214 项生产输入中仅 RemoteCaptureView、AlbumController 与版本信息相对 96 改变。[独立复核](FINISH-REVIEW.md) 为限定 ship：逐张查看 20 张原生截图，无必改项；不是全 App 或实体相机认证。

**Key Characteristics:**

- 可用但关闭的网格／直方图保持完整亮度，选中使用现有杏色。
- 真实禁用状态继续表达相机可用性，取景画面与工具排列保持。
- 保存位置与可选 JPEG 传入仍收纳在齿轮中。

## Colors

### Primary

杏色 `photo-accent` 表示网格开启或直方图显示，沿用现有强调色。

### Neutral

暖白 `capture-text` 表示可操作但未选中的工具；`capture-bg`、`capture-panel` 与 `capture-secondary` 继续承担取景背景、设置面板与说明。精确颜色以 frontmatter 为准。

**The Available Is Visible Rule.** 网格关闭、直方图收起时仍以完整亮度显示暖白图标；选中改为杏色，两态 alpha 均为 1。不得用禁用式降亮度表达关闭。

## Typography

保留系统无衬线与原生 sp 角色，不引入字体或字号。工具保持图标形式，固定操作名称与提示继续为「切换构图网格」和「显示或收起直方图」。

## Layout

工具行仍为齿轮、直方图、构图网格、机身信息，齿轮在直方图左侧。保持既有触点、图标内距、横竖屏布局及完整比例照片区域；保存位置和「拍后传入 App」继续位于齿轮设置中。97 不恢复旧底部保存行。

[原生矩阵](UI-MATRIX.json) 覆盖 phone、实际 font1.3、landscape、dark，各执行同一组 45 项工具栏检查，共 180 次重复／配置检查，零快门指令。每配置 5 张截图，共 20 张；切换前后图像矩形保持。画面及属性来自合成 PTP/IP 夹具，范围仅工具栏冒烟。

## Elevation & Depth

沿用深色面板、原生 ripple 与既有遮暗层，不新增阴影、动效或材质。原生界面不适用 HTML/CSS detector；sidecar 记录原生来源与状态，不另制 Web 效果稿。

## Shapes

保留现有工具圆角、设置面板圆角、代码绘制图标与触点几何，尺寸见 frontmatter。没有新增生产栅格或设计效果图。

## Components

### 网格与直方图

原生 ImageButton 继续使用现有点击回调、可访问名称和提示；同步 selected、颜色与完整 alpha。Android 30+ 通过 stateDescription 分别补充「已开启／未开启」和「已显示／已收起」。这是源码语义与夹具交互证据，不是 TalkBack 实测。实现见 [RemoteCaptureView](../../../app/src/main/java/cc/huevia/ui/RemoteCaptureView.java)。

**The Availability Boundary Rule.** 对焦、快门、最近照片继续由真实能力与结果状态控制 enabled 和既有变暗表现；工具关闭不等于不可用。

### 保留的保存与传输行为

相机存储卡仍是保存位置，可选 JPEG 传入不改变其语义。AF-S 是单次自动对焦，与快门单张释放独立，本轮未改参数映射。

AlbumController 只移除边拍边传中已就绪工作的固定排队等待，保留串行 PTP、原图顺序及忙碌／元数据／失败退避。[性能记录](PERFORMANCE.md) 的同一 8 × 1 MiB 内存夹具各运行一次，4346 ms → 420 ms，前后各 19 项完整性检查；相册回归分别为控制器 889、能力 33、网关 22、项目保存 356、目录 100。数字不代表真实 Wi-Fi 吞吐、相机写卡或实体存储性能；遥控拍后传入走另一条未修改的 downloadPhoto 路径。

## Do's and Don'ts

### Do:

- **Do** 用完整亮度暖白表示可用未选中，用现有杏色表示选中。
- **Do** 保留真实禁用状态、工具几何、完整照片区域和齿轮中的保存选项。
- **Do** 将 97 的结论限定于工具栏状态与已有证据支持的队列调度。

### Don't:

- **Don't** 再以低 alpha 把可用的关闭工具画成禁用。
- **Don't** 把合成夹具、180 次配置检查或限定 ship 扩写为实体相机恢复、全 App 认证或真实无线提速。
- **Don't** 将边拍边传队列收益归到未修改的遥控拍后传入路径。
