# 预设首页筛选 182 · 实现约定

用户选定 `docs/design-review/preset-home-filter-20261109/B-glass-bottom-sheet.png`，并明确新增“预设类型：全部 / NCP / NP3”；这覆盖原三版提案“没有 NCP / NP3”的旧边界。首页原有搜索／添加、来源条、分类横轨、瀑布流与悬浮导航保留，新增入口位于发现色彩／数量行右侧。

面板保存独立草稿；重置只重置草稿，应用提交，关闭、返回与点击外部丢弃选择。风格和首页分类轨共用单个值。在线来源提供三组，本地来源隐藏下载状态，两个来源的风格／类型独立保存。系统支持时使用 Window 背景模糊，失效时同色 99.5% 不透明材料，抑制高对比背景文字透出；选项可滚动，头部关闭与底部操作固定。浮动窗口获得焦点后明确设置系统栏外观，浅色使用深色状态图标，深色使用浅色图标。

背景模糊要求窗口同时为 translucent 和 floating，使用独立 Dialog 主题启用，遵循 [Android Window API](https://developer.android.com/reference/android/view/Window#setBackgroundBlurRadius(int))。系统模糊变化通过监听器切换材料，不把“模糊可用”的系统状态当成截图效果已验证。

面板采用模糊、材料与圆角分层，不使用系统 `DIM_BEHIND` 遮罩。Android 对不覆盖状态栏的 dimming 浮窗可能强制浅色状态图标，见 [AOSP DisplayPolicy](https://android.googlesource.com/platform/frameworks/base/+/master/services/core/java/com/android/server/wm/DisplayPolicy.java) 中 `addStatusBarAppearanceRegionsForDimmingWindow`；移除系统遮罩以保留首页原本的状态栏对比度，模态焦点、外部关闭与底部导航临时隐藏保持。

在线普通浏览／纯分类沿用服务端分页与服务端总量；名称搜索、类型或下载条件使用已有完整目录 API 与缓存契约，先完成完整元数据索引，再组合风格／类型／下载状态／名称并分页展示。不得用浏览第一页补作完整目录。完整目录未取得时显示加载或无法筛选，缓存结果带“缓存”标记。下载状态取已提交的 `PresetLibrary`，配方预览缓存和下载进行中不等于已下载；成功提交或删除后重新计算。

类型由 `OnlinePreset.fileFormat` / `PresetRecord.fileFormat` 决定，导入和下载继续沿用二进制容器与声明一致性校验，不使用显示名称或 URL 扩展名判断。本次不改变相机跨类型导入／转换。旧版缺失类型字段按现有 NCP-only schema 契约读取为 NCP；显式未知类型由现有解析器拒绝，在线读取失败走已标明的完整目录缓存或错误状态，不归入 NCP/NP3。筛选模型本身的未知类型只属于“全部”，不能命中显式类型。

新筛选以 `preset-home-filter-v1` 和 `presetHomeFilterVersion=1` 保存。只恢复本次版本化键，已退役 `onlinePresetFormat` 不可变为隐形过滤条件；用户本次主动应用的类型可跨重启与配置恢复。界面配置变化可重排面板，未应用草稿不会写入偏好。

本文件记录约定，不代表验证已经通过；最终构建、截图、结果与设备还原以同目录最终 README 和证据清单为准。
