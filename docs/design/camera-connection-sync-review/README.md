# Huevia 相机连接与同步工具 · 设计审核 V1

这是独立 HTML 原型。用户已确认按设计接入，当前共享 Flutter 界面源码已更新，详情见 [源码接入记录](implementation/README.md)。HTML 原型自身不连接真实相机，不启动系统设置，不发出发现、连接、拍摄、照片列表或预设读写请求。状态、设备型号、照片数量、下载进度与拍摄参数均为演示数据，不构成兼容性或真机验收结论。

打开 [index.html](index.html) 查看双机审核台，或打开 [关键状态图库](gallery.html) 并排查看 完整状态的固定截图。每台手机内容宽 375px、高 812px，Android 与 iOS 分别展示系统安全区域；左侧可切换浅色、深色及所有关键状态。可直接用浏览器打开，无需构建或联网。也可从仓库目录运行：

```powershell
python -m http.server 4319 --bind 127.0.0.1 --directory docs/design/camera-connection-sync-review
```

访问 `http://127.0.0.1:4319/`。本地服务只提供原型目录。

## 已选方向

用户选择：**单个工具按钮，点击展开面板**。保留原版 Android 暖白、石墨、陶土色与玻璃半透语言。用户随后确认“请按照这个设计”，已授权接入共享界面源码；尚未构建新测试包。

追加审核项：[三张收起状态设计图](collapsed-options/index.html)，分别是文字胶囊、圆形图标、贴边短签。三张使用内置 ImageGen 生成，每张包括浅 / 深色。用户随后选择了 **B · 圆形图标**；现有原型已同步为 52px 圆形玻璃入口，未为三种候选另做原型。

用户随后指出遥控缺少取景画面，并确认采用**独立全屏取景页**。[全屏遥控画面](remote-review.html) 展示主界面及取景辅助；[可交互全屏遥控](screen.html?platform=android&theme=dark&surface=sync&panel=remote) 可切换网格、直方图、点按对焦、暂停 / 恢复和拍摄设置。沿用原遥控摄影深色皮肤，独立于应用的全局浅 / 深色；所有画面为演示。

## 可审核的交互

- 连接页：Wi-Fi / USB 分段切换；相机类型；系统网络引导；折叠的 IP / 端口设置；准备、设备检测、授权、机身确认、连接失败、超时、取消、重试。
- 权限：iOS 明确解释“本地网络”及拒绝后的恢复入口；Android 使用网络连接确认文案；USB 独立说明设备访问权限。不模仿或伪装系统授权弹窗。
- 成功返回：点“开始连接”约 4 秒后完成**演示**，自动回到调用方。同一流程可从同步或预设进入；不拉取照片，不自动填充照片网格。返回同步页后，用户点击“浏览相机照片”才展示预置演示网格。
- 同步工具：只有同步页显示单个浮动圆形按钮，宽高均为 52px，位置在右下角导航上方。空队列不显示计数；有任务显示小数量标记。
- 工具展开：252px 宽的三入口面板；点工具后替换面板内容，不叠加多层玻璃；点外部、关闭或 Escape 收起。
- 下载：空队列约 176px 高；活动队列显示文件、总体进度和暂停 / 继续；失败保留队列并提供重试。空下载不占大面积底部。
- 遥控：用户追加确认采用独立全屏取景页，沿用原摄影暗色界面。上方展示标记为演示的取景画面，下方为只读参数与快门；保留网格、从演示照片计算的亮度直方图、点按对焦、最近拍摄、取景开关及拍摄后传入 App 开关。点快门后禁用约 850ms，再显示一次指令反馈，不持续闪烁。暂停、等待画面、不支持实时取景、断开及拍摄结果待核对均有状态。结果未核对时禁用快门，不自动重拍。返回同步结束取景并保留连接。
- 槽位：C1–C9 在 3 × 3 网格内完整展示；默认“未读取”，不伪造槽位内容。选择槽位后可预览读取、写入的下一步说明，写入需再次核对覆盖目标。
- 作用域：切换底部预设、相册、设置时，工具入口和面板消失；返回同步页时保持收起。当前画廊和其他页仅提供足够的背景与导航关系。

## 直接打开关键状态

- [Android 浅色 Wi-Fi 准备](screen.html?platform=android&theme=light&surface=connection&state=idle)
- [iOS 深色本地网络授权](screen.html?platform=ios&theme=dark&surface=connection&state=permission)
- [iOS 浅色权限未开启](screen.html?platform=ios&theme=light&surface=connection&state=denied)
- [Android 深色连接超时](screen.html?platform=android&theme=dark&surface=connection&state=timeout)
- [USB 设备检测](screen.html?platform=android&theme=light&surface=connection&transport=usb&state=usbfound)
- [成功后回到预设](screen.html?platform=ios&theme=light&surface=connection&state=success&source=presets)
- [同步工具展开](screen.html?platform=android&theme=light&surface=sync&panel=tools)
- [空下载队列](screen.html?platform=ios&theme=dark&surface=sync&panel=downloads&queue=empty)
- [遥控拍照](screen.html?platform=android&theme=dark&surface=sync&panel=remote)
- [C1–C9 槽位](screen.html?platform=ios&theme=light&surface=sync&panel=presets)

## 参照与素材来源

只读参照：当前目录中的 `AGENTS.md`、`PRODUCT.md`、`DESIGN.md`、原版 `app/src/main/java/cc/huevia/ui/UiPalette.java`，以及 Flutter 的 `camera.dart`、`camera_connection.dart`、`sync_tools_dock.dart`、`legacy_glass_sheet.dart`、`legacy_theme.dart`、`camera_remote.dart`、`camera_remote_preview.dart`。原版色值直接沿用；玻璃使用约 83% 浅色 / 88% 深色表面、28px 模糊、边缘高光和柔和阴影。

`apple-tokens.css` 来源：本机 Apple Design 技能的 `assets/tokens.css`，原文件复制并在 `screen.css` 用 Huevia 品牌色覆盖角色变量。

`assets/` 的六张照片均复制自**当前项目** `app/src/main/assets/preset-showcase/` 下的同名 JPG，作为既有项目素材引用；未新增网络下载或生成图片。素材只展示构图、玻璃遮挡与照片密度。

## 审核边界

初始设计阶段仅写入本审核目录。用户批准后已接入 `cross-platform/app` 中的相机相关共享界面与测试；未改 Java / iOS 原生、版本号、公共冻结验收记录。未运行 Flutter、Gradle 或 Apple CI，未提交、推送或发布。HTML 浏览器检查仅证明独立原型，不能作为原生产品验收。

已确认：B 圆形入口、独立全屏遥控及紧凑照片工具栏；新增拍摄时间和名称排序。原生产品视觉与 widget 运行验证仍待后续构建窗口，不能复用 221 的旧结果。

## 原型检查记录

`review/browser-check.json` 记录 92 个手机状态截图与 32 项通过的浏览器交互检查。独立遥控复核后，另用 `review/remote-recovery-check.json` 定向检查了取景状态与拍摄待核对状态的分离：24 个遥控状态截图、12 项检查通过、0 个错误。切换取景开关或退出重进不解除待核对标记，只有明确核对恢复快门。

`review/finish-review.md` 与 `review/remote-finish-review.md` 的结论均限定为独立 HTML 设计审核；不构成产品接入、发布或真实相机测试批准。样式与交互契约见本目录 `DESIGN.md` 和 `design-tokens.json`。素材、截图和三张生成图的来源见 `asset-provenance.json`，对应文件已嵌入来源或精确提示词。

照片工具栏已追加排序入口，原型预览有四项时间 / 名称正倒序。对应示例截图为 `review/sync-toolbar-sort-375.png` 与 `review/sync-toolbar-sort-menu.png`；源码排序只作用于已读取照片，缺少时间的照片放在末尾。
