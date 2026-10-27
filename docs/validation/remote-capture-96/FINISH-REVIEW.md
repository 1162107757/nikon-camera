# 96 独立完成审核

本次重新完整审核三个用户请求及其直接路径：遥控身份误判、编辑器四小方块居中、保存设置收纳。用户在 95 交付后的两张实机截图是本轮问题依据；本结论不继承 95 的 ship，也不是旧候选的 verdict 续审。

## persistence

**clear。** 方向继续继承根 PRODUCT.md／DESIGN.md、95 局部 DESIGN.md 与原型实施约定。用户新指令明确覆盖原型中的底部保存行：保存位置和传入选择收进齿轮，齿轮在直方图左侧。无需新视觉方向或单独 QUALITY BAR 卡。

本结论只绑定 96／0.20.1-beta，APK SHA-256 `2bcb395db84af40a0f6732078fa7ab5707fc93dbd43c2a1794d3420f9a7f0c8e`，3,950,714 字节。独立重算 APK 和 CANDIDATE-IDENTITY.json 的 214 项生产输入，哈希及字节数全部一致，无输入漂移。相对 95 的六个变更输入为版本、PtpDeviceInfo、PtpIpClient、NikonRemoteCamera、PhotoFilterEditor、RemoteCaptureView；没有新增生产栅格。追加需求前的 `8e61d0e0` 及故意失败的旧 95 `cb4d685b` 均不计为本次最终通过证据。

## fidelity

**clear，限定如下证据范围。** 已打开对照用户两张原图：遥控页确实出现“当前相机未开放尼康遥控会话”，编辑器红圈确实针对“查看全部滤镜”按钮。已逐张打开以下当前候选的全部 14 张 required 截图；文件内容、方向和命名一致，无空白、黑屏、错误页面或未完成的捕获。

| 配置／vendor ID | 逐张检查的截图 | 可见结果 |
| --- | --- | --- |
| phone／4294967295 | [ready](2bcb395d/phone-vendor4294967295-fd075da8/run/ready.png)、[options](2bcb395d/phone-vendor4294967295-fd075da8/run/options.png)、[editor-grid](2bcb395d/phone-vendor4294967295-fd075da8/run/editor-grid.png) | 就绪；齿轮和保存设置位置正确；四小方块居中 |
| font1.3／4294967295 | [ready](2bcb395d/font1.3-vendor4294967295-9184995a/run/ready.png)、[options](2bcb395d/font1.3-vendor4294967295-9184995a/run/options.png)、[editor-grid](2bcb395d/font1.3-vendor4294967295-9184995a/run/editor-grid.png) | 放大文字可读；保存位置与传入说明未裁切；图标保持居中 |
| landscape／4294967295 | [ready](2bcb395d/landscape-vendor4294967295-713f8186/run/ready.png)、[options](2bcb395d/landscape-vendor4294967295-713f8186/run/options.png)、[editor-grid](2bcb395d/landscape-vendor4294967295-713f8186/run/editor-grid.png) | 横屏正确；齿轮在直方图左侧；保存设置位于可滚动面板顶部；图标居中 |
| dark／4294967295 | [ready](2bcb395d/dark-vendor4294967295-4a1a324c/run/ready.png)、[options](2bcb395d/dark-vendor4294967295-4a1a324c/run/options.png)、[editor-grid](2bcb395d/dark-vendor4294967295-4a1a324c/run/editor-grid.png) | 深色下新增入口、保存信息与原图标均清楚 |
| phone／6 | [ready](2bcb395d/phone-vendor6-0f75da2a/run/ready.png) | 已连接，可以拍摄 |
| phone／10 | [ready](2bcb395d/phone-vendor10-9074e96f/run/ready.png) | 已连接，可以拍摄 |

1. **遥控身份路径：符合本轮修复。** 两处 gate 共享 `isNikonCamera()`，要求制造商为 NIKON 或以 `NIKON ` 为边界开头，并接受扩展 ID 10、6、`0xffffffffL`；原始字段没有改写。NikonRemoteCamera 仍按实际广告操作分别授予取景、快门和对焦能力。已查阅旧逻辑拒绝与修复后 44 项核心／5035 项传输检查记录；当前六次原生运行均 PASS，包含通用接口拒绝、撤销权限和就绪路径。六张 ready 显示的是夹具的成功连接，不能据此反推用户相机的 DeviceInfo。
2. **四小方块：符合本轮修复。** 当前生产 createDock 清除左 compound drawable，以 LayerDrawable 的 Gravity.CENTER 放置同一 19dp AppIcon，保持 48dp 触点和原底形。四张当前组件截图可见居中，六份当前 report 的 LTR／RTL 白色字形边界偏移均为 `[0,0]`。测量取真实已布局按钮的绘制像素，相对按钮中心计算；旧 95 在新增偏移断言上失败，避免用原错误作通过基线。
3. **保存设置收纳：符合新增指令。** ready 图中底部保存行消失，参数、状态和快门保留，右上重复三点移除；22dp 齿轮在直方图左侧，仍为 48dp 触点。options 将“照片保存位置／相机存储卡”和“拍后传入 App”排在顶部，并说明“照片仍保存在相机，JPEG 另传入 App”。字号 1.3 的说明能自然换行；横屏面板允许滚动。已核对六份报告及探针的真实控件点击：开关开启更新既有控制器，关闭并重新打开面板后仍选中，再次点击可关闭；没有把收纳变成新的保存策略。

## ceiling

这是当前 `2bcb395d` 的一次完整独立 finish review，覆盖本轮三个请求与直接回归。旧 `8e61d0e0` 审核被新增需求中断，未写出 ship。本轮没有另起视觉方向，也没有重开全 App 或遥控／编辑器所有状态的审计。Android Views／Canvas 不适用 HTML／CSS detector；已使用 craft-floor 和 Android 原生要求判断本轮布局及控件。

UI-MATRIX 的 622 是六次配置运行中的检查执行次数（103／103／107／103／103／103），不是 622 个独立场景。全部 79 张当前截图保留为辅助证据，本审核逐张检查的是上述 14 张 required，不声称逐张审核全部 79 张。六份 report 均为 PASS、当前 APK SHA 一致、方向正确且 fixtureCleanup 为 true。

证据来自自有 Pixel_9 模拟器与内存 PTP/IP 字节夹具。editor-grid 是真实生产 PhotoFilterEditor.createDock 装入原生 Dialog 的组件证据，没有绑定用户照片；背后的遥控画面和空缩略图符合这一测试容器用途，不是完整照片编辑流程截图。相机画面是既有合成样片，不是实际 Nikon／Wi-Fi 联调。用户实际 DeviceInfo、用户手机上的完整照片编辑路径、真实相机固件行为仍未实测。本结论允许交付这一局部软件修复供用户验证，不能表述为“用户相机已恢复”或全 App 认证。

## material_fixes

**无本轮未解决的 material fix。** 在有效证据覆盖的三个请求与直接路径内，没有需要追加代码修正、重建或重新捕获的项。

**disposition: ship**

ship 的范围为当前 APK 的身份兼容修复、原生图标居中和保存设置收纳；实际用户相机恢复需由真实设备结果确认。

## keep

- 保留当前小图标、近黑工作区、桃色主快门、完整比例取景及原生 48dp 命中区。
- 保留制造商边界、原始无符号 vendor 字段、广告能力检查、接口权限与明确拒绝；身份兼容不应绕开能力检查。
- 保留齿轮中的只读相机存储位置和可选 JPEG 传入语义，以及现有设置的开关状态和滚动行为。
- 保留编辑器原 19dp 图标、底形、分类位置和点击行为；组件居中结论不扩展为其他编辑器行为已重新验收。
- 保留新旧候选、故意失败的回归证据和来源说明，交付时继续区分模拟器、组件、夹具与用户实机结果。
