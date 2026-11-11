# Huevia 0.31.0-dev+203

开发版，Android 源码 `9578fe80205c84b134c4da598e783991af18bcce`，独立 Android 包名 `cc.huevia.next`。Apple 源码 `12394417e68eedfb780739e60490746676ab06e5` 仅修复一处测试 API 的 J2ObjC 兼容性，生产输入一致。

- `huevia-0.31.0-dev-203-android-arm64.apk`：50,635,814 字节，SHA-256 `74888439756c045b9211bcbacfa8069cab1c711f61aa531ae0991f6ce74e4d08`。
- `huevia-0.31.0-dev-203-android-x64.apk`：54,007,246 字节，SHA-256 `f1da5996b9769c54fdc69b651e247f7c7247dea98265431e3bf2cdfb04334340`。
- `huevia-0.31.0-dev-203-ios-unsigned.ipa`：29,235,002 字节，SHA-256 `dfba0c494cb6cb20ebd531620795fd7e5ab4e262099810e850bb4c246bfc76f0`。iPhoneOS ARM64，最低 iOS 16，需自行签名。

补齐社区评论/回复、消息、投稿编辑和持久重试；在线发布入口、原版未读样式及文件选择取消/重开隔离已接入。202 的边框、构图和精确导出预览保留，203 正式包已再次检查边框面板及实际白底信息框。

Android 47 个界面场景、56 项原生检查、一次实际处理/导出综合流程及 JVM 276 项共享检查通过。APK 签名、模型/字体、ABI、AOT 和 16 KiB 对齐已核验。详见 `build-evidence.json` 和 `docs/migration/validation/community-203/README.md`。

203 Apple Actions 完整通过：73 项 Flutter、276 项共享检查及真实授权/原生流程；IPA 已独立核验，见 `ios-build-evidence.json`。完整迁移、真实账户联网写入、荣耀 Magic Android 12 / 未知型号 NEF 和实体 iPhone 安装仍待验收。
