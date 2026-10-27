---
name: Huevia 107 native refinement
description: 0.21.8-beta 的相册版本徽标、调节入口与实时预览实现快照
colors:
  album-surface: "#FAFAF8"
  album-text: "#262320"
  editor-text: "#F4F5F7"
  editor-accent: "#F2B48C"
  editor-inactive: "rgba(255, 255, 255, 0.6)"
  colour-workspace: "#0E0D0C"
  colour-controls: "#131110"
  selected-band: "rgba(242, 180, 140, 0.1490196078)"
  badge-face: "rgba(41, 39, 36, 0.8666666667)"
  badge-content: "#FFFFFF"
typography:
  parameter-caption:
    fontSize: "10.5sp"
  colour-band:
    fontSize: "12sp"
  badge-count:
    fontSize: "11sp"
rounded:
  badge: "6dp"
  band-selection: "8dp"
  album-thumbnail: "14dp"
---

# Design System: Huevia 107 scoped native snapshot

## Overview

**Creative North Star: "橙光进入照片"**

继承根 DESIGN.md 已记录的视觉世界：暖白相册承载照片，暖黑编辑工作区让照片占主位，杏色表达当前参数与调色选择。本文件只记录 `0.21.8-beta` / versionCode 107 已构建的四项局部修正；根 PRODUCT.md、DESIGN.md 与全局设计侧车保持原样。

**Key Characteristics:**

- 缩略图内部的小型堆叠图标与数量，不增加文件名下方的版本行。
- 曲线/HSL 是灰色工作区入口；杏色仍指示当前基本参数。
- HSL 色点、选中面和文字在原生按钮内共同排布。
- 拖动时显示真实渲染照片，松手后请求正常分辨率预览。

## Colors

### Primary

`editor-accent` 用于当前基本参数、读数、滑块、曲线/HSL 选择与应用动作。它是这两个编辑类中的局部常量，与 UiPalette 的全局 photoAccent 是不同取值，不能用根文档的全局色值替代。

### Neutral

`album-surface` / `album-text` 来自 UiPalette 的浅色配对；编辑工作区使用 `colour-workspace` 与 `colour-controls` 的暗层次。`editor-inactive` 表示可打开的曲线/HSL 入口，并非禁用状态。照片徽标用 `badge-face` 压住任意照片内容，堆叠图标与数字用 `badge-content`。HSL 选中面为半透明 `selected-band`，其最终外观取决于下面的暗底。

## Typography

原生系统 sans 字体，字号使用 sp。基本参数和高级入口共享 `parameterCaption()`：单行、水平居中、顶部对齐，API 28+ 关闭 fallback line spacing，并将首基线到顶部设为 `fp(14)`；较低 API 以字体 ascent 补 padding。`fp(n)` 为 `dp(n × max(1, fontScale))`，不是固定像素。

HSL 色带保留 `AppThemeDark` 的原生 Button 排版及基线行为，没有另设首/末基线或关闭按钮字体留白。刷新时先换背景，再重新设置 padding；源码 padding 不是色点到选中面边缘的实测距离。最终探针只确认运行时 top padding 至少 8dp，原生大字号截图补充确认可见留白。徽标数字关闭 includeFontPadding，随系统字号增长。

## Layout

| 部件 | 已构建的几何 |
|---|---|
| 版本徽标 | FrameLayout 最小 48×48dp 命中区域；可见面宽度按内容、最小 36dp，高度为 `max(22dp, 数字实际文字像素高度 × 1.25)`，不是固定 48dp 方块。 |
| 徽标内容与位置 | 左右内边距 7dp，堆叠图标 13×13dp，数字左间距 4dp；命中区域靠缩略图右下角，距照片右/下各 6dp，可见面靠该区域右下。 |
| HSL 色带 | 行顶外距 8dp、高 56dp；八个按钮各 48×48dp，顶部圆点 9dp，点与文字间距 3dp。refresh 最终 padding 为左4/上10/右4/下4dp；选中背景内缩为左右2/上下6dp。 |
| 曲线/HSL 与基本参数 | 同为顶部 6dp、26dp 图标槽、图文间距 4dp、`fp(20)` 标题槽；普通列宽 `fp(56)`，较长基本参数可扩至 `fp(72)`。 |

纵屏调色工作区是照片在上、滚动控制区在下：HSL 控制区高 264dp、曲线高 330dp；横屏改为照片左侧与宽 330dp 的右侧滚动控制区。顶栏固定，根容器避让 system bars / display cutout。已记录的视口与证据边界见 [DESIGN-SIDECAR.md](DESIGN-SIDECAR.md)。

## Elevation & Depth

本次组件依靠暗色实面与透明叠色分层，没有新增投影或玻璃材质。徽标是照片上的暗色小面；HSL 选择用内缩的圆角面。原生 ripple 仍承担入口按压反馈。

## Shapes

照片裁切在 `album-thumbnail` 圆角内；徽标使用更小的 `badge` 圆角，HSL 选中面使用 `band-selection` 圆角。扩大点击范围不扩大可见面，也不改变相册文件名的排布。

## Components

**The Launcher Rule.** 曲线/HSL 始终清除 selected 状态，图标与文字保持灰色；可编辑时仍能打开对应工作区。不可恢复或尚未就绪时，入口禁用并降至 0.35 alpha。基本参数单独维护选中态、杏色图标/文字与非零值提示点。

**The Thumbnail Rule.** 仅实际分组且版本数大于一时显示徽标。点击连接现有“选择照片版本”原生列表；选择/导入期间停用。父级提供完整的“数量＋选择照片版本”无障碍描述，装饰图标和数字不另设焦点。

**The Preview Rule.** 基本参数、滤镜强度、边框外观拖动和调色工作区使用同一套已有渲染链，交互输入最长边至多 480px（live480），松手请求最长边至多 1280px 的普通预览输入（full1280），均不放大小图。裁剪和边框可能改变输出尺寸；full1280 不是原图全分辨率，也不是导出尺寸。

`LatestPreviewQueue` 只保留一个正在渲染的任务和一个最新待办快照。手势期间，已被后续交互快照取代的交互帧仍可显示；一旦最新请求是普通预览，旧交互帧不再发布。reset/close 的 epoch 会丢弃旧结果；编辑器另检查照片 generation 和账号。它不保证每个 MOVE 都渲染，也不保证 FPS。

基本参数、强度和边框外观以整个手势记一次撤销，编辑历史上限 32。曲线/HSL 的修改暂存在各自对话框：取消/返回不改父编辑器；最新普通预览完成前“应用”禁用，应用后经原照片/账号/起始状态校验只记一个编辑器撤销步骤。边框外观直接更新父编辑器，不套用调色对话框的取消语义。裁剪角度使用已有 Canvas 重绘路径，不经过 live480 队列。

## Do's and Don'ts

### Do:

- 将小型可见面与原生点击范围分别记录和维护。
- 用共享图标槽与首基线辅助方法排列参数入口。
- 将交互预览、普通预览输入和最终导出分开解释。

### Don't:

- 将灰色曲线/HSL 入口绘制为永久选中的参数。
- 把 HSL padding 当作固定的色点边缘距离，或把全局杏色替代局部编辑器常量。
- 将模拟器变帧证据扩展成真机 FPS、相机吞吐、色彩或完整导出认证。
