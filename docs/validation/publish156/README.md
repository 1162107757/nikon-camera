# 156 官网下载上架 · 2026-11-08

用户反馈官网没有更新新版本。原因是此前只上传了测试版草稿；官网按已发布版本读取，仍显示 115。本轮补齐该草稿的上架及官网下载验收。

- 版本：`0.30.2-beta` / 156，渠道 beta，普通更新（`mandatory: false`）。
- 版本 ID：`3e32c8b4-613d-4adf-91c9-26d3badae0ff`；revision 2。
- 上架时间：北京时间 2026-11-08 09:57:02。
- 安装包：31,292,511 字节（29.84 MiB），SHA-256 `9223d32f9db99cec28282c3af007acff9cf1fb36a724c14b2525ad7ccef4fc95`。
- 原签名证书：`04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`，V2／V3 校验通过，包名 `cc.huevia`、最低 API 26。

上架的是 [upload156 兼容包](../upload156/README.md)：保留 ARM64／ARMv7／x86_64，移除 32 位 x86 库，其余 87 项应用负载与原始四 ABI 包逐字节相同。原始包及其冻结验证记录保留。

验证：

1. 后台显示“测试版 · 已上架”和普通更新，见 [admin-published.png](admin-published.png)。
2. 官方更新接口与 `huevia.cc/preset-library` 两个 Origin 查询均返回 156，文件身份一致且非强制更新，见 [api.json](api.json)。
3. 从干净的官网根地址进入下载区，未发布正式版时自动展示当前测试版；UI 显示 `0.30.2-beta`、29.84 MiB、2026/11/08，见 [website-download.png](website-download.png)。
4. 实际点击官网“下载 Android 安装包”，取得完整文件，逐字节大小／SHA 与已上传兼容包一致；再以生产 `inspectApk` 验证版本、包名与签名。完整文件保存在忽略目录 `.tooling/publish156/website-download.apk`，结果见 [publication.json](publication.json)。

本轮只执行版本发布，没有更改网站源码、下载域名、对象存储权限或强制更新策略。旧版 App 的实际安装流程未在本轮重跑；其查询入口已返回新版本。
