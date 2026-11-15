---
name: Huevia 相机连接与同步工具原型
description: 既有 Huevia 暖白、石墨、陶土语言下的独立 HTML 设计审核指南
colors:
  surface: "#f8f7f4"
  card: "#fff"
  container: "#eeece6"
  ink: "#242320"
  secondary: "#635d53"
  accent: "#b3432d"
  accent-soft: "#f4d6c0"
  on-accent: "#85311f"
  outline: "#e4dfd8"
  action: "#242420"
  on-action: "#fff"
  success: "#42735b"
  error: "#ad3b30"
  error-soft: "#f6e7e0"
  dark-surface: "#201f1d"
  dark-card: "#292724"
  dark-container: "#34312d"
  dark-ink: "#f6f1eb"
  dark-secondary: "#cac2b8"
  dark-accent: "#f3b493"
  dark-accent-soft: "#51382d"
  dark-on-accent: "#f3b493"
  dark-outline: "#4c4640"
  dark-action: "#f1ece4"
  dark-on-action: "#29251f"
  dark-success: "#9ac8ae"
  dark-error: "#ffb4a7"
  dark-error-soft: "#422e28"
  remote-surface: "#171816"
  remote-card: "#242622"
  remote-container: "#30312e"
  remote-secondary: "#c5beb4"
  remote-on-action: "#352016"
  remote-outline: "#444640"
  remote-stage: "#090a0a"
typography:
  headline:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif'
    fontSize: "28px"
    fontWeight: 650
    lineHeight: 1.3
    letterSpacing: "-0.8px"
  title:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif'
    fontSize: "16px"
    fontWeight: 600
    letterSpacing: "-0.3px"
  body:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif'
    fontSize: "15px"
  label:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif'
    fontSize: "11px"
  remote-title:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif'
    fontSize: "17px"
    fontWeight: 550
    letterSpacing: "-0.35px"
  remote-parameter:
    fontFamily: '-apple-system,BlinkMacSystemFont,"Segoe UI","Microsoft YaHei",sans-serif'
    fontSize: "18px"
    fontWeight: 500
    letterSpacing: "-0.5px"
rounded:
  input: "11px"
  slot: "13px"
  button: "14px"
  tool-row: "16px"
  tools: "26px"
  sheet: "28px"
  circle: "50%"
spacing:
  small-gap: "4px"
  grid-gap: "8px"
  content-gap: "12px"
  sheet-inset: "16px"
  page-inset: "24px"
components:
  button-primary:
    backgroundColor: "{colors.action}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.button}"
    padding: "12px 16px"
  button-secondary:
    backgroundColor: "{colors.container}"
    textColor: "{colors.ink}"
    rounded: "{rounded.button}"
    padding: "12px 16px"
  input:
    backgroundColor: "{colors.card}"
    textColor: "{colors.ink}"
    rounded: "{rounded.input}"
    padding: "0 13px"
    height: "47px"
  camera-tool-entry:
    textColor: "{colors.ink}"
    rounded: "{rounded.circle}"
    size: "52px"
  tools-panel:
    rounded: "{rounded.tools}"
    padding: "5px 7px 9px"
    width: "252px"
  content-sheet:
    rounded: "{rounded.sheet}"
    padding: "6px 16px 17px"
  slot:
    backgroundColor: "{colors.container}"
    textColor: "{colors.ink}"
    rounded: "{rounded.slot}"
    padding: "11px 12px"
  slot-selected:
    backgroundColor: "{colors.accent-soft}"
    textColor: "{colors.on-accent}"
    rounded: "{rounded.slot}"
    padding: "11px 12px"
  remote-shutter:
    backgroundColor: "{colors.dark-accent}"
    rounded: "{rounded.circle}"
    size: "78px"
  photo-sort-entry:
    textColor: "{colors.ink}"
    size: "44px"
---

# Design System: Huevia 相机连接与同步工具原型

## Overview

**Creative North Star: "清晰连接，轻量工具"**

这是对已实现独立 HTML 原型的扫描记录，适用范围仅为本审核目录。延续既有 Huevia 视觉语言，不建立新的全局品牌规范，也不替代项目根目录的 DESIGN.md。方向依据是 index.html 开头的设计契约、screen.css / screen.js、remote.css / remote-ui.js、board.js 和 README.md。

连接页逐步说明下一件事；同步页保留照片为主体，通过一个浮动入口按需展开工具。用户已选择 B 圆形图标，并追加选择独立全屏遥控取景页。collapsed-options/ 中的三张 ImageGen 设计图及提示词保留为入口选择依据，最终尺寸以代码为准。

用户后续明确批准按此设计接入，并确认紧凑照片工具栏与时间 / 名称两类排序；现已接入 Flutter 源码。接入及验证边界见 implementation/README.md；此记录不表示原生运行、排版或真机验收完成。

**Key Characteristics:**

- 暖白与石墨构成主体，陶土强调状态和选择。
- 系统字体、清楚的步骤与克制的信息密度。
- 玻璃集中在浮动控件；下载和槽位使用内容面板，遥控使用摄影暗色全屏页。

## Colors

暖色中性色维持照片背景的安静感；浅、深主题分别使用前置元数据中的实际 CSS 色值。

### Primary

- **陶土强调色**（accent）：当前选择、焦点、下载进度和连接操作提示。
- **浅陶土底 / 陶土文字**（accent-soft / on-accent）：队列标记和已选槽位。

### Secondary

- **状态绿**（success）：连接与拍摄指令反馈。
- **错误红及浅错误底**（error / error-soft）：权限拒绝、失败与恢复提示；同时给出文字说明。

### Neutral

- **暖白 / 暖深灰表面**（surface / dark-surface）：全屏背景。
- **卡片与容器层**（card / container）：选项、输入框和局部选中背景。
- **石墨 / 暖白文字**（ink / dark-ink）：标题、正文和图标；secondary 用于说明。
- **动作色及反色文字**（action / on-action）：主要按钮；outline 承担边界与分隔。
- **摄影暗色表面**（remote-*）：全屏遥控始终采用独立摄影暗色，不跟随审核台浅深主题切换；文字与强调色复用深色暖白和浅陶土，快门采用浅陶土。

## Typography

全屏使用系统无衬线栈，不引入独立展示字体。前置元数据记录连接标题、面板标题、基础正文、标签和遥控页标题与参数；连接说明另用较小正文（13px，行高 1.75），状态说明行高为 1.9。按钮为中等偏实字重（550）；数字参数、数量与槽位采用等宽数字。

## Layout

审核台并列展示 Android 与 iOS 两个内容区（375 × 812px）。单屏最大宽度为 520px，高度随视口变化，最小高度为 600px；正文可滚动，连接主操作固定在底部区域。连接页左右留白为 24px。

同步工具收起时位于右侧（18px）和底部（108px），在导航上方。展开工具列表宽 252px；内容面板左右各留 12px、底部留 108px，最大高度为屏高减 196px，必要时内部滚动。空下载队列在 375 × 812px 截图中约高 172px，由内容自然撑开，未固定高度。

底部导航容器 Android 高 91px，iOS 高 97px；iOS 增加底部安全区域。C1–C9 使用三列三行网格，间距为 8px。视口宽度不超过 350px 时，连接内容留白减至 20px，标题缩至 26px，内容面板左右留白减至 10px。

遥控是独立全屏页面，不显示同步导航或浮动入口。上方依次为返回与标题、相机 / 连接方式 / 电池、构图工具；中间弹性取景区；下方固定参数、稳定反馈与最近拍摄 / 快门 / 对焦操作。遥控子面板底部留 30px；高度不超过 720px 时收紧参数和操作区，取景最小高度由 210px 减至 180px。

## Elevation & Depth

页面主要通过实色表面与细分隔线组织层级。浮动入口、导航和工具面板使用同一玻璃处理：浅色白色表面透明度约 83%，深色暖灰表面约 88%；模糊为 28px，饱和度为 155%，配合内侧边缘高光和柔和外阴影。实际玻璃、阴影值与系统回退记录在 design-tokens.json。

不支持模糊或用户要求减少透明度时改用实色卡片；高对比度偏好下使用实色表面和清楚的文字色边框。

遥控主画面以实色摄影暗面承托图片；直方图和演示标签使用局部半透明暗底，设置等子面板延续玻璃处理，不遮成同步页的小工具面板。

## Shapes

按钮、输入、槽位与面板遵循前置元数据中的柔和圆角。圆形工具入口为用户已选形态，图标为线性滑杆（22px）；不再使用早期文字胶囊样式。全屏遥控快门为独立圆形控件（78px；短屏为 68px），点按对焦使用浅陶土细框（43 × 36px）。图标默认线宽为 1.7，线端与转角圆润。

## Components

### Buttons and inputs

主要按钮使用动作色，次按钮使用容器色；两者最小高度为 50px。输入框高 47px，使用卡片底和细边框。键盘焦点显示强调色描边（3px，外偏移 3px）；按下按钮缩至 0.97。禁用态取消缩放并降低不透明度。

### Connection flow

Wi-Fi / USB 采用分段选择。流程覆盖准备、设备检测、授权、机身确认、连接中、拒绝、超时、失败、重试与取消。iOS Wi-Fi 指引明确要求手动连接相机网络，并解释本地网络权限和拒绝后的恢复；USB 单独说明设备访问权限。

连接成功返回调用来源，同步和预设均可进入；不会自动装载照片。返回同步后，只有用户点击浏览相机照片才显示预置网格。所有连接与照片状态均为演示。

### Camera tools

收起入口保留 aria-label「相机工具」。空队列不显示 0；活动、暂停或待恢复队列才显示小数量标记。展开提供下载、遥控、预设槽位三个入口；下载与槽位替换面板内容，遥控进入独立全屏页。面板支持点击外部、关闭或 Escape 收起。

### Downloads and slots

下载保留空、活动、暂停和失败状态；失败保留队列并提供重试。

槽位完整显示 C1–C9，默认「未读取」；选择后允许预览读写下一步，写入前再次核对覆盖目标。

### Photo toolbar and sorting

紧凑工具栏左侧为照片来源与已读取数量，右侧依次为 RAW、排序、选择；未读完的产品数量带「+」。排序入口为独立图标按钮（最小 44px，图标 17px），不改变 RAW 开关或选择状态。

用户要求保留「拍摄时间 · 新到旧」「拍摄时间 · 旧到新」「名称 · 升序」「名称 · 降序」四项；产品源码另提供恢复相机原始顺序。排序仅使用已返回元数据，时间读取 capturedAt，缺失或无效时间在两个方向均置末；名称使用数字自然排序，同值保持相机顺序。新页加入后按当前规则插入，不新增相机目录扫描；查看器跟随排序，同时保持当前照片 handle。

HTML 展示入口和四项菜单，截图为 review/sync-toolbar-sort-375.png 与 review/sync-toolbar-sort-menu.png；5 项浏览器检查不构成原生产品排版证据。

### Fullscreen remote view

取景区显示本地 alpine-lake.jpg，并明确标记「取景演示」，不代表实时相机画面。提供三分构图网格、从这张静态照片计算的亮度直方图、点按对焦标记和暂停 / 恢复；快门、光圈、ISO、曝光补偿四项参数只读，详细信息面板列出八项机身信息。

设置面板包含「实时取景」和「拍摄后传入 App」两个显式开关；最近拍摄默认为未核对新照片的空状态。快门指令后禁用约 850ms，再给出一次反馈，参数与状态保持静止。取景状态分为就绪、暂停、等待画面和不支持取景；断开单独呈现。对焦按钮仅在取景就绪、相机已连接、没有发送中的指令且无待核对拍摄结果时可用。

拍摄结果待核对与取景状态独立保存，暂停 / 恢复取景和退出 / 重新进入遥控均不会解除；只有明确点击「已核对相机，恢复拍摄」才解除。待核对或断开时禁用快门，不自动重拍。

左上角返回同步会结束本次取景，保留相机连接和待核对结果。所有画面、参数、对焦、拍摄与传入开关均为本地界面演示。

### Navigation

底部四项导航使用图标与短标签，当前项通过容器底、较实字重和正文色区分。工具入口与面板只出现在同步页；切到预设、相册或设置后消失，回到同步时保持收起。

## Do's and Don'ts

### Do:

- **Do** 保留既有 Huevia 浅深主题和本原型的单圆形入口。
- **Do** 让步骤、失败原因和恢复操作明确可见。
- **Do** 保留减少透明度、高对比度、减少运动与键盘焦点处理。
- **Do** 让全屏遥控的演示标记、只读参数与待核对结果持续明确。

### Don't:

- **Don't** 将三个候选设计图实现成三个产品入口或三个原型。
- **Don't** 持续闪烁就绪提示、重复播报状态，或在空队列显示 0。
- **Don't** 把连接成功等同于加载照片，或把演示槽位和设备状态当作真机结果。
- **Don't** 将本地原型指南扩展为全局品牌变更或产品接入许可。
- **Don't** 将遥控退回小面板、把静态演示图称为真实取景，或自动重发未核对的快门。
