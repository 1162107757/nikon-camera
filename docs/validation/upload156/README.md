# 156 更新通道兼容包与上传

用户于 2026-11-08 请求将新版本上传。目标为原更新管理后台的测试版草稿和已配置的腾讯云 COS 私有存储。

原始 156 四 ABI 包保留：`dist/huevia-0.30.2-beta-debug.apk`，SHA-256 `b2e88b46e8932aba3abba15f663a1282a3179bc48bb77adb3e272e489d8d5fef`，34,581,880 字节，超过现有客户端及服务端的 32 MiB 上限。

上传用包：[huevia-0.30.2-beta-update.apk](../../../dist/upload156/huevia-0.30.2-beta-update.apk)，31,292,511 字节（29.84 MiB），SHA-256 `9223d32f9db99cec28282c3af007acff9cf1fb36a724c14b2525ad7ccef4fc95`。只移除 `lib/x86/` 下四个 32 位 x86 库，保留 `arm64-v8a`、`armeabi-v7a` 和 `x86_64`；不支持仅有 32 位 x86 的设备。87 个保留的应用负载逐项 SHA 与原包完全一致，旧签名元数据随重签重新生成。该包与原包的签名证书一致。

验证：

- ZIP CRC、16 KiB 库／4 字节条目对齐和 V2／V3 签名通过。
- 使用后台生产 `inspectApk` 读取：包名 `cc.huevia`、版本 `0.30.2-beta` / 156、最低 API 26、同一原证书 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`。
- 测试模拟器完整文件覆盖安装成功；针对该兼容包的准确 SHA 重跑 62 项生产 Activity 连接往返检查，通过。详见 [report.json](phone/report.json)。无实体手机或实体相机结论。
- 原始四 ABI 包及其 248 项验证记录未改。保留文件的对应哈希见 [payload-provenance.json](payload-provenance.json)，签名结果见 [signature.txt](signature.txt)。

上传已完成：后台识别为 `0.30.2-beta` / 156、测试版、普通更新、草稿，版本 ID `3e32c8b4-613d-4adf-91c9-26d3badae0ff`。后台验证的大小、包名、最低 API、SHA 和签名均与本地一致，见[后台截图](admin-draft.png)。上传中原登录会话过期，使用浏览器已有登录信息恢复会话后完成上传。

已在 COS 控制台独立查询到新对象：`huevia-updates-1252602548` 桶内 `huevia-updates/app-releases/9223d32f9db99cec28282c3af007acff9cf1fb36a724c14b2525ad7ccef4fc95.bin`，29.84 MB，控制台修改时间为北京时间 2026-11-08 09:49:58。未授权直链返回 403；草稿的公开下载接口返回 404；公开 beta 版本仍为 115。完整核对记录见 [upload.json](upload.json)。本轮没有上架版本、开启强制更新或修改存储权限／上传限额。

后续状态：用户反馈官网仍显示旧版后，已于北京时间 2026-11-08 09:57:02 将此草稿上架为普通更新，revision 2；官网和 App 更新接口已返回 156，官网下载完整 APK 的大小／SHA／签名验证通过。上述草稿状态与 `upload.json` 保留为上传当时的记录；最新状态见[156 发布记录](../publish156/README.md)。
