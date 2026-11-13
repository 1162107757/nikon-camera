# Huevia 跨端开发版 213

验收目标为新版 Android / iOS，应用标识 `cc.huevia.next`，项目版本 `0.31.0-dev+213`。本次继续补齐 11 类迁移工作；多预设置顶、RAW 曝光与高光修复、注册后登录状态更新及有线照片传输保留在新版中。

Android 手机使用 [ARM64 APK](huevia-0.31.0-dev-213-android-arm64.apk)；[x64 APK](huevia-0.31.0-dev-213-android-x64.apk)供相应测试设备使用。iOS 设备包正在 Apple 构建与验证，尚未作为本轮已验收附件交付。每份实际文件的摘要、大小和来源见 [ARTIFACTS.json](ARTIFACTS.json)。

新版新增后台连接保护、遥控与槽位入口、多选接收和保存目标、相邻浏览及 RAW 缩略缓存、人像与自动修补、NEF 原件与配对、批量编辑和删除范围、原生 QQ 接入、更新和旧资料迁入。具体完成证据和仍需实体设备的验收见 [213 总表](../../docs/migration/remaining-work-213.md)。

从旧 Android 迁入时，可在原应用上覆盖安装同签名的 [旧版资料迁出维护包 194](huevia-0.30.34-legacy-export-194.apk)，打开“旧版资料迁出”入口，使用系统文件选择器保存 ZIP。再在新版设置的“旧版资料迁入”中选择 ZIP、预检并确认迁入。迁入保留已有资料，并提供撤回本次迁入。先保留旧应用与导出的 ZIP；此维护包超过旧更新渠道 32 MiB 上限，仅作手动安装附件。

当前 Android 证据含 119 项原生、正式 x64 R8 APK 的 41 项真实模型/渲染/RAW 检查及完整 Flutter/原生流水线；16 KiB 静态对齐通过。实体相机、实体 16 KiB 设备和 iPhone 仍需验证。QQ Android 腾讯登记尚未核实，iOS Universal Link 尚未配置。生产数据库、权限策略和更新通道尚未发布。
