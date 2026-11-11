# Android 186 与共享 188 样式对照

在同一台隔离 Android 12 / API 31 模拟器上并存安装原版和迁移版，分辨率 1080×2340，density 420。图片是实际应用截图，未调整控件或修饰画面。状态栏时间不同。

原版为 `0.30.32-beta+186`；共享版为 `0.31.0-dev+188` 的 x86_64 release/R8/AOT 包，应用源码提交 `362897f`。原 `app/`、`ios/` 共 420 个已跟踪文件仍通过保留校验。

| 页面 | 原 Android 186 | 共享 188 |
| --- | --- | --- |
| 本地预设及浮动导航 | [原版](presets-android186.png) | [迁移版](presets-shared188.png) |
| 未连接同步页 | [原版](sync-android186.png) | [迁移版](sync-shared188.png) |
| 设置 | [原版](settings-android186.png) | [迁移版](settings-shared188.png) |
| Wi-Fi 连接 | [原版](connection-android186.png) | [迁移版](connection-shared188.png) |
| 合成 DNG 的调节页 | [原版](editor-raw-android186.png) | [迁移版](editor-raw-shared188.png) |
| 登录欢迎页 | [原版](welcome-android186.png) | [迁移版](welcome-shared188.png) |
| 密码登录 | [原版](password-android186.png) | [迁移版](password-shared188.png) |

本轮恢复原四入口、浮动导航、双色板、原图标路径、预设摄影样片和实际色调曲线、相册布局、登录结构以及编辑器照片氛围背景、工具分区和黄色滑杆。详情页已独立于根导航，RAW 打开后自动进入编辑，小尺寸显影预览铺满照片视区。连接页使用相机类型卡片和展开式地址设置。

Android 设备的 16 个界面场景通过，覆盖横竖屏、大字体、草稿恢复、曲线/HSL、配方、复制撤销、成品版本、搜索与会话隔离。另存 34 项原生检查和 1 个 Flutter/native 完整图像场景日志。最终 release 包实际完成 DNG 显影和完整 JPEG 导出，并打开系统分享面板；检查时进程存活，进程崩溃缓冲区为空。

这些截图记录已复核页面，不构成所有页面逐像素一致的验收。仍有字体栅格化及少量尺寸取整差异。已连接相机、社区、完整账户流程、批选工具条、人像、局部/修补、原版导出预览等界面仍待迁移或进一步对照；iOS 系统图库适配也未完成。合成 DNG 不能替代用户未知型号 NEF，模拟器不能替代荣耀 Magic 实机稳定性验证。整体状态见 [功能清单](../../feature-parity.md)，包哈希与布局测量见 [验证记录](../android12-style-20261111.json)。
