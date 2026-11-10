---
name: Huevia iPhone Beta
description: 原生 iPhone 预设与相机连接界面的独立设计记录
colors:
  accent-light: "#B3432D"
  on-accent-light: "#FFFFFF"
  accent-dark: "#F3B493"
  on-accent-dark: "#352016"
typography:
  title:
    fontFamily: "iOS system (SF with system language fallback)"
    fontWeight: 700
  headline:
    fontFamily: "iOS system (SF with system language fallback)"
  body:
    fontFamily: "iOS system (SF with system language fallback)"
  footnote:
    fontFamily: "iOS system (SF with system language fallback)"
  caption:
    fontFamily: "iOS system (SF with system language fallback)"
rounded:
  photo-thumbnail: "12pt"
spacing:
  text-stack: "8pt"
  content-stack: "20pt"
components:
  button-prominent-light:
    backgroundColor: "{colors.accent-light}"
    textColor: "{colors.on-accent-light}"
  button-prominent-dark:
    backgroundColor: "{colors.accent-dark}"
    textColor: "{colors.on-accent-dark}"
  photo-thumbnail:
    rounded: "{rounded.photo-thumbnail}"
---

# Design System: Huevia iPhone Beta

## Overview

**Creative North Star: "原生摄影工具"**

Huevia 的摄影参考和暖色强调，落在 iOS 自身的导航、分组列表、文字层级与文件交互中。照片负责表达摄影气氛；操作、连接状态和说明保持清楚、克制。此记录只约束 `ios/` 的 iPhone / iOS 16+ 首个体验版，不替换根目录的 Android 设计系统。

**Key Characteristics:**

- 原生三标签导航、NavigationStack、系统分组表单与确认界面。
- 语义浅深色表面、SF 系统文字及 Dynamic Type。
- 沿用十份已选用的 Pexels 摄影素材，并保留摄影参考声明。
- 文件下载、分享与相机操作呈现真实状态；实体相机验证范围另见 `README.md`。

依据 `Huevia/HueviaApp.swift`、两个颜色资产及 `../docs/validation/ios-selfsign-20261108/final/` 中 0.1.0 build 4 的五张原生模拟器截图记录。浅色与深色大字目录的照片均限制在栏宽内、列顶对齐，首行名称完整显示；详情照片、相机字段和设置分组也已复核。**未纳入规范：** 连接后的槽位与确认状态目前仅有源码依据，未宣称实体 iPhone / Z6II 或用户自签安装验证。

## Colors

### Primary

暖陶土与浅杏色分别来自 `AccentColor` 的浅、深色变体，用于当前标签、系统图标、链接与主操作。主按钮内容使用同模式的 `OnAccent`，下载中的进度指示也使用该前景色。

### Neutral

目录采用 `systemGroupedBackground`；相机、设置与本地预设采用系统分组列表表面。正文使用 `.primary`，格式、分类、说明和脚注使用 `.secondary`。这些角色随系统外观适配，不将截图取色固定为新的背景或灰阶令牌。

**The Paired Accent Rule.** 具有强调色实底的操作始终配对同模式的 OnAccent；文字、图标和进度不能各自选择固定浅色前景。

## Typography

使用 SwiftUI 系统字体与系统语言回退。尺寸由语义文字样式和 Dynamic Type 决定，不把某张截图的点数冻结为全局字号。

- **导航标题：** 根页面使用系统导航大标题，详情与导入页使用 inline 导航标题。
- **Title：** 详情预设名采用 `.title2.bold()`。
- **Headline：** 目录、本地预设名与槽位标识采用 `.headline`；目录名称当前最多两行。
- **Body：** 默认正文用于说明、按钮与表单内容。
- **Footnote / Caption：** 兼容性和功能说明采用 `.footnote`，格式、分类与摄影参考声明采用 `.caption`；辅助文字配 `.secondary`。

**The Native Text Rule.** 扩展屏幕继续使用语义样式和可滚动容器，不通过固定字号或缩字消解 Dynamic Type 的空间需求。

## Layout

底部固定为预设、相机、设置三个 Tab，每个目的地持有原生 NavigationStack。目录上方使用原生搜索和两项 segmented Picker；右上角加号进入系统文件选择。

目录使用顶端对齐的自适应 LazyVGrid（最小列宽 150pt，列距 14pt，行距 20pt），缩略图高度为 192pt。GeometryReader 将填充照片明确限制在分配的栏宽和图高内，再裁切圆角。照片、名称、格式依次纵向排列，名称与元数据留 8pt 间隔；长名称按两行换行，不扩张栏宽。

详情为可滚动的纵向内容，主要内容间距 20pt，名称说明组间距 8pt；主图按原比例适配。外侧留白由 SwiftUI 默认 padding 与系统安全区域管理。相机与设置以 Section 分组，长说明自然换行。

## Elevation & Depth

应用没有自定义阴影系统。层级来自分组表面、系统分隔线、导航栏与标签栏自身的材质，以及 sheet / alert / confirmationDialog 的原生呈现。保持系统提供的选中与焦点反馈，不把截图中的系统材质重写成固定透明度效果。

## Shapes

目录照片使用轻圆角矩形；详情照片当前使用较大的圆角（16pt）。照片保持原始色彩，不以强调色蒙版着色。按钮、搜索、来源选择器、列表卡组和弹层沿用各自系统形状，不提取统一的自定义胶囊或卡片半径。

## Components

### Navigation / Source Picker

标签由 SF Symbols 与文字共同命名，当前目的地使用全局 tint。来源选择为系统 segmented Picker；在线与本地共享搜索入口，本地入口使用原生文件导入与 ShareLink。

### Preset / Photo

照片上方不叠加预设操作。目录缩略图为裁切填充，详情主图为完整比例适配；名称、分类和格式置于图片外。十份摄影参考随包保留原始 JPEG 与来源清单，构建时生成原生 imageset。详情明确展示“摄影参考样片，不代表该预设的相机实拍效果。”

### Buttons / Feedback

下载和详情中的导入使用 `.borderedProminent`，分享使用 `.bordered`；列表操作使用原生行。进行中以 ProgressView 和动作文字表达，相关重复动作禁用。错误使用原生 alert；目录首次加载、失败重试及无匹配结果有对应真实状态。

### Camera Fields / Slot Confirmation

相机 IP 与端口使用 LabeledContent 保留可见标签，输入值右对齐；键盘类型和无自动纠正设置与字段用途一致。槽位行以名称、占用状态和 checkmark 表达选择，源码设置至少 44pt 行高。导入 sheet 先选择槽位，再显示确认；已有内容时显示覆盖说明，并使用 destructive 确认角色。读取、导入核对期间呈现忙碌状态，不能把首次连接画成成功写入。

## Do's and Don'ts

### Do:

- **Do** 保留系统浅深色、Dynamic Type、原生标签及导航行为。
- **Do** 使用配对强调色前景，并保留字段标签、状态文字和可见选择标记。
- **Do** 保留参考照片来源与实拍效果声明；下载、分享、槽位读取和确认均对应真实状态。
- **Do** 将此版本明确为首个 iPhone 体验版；相机导入与自签安装仍需用户在实体设备复测。

### Don't:

- **Don't** 将目录横向溢出或标题裁切当作全出血视觉语言。
- **Don't** 将 Android 的背景、字号、触控尺寸或编辑器材料直接推广为本原生界面的令牌。
- **Don't** 将参考摄影说成预设实拍效果，或据此宣称原生照片调色引擎。
- **Don't** 把有限的 Z6II / NCP 兼容导入界面表述为完整 Android 功能、其他机型或 NP3 相机写入已验证。
