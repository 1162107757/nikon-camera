---
name: Huevia 106 local colour extension
description: 已实现曲线、HSL 与批量复制的局部原生记录
colors:
  workspace: "#0E0D0C"
  controls: "#131110"
  text: "#F4F5F7"
  muted: "#BAB1A7"
  primary: "#F2B48C"
  selected: "rgba(242, 180, 140, 0.1490196078)"
typography:
  title: {fontFamily: "sans-serif", fontSize: "16sp", fontWeight: 400}
  label: {fontFamily: "sans-serif", fontSize: "12sp", fontWeight: 400}
  status: {fontFamily: "sans-serif", fontSize: "11sp", fontWeight: 400}
rounded:
  band: "8dp"
spacing:
  pane-horizontal: "12dp"
  action-height: "48dp"
components:
  selected-band: {backgroundColor: "{colors.selected}", textColor: "{colors.primary}", rounded: "{rounded.band}", height: "48dp"}
---
# Design System: Huevia 106 局部调色扩展

## Overview
**Creative North Star: "照片优先的暖黑调色工作区"**
Operate 模式；本文件仅记录 106 的曲线、HSL 和批量复制，继承暖黑编辑器、系统字体与杏色操作。它是已实现的局部扩展；[根设计记录](../../../DESIGN.md)与[产品上下文](../../../PRODUCT.md)继续保有各自范围，未被本文件替换。没有新增生产栅格素材。
**Key Characteristics:** 照片保留完整比例；调色先暂存再应用；批量范围通过原生对话框明确选择。

## Colors
工作区和控制区以两层近黑色区分；正文、次要状态和杏色操作使用上述实际源码 tokens。所选通道增加杏色透明底和文字；曲线图使用白色网格与 RGB 分色曲线，HSL 颜色点同时配文字名称。此处的杏色以当前源码为准，不从根文件的历史值推导。

## Typography
工作区使用 Android 默认系统无衬线字体，标题、控制标签、状态分别引用 frontmatter。主编辑参数行新增入口为 10.5sp。精确输入和批量 AlertDialog 复用 PhotoEditorTypography：标题 14sp medium、正文/输入 13sp、操作 12sp medium；不引入展示字体。

## Layout
安全区内全屏 Dialog，顶部取消/标题/应用；照片 FIT_CENTER，状态位于照片底部。竖屏控件在下方可滚动面板，曲线高 330dp、HSL 高 248dp；横屏面板移至右侧、宽 330dp 并可纵向滚动。曲线图高 132dp；通道横向滚动，RGB 每项宽 64dp，HSL 每项宽 48dp。操作行高引用 action-height；主编辑入口宽度通过 fp(56)随字号缩放。

## Elevation & Depth
工作区以实色分层，没有自定义投影或模糊；精确输入与批量流程使用深色原生 AlertDialog 及其框架遮罩。

## Shapes
所选通道为小圆角底，左右内缩 2dp、上下内缩 6dp；HSL 色点直径 9dp。普通工作区按钮透明并有杏色原生 ripple；曲线为 Canvas 绘制。

## Components
- 曲线：RGB/红/绿/蓝；点击添加、拖动、上一点/下一点、加点/删点和精确输入。2–12 点，0–255，输入严格递增、端点输入固定；端点删点禁用并降透明度。支持通道/全部重置。
- HSL：八个具名颜色范围，色相/饱和度/明亮度各 −100 至 100；滑杆、点击数值精确输入和当前颜色/全部重置共用模型。
- 预览：修改后显示“预览中”，应用禁用且透明度 0.45；最新渲染成功后恢复。失败显示可点击“预览失败，请重试”，继续禁用应用。取消/Back 不提交；有效应用只增加一步撤销。
- 批量：更多菜单进入同组已下载照片多选，先选 1–100 张，再选默认全开的基础调节/曲线/HSL；零项显示校验。只更新草稿，保留目标滤镜/强度、构图与边框；反馈和菜单均可撤销，后续已修改照片受保护，回执限当前进程/账号。无法恢复保存版本参数时整批写入前提示“保存版本参数不可恢复，请改选原图。”。

## Do's and Don'ts
- **Do** 延续本地编辑器的照片比例、系统控件、dp/sp 和暂存/应用边界。
- **Don't** 将此局部记录扩展为全 App、实体手机、TalkBack、相机或 Nikon/NX 色彩认证。

来源：[PhotoColorDialog.java](../../../app/src/main/java/cc/huevia/ui/PhotoColorDialog.java)、[PhotoFilterEditor.java](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) 的新增入口、[AlbumPanel.java](../../../app/src/main/java/cc/huevia/ui/AlbumPanel.java) 的复制流程及 [PhotoEditorTypography.java](../../../app/src/main/java/cc/huevia/ui/PhotoEditorTypography.java)。方向见 [REQUIREMENTS.md](REQUIREMENTS.md)，实现/身份见 [IMPLEMENTATION.md](IMPLEMENTATION.md)、[SOURCE-IDENTITY.json](SOURCE-IDENTITY.json)。

冻结本地 APK：106 / 0.21.7-beta，SHA-256 `9dcc4dc793d8bb4ddfd89d5bd9b62ff95152e652b33b6ef7d04d9a1fee963ad6`。[最终验证](FINAL-VERIFICATION.json)记录 9dcc4dc7 下竖屏/字号1.3/横屏各 67 项、6 张原生截图；共 201 次含配置重复执行、18 张截图。[初审](FINISH-REVIEW.md)通过 15 张初始截图并发现 F1；[修正裁定](FIX-VERDICT.md)仅将 F1 评为 RESOLVED / scoped SHIP，优先于验证 JSON 中保留的待裁定状态。本次文档记录未重新构建、测试或审图，也不扩大上述证据范围。
