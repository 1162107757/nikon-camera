# Huevia 跨端开发版 212

验收目标：Android 与 iOS 跨端新版，应用标识 `cc.huevia.next`，版本 `0.31.0-dev+212`。

- 我的预设：长按卡片或进入预设详情，选择置顶／取消置顶。支持多个置顶，最近置顶排前，按本机账号保存。
- RAW：关闭自动白点调整、固定用户 EV 的应用位置，并修复饱和中性高光在 LibRaw H2 中变黑的计算问题。
- 账号：注册／登录成功立即更新登录状态；验证码失败会显示原因和刷新后的验证码，保留账号密码。
- 有线照片：设置 → USB 数据线连接 → 检测 USB 相机，选择尼康相机并允许系统访问，即可浏览和手动接收 JPEG／NEF 原文件。

Android 手机使用 [ARM64 APK](huevia-0.31.0-dev-212-android-arm64.apk)；[x64 APK](huevia-0.31.0-dev-212-android-x64.apk)用于对应测试设备。iOS 设备版 IPA 正在 Apple 环境验证，完成后补充。开发版未发布到公开更新通道。

实体 USB 相机／iPhone 尚待现场验证；当前证据包括共享协议夹具、原生编译、Android 模拟器系统发现与图像处理。USB 预设／槽位读写属于另外的迁移范围。

完整来源、文件摘要、验证日志与限制见 [212 验证记录](../../docs/migration/validation/features-212/README.md)。
