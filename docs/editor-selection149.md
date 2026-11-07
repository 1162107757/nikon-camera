# 149 · 导出文案、人像参数与顶部来源手势

本轮按用户要求将照片编辑页右上角“保存”改为“导出”，快捷操作改为“导出到手机相册”；人像强度条只在存在明确选中参数时出现。在用户明确限定的三组顶部来源间增加左右滑动：在线预设／我的预设、相机照片／边拍边传／已下载、应用相册／手机相册。在线预设的风格分类不属于本轮切换范围。

这是现有原生摄影工作区内的 Operate 精修。保留 adaptive UiPalette、石墨／桃色工作区、系统 sp 字体、原生 Views、AppIcon 和 Ripple，没有新增视觉世界、生产图片或全局 tokens。[方向契约](../.impeccable/review/editor-selection149/contract.md)限定本轮行为与验收范围。

## 已实施

- 编辑页初次构建和后续状态刷新统一使用“导出”；进行中使用“导出中…”，空闲下载图标和“导出当前编辑效果到手机相册”无障碍描述同步。快捷对话框标题为“导出照片”，关闭按钮描述为“取消导出，返回照片”，主操作为“导出到手机相册”。
- 人像主强度行以真实工具选中状态为显示条件。原始肤色和无参数选择时隐藏整行，并让控制区收回 48dp；面部默认选中第一项“提亮”参数。自然精修在现有皮肤横向工具轨中拥有明确选中项，光照精确横／纵轴按钮也记录选中状态。画笔／祛痘大小条仍归属于当前工具。
- 新增 `SubcategorySwipeLayout`，完成横向手势后调用已有来源处理函数，一次切换相邻一项，边界不循环。它不拖动页面；同一根页面中的切换继续走 `PageTransitions.cancel`，保持即时更新。
- 横向工具轨、输入框与滑杆保留横向输入；纵向滚动、小幅位移和多指手势不切换来源。照片选择／导入锁定、沉浸编辑／详情及 RAW 工作区保持原有手势边界。设置页没有新增来源标签，底部根导航没有新增左右滑动。

实现依据：[MainActivity.java](../app/src/main/java/cc/huevia/MainActivity.java)、[SubcategorySwipeLayout.java](../app/src/main/java/cc/huevia/ui/SubcategorySwipeLayout.java)、[LocalAlbumPanel.java](../app/src/main/java/cc/huevia/ui/LocalAlbumPanel.java)、[AlbumPanel.java](../app/src/main/java/cc/huevia/ui/AlbumPanel.java)、[PhotoPortraitDialog.java](../app/src/main/java/cc/huevia/ui/PhotoPortraitDialog.java)、[PhotoQuickSaveDialog.java](../app/src/main/java/cc/huevia/ui/PhotoQuickSaveDialog.java)。

## 保留的行为边界

来源点击处理函数继续拥有切换、加载、权限和锁定逻辑。手势只是既有入口的另一种触发方式，不修改在线风格分类、相机连接或照片接收规则。人像预览、提交／取消、模型和渲染链路不由本轮改写。

148 的每次新导出生成手机相册新副本政策继续有效；同一失败任务仍保留冻结身份与完成回执。保存版本／明确当前编辑的源身份、预览对应、命名、账户校验，以及 JPEG 原始文件确认／源哈希检查和 NEF 回调均保留。148 的八张实际 JPEG 证明仅属于历史版本，本轮不据此声称重新导出验证。

## 冻结安装包

- 文件：[huevia-0.28.12-beta-debug.apk](../dist/huevia-0.28.12-beta-debug.apk)
- `versionCode`：149；`versionName`：`0.28.12-beta`
- 大小：33,589,719 字节
- SHA-256：`ebd82fef4eb7db6319457d119ee6ec065a04026d70a1b45f1da696f8b2dfb4d6`
- 构建、APK v2／v3 签名验证通过；模拟器已安装 APK 哈希与冻结包一致。

## 验证与复核

最终包汇总为 [validation.json](validation/editor-selection149/validation.json)，各配置报告保留在同目录；原生记录位于 [.tooling/editor-selection149/native/](../.tooling/editor-selection149/native/)，身份与早期诊断位于 [.tooling/editor-selection149/](../.tooling/editor-selection149/)。

| 最终包配置 | 重复断言执行 | 结果 |
| --- | ---: | --- |
| 手机 | 38 | PASS |
| 字号 1.3 | 38 | PASS |
| 320dp 窄屏 | 38 | PASS |
| 深色 | 38 | PASS |
| 紧凑横屏 | 38 | PASS |
| 平板竖屏 | 38 | PASS |
| 平板横屏 | 38 | PASS |
| 合计 | 266 | 七配置全部 PASS |

266 是同组检查跨配置的重复断言执行，不能称为 266 个独立场景。七配置均使用上述同一产品 APK；前六配置与平板横屏的探针夹具代次分别记录。[21 张必要截图清单](../.impeccable/review/editor-selection149/required-captures.json)包含手机九张及其余六配置各两张导出／自然精修状态。[最终独立复核](../.impeccable/review/editor-selection149/review.md)为 **SHIP**：21 张必要截图全部打开并判定有效，无实质修改项，TYPE／MATERIAL／GROUND 与现有工作区一致。该结论仅覆盖本轮导出命名、人像参数所有权、三组来源手势及直接相关回归，不构成全应用、完整人像处理或硬件验收。

验证使用自有 Pixel 9、API 37.2 模拟器，包含实际注入的来源手势和编辑／快捷导出入口。人像状态使用隔离生产 `PhotoPortraitDialog`，配合合成皮肤蒙版、手动人脸和不执行处理的 Renderer；自然精修在准备阶段验证选中状态后取消。这证明控件所有权与显示／布局状态，不构成完整人像推理或修图效果验收。字号及窄屏／紧凑／平板形态均在同一模拟器上调整，不能推广为实体设备证明。

首个 f099 候选把带 padding 的纵向列表误识别为横向滚动内容，导致手势未切换；最终实现收窄为实际横向输入控件，初始失败与 trace 保留。横向轨测试夹具另行设置最小宽度以形成真实横向滚动范围；平板横屏的 2512px 轨道宽于此前固定 2400px 的子内容，因此该配置只重跑夹具修正后的相同检查，产品 APK 不变。首六配置的探针 APK／源码归档为 `probe-six-modes.apk`／`probe-six-modes.java`，最后配置的夹具代次分开记录。这些夹具修正不属于产品缺陷。

本轮没有实际 JPEG 发布、原始文件实际保存测试或四档编码重跑。无实体相机／设备、RAW、TalkBack、真实 OTA、旧系统或性能验收。仅本地交付；未上传、未发布更新通道、未 Git 提交或推送。微信仍待手动进入认证，未发送文件。
