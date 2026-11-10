# iOS 准备状态入口 · 2026-11-08

已在官网首屏、官网下载区和完整下载页添加 iOS 入口，显示“正在准备中”。使用原生 disabled 按钮，不设置虚假链接；说明开放下载后会在本页更新，没有承诺日期。手机上首屏两个平台入口上下排列，桌面并排显示。FAQ 与完整下载页的平台说明同步更新。

源码修改：`online-library/home/index.html`、`home/home.css`、`download/index.html`、`download/download.css`。

完整下载页只覆盖生产函数中的两个 HTML／CSS 文件，其余负载、文件模式、运行环境、COS 模式与 `HueviaUpdatePackageRole` 保留。见 [function-deployment.json](function-deployment.json) 与 [function-overlay-audit.json](function-overlay-audit.json)。官网静态文件复制为新版本目录，核对其他 14 个文件哈希后原子切换 `current`。原目录保留，Caddy 配置、DNS、证书未改；通过版本化样式 URL 处理浏览器复用旧 CSS 的问题。

iOS 首屏版本目录为 `20261108-ios-2a9586e4`；后续下载错误修正又更新了 HTML，当前目录见[下载修复记录](../download-json-20261108/README.md)。

现有主页与下载页 9 项测试通过；四份线上 HTML／CSS 回读与本地一致。实际桌面宽度 2048、手机宽度 390 核对，iOS 按钮禁用、无 href、高度 54px，手机没有横向溢出。结果见 [browser-checks.json](browser-checks.json)。可选的首屏手机截图超时，保留实际布局数据，不将其记为截图通过；完整下载页手机截图已保留。临时视口已恢复，预览服务与云控制台临时页已关闭。

![首屏双平台入口](hero-desktop-live.jpg)

![完整下载页手机布局](full-mobile-live.jpg)

后续下载行为修复未改变 iOS 状态文案、布局或 Android 156 安装包，详见[下载修复](../download-json-20261108/README.md)。
