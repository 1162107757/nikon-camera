# 209 相机缩略图修复包

修复 Wi-Fi 相机 RAW 文件只有名称、没有缩略图的问题。同步首页和连接页共用 JPEG / RAW 筛选，显示相机生成的 JPEG 预览，并支持实际目录刷新和缩略图单独重试。浏览预览不会下载 NEF 原文件。

Android 两个 APK 源码为 `6ccb354c310cad025061f89315eb06aebc2a6fb3`；Apple IPA 验证源码为 `5ad0c600de6f837ba01289473d0851ec15dfc0e7`，两者只相差一个测试文件的图片首帧等待方法，生产代码一致。

Android arm64 包用于手机，最低 Android 8；x64 包用于 Android 12 模拟器。应用标识 `cc.huevia.next`。IPA 为 iPhoneOS ARM64、iOS 16+ 未签名设备包，需自行签名安装。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| huevia-0.31.0-dev-209-android-arm64.apk | 51078214 | `0e7f0a856a3fc52d2ec7c2dcc300c710b343c69a1ba2e7bf594d6b326fa5b1dc` |
| huevia-0.31.0-dev-209-android-x64.apk | 54449646 | `f29cdf7b31ac2b3fd31859ea4a0b743bfc8821d9d9ef0549d5779d820e460254` |
| huevia-0.31.0-dev-209-ios-unsigned.ipa | 29473275 | `6f67e5a4b6f40f4e8fafc998a36f100c3fe8c08401c2fc682c2112992b44bef9` |

Android 专项 7 个界面场景和真实 release / 自建 PTP/IP 流程通过，验证 3→4 张缩略图、格式选择保留、预览回退和原片下载次数为 0。最终 Apple 170 项 Flutter、565 项共享核心、38 项原生头像及真实原生综合场景通过，见 [Actions](https://github.com/1162107757/nikon-camera/actions/runs/43204328202)。实体 Nikon Z6II / iPhone 相机仍需复测。

原工程和历史记录保留，完整迁移尚未完成。详见 [209 冻结记录](../../docs/migration/validation/camera-preview-209/README.md) 与 [功能清单](../../docs/migration/feature-parity.md)。安装包为本地构建产物，不强制加入 Git。
