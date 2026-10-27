# 100 / 0.21.1-beta 验证范围

2026-10-25。用户授权完成修复后上传，并实测强制更新。

- 相机连接：服务独立时钟，立即首轮/3秒周期，最多一个待处理心跳，worker 串行，不打断在途原图；补服务/锁/命令与事件通道及导出阶段固定诊断。未加入未证实的厂商休眠命令或盲目重连。
- 下载进度和多选动作：宿主返回真实悬浮导航高度+14dp底距，phone footer另有12/8dp内边距；rail/沉浸0。MainActivity与probe共享同一公式。
- 已下载：支持多选删除App内原图/效果，确认范围，保留相机/手机相册；复核修正准备任务为APP_ONLY，避免公共存储/通知权限。
- 更新：沿99已验证更新器，部署014及发布服务/管理页，目标cc.huevia/beta100强制；稳定通道和既有发布行保持。远程结果另记。

报告白名单分析：12,853,156字节原图接收111,032ms，payload读取110,465ms，写盘77ms。首次PTP失败先于Wi-Fi lost。用户补充相机已黑屏，尚不能判定显示关闭、待机、无线链路或OEM后台限制的具体责任；现有报告快照不含后续导出完成后的事件。

宿主测试：Controller heartbeat10 / runtime29 / PTP5043 / gallery459 / Controller delete23通过。原生测试是实际AlbumPanel/GlassBar组件、替代Activity、共享nav helper，不能替代完整Main运行或真实相机/OEM后台验证。组件probe只取消删除确认，实际删除与public/camera隔离由定向宿主测试和静态复核覆盖。

源码以FINAL-IDENTITY.json的214项输入与APK SHA绑定，工作区含其他任务已完成但未提交改动，不对全仓dirty作归属推断。

## 已发布及正向升级

100已上架cc.huevia/beta，id `a7a5ad8b-db8a-4de6-b951-adf0a71ff02c`，mandatory=true，revision3。[双Origin及旧版本保持证据](REMOTE-VERIFICATION.json)验证99必须更新，100/101/不兼容系统不强制，14条旧记录仅新增默认false。014及代码44项上线，环境与六旧APK保留。

[真实99→100记录](client-99-to-100/RESULT.json)：未注入元数据、未替代MainActivity；旧99真实HTTPS检查、OS DownloadManager、完整校验、未知来源系统UI、系统更新确认、Play Protect正常扫描后覆盖安装100。返回和外部点击无法关闭强制提示；安装后的SHA完全匹配发布包，firstInstallTime与深色偏好保留，当前版显示最新。16项人工观测标准通过；原生相册组件另有171项检查/9图。

[最终汇总](FINAL-VERIFICATION.json)及[214项输入身份](FINAL-IDENTITY.json)。最终输入无漂移，APK SHA `4ebc35f9fc5930080ba994a6bffe7538feec5bc8679066c698d8f3001b9e37f0`。仅操作自有只读5586，测试包/设置/夹具已清理，首次异常遗留夹具也按精确路径及内容SHA清理，模拟器进程和serial均确认消失。实体手机及相机未操作。已向另一协作聊天交接100身份与发布策略，后续版本须递增。
