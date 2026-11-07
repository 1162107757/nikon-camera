---
name: Huevia
description: 橙光、暖白与炭黑的原生 Android 摄影工作流
colors:
  surface: "#FAFAF8"
  container: "#EFEDE9"
  card: "#FFFFFF"
  text: "#262320"
  secondary-text: "#706A63"
  primary: "#B3432D"
  on-primary: "#FFFFFF"
  primary-container: "#F4D6C0"
  on-primary-container: "#85311F"
  outline: "#E4DFD8"
  success: "#42735B"
  error: "#AD3B30"
  action: "#46413B"
  action-end: "#27241F"
  on-action: "#FFFFFF"
  navigation-glass: "rgba(250, 250, 248, 0.9607843137)"
  dark-surface: "#201F1D"
  dark-container: "#33302C"
  dark-card: "#292724"
  dark-text: "#F6F1EB"
  dark-secondary-text: "#BAB1A7"
  dark-primary: "#F3B493"
  dark-on-primary: "#352016"
  dark-primary-container: "#51382D"
  dark-on-primary-container: "#F3B493"
  dark-outline: "#4C4640"
  dark-success: "#9AC8AE"
  dark-error: "#FFB4A7"
  dark-action: "#F0E8DF"
  dark-action-end: "#DAD0C5"
  dark-on-action: "#26211C"
  dark-navigation-glass: "rgba(41, 39, 36, 0.9411764706)"
  photo-accent: "#F3B493"
  photo-track: "#635247"
  photo-control-scrim: "rgba(38, 35, 32, 0.7215686275)"
  editor-canvas: "#141415"
  editor-tools: "#0B0B0B"
  editor-divider: "#292929"
  editor-text: "#F4F5F7"
  prisma-yellow: "#FFE335"
  prisma-white: "#FFFFFF"
  prisma-ink: "#191E17"
  prisma-text: "#F4F5F7"
  prisma-label-ink: "#1F2B29"
  prisma-canvas: "#242B27"
  prisma-tool: "rgba(16, 20, 18, 0.6117647059)"
  prisma-tool-selected: "rgba(17, 23, 19, 0.9019607843)"
  prisma-muted: "#C8CDCA"
  prisma-selection-frame: "#BBB9A1"
  prisma-selection-label: "#FFFFFF"
  prisma-selection-fill: "rgba(18, 28, 23, 0.0941176471)"
typography:
  page-title:
    fontFamily: "sans-serif-medium"
    fontSize: "26sp"
    fontWeight: 500
    letterSpacing: "-0.02em"
  back-page-title:
    fontFamily: "sans-serif-medium"
    fontSize: "18sp"
    fontWeight: 500
    letterSpacing: "-0.02em"
  preset-name:
    fontFamily: "sans-serif"
    fontSize: "15sp"
    fontWeight: 700
  body:
    fontFamily: "sans-serif"
    fontSize: "15sp"
    fontWeight: 400
  source-label:
    fontFamily: "sans-serif"
    fontSize: "13sp"
    fontWeight: 400
  navigation-label:
    fontFamily: "sans-serif"
    fontSize: "11sp"
    fontWeight: 400
  prisma-filename:
    fontFamily: "sans-serif-medium"
    fontSize: "13sp"
    fontWeight: 500
  prisma-caption:
    fontFamily: "sans-serif"
    fontSize: "10sp"
    fontWeight: 400
  prisma-label:
    fontFamily: "sans-serif"
    fontSize: "10.5sp"
    fontWeight: 400
  prisma-category:
    fontFamily: "sans-serif"
    fontSize: "11.5sp"
    fontWeight: 400
  prisma-auxiliary:
    fontFamily: "sans-serif"
    fontSize: "11sp"
    fontWeight: 400
rounded:
  field: "14dp"
  photo: "14dp"
  navigation-selection: "16dp"
  source-pill: "19dp"
  preset-card: "20dp"
  group: "22dp"
  photo-control: "24dp"
  source-track: "25dp"
  button: "26dp"
  fab: "28dp"
  prisma-thumbnail: "7dp"
  prisma-circle: "50%"
spacing:
  gap: "8dp"
  grid-horizontal: "12dp"
  grid-vertical: "14dp"
  page: "20dp"
  touch-target: "48dp"
  prisma-filter-gap: "14dp"
  prisma-rail-inset: "18dp"
components:
  primary-button:
    backgroundColor: "{colors.action}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.button}"
    padding: "10dp 16dp"
    height: "48dp"
  secondary-button:
    backgroundColor: "{colors.container}"
    textColor: "{colors.text}"
    rounded: "{rounded.button}"
    height: "48dp"
  input-field:
    backgroundColor: "{colors.container}"
    textColor: "{colors.text}"
    rounded: "{rounded.field}"
    padding: "12dp 14dp"
  category-selected:
    backgroundColor: "{colors.primary-container}"
    textColor: "{colors.on-primary-container}"
    rounded: "{rounded.photo-control}"
    padding: "9dp 14dp"
    height: "48dp"
  source-pill:
    backgroundColor: "{colors.card}"
    textColor: "{colors.text}"
    rounded: "{rounded.source-pill}"
    height: "40dp"
  settings-group:
    backgroundColor: "{colors.card}"
    textColor: "{colors.text}"
    rounded: "{rounded.group}"
  preset-card:
    backgroundColor: "{colors.card}"
    textColor: "{colors.text}"
    rounded: "{rounded.preset-card}"
  navigation:
    backgroundColor: "{colors.navigation-glass}"
    textColor: "{colors.text}"
    height: "68dp"
  photo-control:
    backgroundColor: "{colors.photo-control-scrim}"
    textColor: "{colors.on-action}"
    rounded: "{rounded.photo-control}"
    height: "48dp"
    width: "48dp"
  editor-dock:
    backgroundColor: "{colors.editor-tools}"
    textColor: "{colors.editor-text}"
    padding: "0dp 10dp"
    height: "224dp"
  prisma-export:
    backgroundColor: "{colors.prisma-yellow}"
    textColor: "{colors.prisma-ink}"
    height: "42dp"
    width: "68dp"
  prisma-tool:
    backgroundColor: "{colors.prisma-tool}"
    textColor: "{colors.prisma-text}"
    rounded: "{rounded.prisma-circle}"
    height: "39dp"
    width: "39dp"
  prisma-tool-selected:
    backgroundColor: "{colors.prisma-tool-selected}"
    textColor: "{colors.prisma-yellow}"
    rounded: "{rounded.prisma-circle}"
    height: "39dp"
    width: "39dp"
  prisma-filter-card:
    backgroundColor: "{colors.prisma-white}"
    textColor: "{colors.prisma-label-ink}"
    typography: "{typography.prisma-label}"
    rounded: "{rounded.prisma-thumbnail}"
    height: "83dp"
    width: "66dp"
  prisma-secondary-history:
    backgroundColor: "transparent"
    textColor: "{colors.prisma-text}"
    height: "48dp"
---

# Design System: Huevia

## 柔和卡片选择当前规则（153 / 0.29.2-beta）

153 是用户指定的卡片选中态细化，继续采用已批准 Prisma 世界与下方 152 的布局／共享工具。当前规则来自 `PhotoPrismaStyle` 的共享 selection 角色与实际卡片构造；主按钮和圆形工具继续使用原有黄色。

- 原肤、内置、个人与自定义肤色卡共用 1dp 柔和灰金框、轻透选中底和中性白选中文字；对应 `prisma-selection-frame`／`prisma-selection-fill`／`prisma-selection-label`。勾选、实际颜色、选中语义和点击行为保留。
- 滤镜条／完整滤镜选择器、快速预览和边框模板共享卡片边框角色。轻透填充仅用于肤色与大卡片；白底滤镜条名称仍使用深色，避免把浅色选中文字套到白底上。
- 原 2dp 饱和黄框与不透明肤色选中底是本次移除的高反差缺陷，不再作为卡片规则。编辑范围线、色盘游标和键盘焦点各自保留操作语义，布局、模型、渲染、草稿与导出不变。

**The Quiet Card Selection Rule.** 卡片选择使用 1dp 柔和边框，并保留勾选与原生 selected 语义；中性白字和轻透底按卡片材料使用。主操作／工具强调与编辑范围、游标、焦点不随卡片角色一同弱化。

当前本地 APK 为 153／0.29.2-beta，33,606,103 字节，SHA-256 `10acc7eebc77bc6f12ad36323f10f92f1d9f518e55621c87de8e5b2940a3c21e`。六项生产输入改变；Android 17／API 37 所属模拟器七模式各 10 项，共 70 次有界选择切换／文件／夹具保护断言与 42 张当前原生图。152 的 723 次广泛检查保持历史，不计为 153 重跑。见[实施](docs/selection-soft153.md)、[验证](docs/validation/selection-soft153/validation.json)与[完整复核](.impeccable/review/selection-soft153/review.md)（FIX，仅小字对比度）；选中文字已改为中性白，[评分 verdict](.impeccable/review/selection-soft153/verdict.md)为限定 ship：卡片文字对比度修正 resolved（横屏约 4.82:1），无直接回归，仅覆盖该评分修正；未作实体机或公开发布结论。

## 编辑续接与共享工具历史规则（152 / 0.29.1-beta）

152 延伸已批准的 Prisma 编辑原型，不更换视觉世界。本节覆盖下方 151 及更早主编辑／专用工作区中冲突的菜单、材料和控制规则；其他产品页面保持原有世界。实际代码权威为 `PhotoPrismaStyle`、`PhotoWorkspaceUi`、`PhotoFilterEditor`、`AlbumPanel` 和各原生编辑面板。

- 主编辑及皮肤／面部／塑形、曲线、HSL、调色盘、去灰、局部、涂抹和精细裁切共用有界、后台生成的照片氛围、半透明炭黑圆形工具、黄色选择／主操作和白色滑块。工具可见圆盘为 39dp，滑块圆点为白色 14dp；系统 sans 与 sp 缩放保留。照片及色卡的真实颜色不改成强调色。
- 圆形状态材料按矩形目标的短边定半径，图标与普通／按下／焦点／选中圆盘共享中心；重置使用共用 `AppIcon.drawRefresh`，原生操作目标至少 48dp。二级撤销／重做沿用正圆弧与精确水平镜像。
- 皮肤／面部／塑形的历史行透明，连续显示照片氛围；对比度只由各个圆形控件承载，不恢复整条深色底带。
- 塑形为等宽的瘦身／瘦腿／拉长／范围／重置五个圆形工具。范围切换参数，重置只影响当前项并可撤销；双腿／单腿紧随所属瘦腿强度。工具区折叠 180dp、展开 372dp，加 `72dp × (max(1, fontScale) − 1)` 后不超过可用主体半高。自动定位／背景保护用 `prisma-auxiliary` 与 `prisma-muted` 降为次级操作。
- 局部新建说明只在顶部原生选择行出现一次，保持与底部历史工具栏分离。
- 关闭旁常显三点菜单，保留既有实际能力、条件及处理事件；通用原生确认／输入框保持平台结构，各子编辑器保留应用／返回事务。

**The Shared Photo Family Rule.** `prisma-*` 的共同材料与控件规则用于主编辑和已列明的二级工作区；具体参数、色卡和算法保持各自语义。圆形控件承担状态对比，二级历史行不以全宽深色带替代照片氛围。

**The Distinct Body Action Rule.** 塑形同时出现辅助视口与参数操作时，上方范围可见性用眼睛、适应照片用四角框；下方范围参数用滑块图标，当前项重置保留带文案的圆箭头。不同作用不以重复图形暗示同一操作。

**The Resumable Draft Rule.** 普通打开照片恢复当前账号与原图身份的 pending draft，关闭仍保存编辑参数；只有明确选择已保存版本时走 `bindSavedVersion`。照片从手机相册重新导入仍保留相同草稿身份，不用显式版本查看替代正常编辑续接。

本地制品为 152／0.29.1-beta，SHA-256 `eb36fb3f174c52e55fd6f8b417ec0f9af95d755e5fea4c9e17bc8a8011d50b07`。同一包七模式 708 次含重复断言／98 张图，独立强停准备 6 项与重开 9 项／1 张图，共 723 次／99 张。305 项生产输入冻结，其中相对 151 有 24 项改变。实际 MediaStore JPEG 导入已覆盖，未新增端到端相册导出、实体机或公开发布验收；人脸／覆盖蒙版与预设为明确 QA 数据。

见 [152 实施](docs/editor-continuity152.md)与[验证](docs/validation/editor-continuity152/validation.json)。完整[最终复核](.impeccable/review/editor-continuity152/final-review.md)为 fix，仅余辅助视口／显示范围与参数操作的图标歧义；区分图标的修正已落地并完成同包验证，[评分 verdict](.impeccable/review/editor-continuity152/verdict.md)将唯一塑形图标歧义判为 resolved、remaining clear、ship，仅覆盖该项修正及直接回归，不是整页或全应用通过。当前环境经直接读取系统属性确认为 Android 17／API 37（sdk 37、release 17、previewSdk 0）。

## 图片编辑页历史规则（151 / 0.29.0-beta）

以下保留 151 当时的实现与验证；其已批准的 [Prisma 原型](docs/design-review/prisma-editor-20261107/prototype.html) 和滤镜间距仍是沿用基础，冲突处以上方 152 当前规则为准。

- 照片按实际比例完整显示，后台生成的小尺寸模糊采样延伸至编辑背景；绘制过程中不解码。
- 顶部居中文件名、关闭圆钮与黄色 `#FFE335` 导出胶囊；真实系统安全区和原生字号保留。
- 照片右上圆钮切换分割对比；白色分割线支持拖动、方向键和辅助功能进度操作。
- 照片下方依次为历史行、五个圆形工具（滤镜／调节／裁切／人像／边框）、当前工作区。白色滑杆圆点、白底滤镜名称、黄色选中边线。
- 撤销／重做使用等宽高 17×17 图标坐标边界内的 300° 正圆弧与连续圆头箭头，重做为精确水平镜像；位置、命中范围与历史语义保持原有实现。
- 滤镜卡片采用明确的 **14dp 外间距**，列表两侧 18dp 内缩；名称不得被缩略图或容器裁切。
- 调节标题与数值位于滑杆上方。裁切比例选中为黄色，旋转、翻转与重置文字为白色，禁用态降低透明度。
- 短窄竖屏使用 160dp 工作区与 67dp 主工具行，减少容器留白以保留照片主体；字体跟随系统，输入行保留 48dp 操作范围。横屏保留工具先于面板的顺序。
- 常规工作区为 184dp、主工具行为 67dp，随 `max(1, fontScale)` 增长；短窄竖屏（宽 <600dp 且高 <720dp）两者固定为上述紧凑高度，sp 仍跟随系统。历史行和分类／输入行为 48dp，顶部行为 56dp。
- 机器 tokens 中滤镜卡片为常规基础尺寸，随 `max(1, fontScale)` 增长；紧凑卡片固定为 66×59dp，其中缩略图 39dp、白色名称区 20dp。常规图／名称区分别为 62dp／21dp，黄色选中边线为 2dp。导出可见胶囊处于 80×48dp 原生命中范围；照片本身不加圆角或遮罩。
- 预设、曝光单位、系统栏和既有专用工具按真实能力显示；示意 CSS 滤镜和人像算法不进入生产。

实现与验证见 [151 实施](docs/prisma-editor151.md)。本轮未新增生产栅格图片。

**The Editor Scope Rule.** 本节及 `prisma-*` tokens 只约束当前主图片编辑页；下方 `editor-*` 的固定炭黑材料与旧面板尺寸保留为专用工作区／历史记录，不能覆盖本节。照片本身和系统字号、安全区是布局输入，不复制原型中的假系统栏或示意效果。

当前 [圆箭头专项复核](.impeccable/review/prisma-editor151-round/review.md) 为 ship，覆盖圆度、镜像、箭头连接、裁切及原位置／语义。当前 SHA `2eda2c2cfec6ada7af1abdd29f03034c91888ed5476de97d39d5e3c5fc9f2dad` 完成手机与 1.3 字号各 57 次检查；此前七配置 400 次布局验证及三项修正 [verdict](.impeccable/review/prisma-editor151/verdict.md) 仍归属 `5a39…` 候选，不能标为本次重跑。以上均不代表全应用或硬件验收。

## Overview

**Creative North Star: "橙光进入照片"**

Huevia 的原生 Android Java / Views 采用用户批准的橙光世界：暖白层次、橙杏光晕、炭黑胶囊与系统无衬线字。光晕为发现预设建立气氛，照片仍是内容；编辑时让位于完整比例画布、黑色工具区与杏色控制。

本文件记录 0.17.4-beta（88）的实际实现；本次按用户参考图将手机悬浮底栏四边统一为 5dp 内缩，让首尾选中项与外栏弧线同心、等距，保留 87 的 68dp 基础高度、86 的整项选中态、85 的悬浮位置与内容留位，以及 84 的暖色设计与四个根入口，全面取代原生界面此前的云白／蓝色声明。当前代码权威为 [UiPalette](app/src/main/java/cc/huevia/ui/UiPalette.java) 与 [HueTheme](app/src/main/java/cc/huevia/ui/HueTheme.java)，布局取自 [MainActivity](app/src/main/java/cc/huevia/MainActivity.java)、[LocalAlbumPanel](app/src/main/java/cc/huevia/ui/LocalAlbumPanel.java)、[AlbumPanel](app/src/main/java/cc/huevia/ui/AlbumPanel.java)、[PhotoFilterEditor](app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) 及其原生面板。批准的 [详细交互稿](docs/design-review/insurance-inspired-20261023/detailed/index.html) 与 [84 需求](docs/design-review/orange-ui-84/REQUIREMENTS.md) 解释意图，发生差异时以本版实际颜色、布局与截图为准。

浅色与深色是完整配对的语义系统，设置中的跟随系统／浅色／深色保持持久化。保留现有 Huevia 标识、代码绘制图标族和有来源的照片模板；本轮新增生产栅格为零。下方 Web 管理后台和旧社区／版本 Web 记录保留独立作用域，不能反向覆盖当前原生规则。

**Key Characteristics:**

- 暖白页面、白色分组与暖石墨深色。
- 橙杏光区只承担预设发现页的光感，照片与真实状态保持清楚。
- 炭黑渐变主动作、杏色选择态与可读的深陶土选中文字。
- 四个根入口、紧凑高度重排、宽屏侧栏和原生 48dp 操作目标。
- 系统 sans-serif 与 sp 字号；编辑工具保留黑底、杏色强调和完整比例照片。

**84 历史验证（不覆盖 85–88 的悬浮导航、选中态与几何变更）：** 最终视觉证据为 [.impeccable/review/orange-ui-84/](.impeccable/review/orange-ui-84/) 的 phone、large-font、landscape、dark、tablet 原生截图，含 presets、settings、live、editor-adjustments、import-slots 和 crop；[实体手机证据](docs/validation/orange-ui-84/physical/) 来自 OnePlus Ace 5 的现有用户数据。最终包 SHA-256 为 `b4a5b10fa5dffcd0850508eb0a7dc4a88cffa47ca5a2b2ed3894dfd2efcbdd03`（3,532,397 字节）。[矩阵](docs/validation/orange-ui-84/matrix.json) 为 PASS、sourcesStable 为 true：手机／1.3 字号／深色／平板各 364，横屏 365，共 1,821 次重复断言执行，非独立场景数量。最终 [修正复核](docs/validation/orange-ui-84/FIX-VERDICT.md) 将 M1–M6 评分为 resolved、remaining clear、disposition ship，范围限六项修正与直接回归；完整首轮见 [FINISH-REVIEW](docs/validation/orange-ui-84/FINISH-REVIEW.md)。实体证据限保数据覆盖安装与只读界面对照，没有相机写入、导出或账号修改；不构成生产网络、真实相机、FPS 或 TalkBack 认证。

早期原生规则仅为历史。旧 Apple 方案及照片编辑演变可查 [旧版完成复核](docs/design-review/apple-glass/finish-review-0.5.2.md)、[80](docs/design-review/photo-basic-adjustments-20261022/REQUIREMENTS.md)、[81](docs/design-review/photo-composition-recipes-20261023/REQUIREMENTS.md)、[82](docs/design-review/photo-filter-navigation-20261023/REQUIREMENTS.md) 和 [83](docs/design-review/local-album-20261023/REQUIREMENTS.md)，不重新累计为 84 的验收。

**89 局部实际落地（2026-10-24）：** [照片边框](docs/design-review/photo-borders-20261024/IMPLEMENTATION.md)沿用以上橙光全局世界与原生黑色编辑区；标题、根导航和全局布局未重设计。三款边框与小机型栏以用户批准的 [v3 稿](docs/design-review/photo-borders-20261024/border-templates-v3.png)及其[批准记录](docs/design-review/photo-borders-20261024/border-templates-v3.json)为方向，实际 Android Views／Canvas 产物为当前局部规则。协调加入的[相册缩略图占位](docs/design-review/thumbnail-placeholder-20261024/IMPLEMENTATION.md)只定义加载／不可用／真实照片状态，不改变边框及全局世界。最终 89 / 0.18.0-beta 本地 APK 的 SHA-256 为 `1f74ece275423198208750b804e7dad8e72c443b881c02eccb85eea9c4cd2ba0`；[边框最终 SHIP](docs/validation/photo-borders-89/FIX-VERDICT.md)只关闭初审两个 P2 及横屏可达性补证，[占位 PASS](docs/validation/thumbnail-placeholder/FINISH-REVIEW.md)保持独立组件范围。边框 282 次重复／配置断言与 76 个产物、占位 150 次重复／配置检查与 9 张 PNG 分别记录，不合并为独立场景；本轮未实体安装或公开发布，没有 HTML／CSS 检测适用面。

## Colors

配色从暖白与石墨中展开，用深陶土指示普通界面操作、杏色表达选择和照片工具强调。上方 frontmatter 为精确原语；Android ARGB 的透明颜色在其中转换为 CSS rgba，避免把 alpha 当成红色。 `.impeccable/design.json` 的色阶为面板按 OKLCH 生成的展示扩展，不是新增的 Android 调色板；HTML 标本将 dp／sp 以 CSS px 近似显示，原生源代码仍为组件行为权威。

### Primary

- **深陶土**（primary）：普通界面的链接、输入／状态强调与槽位选中描边；不再使用系统蓝作为全局操作色。
- **杏色选择底与深陶土选中文字**（primary-container / on-primary-container）：分类胶囊、槽位等小字选中态。深色分别采用暖棕底与浅杏字。
- **照片杏光**（photo-accent / photo-track）：黑色照片工具的滑杆、选中参数、导出和直播进度；轨道保持暖棕。

### Neutral

- **暖白页面、白色内容、暖灰容器**（surface / card / container）：建立页面、分组和字段层次；深色对应暖石墨页面、抬高的深棕灰容器与卡片。
- **炭黑渐变动作**（action → action-end / on-action）：HueTheme 主操作与悬浮加号。深色反转为暖米色渐变与深色文字。社区、更新、RAW 和回执的部分原生面板使用同一 action 角色的实色变体。
- **暖墨正文、暖灰辅助字与细分隔**（text / secondary-text / outline）：稳定的信息层次，深色使用对应浅暖色。
- **轻透导航底**（navigation-glass）：手机 GlassBar 使用暖白／暖石墨染色与条件式背景模糊；不满足材料条件时采用不透明 card。宽屏侧栏沿用轻透实色。
- **照片画布与黑色工具**（editor-canvas / editor-tools / editor-divider / editor-text）：与 App 浅深外观独立，持续服务照片编辑。

成功与错误沿用各自语义角色并配文字。连接状态只来自实际已验证会话；“未连接”“正在读取”“待核对”不能由装饰圆点替代。

**The Native Authority Rule.** 新增原生页面从 UiPalette 和 HueTheme 取值；历史蓝色记录及浏览器原型不再定义本版原生全局样式。

**The Selected Text Rule.** 杏色选择底必须配 onPrimaryContainer，不能直接把 primary 当作小字颜色。 最终独立计算中，浅色选中配对为 6.1986:1、深色为 6.0206:1；这两个结果限相应实色配对。

## Typography

**Display / Body Font:** Android 系统 `sans-serif`；标题和部分标签使用 `sans-serif-medium`，不打包 SF 字体。文字使用 sp，布局与命中区域使用 dp；frontmatter 中的单位是原生单位。

### Hierarchy

- **根标题**：26sp、系统 medium，字距 -0.02em；带返回页与紧凑根标题为 18sp，同样单行并在必要时省略。
- **照片／预设信息**：正常卡片名称为 15sp 粗体，紧凑高度为 13sp 单行；格式与分类为 11sp，设置相机型号为 19sp。
- **正文与操作**：正文通常 14–16sp，主要按钮 14–15sp，来源与分类 13sp，辅助说明 11–13sp。
- **根导航**：11sp，当前目的地加粗；图标和文字共同表达目的地。
- **编辑器**：参数与模式 13–14sp，辅助状态 11–12sp；精确值仍能显式输入，不用缩字代替可读性。

**89 边框局部字形：** 机型选择栏使用系统 11sp 名称与 9sp 自动／手动状态，14dp 相机图形置于完整 48dp 行内；缩小的是图形与文字，操作行不随之缩小。侧栏成品参数使用 Tomorrow ExtraBold Italic（SIL OFL 1.1），仅为参考字体的接近匹配；原参考字体未识别。成品字形按照片比例绘制，设置界面仍使用原生 sp。Nikon 使用有来源的官方字标和黄色方标，富士／索尼／佳能仅用中性品牌文字，不声称官方 Logo。

**The Reachable Action Rule.** 自有主要操作保留至少 48dp 命中区域，紧凑高度通过合并信息、滚动与重排节省空间。 内建系统对话框保持 Android 自身排布；48dp 是本版自有主要操作的设计基线，不宣称所有系统生成子控件都完成逐项测量。

## Layout

100 下载进度／多选动作区域通过宿主取得导航实际像素遮挡量。窄屏分别取整导航高度与14dp底距后相加，避免合并取整少1px；进度另留12dp、多选另留8dp。侧栏与沉浸返回0；内容与系统栏inset不重复计算。


根目的地固定为“预设／同步／相册／设置”。“同步”承载相机、边拍边传与已下载；“相册”默认 App 内，并列手机来源。详情、导入确认／结果、账号、社区、更新与沉浸照片按实际返回层级显示，编辑时隐藏根导航。系统栏、刘海与输入法安全区由 WindowInsets 处理；对话框关闭及窗口恢复焦点后重新应用系统图标明暗。

- **手机与宽屏**：宽度小于 600dp 使用居中的 GlassBar 悬浮底栏，宽 `min(360, screenWidthDp − 48)` dp，基础高 68dp，按 `68 + round(max(0, fontScale − 1.2) × 24)` dp 增长；底部距 WindowInsets 安全区内缘 14dp。宽度不小于 600dp 保持 80dp 左侧栏，剩余工作区居中且最大宽 720dp。侧栏每项 72dp，选中图标底为 54 × 30dp 的杏色胶囊。
- **内容节奏**：预设标题／来源和设置左右留白通常 20dp，预设网格左右 18dp，列距 12dp、行距 14dp；设置组按 24dp 标题上留白、9dp 标题下留白分隔。设置行最小高 66dp，左图标为 32dp 暖灰底。
- **预设发现**：正常高度保留标题、简短引导、48dp 来源控制、连接卡、分类、真实计数和双列卡片。有效工作区达到 600dp 时三列；非紧凑且字体比例不小于 1.8 时回退单列。正常卡片图高为卡宽的 1.10 倍；卡片不是旧版固定 4:5 封面规则。
- **紧凑高度**：screenHeightDp 小于 480 时，光区由 218dp 收至 168dp，根标题／连接状态合并；隐藏引导与独立连接卡，来源与个人状态同排，收紧分类与计数间隔。列数取 `max(3, effectiveWidthDp / 170)`，图片高 80dp；最终横屏证据显示四张完整卡片及可达加号，不强制所有紧凑设备恰好四列。
- **相册与加号留位**：日期分组、方形缩略图、文件名和真实版本信息保持可见；紧凑横屏把来源与摘要合并并按可用区域重算列数。LocalAlbum 在 `screenWidthDp < 600` 时导航预留为 `104 + round(max(0, fontScale − 1.2) × 24)` dp，宽度不小于 600dp 时保持 `92 + round(max(0, fontScale − 1.2) × 20)` dp；列表另留 8dp、相册加号另留 12dp，授权空态可滚动。预设加号仅在紧凑高度且 `screenWidthDp >= 600` 时距底部 16dp，其余为 `104 + round(max(0, fontScale − 1.2) × 24)` dp。预设列表仅在紧凑高度且 `screenWidthDp >= 600` 时保留 76dp 底部内边距，其余为 `108 + round(max(0, fontScale − 1.2) × 24)` dp，使小于 600dp 的紧凑窗口仍为浮栏留位。
- **照片编辑**：完整比例照片填入可用画布，保留缩放与平移。竖屏工具区高 224dp；横屏使用右侧 300dp 工具区，构图也在横屏采用 300dp 可滚动侧控件。工具换页不跳动画布；滤镜／调节／构图／配方共用稳定入口。

- **89 边框局部布局**：原黑色 176dp 内容区＋48dp 工具导航及分隔线保持不变；五个入口依次为“滤镜／调节／构图／边框／配方”。边框内“样式／信息／外观”使用同一内容区，样式展示当前照片的四个真实缩略图和紧凑机型行；横屏沿用侧工具区，机型选择的应用操作通过实际滚动到达。

## Elevation & Depth

层次主要来自暖白／卡片／容器的色调差、留白与细分隔。HueTheme 卡片在浅色为 2dp elevation，环境／聚光阴影分别为 Android ARGB `#12302B23` / `#18302B23`；深色为 0dp。来源选中胶囊仅 1dp，悬浮加号 4dp；普通主按钮清除默认 elevation 与 StateListAnimator。

预设首页光区由 HueTheme 的缓存线性／径向 shader 叠加并渐隐至页面色，不使用栅格背景、模糊捕获或持续动画。手机悬浮底栏恢复 GlassBar：8dp elevation，浅色环境／聚光阴影为 Android ARGB `#26302B23` / `#30302B23`，深色为 `#40000000` / `#60000000`；0.5dp 细边为暖棕灰 `#18302B23`，深色 `#35FFFFFF`。API 31+ 且非低内存、硬件加速、动画开启、非省电状态时，对独立内容层以 1/6 尺寸采样并施加 18dp 模糊，上限每 100ms 一次；只由来源绘制帧驱动，无常驻定时器。条件不满足、采样失败或无背景时退回不透明 card，卸载释放采样。宽屏侧栏保留轻透实色与右侧分隔。黑色照片工具保持平面；收藏、更多与图标对比使用 photo-control-scrim，最差白底合成后的白色图标对比为 6.2610:1。

页面切换使用 PageTransitions 的可打断入场：普通 220ms、20dp、初始 alpha 0.82；照片 180ms、最多 8dp、初始 alpha 0.65；曲线为 cubic-bezier(0.22, 1, 0.36, 1)。系统动画关闭、视图卸载或取消时恢复完全可见。这里记录源码行为，不声称物理帧率或流畅度已认证。

**The Photograph Rule.** 照片内容保持真实来源与状态；光晕、模拟角标和工具不能冒充真实相机效果或遮掉关键内容。

## Shapes

圆角由角色确定：字段与本地照片 14dp，宽屏侧栏选中图标底 16dp，预设来源选中胶囊 19dp，预设卡片 20dp，设置与相机分组 22dp，照片控制及部分紧凑操作 24dp，来源轨道 25dp，主按钮 26dp，悬浮加号 28dp。手机悬浮根导航的外轮廓与 Rim 使用实际栏高的一半作圆角，整项选中底使用实际单元高度的一半；它们随字号引起的高度变化计算，不再使用固定 34dp／28dp 半径。宽屏保持全高侧栏。

AppIcon 沿用代码绘制的 24dp 画布、1.8 单位圆头／圆角线条；结构图标不换成 emoji。头像与状态点保持圆形。照片控件的衬底跟随命中区域，收藏与更多之间保留 8dp 间隔。诊断界面沿用独立 DiagnosticTheme，不作为消费界面的模板。

## Components

### Buttons

主操作沉稳、可辨：HueTheme 使用垂直 action 渐变、on-action 文字、26dp 胶囊与原生 RippleDrawable；次操作用 container / text。禁用使用 container / secondary-text，任务中不得靠换色制造可继续的错觉。普通自有操作至少 48dp，账号部分主要表单为 52dp。悬浮加号在预设页为 54dp、相册为 56dp，使用相同动作材料；每页只有一个对应主添加入口。

### Chips & source controls

分类以 48dp 目标承载、左右 14dp 内边距，未选为 container / text，选中为 primary-container / on-primary-container 并设置 selected。预设来源外层高 48dp，可见选中胶囊高 40dp、白卡片／深色卡片底；相册 App 内／手机沿用相同卡片选中语言。来源、分类和数量来自实际列表。

### Cards & settings

预设卡片用 20dp 圆角、真实预览、名称、NCP／NP3 格式和分类建立层次；失败保留真实原因与重试，不用随机滤镜补图。设置相机卡与分组为 22dp，行内图标用暖灰小底、文字与尾部箭头／实际值；分隔从文字列开始。RAW 列表、回执、账号、投稿、评论、消息和更新复用语义色、系统字与原生弹窗，保留各自真实状态和业务边界。

### Inputs & dialogs

暖灰容器、14dp 圆角、通常 15–16sp 正文与明确标签。已有表单继续使用 Android 输入法、文件选择、权限和系统对话框；错误显示文字并保留可修正输入。私密字段、提交中禁用、取消与返回保留既有行为。恢复页面时系统栏图标跟随当前明暗表面。

### Navigation

手机悬浮底栏／宽屏侧栏都保留四个有文字的目的地；悬浮材料和尺寸遵循上方布局与深度规则。手机底栏的水平 navigation 填满悬浮容器，四边内边距统一 5dp；四个单元等宽、填满内侧可用高度，单元左右外边距均为 0。单元内的图标与名称保持居中，上下内边距各 4dp、最小高度 58dp，图标槽为 54 × 26dp，11sp 名称上方间距为 2dp。选中项用完整杏色底包住图标和名称，布局后按实际单元高度的一半设置圆角；图标槽没有单独底色。首尾选中项与外栏在左右、上下均内缩 5dp，内外弧线同心。宽屏竖向侧栏保持左右 8dp／上下 6dp 内边距，单元高 72dp、最小高 58dp、左右各 1dp 外边距；仍只为 54 × 30dp 图标槽显示 16dp 圆角杏色底，名称上方间距为 3dp。两者选中图标均为正文色、标签加粗，未选图标和标签为辅助色。设置未读圆点为 8dp，内容说明包含未读数；数字消息胶囊与真实服务端已读状态一致。

### Import slots

原生三列槽位网格展示 C1–C9 或设备实际支持数量；单元最小高 84dp、13sp 最多三行，显示真实占用名称／空槽位，选中为杏底深陶土字和操作色描边。兼容摘要、参数调整、明确目标及覆盖确认仍是独立可读步骤；NP3 的不可写入状态不因新外观改变。

### Photography tools

预览主图分别标注模板模拟、发布者样片与真正照片；来源见 [模板素材记录](docs/assets/preset-template-provenance.md)。详情的只读色调曲线继续读取真实采样，使用当前 primary 与有标签参考线。编辑工具为黑底、浅文字、杏色滑杆与选中参数；13 项调节、精确值、撤销／重做、构图与配方保持真实状态。

HoldToCompare 的文字或图标目标为 48dp，照片上图标态使用共享深色衬底；文字态保留自己的深色半透明胶囊与白色细边。按住显示真正原图，松开、移出、取消、失焦或隐藏恢复效果；键盘／辅助点击为两次点击切换。更改对比状态保持照片变换，不在按下时执行图片 IO。当前功能与代码语义不等于 TalkBack 实测。

### Photo borders · 89

照片保留完整内容，边框在色彩处理和定向构图后向外追加画布；预览、模板缩略图与完整 JPEG 共用按照片比例排版。模糊居中以照片模糊底、圆角原片、下方软影及居中品牌／机型／参数组组成；模糊侧栏以左侧品牌与 F／ISO／S 参数配右侧完整照片；白底信息条保留品牌／机型、黄色 Nikon 方标、分隔、参数与原拍摄时间的层次。照片输出中的模糊和阴影属于边框，不推广为 App 表面材料。

机型默认读取原图 EXIF，手动模式提供尼康／富士／索尼／佳能、机型搜索与自定义；信息页可补填或隐藏机型、焦距、光圈、快门、ISO、拍摄时间，缺失信息自动隐藏。外观提供边距、圆角、阴影、背景模糊与 Logo 选择。手动值只改变边框展示；保留原图字节与现有保存位置／新副本规则。PED4 兼容旧草稿的默认无边框，撤销、重做、草稿、冻结身份和逐张批量均承载独立边框设置。

**The Border Space Rule.** 品牌按真实绘制字形测量并约束在明确槽位内；品牌／机型组合留出间隔，白底品牌不越过分隔或参数，长文字在各自分配范围内缩放。保持 Nikon 官方标志的原始比例，不用中性文字的宽度估算代替真实绘制尺寸。字段、自定义机型及 Logo 子弹窗随当前编辑绑定关闭，旧 owner／绑定代次／原图身份的回调不能写入新草稿。

### Detail loading · 94

保留93的紧凑玻璃控件。进入细节立即显示界面，后台校验源后先出真实缩略预览，再补完整帧；“载入中…”／“细化中…”按内容宽度排版，不用weight零宽文本计算胶囊。尺寸未知时不显示右上标签，已知时只显示尺寸，当前请求完整帧返回后才显示倍率。适应画面的临时预览不能认证100%／200%。中性JPEG直接读取，区域解码保留邻块像素并整数裁回，奇数采样边缘按实际bitmap尺寸处理。名称统一“边拍边传”，历史版本记录保留旧称。[94实施与证据](docs/validation/photo-detail-load-94/IMPLEMENTATION.md)固定本轮结果，未扩大原型或重新设计页面。

### Detail, histogram & export · 91

本轮按[已批准技术需求](docs/design-review/photo-detail-export-histogram-20261024/REQUIREMENTS.md)延伸黑色编辑器与杏色控件，保留“滤镜／调节／构图／边框／配方”、系统字体、既有工具区和全局导航。用户随后否定大黑底面板与连体大选择、要求照片更大与小玻璃浮层，对应旧图视觉由[GLASS-BRIEF](docs/design-review/photo-detail-export-histogram-20261024/GLASS-BRIEF.md)覆盖。最终f717151b…实现、三配置原生回归与本轮有界独立修正确认已完成；不以旧功能PASS或独立ship代替用户最终视觉批准。

主编辑入口按用户最新反馈由“细节100%”改为“查看细节”：深色实际照片玻璃承载18dp放大镜和12sp文字，内容宽约91dp，视觉高32dp／触达48dp，贴实际照片左下并有点击反馈，进入真实细节页。图标与文字在浅照片上仍须可读，不以白图标落白底形成看似留白的入口。

细节使用满安全区独立画布，不以大footer占高。实际照片左下锚定约232×55dp缩放palette，仅“适应／100%／200%”三按钮，选中视觉32dp、触达48dp。按用户后续要求，尺寸／倍率拆成照片右上11sp单行小玻璃tag，避开header及顶部216dp比较胶囊；比较保留“当前效果／调色前”，详细说明进入info，定位小窗右下避让palette。100%仍是内容像素与屏幕物理像素1:1，200%不增加真实细节，同构图对比不含外加边框。顶部操作按真实systemBars／displayCutout避让，深底使用白色系统图标，不重复叠加insets。不可恢复历史版本明确“已保存版本／查看完整文件像素”，保留烘焙内容并禁用调色前，不因精简控件而省略限制。

直方图从照片工具开关，通常280×104dp玻璃浮层跟随照片变换；上方有足够留白优先放留白，紧凑横屏可沿照片下缘并避两角操作，保持主体与曲线完整。1.3字号按需约316dp／上限328dp并受可用宽度约束，百分比完整。亮度／RGB以轻下划线表达，暗部／高光为相隔6dp的独立28dp视觉chip、触达48dp。模式线为Ripple背景中的实体LayerDrawable／GradientDrawable层14×2dp、bottomInset12dp（y34–36），非选中透明；清theme tint。旧onDraw已移除，5e…移动线／关闭outline clip仍FAIL，裁切仅未证实假说。背景后清零padding／居中、header关闭baseline对齐，以实际glyph和framebuffer核对。横屏不重复扣剩余高度64dp，info有独立槽位。更新／不可用／零值分别表达，警示仅供诊断。`PhotoGlassDrawable`采样真实照片局部，最长192px后box blur、约65%深tint／35%图色加细rim，不写入照片、1:1数据、统计或导出。

导出页将照片摘要、完整／分享／自定义、实际含框尺寸／JPEG 质量、保存位置／方式、体积说明与主操作放在同一流程；内容可滚动，主要操作固定。紧凑横屏只固定主按钮，低强调的JPEG／NEF原始文件动作随正文滚动，保留参数阅读空间。完整默认质量95，分享长边≤2048／质量90且不放大，自定义640–8192／质量70–100。自定义初值为 min(4096,完整长边)／90，单张不超过完整尺寸，批量按每张完整尺寸限制。质量100不称无损，无可靠预估时写“导出后显示实际大小”。

**The Export State Rule.** “尚未生成”“App 内已有”“手机相册仍存在”“明确缺失”“上次未完成”“暂无法核对”由真实成品与回执核对决定；默认操作随状态变为导出、查看、重新保存或核对继续，未知不等于缺失。非法输入清除核对中文字，禁用主动作说明修正输入。“另存新副本”必须明确选择。主编码成品标明保留拍摄信息、不含定位；独立的“保存 JPEG 原始文件”另行确认忽略编辑与规格且可能保留定位。进度按真实逐项状态显示，进度条仅表达已完成／总数，取消项目不填成成功；进度页使用不透明系统栏。关闭面板与明确停止分开，接受后快照不随继续调图或重绑而变化。

历史矩阵、5be字形失败及[5e模式线失败](docs/validation/photo-image-upgrade-91/glass-5e9688ba-mode-line-fail/)保留原身份，不跨轮累加。最终f717…[当前矩阵](docs/validation/photo-image-upgrade-91/UI-MATRIX.json)phone172／font1.3 172／landscape174，共518次重复／配置断言；每配置三阶段模式线均活动172/216、非活动0，阈值未改、字形无交叠／裁切；1:1对照各1849点最大差0。[最终独立确认](docs/validation/photo-image-upgrade-91/FINISH-REVIEW.md)已将G1–G3及尺寸tag／紧凑入口判resolved、clear、限定ship，只限这些修正及直接回归，非用户最终视觉批准或全App认证。206输入与包／签名身份、夹具／设置／权限恢复及自有模拟器关闭完成。dark eaa143／backend b5 169／progress 0d35 23仍为明确旧SHA，不称最终包全测，详见[实施记录](docs/validation/photo-image-upgrade-91/IMPLEMENTATION.md)。未扩为实体手机、MediaStore发布、相机、tablet、性能或TalkBack认证。

### Editor & detail · prototype v3

**后续93最终：** 用户未接受92控件对齐／内距／圆角与构图按钮，此前31图复核漏检；93全面收紧文字、统一4dp等距分段和居中chip、同排小构图动作、原生弹窗14／13／12／13sp。初始d4b像素FAIL后补scroll及输入20dp左距，最终`37895934…`（207输入）同SHA phone635／font1.3 635／landscape647 PASS；文字起点差0px、选中面四边11px等距、真chip绘制原阈值PASS。限定最终15图修正／回归确认，不称97PNG逐张审；v4`c1728206…`的46项与2组仅认证静态事件。清理完成，限定SHIP可交用户审核，非用户视觉接受；旧92只留历史，不扩大导出／批量。见[93实施](docs/validation/photo-polish-93/IMPLEMENTATION.md)及[最终复核](docs/validation/photo-polish-93/FINISH-REVIEW.md)。

**以下为原型先行时点历史：** 用户要求按[新原型](docs/design-review/photo-detail-glass-redesign-20261024/index.html)实现编辑页／查看细节，随后调整为先完善原型，再继续已授权的两页原生实现；导出HTML补齐不扩大原生改造。v3以照片主导画布、两行chrome、176dp面板＋48dp五入口、300dp横屏右轨及小玻璃浮层串起编辑、构图、完整选择与细节；导出另有六种可操作场景。主原型46项、导出21组安全静态检查分别PASS，不能当作浏览器布局／像素、视觉接受或新原生效果证明。file预览被安全策略拒绝，未绕服务器／其他浏览器。原型阶段三处原生草稿暂存，未构建／安装v3新包，dist仍旧91／f717，旧证据不认证新草稿；见[设计规格](docs/design-review/photo-detail-glass-redesign-20261024/DESIGN.md)、[总记录](docs/design-review/photo-detail-glass-redesign-20261024/PROTOTYPE-REVIEW.md)与[原生时点](docs/design-review/photo-detail-glass-redesign-20261024/NATIVE-DRAFT.md)。新视觉仍待用户审核，原生后续由新候选实际验证更新。

### App update prompts · 99

新版本提示显示版本、体积、更新说明及明确动作；普通更新可立即更新或稍后，同一APK8小时内不重复。提示沿用现有系统弹窗与紧凑字号，使用不透底的圆角卡面，长说明滚动、底部动作固定；下载进度和错误原位刷新，不重建相机页面。强制更新只提供下载／安装、重新检查和退出应用，Back／点外部不能跳过；策略取消或撤回后关闭限制。相机传输／导入中等待安全时点，不能静默安装。测试版未选通道时自动跟随beta，明确选择仍保留。后台普通／强制设置需部署014和对应服务后生效，本轮未线上开启。

### Live & local album

边拍边传保持项目行、主图、真实传输／保存状态、接收记录和缩略图顺序；照片动作与进度采用 photo-accent，track 使用 photo-track，选中操作条横向滚动并留出计数空间。相册使用单一 56dp 加号和 48dp 更多入口，未授权时居中显示“点击获取授权”与简短引导；授权、导入和保存反馈不以静态空卡代替。

### Album thumbnail placeholders · 89

`LocalAlbumPanel`／`PhotoPlaceholder` 保留原方格、14dp 圆角、日期、文件名和选择层。占位从现有 container 向 card 混合 22%，使用 AppIcon 小照片符号，通常 24–28dp、紧凑格最小 18dp；灰线从辅助字色向占位底混合 25%。等待时为静态三点，中央杏色、两侧灰色；无逐格动画、常驻计时器或额外图片解码。失败显示 10sp“暂无预览”，不足以容纳时保留图形与状态描述；沿用更多菜单的刷新入口。

**The Thumbnail State Rule.** 占位图在容器 bounds 内绘制且不声明 intrinsic 尺寸，仅内部符号使用固定 dp，避免 CENTER_CROP 放大导航图形。真实 Bitmap 就绪后仍用 CENTER_CROP 并替换占位，恢复文件／版本描述。加载、不可用、成功和刷新恢复必须反映真实状态，不伪造照片；原 12MiB 缓存、两个 worker、24 个排队位置、失败去重和过期绑定校验保留。

## Do's and Don'ts

### Do:

- **Do** 从 UiPalette / HueTheme 和本版原生截图提取规则，维护浅深色完整对应。
- **Do** 在分类、槽位选择等杏色小字区域使用 onPrimaryContainer，并同时保留选中语义。
- **Do** 为连接、权限、下载、保存、加载和失败提供真实文字状态；圆点与颜色只作辅助。
- **Do** 保留 sp 字号缩放、系统返回、WindowInsets 安全区、48dp 主要操作与完整比例照片。
- **Do** 保留现有标识与模板溯源；模板模拟、发布者样片和用户照片分别标识。

- **Do** 将边框品牌／机型／参数约束在各自槽位，原图内容、字节和自动／手动来源保持清楚。
- **Do** 以固定小占位符号表达真实加载或不可用状态，就绪后显示真实 CENTER_CROP 照片。

### Don't:

- **Don't** 把旧原生蓝色或原型示例数据当作当前实现；恢复悬浮导航时仍使用现有暖色 tokens 与真实四个入口。
- **Don't** 用橙色铺满所有表面；编辑画布与工具保持黑色材料，局部操作使用杏色。
- **Don't** 用无底白图标直接覆盖任意照片；收藏、更多和图标对比使用共享照片控件衬底。
- **Don't** 将模拟、下载、导入读回、实际拍摄与已发布／已安装混称同一种成功。
- **Don't** 把重复断言次数或限定 UI 复核写成真实相机、生产网络、FPS、颜色标定或 TalkBack 认证。

- **Don't** 将参考字体近似匹配或其他品牌的中性文字称为相同字体／官方 Logo，也不把边框材料推广为全局材料。
- **Don't** 用会被 CENTER_CROP 放大的导航图形或设计稿切片代替原生占位，也不将不同专项的重复断言相加为独立场景。

**以下既有作用域原文保留：** Web 管理后台继续独立；末尾 0.10.1 节的 Android 描述与证据仅属于 55 历史版本，其云白／系统蓝和三个根目的地不适用于当前原生系统。混合记录中的 Web 社区、版本与下载指导保留原范围。

## Web 管理后台（2026-10-18）

### Overview

管理后台沿用“云白与石墨”的语义色彩，以左侧任务导航、右侧工作区承载预设维护与 App 用户管理。它是独立的 Web 表面；以上 YAML、原生字号、圆角与导航规则仍属于 Android，不因本节而改变。Web 的实际来源为 [页面结构](online-library/admin/index.html)、[交互](online-library/admin/app.js)及 [最终样式](online-library/admin/styles.css)；[基础 tokens](online-library/admin/tokens.css)先加载，后加载的样式覆盖其颜色、字体与组件尺寸。

### Colors

Web 使用下列有效语义角色。浅色成功绿已为状态文字单独加深；不要用 Android 的成功绿替换它。

| 角色 | 浅色 | 深色 |
| --- | --- | --- |
| 页面 / 次级表面 / 内容表面 | `#F7F8FA` / `#EEF0F4` / `#FFFFFF` | `#22252A` / `#30353D` / `#2A2E34` |
| 正文 / 次要文字 | `#20242B` / `#626B78` | `#F4F5F7` / `#ADB6C3` |
| 操作 / 操作上文字 / 选中底色 | `#0065DC` / `#FFFFFF` / `#E9F1FF` | `#8DBBFF` / `#07244A` / `#263D5A` |
| 分隔 | `#D9DEE6` | `#474E58` |
| 成功 / 错误 / 警示 | `#217A43` / `#BA302A` / `#946200` | `#7ED9A1` / `#FFB4AB` / `#EAC17C` |

**The Semantic Status Rule.** 绿色、警示色和圆点必须配合文字标签。QQ 是否配置、用户是否启用和预设是否上架使用各自的真实服务端状态；占位提示沿用不透明的次要文字色（`opacity: 1`）。外观提供跟随系统、浅色与深色，并在当前浏览器持久保存。

### Typography

采用系统字体栈 `-apple-system, BlinkMacSystemFont, "Segoe UI", "PingFang SC", "Microsoft YaHei", sans-serif`，正文为 15px（`.9375rem`），行高 1.5。页面标题为 28px（`1.75rem`）、700 字重、字距 -0.025em；预设名称为 15px，用户昵称为 14px，按钮和字段标签通常为 13px，辅助时间与说明为 11–12px。时间、计数和用户属性使用等宽数字；不用展示字体干扰维护工作。

### Layout

桌面侧栏固定于左侧，宽 232px；761–1150px 视口缩为 204px。顶部与主内容同步留出侧栏宽度，内容左右内边距通常为 32px，中等视口为 24px，1500px 及以上为 48px。侧栏只提供“预设管理”“用户管理”，当前目的地用蓝字与浅蓝底标记。

760px 及以下将导航重排为顶部横向两项；顶部工具区固定高 72px，导航紧接其下，内容不保留桌面侧栏空位。内容左右留白为 20px，380px 及以下为 14px。列表由多列改为纵向信息行：用户时间保留明确标签，较窄桌面可隐藏注册时间列，详情仍可查看完整属性。切换目的地后将工作区焦点与滚动位置回到顶部；关闭用户详情恢复原列表滚动位置。

### Elevation & Depth

工作区主要依靠实色表面、细边界与留白建立层次。顶部栏不使用模糊或阴影，登录卡同样保持平面。右侧详情 / 编辑抽屉与居中确认对话框使用遮罩和对话框阴影；底部短提示保留局部半透明材料。减少透明效果偏好改用实色后备。

### Shapes

按钮、搜索框与当前导航采用较紧凑的圆角（10px），桌面列表容器为 14px，手机列表为 12px，登录卡与确认框为 16px。桌面抽屉左侧圆角为 16px，760px 及以下取消圆角，600px 及以下扩为全屏。头像保持圆形，状态标签保持胶囊形；图标统一为细线、圆头、圆角 SVG。

### Components

- **操作与字段：** 主按钮用操作色，次操作用内容表面和描边，安静操作用文字。一般按钮最小高 42px，导航项为 46px，搜索与筛选为 44px；顶部、分页及手机局部操作按源码收紧。键盘焦点使用 3px 操作色外框；提交期间禁用重复操作并显示进行中文字。按钮颜色反馈为 160ms，抽屉入场约 200ms；减少动效时关闭过渡与动画。
- **预设列表与编辑：** 工具栏包含名称 / 简介 / 机型搜索、状态、分类筛选和排序；内容行以效果图、名称、分类、状态及维护入口建立层次。编辑器的单分类支持建议值或自由输入。草稿、版本、上架、下架与待更新分别表达，保存不等于上架。
- **用户列表与详情：** 昵称 / 用户 ID 搜索、状态筛选、分页及正常 / 停用计数读取服务端结果。列表展示头像、来源、状态、注册与最近登录；详情补充累计登录、最近更新及脱敏 QQ 标识。加载、错误、无用户和无搜索结果有独立文字状态；头像缺失使用统一线性占位图标。
- **账号状态确认：** 启用与停用均需明确确认。停用说明 App 会话失效且资料保留；资料冲突提示重新读取详情。普通 App 用户与管理员账号独立，不以 QQ 用户替代后台登录。
- **QQ 接入提示：** 用户已确认尚未申请 QQ 互联。后台根据服务端返回显示待接入状态，空列表说明接入后才会出现注册用户；已配置只代表配置状态，不代表真实 QQ 登录已验收。

### Do's and Don'ts

- **Do** 从最终 Web 样式提取有效值，保留浅深色、键盘焦点和减少动效偏好。
- **Do** 让真实状态、空态与下一步操作优先于装饰；用户详情只展示脱敏 QQ 标识。
- **Don't** 用本节的 px、侧栏或 Web tokens 覆盖 Android 的 dp / sp、底部导航或既有 sidecar。
- **Don't** 把本地合成用户或截图写成真实 QQ 用户、手机登录或线上部署证据。

独立完成复核结论为 **SHIP，仅限已审阅的 Web UI**。本地桌面与窄屏合成截图、对比度修复及测试边界见 [管理后台完成复核](docs/design-review/admin-management-2026-10-18.md)。本节不表示新版线上部署、真实 QQ 登录、Android 新登录或真实手机已验收。

## 0.10.1-beta · 社区、版本管理与下载

**历史混合记录（55 / 0.10.1-beta）：** 以下原文的 Android 色彩、导航与界面证据只记录该历史版本；当前原生规范以本文件前八节为准。其中 Web 社区、版本管理与下载页的独立指导原文保留。

### Overview

社区和可选更新继续使用云白／石墨、系统蓝及系统无衬线字体。Android 的来源为 [CommunityPanel](app/src/main/java/com/nikonpreset/usbprobe/ui/CommunityPanel.java)、[注册验证](app/src/main/java/com/nikonpreset/usbprobe/ui/AccountPanel.java)及 [UpdatePanel](app/src/main/java/com/nikonpreset/usbprobe/ui/UpdatePanel.java)；Web 来源为 [社区样式](online-library/admin/community.css)、[版本样式](online-library/admin/releases.css)与 [下载页样式](online-library/download/download.css)。本节追加局部组件规则，前述 Android tokens 和相机／直播历史保持其原范围。

### Layout

Android 在线预设页提供“发布预设”和消息入口，设置增加“我的投稿”“消息”“检查更新”，既有三个根目的地保持不变。社区详情按封面、作者／来源、简介、下载、交流排序；顶级评论与 20dp 缩进的回复形成两级，更多评论和更多回复有显式加载操作。投稿编辑使用纵向字段、文件操作、权利确认和审核状态；待审时清楚说明暂不能编辑。

后台桌面侧栏在原有预设、用户管理后增加“社区管理”“App 版本”；所有启用管理员均可访问版本管理。760px 及以下四项横向导航可水平滚动，文字保留、图标隐藏。社区内的五项栏目另行横向排列；700px 及以下内容行换行、规则表单由双列改为单列。版本区先展示上传表单，再展示真实渠道、版本与状态；700px 及以下重排为两列／纵向信息。下载页主内容最大 960px，标题与下载主操作居中，更新说明与二维码在桌面分两列，600px 及以下改为单列，主下载按钮宽度上限 320px。其后三张原生界面预览在桌面为三列、间距 24px；600px 及以下为可横向滚动、逐项吸附的画廊，每项占宽 78%、间距 18px。

### Components

- **注册图形验证：** 原生表单内使用 84dp 高的 PNG 图片区域、12dp 圆角和明确的验证码字段；图片可点击更换，加载、失败和过期使用文字说明。图片只承担图形验证，不当作产品插画。
- **投稿与评论：** 草稿、待审核、已发布、未通过和已下架分别表达；权利复选项最小高 48dp。顶级评论保留作者、正文、时间和回复操作，自有内容提供删除确认，其他内容提供举报。新号未有可见评论时，注册首 24 小时内评论先送审，提交反馈为“评论已提交，审核后展示”；待审内容不显示为已公开成功。已公开评论删除后显示“评论已删除”，从未公开的待审内容删除不生成公开占位。消息目标已删除、隐藏或下架时明确不可用。消息未读数、逐条阅读与“全部已读”使用同一服务端状态。
- **更新面板：** 25sp 标题、48dp 高的渠道入口、24dp 圆角版本卡；下载主操作高 50dp，取消操作高 48dp。检查、下载、校验、完成和错误有独立文字及进度，下载进度原位更新，不重建相机页面。安装前的任务阻拦、断开相机确认和 Android 安装确认保持独立。
- **后台审核：** 14px 圆角列表与 18px 圆角对话框承载投稿、文件、历史修订及审核操作；评论正文保留换行并折行长文本。待审评论提供“通过审核”“不予展示”，分别进入现有 restore／hide 操作和明确确认；已可见／隐藏评论使用隐藏／恢复。状态及处理说明配文字，风控规则保存成功用成功色，错误用错误色；规则变更审计显示前后值。键盘焦点为 3px 操作色外框。
- **版本与下载：** 后台版本表与上传面板使用 20px 圆角，详情对话框为 24px，包名、哈希和证书长串可折行。发布有二次确认，草稿、已上架与已撤回使用真实状态。公网下载页复用 Web 语义色，54px 高胶囊主按钮、明确正式／测试标签、最低 Android 版本、大小和更新说明；校验信息收在可展开区，二维码指向当前渠道的下载页。三张界面预览来自 `community-native/final/light/` 的真实 Java Views QA 截图，分别说明交流、投稿和消息，明确注明“截图内容为演示数据”；保留图片替代文字及各自说明，不将演示评论当作真实用户内容。下载页保留浅深色、键盘焦点、减少动效和高对比偏好。

### Do's and Don'ts

- **Do** 区分游客浏览、登录后投稿／交流、审核通过和公开下载；用作者及来源标签说明官方精选与用户分享。
- **Do** 分开表达下载完成、安装包校验完成、管理员上架和用户确认安装；相机任务进行中有清楚的继续条件。
- **Don't** 将本地合成投稿、评论、账号或发布状态用作真实生产内容或用户手机升级证据。
- **Don't** 将图形验证码写成商业级机器人防护或绝对防刷，也不把截图复核推广为 TalkBack、相机兼容性、下载恢复或安装实测。

独立 UI 复核的 **SHIP 仅限审阅的九张截图**。[Web 操作记录](.impeccable/review/releases-community-ui-qa.json)使用隔离 localhost、内存记录与真实既有 APK 元数据；其中早期测试账号名称不是当前版本管理权限规则。原生候选 `ee597f811e370e42e71e9af5faeca6fc1edbca191a7b0799106c72cbd8308963` 的 [final 证据目录](.impeccable/review/community-native/final/)包含浅色、深色、深色横屏各 41 项合成界面检查，以及独立真实公网验证码 GET／PNG 显示 11 项，SHA 与检查范围不改写为后续包。

最终 55 / `0.10.1-beta` 已发布至 beta，3,257,885 字节、SHA-256 `81021bfc4d7468dd8181d899f9ae5f4a260fbf30b95ac0eefc2be18ffaf9cca6`。新号首评送审及 Android 反馈已实施，独立 [真实更新验收](.impeccable/review/update-native/README.md)覆盖隔离新模拟器 5562 的取消／强停恢复、校验、未知来源授权、系统安装器和正常 Play Protect 扫描后升级至公开 55，并核对包哈希及保留自有私有标记；该证据不由旧截图推断，不涉及用户手机或相机。新增下载画廊的 [生产页面检查](.impeccable/review/download-final/report.json)为游客 GET，覆盖桌面、手机浅深色、三张预览、公开 55 及无页面溢出；不扩展原九图 SHIP。当前网址是 CloudBase 测试域名，首次浏览器访问可能有平台确认，正式商业域名未配置。完整流程、限制、基线来源及证据分类见 [社区与更新说明](docs/community-and-updates.md)。

## Native Android controls · 146（原生控件范围复核通过）

本附录仅记录 146 共享原生控件的已验证实施，不改写前言 tokens、既有配色、历史版本元数据或 Web 规范。[原生控件表面](.impeccable/surfaces/native-controls.md)、[146 实施与证据](docs/native-ui146.md)、[验证](docs/validation/native-ui146/validation.json)及[最终复核](.impeccable/review/native-ui146/review.md)记录范围。146 本轮完整范围复核为 **SHIP**，无实质修改项，25 张必要截图均有效。

**保留原生契约。** AppDialog.Builder 创建真实 Android AlertDialog；附着后的样式装饰保留调用方的按钮回调、选择适配器、取消规则和 OnShow 输入校验。共享弹窗采用 16sp 标题、14sp 正文／选择文字、13sp 操作文字、至少 48dp 操作目标、24dp 卡面圆角和最大 520dp 宽度；长标签或三按钮组纵向排列，操作保持平面 Ripple。

**边界与标记各留一层。** 裸表单使用 12dp 外侧留白，已有自定义输入内距保持原样；标题与正文均衡折行。选择行保留一个指示标记，直接 RadioButton／CheckBox 图形采用对称 8dp 间距。删除／清空操作使用卡面上的错误色文字与描边，浅色组合约 6.1:1；普通主操作保持柔和底色。

**从绘制窗口取主题。** 浅深色主题为原生按钮、输入、菜单、Spinner、勾选／单选／开关、滑杆和进度提供默认样式；UiPalette.forTheme 尊重编辑器包装上下文的明暗角色。现有 UiPalette 色值不变，不建立第二套配色。PhotoEditorTypography 复用共享 builder／样式。SkinTonePicker 名称输入与弹窗同用 AppThemeDark；实际生产视图在两种应用主题下打开后取消，验证深色输入角色，不执行色卡保存。更新提示版本字号收至 18sp，原有强制更新回调与不可取消规则保留。

**只装饰应用拥有的界面。** 三处前台 Toast 调用迁移至 AppNotice：13sp 短文、16dp 圆角、边界与顶部安全区留白。后台服务 Toast、系统权限、外部文件选择与 Android 安装器沿用平台界面。相册来源保持用户确认的四字标签 应用相册 / 手机相册；部分授权在既有计数区显示“已授权 · 共 x 张”。内部枚举、偏好键和存储路径保持既有身份。

当前同包原生七配置各 33 次检查，共 231 次重复断言执行；另有 52 次导出回归并实际发布两个独立 JPEG，以及 45 次保存版本选择回归且不新增导出。三个测试范围分别记录，四档编码未重跑。真实相册／分类／名称输入视图与其他组件夹具分别限定证据；强制更新夹具不认证真实 OTA、下载或安装。源码审计数量不等于运行场景数。不认证实体设备、TalkBack、相机／RAW、传输、旧系统或性能。微信停留在认证界面，文件传输助手交付待用户进入微信后进行，尚未发送。

## Advanced export settings · 147

### Overview

本附录仅记录 147 导出更多设置的局部整理。沿用现有原生摄影界面，不改写全局 tokens、侧车、历史元数据或既有世界。[实施与证据](docs/export-settings147.md)、[表面契约](.impeccable/surfaces/photo-filter-editor.md)及[复核材料](.impeccable/review/export-settings147/)限定范围。

### Colors

导出页继续由 UiPalette 的 surface、container、card、text、secondary 与 primaryContainer／onPrimaryContainer 提供浅深色角色。正文卡组和原始文件的柔和底色区分信息层级，主导出保持既有动作色；不建立新色值或固定深色导出页。

### Typography

使用系统 sp 字体，沿用 18sp 页面标题、14sp 文件摘要与主操作、12–13sp 说明／格式文字；单张成品尺寸收为 20sp。原始文件格式名紧凑单行，完整含义由分区说明与无障碍名称承载。原始文件标题／说明、自定义质量标签／输入在各自行中垂直居中。

### Layout

**The One Export Rail Rule.** 高级导出滚动正文与固定底部动作共享最大 680dp 轨道，保留系统安全区。尺寸、格式及质量同组，副本选项另组；短横屏仍可滚动查看全部设置。

### Elevation & Depth

以既有卡面和柔和底色建立层级，按钮保持平面 Ripple，不继承原生按钮阴影。

### Shapes

设置卡组沿用 16dp 圆角；原始文件按钮沿用 12dp 圆角。两种格式均可用时等宽排列，中间留 8dp 间距。

### Components

**The Primary Footer Rule.** 固定底栏仅放 52dp 编辑成品导出主操作。JPEG／NEF 原始文件动作放入滚动正文的“原始文件”区，标明“不应用编辑”，采用至少 48dp 的格式下载按钮和现有 AppIcon。常规快捷保存的“更多设置”采用柔和底色与箭头，紧凑横屏保留标题行入口。按钮样式不改变 PHONE_ALBUM、默认新副本、显式复用、原始文件确认／哈希或回调身份。

### Do's and Don'ts

- **Do** 将成品导出与原始文件下载以位置、层级和说明区分，并保留各自真实动作与完整无障碍名称。
- **Do** 让正文与主操作在宽屏使用同一内容轨道，在短屏保留滚动与可达主操作。
- **Don't** 将修正前首候选的验证次数、夹具回调或历史评分当作最终包／实际原始文件存储验收。

147 最终本地包 SHA-256 为 `efb8ee80416a36af4c0f2d91c0ea0bb48953965b6959ab55bded78604d5a24c7`（33,589,719 字节），构建及 v2／v3 签名验证通过。[最终矩阵](docs/validation/export-settings147/validation.json)手机 76 次，其余六配置各 69 次，共 490 次重复断言执行全部 PASS；29 张最终必要截图经重新打开全部有效。实际生成两个独立、已完成的 2400×1600 MediaStore JPEG 且源哈希不变。[最终修正复核](.impeccable/review/export-settings147/review.md)为 **SHIP**：M1／M2 均 resolved，未观察到直接回归，remaining clear，最终 APK 哈希已核对；verdict-pass 仅对这两项对齐修正评分，不构成整个表面或全应用批准，不借用首候选次数或历史 SHIP。JPEG／NEF 原始文件夹具只分发回调，未实际存储原始文件；四档编码未重跑。不认证实体设备、相机／RAW、TalkBack、OTA、旧系统或性能。仅本地交付，未上传、发布或 Git 提交／推送；微信仍待手动认证，未发送文件。

## Only new gallery copies · 148

### Overview

本附录记录“导出只能是另存新副本”的局部原生精简，取代 145–147 中“默认新副本、允许显式复用”的规则。保留已建立的摄影界面与历史记录，只追加当前行为；不重新生成全局 tokens 或侧车。[实施与证据](docs/export-new-copy148.md)及[表面契约](.impeccable/surfaces/photo-filter-editor.md)限定范围。

### Colors

沿用 UiPalette 的浅深色表面、文字与柔和动作色角色，不增加颜色或替代信息卡。

### Typography

沿用 147 的系统 sp 层级：页面标题、摘要、尺寸、细节与主操作保持各自原有角色。删除控件后不以新说明文字填补空位。

### Layout

保留正文与固定主操作共用的 680dp 内容轨道、安全区与滚动行为。移除保存方式整组后，尺寸／格式／质量直接接后续预览及原始文件区；固定底栏仍只放成品导出主操作。

### Elevation & Depth

继续使用既有卡面层级与平面 Ripple，不增加按钮阴影。

### Shapes

设置卡、格式按钮、固定主操作的既有圆角与触控尺寸保持不变。

### Components

**The Fresh Export Is a New Copy Rule.** 每次新发起的快捷／高级、单张／批量、保存版本／当前编辑导出都请求手机相册新副本。界面不再显示保存方式、额外副本勾选、复用结果入口或已保存文件可用性等待。选择的文件与编辑身份、预览、校验、命名和队列仍使用既有流程。

**Keep Retry Identity.** 新请求创建新副本，同一失败任务沿用冻结回执及 publicationCompleted 逻辑，避免对该任务已完成项目重复发布。JPEG 原始文件确认／源哈希校验与 NEF 回调继续保留；相机接收保存位置流程不由此改变。

### Do's and Don'ts

- **Do** 保留“原始文件／不应用编辑”与紧凑 JPEG／NEF 格式按钮，区分原始文件和编辑成品。
- **Do** 删除失去意义的整组设置，让原有内容自然上移。
- **Don't** 从“新副本”推导为重试已完成项目时再次发布，也不以旧版本可选复用规则覆盖本轮明确政策。

148 本地冻结包为 33,585,623 字节、SHA-256 `322c145964cbad9102172fc607f0f6c2a7ac2defbfaf69689aa2b792d5c6dd05`，构建、v2／v3 签名及已安装哈希核对通过。[七配置矩阵](docs/validation/export-new-copy148/validation.json)共 506 次重复断言执行全部 PASS；实际重复单张及三张批量导出生成八个独立、已完成的 2400×1600 MediaStore JPEG，三个源哈希不变。同包保存版本选择回归另行通过 45 次检查且不新增导出。[最终独立复核](.impeccable/review/export-new-copy148/review.md)为 **SHIP**，九张必要截图全部有效，没有实质修改项；完整覆盖 148 的控件移除、新副本政策及直接相关布局，当前 PRODUCT、DESIGN 附录与表面契约一致，不构成全应用或硬件认证。原始文件夹具仅分发回调，四档编码未重跑。不认证实体设备、相机／RAW、TalkBack、OTA、旧系统或性能；仅本地交付，未上传、发布、提交／推送，微信仍待认证且未发送文件。

## Editor selection and source gestures appendix (149 / 0.28.12-beta)

本附录只记录导出命名、人像参数所有权与顶部来源手势的原生 Operate 精修。沿用 adaptive UiPalette、石墨／桃色摄影工作区、系统 sp 层级、既有材料与 Ripple；不重新生成全局 tokens 或侧车。[实施与证据](docs/editor-selection149.md)及[表面契约](.impeccable/surfaces/photo-filter-editor.md)限定本轮范围，历史验证按所属版本保留。

**The Control Has an Owner Rule.** 人像主强度条只有在对应工具真实选中时显示。原始肤色和无参数状态隐藏整行并收回 48dp；面部保留默认选中的“提亮”项，自然精修在既有皮肤横向轨中有选中项，精确光照轴也显式选中。画笔／祛痘大小条仍属于当前工具，预览、提交／取消与渲染链路保持原样。

编辑页初次与动态刷新统一使用“导出／导出中…”，快捷对话框使用“导出照片／导出到手机相册”，图标及无障碍描述同步。148 的每次新导出产生手机相册新副本与同一失败任务身份规则继续有效。

149 历史来源动效记录（“即时更新、无横向动效”已由下方 150 附录取代，手势与输入边界保留）：左右手势仅补充在线预设／我的预设、相机照片／边拍边传／已下载、应用相册／手机相册的既有点击入口。完成一次横向手势只切换相邻一项，边界不循环；同根页面仍通过 PageTransitions.cancel 即时更新，不加入横向页面动效。横向轨、输入框、滑杆、纵向滚动和多指输入保留边界；选择／导入、编辑／详情及 RAW 工作区不切来源。在线风格分类、设置和底部根导航没有新增此行为。

149 冻结 APK 为 33,589,719 字节、SHA-256 `ebd82fef4eb7db6319457d119ee6ec065a04026d70a1b45f1da696f8b2dfb4d6`，构建、v2／v3 签名及安装哈希一致。[七配置矩阵](docs/validation/editor-selection149/validation.json)各 38 次检查，共 266 次重复断言执行全部 PASS；同一产品 APK 的前六配置／平板横屏探针夹具代次分别记录，最后一项只修正夹具宽度。[最终独立复核](.impeccable/review/editor-selection149/review.md)为 **SHIP**，[21 张必要截图](.impeccable/review/editor-selection149/required-captures.json)全部打开且有效，无实质修改项，TYPE／MATERIAL／GROUND 与现有工作区一致；结论仅覆盖本轮三项改动及直接相关回归。自有 Pixel 9 API 37.2 上验证实际来源手势与编辑／导出入口；人像仅用生产对话框和合成蒙版／手动人脸／不执行处理 Renderer 验证状态，自然精修准备时取消，不认证完整推理或修图效果。本轮无实际 JPEG 发布、原始文件实际保存测试或四档编码；148 的八张 JPEG 保留为历史证明。无全应用、实体设备、相机／RAW、TalkBack、OTA、旧系统或性能验收；仅本地交付，未上传、发布、提交／推送或微信发文件。

## Source motion appendix (150 / 0.28.13-beta, current)

用户“要加左右滑动的过渡效果，太生硬了”仅取代上述三组顶部来源在 149 的即时／无横向位移规则。保留既有 native Operate 世界、UiPalette、系统 sp 层级、静止几何和材料；不新增全局 tokens、侧车 schema 或持久图片。[实施与证据](docs/source-motion150.md)、[方向契约](.impeccable/review/source-motion150/contract.md)限定范围。

**The Fixed Context Rule.** 标题、来源条、预设浮动按钮及根导航／展开导航栏保持固定；来源条下方内容跟手，阻力 0.65，位移上限为视口宽度的 0.35。完成手势仍只切相邻一项且不循环；点击按来源索引决定方向，跨项点击直接到目标而不激活中间来源。完成过渡为 240ms、回位为 170ms，缓动为 `[0.22, 1, 0.36, 1]`。系统禁用动画时来源切换无空间位移。

**The Moving Body Owns Touch Rule.** 画布移动时正文点击由容器拦截，固定来源条保持可点；横向轨、输入框／滑杆、纵向与多指输入以及选择／导入、编辑／详情／RAW 门禁继承 149。支持快速反向、缓存／重建根视图交接；离开页面、来源上下文禁用或视口改变时清理。仅暂存一张最多 2MP 的出场 UI 位图，中断重截合成画面时短暂与旧图重叠，随后回收；不逐帧截图、不用于照片处理。风格分类、设置与根导航没有新增滑动，导出和人像规则保留原版本归属。

[最终独立复核](.impeccable/review/source-motion150/review.md)为限定范围 **SHIP**，25 张必要原生截图有效且哈希匹配，无实质修改项。[验证](docs/validation/source-motion150/validation.json)为 phone 70、六种其他配置各 16、关闭动画 9，共 175 次动效重复断言；另有未改编辑器探针的 phone 38 次直接回归，合计 213 次。其他配置只覆盖三组来源截图及实际正文点击夹具，未重复完整 70 项。中间截图暂停实际动画并等待渲染，不能认证 FPS／触感；证据仅来自 Pixel 9 API 37.2 模拟器，不扩大为全应用、硬件、完整人像处理或实际公共 JPEG 导出验收。149 及更早冻结记录保持其版本边界。
