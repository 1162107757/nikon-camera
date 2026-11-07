---
name: Huevia four-home review prototype
description: Local visual record of a proposed photographic home interface, pending user approval.
colors:
  charcoal: "#242420"
  paper: "#f8f7f4"
  ink: "#242320"
  muted: "#706b63"
  secondary-ink: "#635d53"
  control-ground: "#eeece6"
  source-ground: "#eeece7"
  white: "#ffffff"
typography:
  ui:
    fontFamily: '"Segoe UI Variable", "PingFang SC", "Microsoft YaHei UI", sans-serif'
  title:
    fontSize: "26px"
    fontWeight: 600
    lineHeight: 1.15
    letterSpacing: "-0.035em"
  body:
    fontSize: "12px"
  label:
    fontSize: "11px"
rounded:
  photo: "17px"
  pill: "24px"
spacing:
  screen-gutter: "19px"
  photo-gap: "10px"
components:
  action-primary:
    backgroundColor: "{colors.charcoal}"
    textColor: "{colors.white}"
    rounded: "{rounded.pill}"
    padding: "0 19px"
---

# Design System: Huevia 四个主页提案

## Overview

**Creative North Star: "照片先行的轻玻璃图库"**

本地代码原型的视觉记录，仍待用户批准；只适用于预设、同步、相册、设置四个主页。用户指定参考的暖白摄影界面是视觉依据，网页宣传横幅的紫色不是界面配色。**Key Characteristics:** 摄影占主位、紧凑界面字、白与炭黑浮动控件、柔和桃色评审背景。

## Colors

**Primary:** 炭黑承载选中导航、分类和主要操作，配白字。**Neutral:** 暖纸色作页面底，墨色作正文，灰褐色作次级信息，浅暖灰区分来源与分类控件。桃／粉色渐变只出现在总览背景，照片提供主要色彩。

**The Photo First Rule.** 大面积色彩来自摄影；浮动操作保持中性色。修复后的来源／分类、传输数据与设置页脚对比度记录在 `review/contrast-fix.json`；这是一项局部修复证据。

## Typography

全部界面采用前述系统字体栈。主页标题最显著，常规操作与列表多为 12px，次级标签多为 10–11px，少量照片徽标为 9px；标题在窄屏下降为 24px。字重克制，细线 SVG 图标陪衬文字。系统字用于本原型的紧凑界面，不建立额外展示字体规范。

## Layout

手机基准为 390×844；内容横向留白 19px，330px 及以下降为 15px。相册为两列错列摄影，间隔 10px；预设两列，来源相机网格三列。内容独立滚动，浮动导航固定在下方，传输卡位于其上，专门增加内容底部留白。总览四个画框等比缩放；中屏横向滚动，小屏呈单屏应用。

## Elevation & Depth

白色半透明层、背景模糊和软影共同表达浮动操作。导航使用 24px 模糊，选择条 26px，照片徽标 14px；实体照片保持清晰。复用的低浮层阴影为 `0 9px 28px -16px #453b3060`。常规切页为 0.28s，按下缩至 0.97；尊重减少动态效果偏好，静态截图单独关闭入场效果。

## Shapes

照片以柔圆矩形裁切，常见圆角 16–17px；来源和主要操作采用胶囊形，图标按钮为圆形。导航外轮廓 34px、内选中轮廓 29px；来源选中项上下内距均为 3px，导航均为 4px。选中底色包住图标和名称。

## Components

**The Whole Selection Rule.** 导航图标与名称一起选中，保持均匀内距与同心圆角。来源条以白底选中，分类条以炭黑选中；照片角标使用紧凑玻璃层。选择时出现浮动操作条并禁用来源；传输卡保留文件信息及独立进度轨。设置使用浅色分组和细分隔线。按钮有按下反馈，键盘焦点采用暖棕色 2px 外框。下游操作仅显示沿用现有界面的说明。

## Do's and Don'ts

- **Do** 保持摄影密度、紧凑层级，以及浮层与内容／导航之间的可见间距。
- **Do** 保留完整的图标加名称选中形状，以及来源和分类各自的状态。
- **Don't** 将本提案当作原生应用规范、用户批准或图片处理设计授权。
- **Don't** 将参考网页宣传横幅的紫色移作主页底色。

未固化为系统规则：演示照片、虚拟状态、评审画框与一次性素材；它们服务于这次提案，不是生产设计承诺。本次只写本地文档，不生成全局或 sidecar 规范。
