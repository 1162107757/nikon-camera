# Huevia 229 测试包

仅供用户测试，未发布。iOS 为未签名 IPA，需要自行签名安装。Android 手机使用 android-arm64.apk；android-x64.apk 供模拟器验证。

- 连接页采用已确认的 A 方案：顶部 Wi-Fi／USB 双标签，新连接默认 Wi-Fi；切换方式不直接断开已有会话。
- USB 目录增加空卡槽处理与有限重试，并补充存储／照片枚举诊断。
- 重新连接失败后刷新真实连接状态，避免显示失效的旧会话。

已通过 macOS 全量 731 项 Flutter 测试、5 项 UIKit 检查、1 个原生场景及 Android 独立 USB helper 的 124 项边界检查；Android 两个 release 包通过签名和 16 KiB 对齐检查，已安装 x64 release 验证实际连接页面。

Z6 II USB 实机尚未验证。请优先测试原数据线连接后的相机照片目录、缩略图、JPEG／NEF 下载，以及返回原功能后的连接保持与重连。

文件大小、SHA-256 和冻结源码提交见 ARTIFACTS.json、SHA256SUMS.txt。
