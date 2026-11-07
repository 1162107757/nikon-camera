# 顶部来源切换过渡 · 150 / 0.28.13-beta

用户提出“要加左右滑动的过渡效果，太生硬了”。150 仅取代 149 对以下三个顶部来源选择器的“即时切换、无横向位移”规则：在线预设／我的预设、相机照片／边拍边传／已下载、应用相册／手机相册。149 的来源手势与输入边界继续生效；导出命名、人像参数所有权和 148 的新副本导出政策保持各自版本的规则与证据。

## 实现

- 来源条下方内容跟手移动，阻力为 0.65，位移最多为视口宽度的 0.35；完成手势只切换相邻一项，边界不循环。短拖或取消以 170ms 回位；确认切换以 240ms 完成横向过渡，缓动为 `[0.22, 1, 0.36, 1]`。
- 点击按来源索引决定方向，直接点击非相邻来源只调用目标处理器，不经过中间来源。保留既有加载、权限、缓存、滚动、选择和导入逻辑；标题、来源条、预设浮动按钮、底部导航及展开导航栏保持固定，静止后的几何、字体与颜色沿用现有原生界面。
- `SubcategorySwipeLayout.changeSource` 包装三个页面的既有来源处理器；`MainActivity`、`AlbumPanel`、`LocalAlbumPanel` 接入内容锚点。支持快速反向操作及缓存／重建根视图交接；离开页面、来源上下文禁用或视口变化会结束过渡并清理状态。`PageTransitions` 本身未改。
- 过渡保留一张最多 2,000,000 像素的临时出场 UI 位图；中断时先截取当前合成画面再回收旧图，存在短暂重叠。没有逐帧截图、持久资源或照片处理；完成／取消后回收。画布移动期间拦截正文点击，防止旧命中区域触发操作，固定来源条仍可点击。
- 系统禁用 `ValueAnimator` 时来源仍可切换，拖动和切换均无空间位移。横向轨、输入框／滑杆、纵向与多指输入保留所有权；选择／导入、编辑／详情／RAW 等既有门禁保留。风格分类、设置和根导航没有新增左右滑动。

## 冻结交付身份

| 项目 | 结果 |
| --- | --- |
| 本地 APK | [huevia-0.28.13-beta-debug.apk](../dist/huevia-0.28.13-beta-debug.apk) |
| 版本 | versionCode `150`，versionName `0.28.13-beta` |
| 大小 | `33,593,815` 字节 |
| APK SHA-256 | `462e6710f2e324ce97188602013a35516797e6267316b85091cabf19ce63f782` |
| 构建／签名／安装 | 构建通过，v2／v3 校验通过，安装包哈希一致 |
| 最终来源动效探针 SHA-256 | `cc25dd33b3e524382ae6d3ebe08a0b5b421bdf84a1cb5c84629014c8cd24a3a5` |

本轮产品交互代码只涉及上述四个 Java 文件，另有应用版本和探针 manifest 元数据、新增动效探针与运行脚本。`PhotoExportDialog`、`PhotoVersionExport`、`PhotoPortraitDialog`、`PageTransitions` 保持 149 代码。冻结的 308 项来源／测试哈希复核无漂移。

## 证据与复核

[方向契约](../.impeccable/review/source-motion150/contract.md)、[汇总验证](validation/source-motion150/validation.json)与[最终独立复核](../.impeccable/review/source-motion150/review.md)为本轮权威记录。复核结论为 **SHIP**，无实质修改项；[25 张必要原始原生 PNG](../.impeccable/review/source-motion150/required-captures.json)均逐张打开、有效且哈希匹配。范围仅为这三个来源选择器及直接相关回归。

| 验证 | 重复断言执行数 | 覆盖 |
| --- | ---: | --- |
| [phone](validation/source-motion150/phone.json) | 70 | 完整来源动效、跟手／回位／反向／交接／清理及实际正文点击命中保护 |
| [font](validation/source-motion150/font.json)、[narrow](validation/source-motion150/narrow.json)、[dark](validation/source-motion150/dark.json)、[tablet](validation/source-motion150/tablet.json)、[compact](validation/source-motion150/compact.json)、[tablet-landscape](validation/source-motion150/tablet-landscape.json) | 各 16，共 96 | 各三组来源原生动效截图及实际正文点击夹具；没有重复完整 70 项 |
| [reduced](validation/source-motion150/reduced.json) | 9 | 系统动画缩放为零，来源可切换且无空间位移 |
| [未改 EditorInteractionProbe 的 phone 回归](validation/source-motion150/regression-phone.json) | 38 | 横向轨／滑杆／纵向输入所有权，来源边界与选择／编辑排除，149 导出文案和人像选中状态 |

八种动效模式均 PASS，共 175 次重复断言执行；加直接回归为 213 次，不能视作 213 个独立场景。截图捕获会暂停实际原生动画到观察到的中间进度、请求重绘并等待 100ms 渲染排空，用于核对位移与布局，不证明帧率或触感。早期诊断 APK、探针和截图代次均排除在最终验收计数之外。

## 边界与交付状态

证据来自自有 Pixel 9 API 37.2 模拟器；大字体、窄屏、暗色、紧凑和平板纵横屏均为同机配置模拟。模拟器已按硬件守卫重置并关闭，未触碰实体设备。人像直接回归使用合成蒙版／手动人脸／不执行处理的 Renderer，只验证状态；没有完整人像处理、实际公共 JPEG 导出、相机／RAW、实体手机／平板、旧系统、TalkBack、OTA 或 FPS 认证。旧版导出证据保留其历史版本边界。

仅本地交付，未云端发布、Git 提交或推送。微信仍停在“进入微信”，需要用户手动认证；未发送文件。当前 computer-use 规则禁止自动操作用户认证对话框。
