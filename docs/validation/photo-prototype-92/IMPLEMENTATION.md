# 92 · 编辑器与细节页原型落地

日期：2026-10-24。**历史记录：92功能证据保留，视觉未获用户接受，不作为当前交付。** 用户随后指出警示图标贴边、比较／缩放选中面间距和圆角错误、构图按钮过大，并追加全面检查文字。此前31图复核漏检这四类问题，原限定结论不能证明最终视觉已满足。当前93候选及新验证见[93实施记录](../photo-polish-93/IMPLEMENTATION.md)与[93完成复核](../photo-polish-93/FINISH-REVIEW.md)。

用户指定 [v3 主原型](../../design-review/photo-detail-glass-redesign-20261024/prototype.html) 实现图像编辑页／查看细节，随后要求“可以先完善原型”。已先补齐本目录两套 HTML 交互，再继续此前授权的两页原生实现。导出设置／批量进度／结果汇总只完善 HTML；本轮原生仍接已有导出流程。

## 实施范围

| 位置 | 当前实际接入 |
| --- | --- |
| [AlbumPanel](../../../app/src/main/java/cc/huevia/ui/AlbumPanel.java) | 竖屏两行紧凑 chrome、照片剩余空间、左下玻璃细节入口与右下比较；横屏照片左侧和 300dp 右轨，头部移入右轨，照片操作由文件名旁下拉入口保留。真实系统栏／cutout／手势 insets 避让。 |
| [PhotoFilterEditor](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) | 同一 176×fontScale 内容容器和 48×fontScale 五工具导航；滤镜来源小分段、分类／卡片横滑、可输入真实强度；调节拆为撤销与精确值、滑杆、说明、参数条；构图先摘要再进入暂存；配方真实保存与管理。切组只切工具区。 |
| [PhotoCropDialog](../../../app/src/main/java/cc/huevia/ui/PhotoCropDialog.java) | 头部覆盖照片 stage，紧凑比例／拉直／旋转／重置与摘要；沿用实际四角、框内移动和几何运算，取消不提交、应用可撤销。 |
| [PhotoBorderPanel](../../../app/src/main/java/cc/huevia/ui/PhotoBorderPanel.java) | 四张真实渲染样式卡，下方独立滚动真实已有信息；外观、显示项、Logo、机型补填和撤销／重做保留在实际设置入口。未增加镜头／署名持久字段或假 EXIF。 |
| [PhotoHistogramPanel](../../../app/src/main/java/cc/huevia/ui/PhotoHistogramPanel.java) | 模式文字加实体 2dp 短线；独立暗部／高光斜纹 chip，关闭描边／开启杏色；52dp 曲线与 0／255、8 位 sRGB 说明。百分比保留在辅助描述与可点说明内，实际 256 bins 统计输入不变。 |
| [HoldToCompare](../../../app/src/main/java/cc/huevia/ui/HoldToCompare.java) | 编辑页按钮使用真实照片局部采样玻璃，32dp 视觉／48dp 触达；沿用按住、松开、取消和键盘辅助点击的完整原图比较。 |
| [PhotoDetailDialog](../../../app/src/main/java/cc/huevia/ui/PhotoDetailDialog.java)／[PhotoDetailView](../../../app/src/main/java/cc/huevia/ui/PhotoDetailView.java) | 安全区内全画布、52dp 两行头部和实际文件名；上方比较胶囊、右上独立尺寸／倍率、左下三档缩放、右下放大定位窗、避让浮层的底部说明。加载／失败／重试和已保存版本不可恢复原因来自真实状态。 |

原型 390×844／844×390 是布局参考；假状态栏、假 homebar、演示设备圆角不进入 App。元信息行至少 48dp；28／32／40dp 是视觉面，不以缩小触达换取紧凑布局。细节浮层按照片 stage 安全区锚定；图片保持比例，真实图边可能在 stage 内。

100% 仍为一个内容像素对应一个屏幕物理像素。当前效果来自完整分辨率处理面、JPEG 编码之前；调色前保持同构图。不可恢复的历史 JPEG 查看完整已保存像素及已烘焙边框，不推测去框。玻璃、警示与直方图不进入源文件、草稿或导出像素。

## 候选与源码身份

所有候选均为 versionCode 92／`0.19.1-beta`、3,905,658 字节，完整 SHA 和各自证据分别保留：

| 阶段 | APK SHA-256 | 结果与范围 |
| --- | --- | --- |
| 初始布局候选 | `a1498dae0cfd59ebef831a5ea4e4fd25b532ba58d8702f55e92c68294c4ce0dc` | phone 发生真实布局请求循环，首轮中止，未形成三配置通过；[初始归档](initial-a1498dae-blocked/phone/blocking-layout-abort.json)保留。 |
| 完整矩阵候选 | `f919bd9821634e31c52d6e8cb7661810d07fd6796b27d5abcc6488022ce41379` | 布局与交互修正后，phone 239／font1.3 239／landscape 251 次断言执行均 PASS；[矩阵](UI-MATRIX.json)及各模式原报告属于此 SHA。 |
| 后续单项候选（非最终交付） | `7b69df3e8ceb7cb018fff1a3553e9dfbc99d4a25a0c4c9ce5b8fd79837e380c8` | v2／v3 签名通过，仅修改历史已保存版本原因文字为白字＋黑色阴影，位置、尺寸不变；该状态横屏单项59次断言后来PASS；用户新视觉反馈由93继续处理。 |

[当前源码快照](source-snapshot.json)固定 7b69 的 206 项构建输入；[完整矩阵源码快照](f919-full-matrix-source-snapshot.json)保留 f919。对照仅 `PhotoDetailDialog.java` 一项改变，其余 205 项输入相同。7b69 不重新宣称做过 729 次完整矩阵；它的直接设备结论只属于新增的横屏可读性确认，其余实现依据明确追溯至 f919 与该一行源码差异。

本地 APK 为 [huevia-0.19.1-beta-debug.apk](../../../dist/huevia-0.19.1-beta-debug.apk)。没有实体手机覆盖安装或公开发布。

## 完整原生矩阵：f919

原生检查在独占、只读 Pixel_9 模拟器 `emulator-5586`、自有 JPEG／草稿夹具上执行。没有操作实体手机、其他模拟器或真实相机，也没有发布 MediaStore 文件。

| 配置 | 原报告 | 断言执行 | 实际系统配置 | 1:1 直接像素证据 |
| --- | --- | --- | --- | --- |
| phone | [report.json](phone/report.json) | PASS 239 | fontScale 1.0／竖屏／浅色 | framebuffer 1849 点、最大通道差 0；tile 1848 点、错误 0 |
| font1.3 | [report.json](font1.3/report.json) | PASS 239 | 实际 fontScale 1.2999999523／竖屏／浅色 | framebuffer 1849 点、最大通道差 0；tile 1848 点、错误 0 |
| landscape | [report.json](landscape/report.json) | PASS 251 | fontScale 1.0／横屏／浅色 | framebuffer 1849 点、最大通道差 0；tile 2772 点、错误 0 |

合计 **729 次含配置重复的断言执行**，不是 729 个独立用户场景。像素映射分别见 [phone](phone/pixel-mapping.json)、[font1.3](font1.3/pixel-mapping.json)、[landscape](landscape/pixel-mapping.json)，只证明对应夹具和记录位置的真实映射，不代表颜色标定或所有照片质量。

本轮实际覆盖的直接交互包括：

- 编辑器五工具切换保持照片 stage、像素与草稿，完整滤镜选择框、边框信息及设置／配方入口可达；调节精确值、撤销／重做接实际状态。
- 强度精确值使用实际解析的 638B `Bluesky.NCP`（SHA-256 `2bab29630bbc537025c5daf68f6b7ab90a866e5c97e6dc7430dd4fe4ad547eb6`）并只存自有 JPEG 草稿；确认未改数值不新增撤销、草稿改写或预览请求，没有写入预设库。它不是生产在线目录或真实相机试拍验证。
- 右上尺寸／倍率 26dp 视觉标签有独立真实 48dp 动作范围；原生触摸在标签外、动作范围内打开说明。细节 100%／200%、定位窗、适应恢复、同位置比较、真实文件名与状态、同文件显式 rebind 后旧 dialog 失效均通过。
- 构图独立暂存、取消不提交、应用与一次撤销通过；横屏上方两个角以真实触摸拖动改变 geometry，见 [crop-upper-corner-touch.json](landscape/crop-upper-corner-touch.json)。不是以直接改模型冒充手势。
- 直方图模式实体下划线、独立警示、实际图表／sRGB 说明与开关隔离；源夹具 SHA 保持，警示关闭／开启的导出夹具留存。没有因 UI 重排重测未改导出／批量后端。

[f919-injection-harness-fail](f919-injection-harness-fail/phone/report.json)保留较早探针失败：`Instrumentation.sendPointerSync` 的目标 UID／焦点注入限制。改为已获焦点的原生 `UiAutomation` touchscreen 注入后，**同一 f919 APK** 完整三配置通过；这不是额外产品修复，也不合并旧失败中的部分检查数。

## 原生图与有界复核

实际截图来自 f919，均有模式环境与候选 SHA，示例入口：

- phone：[编辑页](phone/hero-editor-closed.png)、[直方图](phone/hero-editor-expanded.png)、[细节](phone/hero-detail.png)、[五工具返回](phone/hero-editor-five-tools-returned.png)。
- 大字号：[编辑页](font1.3/hero-editor-closed.png)、[细节](font1.3/hero-detail.png)。
- 横屏：[编辑页](landscape/hero-editor-closed.png)、[细节](landscape/hero-detail.png)、[构图上角](landscape/tool-crop-upper-corners.png)。

独立源码复核的三项修正已获限定 PASS。独立视觉复核审阅 31 图，唯一 HOLD 为横屏已保存版本原因文字压到明亮照片而不可读；7b69 只将该文字改为白色＋黑影，布局保持。最终单图确认及限定结论见 [FINISH-REVIEW.md](FINISH-REVIEW.md)，该单项随后完成59次断言PASS；用户新增四类反馈仍未由92解决，不写用户已批准视觉。

## 清理与验证边界

[f919 UI-CLEANUP](UI-CLEANUP.json)确认 9 份自有 JPEG、3 份草稿删除，删除前源 SHA 不变；App 外观及系统字体／旋转／夜间模式／原有权限在三模式恢复，探针卸载并核对不存在。细节源 close／owner invalidation 已断言；产品包不可调试，未独立检查私有临时缓存目录最终为空。此时模拟器留给 root 做最终有界确认，不能把 UI-CLEANUP 写成模拟器已关机。

7b69 单项确认的夹具、设置恢复和模拟器关闭尚待最后记录。旧 [91 最终身份](../photo-image-upgrade-91/FINAL-IDENTITY.json)及[实施记录](../photo-image-upgrade-91/IMPLEMENTATION.md)保持原 SHA 和范围。91 的 backend／progress／dark 等没有在本轮重跑，不列作92直接验证。

两份 HTML 的 46 项主原型 DOM 检查与 21 组导出静态检查分列于 [原型完成记录](../../design-review/photo-detail-glass-redesign-20261024/PROTOTYPE-REVIEW.md)。原型 `file:` 浏览器预览被策略拒绝，未换服务器／其他浏览器绕过；没有浏览器实际布局／像素通过结论，静态检查不计入原生断言。

本轮不认证实体手机／相机、真实 MediaStore 公有副本生命周期、生产账号／在线目录、dark 完整矩阵、tablet、FPS、色彩标定或 TalkBack；没有线上发布或用户最终视觉接受结论。


## 状态终止点

7b69横屏历史已保存版本确认见[原报告](landscape-saved-reason/report.json)，PASS59次；其[单项清理](landscape-saved-reason/CLEANUP.json)保持该SHA范围。92后续未因功能通过而获得用户视觉批准，7b69不作为最终交付。93重新处理用户指出的四类问题并全面收紧文字，新候选必须有自己的原型身份、原生图、报告与清理，不能继承92检查数。
