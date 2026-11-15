# Huevia 226 测试包

Android 与 iOS 均已接受为本地测试包，使用同一冻结产品来源 `ed48347f1b3e6c92492207259cf24d1613ea12e3`。**只供测试，未发布到商店或更新渠道。**

- [Android ARM64](huevia-0.31.0-dev-226-android-arm64.apk)：手机安装使用。
- [Android x64](huevia-0.31.0-dev-226-android-x64.apk)：模拟器使用。
- [iOS 未签名 IPA](huevia-0.31.0-dev-226-ios-unsigned.ipa)：安装前自行签名。

正式显示名为 Huevia，应用 ID 保持 `cc.huevia.next`。采用批准的 A 接收面板：中央大号开始按钮、JPEG / Nikon NEF RAW 选择。修复接收记录被底部四标签遮挡、旧 busy/session/job 阻塞重连，以及切换账号后旧下载回复覆盖新状态。

[Mac full 43663233293](https://github.com/1162107757/nikon-camera/actions/runs/43663233293) 与独立验包通过：697 Flutter、5 UIKit、1 原生流程；JVM 1865、Android 精确 R8 123、返回 4+2 与实际界面 3 项通过。正式名、未签名 IPA、10 张预设预览图及原生模型资源均已核验。完整 [测试指南](../../docs/migration/local-testing-226.md)、[SHA 清单](ARTIFACTS.json) 与 [验收记录](../../docs/migration/validation/features-226/README.md) 已保存。

iOS QQ Universal Link/AASA 尚未配置，使用账号密码。实体 Z6II Wi-Fi/蜂窝、USB、原生 QQ、16KiB 真机及自签 iPhone 仍待实测；主机和模拟器证明不能替代真机结果。
