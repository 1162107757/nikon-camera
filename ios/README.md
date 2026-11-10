# Huevia iOS 0.1.0 — 自签名首包

最低 iOS 16，iPhone 原生 SwiftUI 工程。此工程独立于 Android，首版提供真实在线预设库、SHA-256 校验下载、本地 NCP／NP3 文件及系统分享、Z6II Wi-Fi 槽位读取与确认后的 NCP 兼容导入。照片调色、RAW、USB 和 NP3 相机写入不在此首包范围。

相机导入移植自当前项目的 PTP/IP 双通道和严格 NCP 子集：仅在设备声明所需操作并确认 Z6II 后读取 Standard/C1–C9；每次登记前重新核对能力、标准参数和两次目标槽位；一条连接的一次登记必须精确读回，结果不确定则断开且不自动重试。确认覆盖后才写入，首次连接不会写入。不得把模拟器或脚本相机测试当成实体相机验证。

在 Mac 或 macOS CI 上执行：

```sh
swift test --package-path ios
bash ios/scripts/build-unsigned.sh /absolute/output-directory
```

不需要 Apple 证书、私钥、描述文件或开发者账号。输出是真正 `iphoneos/arm64` 的 `Payload/Huevia.app` IPA，签名步骤留给使用者；无法直接安装未签名包。自签工具必须为 `cc.huevia.ios` 应用提供有效签名及匹配的安装描述文件，保留本地网络用途说明。签名有效期由自己的签名方式决定，工程不承诺永久有效。

GitHub Actions `.github/workflows/ios-unsigned.yml` 在 `codex/ios-unsigned-*` 私有分支构建：运行核心测试、生成设备 IPA、验证 Mach-O 平台及 ARM64、启动真实 iPhone 模拟器并保留五张截图，逐一确认十张参考图片可在 iOS 解码。产物保留七天；未上架 TestFlight、App Store，也不发布到 Huevia 网站。

`ios/scripts/generate_project.py` 使用 Python 标准库生成 Xcode 工程，不下载外部依赖。`build-unsigned.sh` 用 Xcode 自带工具从当前 Huevia 图标源生成 AppIcon。摄影参考复用项目已选用的十份 Pexels 素材，完整来源在 `Huevia/Resources/showcase-provenance.json`，不当成滤镜实拍结果。

实际构建结果、IPA 摘要、编译环境和验证范围另存于本次交付记录；只有拿到云端构建产物并通过验证，才能宣布 IPA 已生成。安装、自签及 Z6II 导入需用户在实体 iPhone 上复测。
