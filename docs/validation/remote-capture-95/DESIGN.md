---
name: Huevia 遥控拍摄 · 95
description: 已批准原型在 Android Views 中的局部落地，完整取景与单一桃色快门
colors:
  workspace: "#121313"
  viewfinder: "#090A0A"
  panel: "#272625"
  instrument: "#191A18"
  text: "#F6F1EB"
  secondary-text: "#BEB9B2"
  accent: "#F3B493"
  accent-ink: "#352016"
  divider: "#343535"
  tool-backing: "rgba(11, 12, 12, 0.8196078431)"
  curtain: "rgba(18, 19, 19, 0.8509803922)"
  ripple: "rgba(243, 180, 147, 0.1490196078)"
  warning: "#FFB4A7"
  focus-confirmed: "#9AC8AE"
  switch-off-thumb: "#CBC7BF"
  switch-on-track: "#A36B4C"
  switch-off-track: "#66645F"
  histogram-luminance: "#C7C4BB"
  histogram-red: "#FF707C"
  histogram-green: "#95CCA8"
  histogram-blue: "#79A9FF"
typography:
  title:
    fontFamily: "sans-serif-medium"
    fontSize: "17sp"
    fontWeight: 500
  title-landscape:
    fontFamily: "sans-serif-medium"
    fontSize: "15sp"
    fontWeight: 500
  reading:
    fontFamily: "sans-serif-medium"
    fontSize: "20sp"
    fontWeight: 500
    fontFeature: "tnum"
  reading-landscape:
    fontFamily: "sans-serif-medium"
    fontSize: "18sp"
    fontWeight: 500
    fontFeature: "tnum"
  control:
    fontFamily: "sans-serif"
    fontSize: "13sp"
    fontWeight: 400
  support:
    fontFamily: "sans-serif"
    fontSize: "11sp"
    fontWeight: 400
  compact-identity:
    fontFamily: "sans-serif"
    fontSize: "10sp"
    fontWeight: 400
  caption:
    fontFamily: "sans-serif"
    fontSize: "9sp"
    fontWeight: 400
rounded:
  control: "12dp"
  tools: "10dp"
  instrument: "9dp"
  sheet: "24dp"
  circular: "50%"
spacing:
  small: "4dp"
  gap: "8dp"
  inset: "12dp"
  panel: "20dp"
  touch-target: "48dp"
components:
  icon-action:
    textColor: "{colors.text}"
    rounded: "{rounded.control}"
    padding: "13dp"
    width: "48dp"
    height: "48dp"
  icon-action-selected:
    textColor: "{colors.accent}"
    rounded: "{rounded.control}"
    padding: "13dp"
    width: "48dp"
    height: "48dp"
  primary-action:
    backgroundColor: "{colors.accent}"
    textColor: "{colors.accent-ink}"
    typography: "{typography.control}"
    rounded: "{rounded.control}"
    height: "48dp"
  shutter:
    backgroundColor: "{colors.accent}"
    rounded: "{rounded.circular}"
    width: "84dp"
    height: "84dp"
  shutter-landscape:
    backgroundColor: "{colors.accent}"
    rounded: "{rounded.circular}"
    width: "74dp"
    height: "74dp"
  reading:
    textColor: "{colors.text}"
    typography: "{typography.reading}"
  histogram:
    backgroundColor: "{colors.instrument}"
    textColor: "{colors.text}"
    rounded: "{rounded.instrument}"
    width: "190dp"
    height: "64dp"
  sheet:
    backgroundColor: "{colors.panel}"
    textColor: "{colors.text}"
    rounded: "{rounded.sheet}"
    padding: "14dp 20dp 20dp"
---

# Design System: Huevia 遥控拍摄 · 95

## Overview

**Creative North Star: "橙光进入照片"**

这是 Huevia 既有原生世界在遥控拍摄表面的局部记录：近黑工作区承托完整画面，小机型和小图标退到画面周围，桃色集中标记主快门与选中状态。它继承用户批准的[原型实施约定](../../design-review/remote-capture-20261024/IMPLEMENTATION-CONTRACT.md)，不另设视觉方向。全局品牌与其他表面仍见根 [DESIGN.md](../../../DESIGN.md) 和 [PRODUCT.md](../../../PRODUCT.md)。

规范以 [RemoteCaptureView](../../../app/src/main/java/cc/huevia/ui/RemoteCaptureView.java)、[Activity](../../../app/src/main/java/cc/huevia/RemoteCaptureActivity.java) 和 [Controller](../../../app/src/main/java/cc/huevia/remote/RemoteCaptureController.java) 的实际代码为准；原型 HTML／CSS／JS 是批准的设计来源，生产界面没有 WebView。当前是原生 Material 无 ActionBar Activity、Android Views 与 Canvas；不据平台指南补写代码尚未提供的主题、动效或组件。

本文对应 95／0.20.0-beta，APK SHA-256 为 `cb4d685bfdc9ddae3663b84e0836d45a5b61085ce55967f8f1fa4f81c39e3012`，身份见 [FINAL-IDENTITY](FINAL-IDENTITY.json) 与 [CANDIDATE-IDENTITY](CANDIDATE-IDENTITY.json)。[UI-MATRIX](UI-MATRIX.json) 记录自有 Pixel_9 模拟器和合成 PTP/IP 夹具的 372 次配置检查、49 张原生截图；不是独立场景数或真实相机证据。[完整初审](FINISH-REVIEW.md)的 `disposition: fix` 保留；[后续 verdict](FIX-VERDICT.md) 仅判 M1–M4 resolved、remaining clear、`disposition: ship`，不构成全表面重新认证或用户最终视觉接受。本文件只碳化已落地设计，没有新增运行、设备或视觉审核结论。

**Key Characteristics:**

- 完整比例取景、近黑仪表材料与紧凑的机型／工具。
- 四个只读读数围绕单一桃色双环快门组织。
- 可移动、收起和放大的同帧直方图；旧帧明确暂停。
- 原生 sp 字号、安全区、系统返回与至少 48dp 操作目标。
- 竖屏上下布局，横屏左图与可滚动右侧控制区。
- 拒绝、中断、离线和未知拍摄结果分别给出真实状态。

## Colors

配色延续照片工具的暖桃色与近黑中性层次。上方 frontmatter 是精确原语；ARGB 透明色已转换为对应的 CSS rgba，供文档工具读取。该工作区在系统浅／深外观下都使用固定深色材料。

### Primary

- **桃色仪表强调**（accent）：主快门、选中直方图／网格、选中亮度／RGB 按钮和开启的 Switch thumb；小图标仍保持原尺寸。
- **深陶土墨**（accent-ink）：桃色按钮文字、快门工作标记，使浅暖强调面保留清楚的内容。

### Neutral

- **近黑工作区与取景底**（workspace / viewfinder）：前者承载标题和控制区，后者承托比例适配留下的空间与取景工具行。
- **暖炭弹层与深色仪表**（panel / instrument）：区分原生 sheet 与直方图，不引入装饰纹理。
- **暖白文字、暖灰辅助文字与细分隔**（text / secondary-text / divider）：对应主读数、机型／标签／说明和控制区边界。
- **工具衬底与中断遮罩**（tool-backing / curtain）：前者完整包住横屏三工具组；后者覆盖暂不可用的画面并保留恢复动作。
- **桃色涟漪与开关中性色**（ripple / switch-off-thumb / switch-on-track / switch-off-track）：沿用 Android RippleDrawable 与原生 Switch 的真实状态材料。

### Semantic instruments

- **结果警示与已确认焦点**（warning / focus-confirmed）：分别用于未知结果／断开操作与相机报告已合焦的对焦框。
- **亮度与 RGB 曲线**（histogram-luminance / histogram-red / histogram-green / histogram-blue）：只编码预览像素统计通道；不是第二套操作色。

**The State Color Rule.** 选中工具必须实际绘成桃色，未选中工具保留中性文字色；关闭的 Switch thumb 使用中性颜色。颜色不能替代状态文字和禁用语义。

## Typography

**Display Font:** 本表面没有展示字体。

**Body Font:** Android `sans-serif`；标题和主读数为 `sans-serif-medium`。系统决定实际字形和语言 fallback，不内嵌品牌字体。

**Character:** 字体承担清楚、紧凑的相机仪表层次。原生 TextView 使用 sp，关闭额外 font padding；未显式设置的行高与字距不在此发明。

### Hierarchy

- **Title**（title / title-landscape）：竖屏标题与 sheet 标题使用前者，横屏工作区标题使用后者。
- **Readings**（reading / reading-landscape）：竖屏四列与横屏二乘二读数，启用 `tnum`；曝光补偿的 EV 后缀为主值的 0.55 倍。
- **Control**（control）：sheet 按钮、开关默认标题和参数详情；主工作区的传入开关实际缩为 compact-identity 字号。
- **Support**（support）：参数标签、状态、竖屏机型、机身模式和 sheet 说明。横屏机型与电量使用 compact-identity。
- **Caption**（caption）：最近拍摄和对焦的辅助标题。Canvas 小直方图标题按相同 9sp 视觉尺寸跟随系统 fontScale；放大图绘字为 11sp 的对应计算。

**The Read-Only Instrument Rule.** 数字是当前相机属性的读数，不是可编辑字段；未提供的项目显示“—”，不以照片 EXIF 或示例参数填充。

## Layout

入口为「同步 → 相机照片 → 遥控拍摄」。既有四个根导航及同步页结构保留，专用 Activity 进入固定深色工作区。Activity 把 system bars 与 display cutout 的 WindowInsets 应用于整个表面，并保留系统栏与系统返回；返回结束取景且保留连接。

竖屏顶部为 48dp 标题栏和 32dp 机型／电量行；48dp 工具行在取景区域上方。中央取景使用剩余高度，底部依次是四列读数、至少 48dp 高状态区、最近拍摄／84dp 主快门／对焦，以及相机保存位置和可选传入开关。

横屏由实际 `Configuration.ORIENTATION_LANDSCAPE` 决定，不使用 Web 宽度断点。机型与电量进入顶部右侧 217dp 区域；左侧完整取景上覆盖模式与三工具组，右侧为同宽可滚动控制区。读数重排为二乘二，主快门缩至 74dp。控制内容过高时滚动，不把下方动作是否可见等同于是否可达。

取景帧按 `min(容器宽/图宽, 容器高/图高)` 居中绘制；留黑随比例变化，不裁切、不拉伸。三分网格只绘在实际图像矩形内，对焦点击也只映射该矩形。小直方图独立于图像矩形，可拖动到取景容器范围内；初始靠左下，尺寸为 190×64dp。拖动位移超过 8dp 才进入移动，轻点打开大图。

sheet 由原生 Dialog + ScrollView 构成：竖屏贴底、全工作区宽，高度为 `min(600dp, 工作区高度 × 0.78)`；横屏贴右，宽 390dp、高度填满。面板左右／底部 20dp、顶部 14dp。布局保留 48dp 关闭、按钮和开关行，允许系统字号令内容增高。

**The Whole Frame Rule.** 让完整画面与主快门先被看见；不要为填满容器而改变取景比例，也不要放大机型或可见图标来填空。

## Elevation & Depth

工作区、工具和读数通过实色明度、细分隔及局部衬底建立层次，代码没有为它们绘制自定义投影或模糊。横屏工具组使用有界深色背景，以免亮画面直接落在图标后；机身模式另有自己的小块深色背景。Dialog 使用原生窗口与 0.55 的 dimAmount 分离当前任务，窗口本身的系统效果仍由 Android 管理。

这里没有新增的品牌过场、弹簧、快门闪白或常驻加载动画。RippleDrawable 反馈、按下／禁用状态和直接拖动来自实际控件；500ms 的视图更新是状态刷新，不是动画时长。sidecar 中的色阶仅供文档面板展示，不是新的原生 tonal elevation 或生产调色板。

## Shapes

原生几何保持少量明确角色：普通动作和最近缩略图采用 control 圆角，横屏三工具衬底采用 tools 圆角，直方图采用 instrument 圆角，sheet 采用 sheet 圆角。模式小背景在代码中为 8dp 圆角，不把这一局部值推广为全局形状。

主快门为 Canvas 双圆：外环 2dp 描边，外圆半径比 View 半尺寸小 2dp，内实心圆再缩 7dp；它不是普通圆角矩形。工作时中心绘制深色小方块；键盘焦点额外绘制暖白内环。可见工具字形由 48dp 触点内的 13dp padding 保持紧凑，源图标为原生矢量／Canvas 绘制，没有生产栅格图标切片。

## Components

### Context and tool actions

标题栏提供返回、当前页标题和拍摄设置。机型、电量、模式与三工具是辅助仪表，不抢画面。图标按钮保留可访问名称、tooltip 和 RippleDrawable；直方图／网格拥有真实选中状态及显式色彩过滤。未选中工具 alpha 为 0.55；能力不可用的对焦 alpha 为 0.4，并实际 disabled。

### Current readings

快门、光圈、ISO、曝光补偿均来自当前连接属性，详情 sheet 继续绑定同一状态。超过 5 秒未更新的参数阻止快门并显示“参数正在更新，暂不可拍摄”。不提供参数编辑、视频、B 门、连拍或定时器。

### Shutter and action feedback

单一主快门只在能力、新鲜参数、静态拍摄模式、非工作中且没有 UNKNOWN 结果时启用。禁用时绘制 alpha 为 105/255；准备／拍摄中显示中心工作标记。按钮／点按对焦受相机能力与当前取景限制；明确的对焦拒绝和快门拒绝说明保留 4000ms，正常轮询不能立即覆盖它们。

快门发送前保存相机身份及基线文件列表。结果未知时快门保持禁用，不自动补发；状态区与最近拍摄入口打开“核对拍摄结果”sheet。用户先查看相机最近照片，符合控制器条件后才出现“已核对相机，恢复拍摄”。重连也不自动解除限制。

### Preview, grid and movable histogram

显示位图和亮度／RGB 统计来自同一个解码帧。小图可以拖动、收起和点按放大；放大 sheet 提供两个现有模式按钮、160dp 图表及“显示在取景页”开关。RGB 共用最大值缩放，亮度使用自身最大值。图表只作相机处理后预览的曝光参考，不称 RAW 数据。

新鲜条件由控制器检查连接、取景开启、未暂停、帧序号及 2 秒时效，并排除准备／拍摄过程。旧图保留时绘制“上次取景 · 已暂停”，曲线随之减弱；无图时显示“等待取景”。连接丢失、关闭取景、取景暂停、无图或帧超过 3 秒时显示画面遮罩和相应恢复／重连动作。直方图的暂停判定与画面遮罩判定各有阈值，不混称持续实时数据。

### Recent capture and transfer

最近拍摄入口使用 48dp 缩略图，入口内缩略图可 CENTER_CROP；打开后在 sheet 中 FIT_CENTER 看完整预览，并显示文件名与“已保存到相机／已传入 App”。JPEG 可另传入 App，RAW 说明返回同步查看原文件；相机保存与传入 App 是两个状态。

断线仍可查看保留的最近预览。尚未传入的 JPEG 动作改为“重连后可传入 App”，disabled、alpha 0.45，并说明返回取景页重连。正在工作或已传入时同样使用真实禁用与对应文字，避免静默无响应。

### Native settings and sheets

设置只有当前实现的实时取景、构图网格、拍后传入 App、只读参数入口与断开连接。Switch 的 thumb 和 track 区分开／关状态；控制器更新状态时不触发重复命令。亮度／RGB 选中按钮为桃色底、深墨字，未选中为深色底、暖白字。所有 sheet 允许关闭和滚动；没有为文档预览增添输入框、导航目的地或产品开关。

## Do's and Don'ts

### Do:

- **Do** 以批准的局部原型和实际原生代码延续近黑、桃色、紧凑机型与小图标。
- **Do** 保留完整比例画面、48dp 操作目标、sp 字号、WindowInsets、系统返回和可滚动 sheet。
- **Do** 让显示帧与统计同源，并明确区分等待、实时、暂停和断线。
- **Do** 让只读参数、相机保存、传入 App 和未知拍摄结果各自反映真实状态。
- **Do** 将本地模拟器／合成夹具证据与真实 Nikon 相机联调分别记录，保留初审和后续有界 verdict。

### Don't:

- **Don't** 裁切或拉伸取景来消除留黑，或用大机型文字和大图标填满工作区。
- **Don't** 将参数读数变成设置控件，或以 EXIF、样例参数和文档预览冒充当前相机数据。
- **Don't** 把旧直方图当作实时分布、把预览统计称为 RAW 数据，或在未知结果后自动重发快门。
- **Don't** 在未传入 JPEG 的离线状态提供无解释的可用传入动作，或让轮询立即抹去拒绝原因。
- **Don't** 把文档性 HTML／CSS 组件预览当成生产实现、原生截图、实机验证或全表面认证。

本边界新增生产栅格为零；生产表面是 Android Views／Canvas，HTML／CSS detector 不适用。sidecar 的 HTML／CSS 只是原生设计系统的文档性近似标本，dp／sp 在浏览器中以 CSS px 近似，不能替代 Android 文字缩放、触摸、无障碍、生命周期或窗口行为。真实 Z6II 固件互操作、无线吞吐、持续帧率和完整 TalkBack 仍不由这些证据认证；历史原型与根设计文档保持各自原范围。
