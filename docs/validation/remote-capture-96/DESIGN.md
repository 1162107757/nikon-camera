---
name: Huevia 96 — 遥控设置与滤镜入口
description: 已批准橙光世界中的原生 Android 局部实现记录
colors:
  capture-bg: "#121313"
  capture-panel: "#272625"
  capture-text: "#F6F1EB"
  capture-secondary: "#BEB9B2"
  photo-accent: "#F3B493"
  editor-text: "#F4F5F7"
  editor-dock: "#131110"
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
  editor-grid-face: "10dp"
  capture-panel: "24dp"
spacing:
  touch-target: "48dp"
  editor-grid-glyph: "19dp"
  editor-grid-face: "36dp"
  editor-grid-inset: "6dp"
  panel-horizontal: "20dp"
  panel-top: "14dp"
components:
  capture-tool-action:
    textColor: "{colors.capture-text}"
    rounded: "{rounded.capture-tool}"
    width: "{spacing.touch-target}"
    height: "{spacing.touch-target}"
  capture-settings-panel:
    backgroundColor: "{colors.capture-panel}"
    textColor: "{colors.capture-text}"
    rounded: "{rounded.capture-panel}"
    padding: "14dp 20dp 20dp"
  capture-transfer-switch:
    textColor: "{colors.capture-text}"
    typography: "{typography.setting-label}"
    height: "{spacing.touch-target}"
  editor-grid-target:
    textColor: "{colors.editor-text}"
    width: "{spacing.touch-target}"
---

# Design System: Huevia 96 局部实现

## Overview

**Creative North Star: "橙光进入照片"**

延续根 [DESIGN.md](../../../DESIGN.md) 已批准的原生 Android Java / Views 世界：炭黑摄影工具、暖白文字与杏色选择态。此处只记录 96 的保存设置收纳和滤镜入口对齐；全局规则仍以根文档为准，Operate 任务范围见 [BRIEF.md](BRIEF.md)。

当前版本为 96 / 0.20.1-beta，绑定 APK SHA-256 `2bcb395db84af40a0f6732078fa7ab5707fc93dbd43c2a1794d3420f9a7f0c8e`。[独立审核](FINISH-REVIEW.md) 的 ship 限本轮三个请求；[矩阵](UI-MATRIX.json) 为六次原生运行、622 次配置检查和 79 张截图，审核逐张检查其中 14 张 required。相机证据来自内存 PTP/IP 夹具和合成样片；editor-grid 为真实 createDock 装入原生 Dialog 的组件证据，未绑定用户照片。没有实体设备、发布或新增生产栅格资产，HTML/CSS detector 不适用于此原生实现。

**Key Characteristics:**

- 保存设置归入取景工具行的小齿轮，让竖屏取景获得原底部保存行的高度。
- 四方块保留原图标、颜色、底形和触点，仅修正整体居中。

## Colors

### Primary

杏色 `photo-accent` 延续遥控工具选中态和开关开启态；本轮没有引入新强调色。

### Neutral

`capture-bg` 承托取景与控制区，`capture-panel` 区分设置面板；`capture-text` 与 `capture-secondary` 分别承担操作和说明。滤镜入口继续使用 `editor-text`，工具坞沿用 `editor-dock`。精确值仅由上方 frontmatter 定义；sidecar 色阶只服务文档面板展示。

## Typography

遥控设置采用系统无衬线，标题使用中等字重，条目与解释使用常规字重；角色及原生 sp 值见 frontmatter。没有新字体或新字号体系。滤镜四方块为无文字入口，保留「查看全部滤镜」的可访问名称和提示。

## Layout

**The Settings Consolidation Rule.** 工具行顺序为齿轮、直方图、构图网格、机身信息；齿轮在直方图左侧。底部保存说明／开关行和右上重复三点均已移除，释放的竖屏高度交还取景区域。此用户追加指令覆盖旧原型的底部保存行。

设置顶部先显示「照片保存位置：相机存储卡」只读行，再显示「拍后传入 App」及说明「照片仍保存在相机，JPEG 另传入 App」。其后保留实时取景、构图网格、机身参数和断开连接。竖屏从底部展开，最大高度为界面高度的 78% 且不超过 600dp；横屏面板靠右、宽 390dp、占满可用高度，内容可滚动。工具触点与设置开关行使用 frontmatter 的原生触点尺寸。

## Elevation & Depth

本轮没有新增阴影或动效。遥控设置依靠深灰面板、圆角和 Dialog 背后的 0.55 遮暗形成层次；滤镜工具坞保持零 elevation。sidecar 的 HTML 仅为原生设计说明预览，不是生产 Web 实现或原生截图。

## Shapes

遥控工具延续圆角触点，设置延续圆角面板。滤镜入口的底形为细白描边与低透明白填充，视觉面高度取 `editor-grid-face`，左右各内缩 `editor-grid-inset`；圆角取 `editor-grid-face` 圆角 token。视觉底形位于较大的触点内，二者不可混为一项尺寸。

## Components

### 遥控工具与保存设置

紧凑、可辨认的原生 ImageButton 与 Switch。齿轮的可访问名称为「拍摄设置」；直方图和网格选中时使用杏色。相机存储卡是只读事实，JPEG 传入为可选开关；开关打开、关闭与重开保持选择的路径已在当前原生批次验证。实现见 [RemoteCaptureView](../../../app/src/main/java/cc/huevia/ui/RemoteCaptureView.java)。

### 查看全部滤镜

**The Whole Target Center Rule.** 同一 AppIcon.GRID 以 LayerDrawable 的 Gravity.CENTER 放在整个触点中心，清除空文字按钮的 compound drawable 与其定位内边距。字形尺寸取 `editor-grid-glyph`，触点宽度取 `touch-target`；基础行高使用该触点值，放大字号时随原生 fp 行高扩展。当前六次运行的 LTR／RTL 白色字形边界中心偏移均为 `[0,0]`；这证明组件对齐，不代表完整照片编辑页面复测。实现见 [PhotoFilterEditor.createDock](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java)。

本轮第三项为非视觉的 Nikon MTP 身份兼容：制造商边界为 NIKON，接受扩展 ID 10／6／0xffffffff，实际操作仍受相机广告能力约束；用户原始 DeviceInfo 未知，不能据此宣称真机恢复。

## Do's and Don'ts

### Do:

- **Do** 保持齿轮在直方图左侧，并将保存位置与可选 JPEG 传入放在设置顶部。
- **Do** 保留四方块的原 AppIcon、颜色、底形和原生触点，按整个触点居中。

### Don't:

- **Don't** 把 95 或追加要求前原型的底部保存行写成当前布局。
- **Don't** 将夹具连接成功或组件截图表述为用户相机恢复、完整编辑流程或全 App 认证。
