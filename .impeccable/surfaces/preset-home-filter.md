# 预设首页筛选 · 182

## 范围与权威

这是 Huevia 既有纸白四首页世界中的 Android Java / Views **Operate** 表面：从预设首页选择条件，查看匹配预设。产品身份及全局材料仍由 [PRODUCT.md](../../PRODUCT.md) 和 [DESIGN.md](../../DESIGN.md) 承载；本 brief 只记录 182 / `0.30.28-beta` 已构建的局部扩展，不更新全局 tokens 或设计 sidecar。

用户批准 [B 版玻璃底部浮层](../../docs/design-review/preset-home-filter-20261109/B-glass-bottom-sheet.png)，随后明确增加“预设类型：全部 / NCP / NP3”，覆盖提案原先不含类型组的边界。实际尺寸、状态与响应行为以冻结的 [PresetFilterSheet.java](../../.tooling/preset-filter182/final-source/app/src/main/java/cc/huevia/ui/PresetFilterSheet.java)、[PresetHomeFilter.java](../../.tooling/preset-filter182/final-source/app/src/main/java/cc/huevia/library/PresetHomeFilter.java)、[MainActivity.java](../../.tooling/preset-filter182/final-source/app/src/main/java/cc/huevia/MainActivity.java) 及沿用的 [UiPalette.java](../../app/src/main/java/cc/huevia/ui/UiPalette.java) 为准；后续任务的 live source 不改变此冻结记录。

## 已构建的表达

- 首页发现色彩／计数行右侧增加 48dp 筛选入口。保留原搜索、添加、来源条、分类横轨、瀑布流及浮动导航；浮层打开时临时隐藏根导航，dismiss 后恢复。
- 复用 `UiPalette.home`：浅色暖纸表面、炭黑选中胶囊和应用操作，深色使用配对暖石墨及浅米色选中／操作。选中项同时显示勾选，完整分组及选项名称由原生辅助描述承载。
- 系统 sans-serif / sp；标题 18sp，分组和选项 12sp，底部动作 14sp。胶囊、关闭及操作保留至少 48dp 命中范围。选项最多两行，行高按实际文字测量；列数随可用宽度和系统字号缩减。
- 面板圆角 28dp，胶囊圆角 24dp；最大宽度 520dp，按系统栏／cutout 安全区约束高度。头部关闭与底部重置／应用固定，剩余高度交给有界选项滚动区，避免窄屏、大字或横屏遮挡末端操作。
- 支持时使用真实 Window 背景模糊（半径 28dp）与 83% 表面材料；模糊不可用时切换同色 99.5% 高不透明材料，抑制背景字形透出。使用 translucent、floating 原生 Dialog 窗口与系统模糊监听，不以模糊可用状态替代视觉证据。
- 不使用 `DIM_BEHIND`：保持浅色首页的深色状态图标对比度；窗口获焦后明确设置浅色深图标／深色浅图标。模态焦点与外部点击关闭仍保留。

## 条件与事务

在线来源依次提供风格、下载状态（全部／未下载／已下载）、预设类型（全部／NCP／NP3）；“我的预设”隐藏下载状态组。风格与首页分类横轨共用一个值；两来源分别保存风格和类型，在线下载条件单独保存。

面板持有独立草稿。选择和重置只改草稿，应用才提交；关闭、返回和外部点击丢弃未应用修改。已应用条件写入 `preset-home-filter-v1`，配置恢复使用 `presetHomeFilterVersion=1`；不恢复已退役格式键造成隐形过滤。

普通浏览及纯风格条件沿用服务端分页与总量。名称搜索、类型或下载条件取得完整目录元数据／既有缓存后，组合风格、类型、下载状态及名称，按完整匹配集计数，再以 20 条递增展示。完整目录未取得时显示加载或可重试错误，缓存结果明确标注，不能用第一页假装全库。

下载状态依据已提交 `PresetLibrary`，预览缓存与下载进行中不算已下载；提交或删除成功后重算。类型来自已校验的 `fileFormat` 元数据及既有二进制校验，不猜名称或 URL；旧 NCP-only schema 缺失字段沿原契约读取为 NCP，显式未知类型由原解析器拒绝，筛选模型中的未知类型只匹配“全部”。相机跨类型导入／转换未改。详细边界见 [实现约定](../../docs/validation/preset-filter182/implementation.md)。

## 冻结验证与边界

本地签名交付为 [huevia-0.30.28-beta-update.apk](../../dist/upload182/huevia-0.30.28-beta-update.apk)，SHA-256 `bb8f5c66282c9731e58b84bf7a68e3f8fa9236532003fd27de1a6a9c09518645`；精确构建／payload／签名身份以 [验证记录](../../docs/validation/preset-filter182/README.md) 为准。

- 四种原生配置：常规手机、320dp 窄屏／1.3 字体／深色／禁用模糊、深色横屏／1.3 字体、平板。各 77 项，共 308 次含重复检查；28 张 PNG 由 [matrix.json](../../docs/validation/preset-filter182/matrix.json) 与 [capture-index.json](../../docs/validation/preset-filter182/capture-index.json) 绑定最终包。
- [host.txt](../../docs/validation/preset-filter182/host.txt) 为 84 项筛选／迁移／草稿及完整目录／缓存／搜索检查；[host-camera.txt](../../docs/validation/preset-filter182/host-camera.txt) 为 323 项既有相机预设检查。[行为保留](../../docs/validation/preset-filter182/behavior-preservation.json) 记录 181 相册选择沿用，不能把它写成本轮重新认证。
- [独立最终复核](../review/preset-filter182/review.md) 的 disposition 为 **ship**，只关闭 F1 深色降级透字与 F2 浅色状态图标对比度，并检查受影响区域的直接回归；不是整表面或全应用批准。

原生证据来自模拟器、合成目录与受控预览错误态；未连接实体手机／相机，未验证线上服务端到端，也不认证 OEM 玻璃效果、实体手势体验或实际相机联动。此为本地交付，未公开发布。既有全局设计索引漂移未在本任务中修补；本轮没有新增生产 raster，也不把批准 comp 或 QA 截图当作生产材料。
