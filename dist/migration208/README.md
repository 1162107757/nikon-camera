# 208 开发验证包

源码：`1e5acb6c57e63f9a586235109f19b2f66336fdc1`。原工程和历史包保留，完整迁移仍在进行。

接续 207，实现 Android / iOS 原始 JPEG 直接保存到系统相册，保持原文件字节、EXIF 和方向，支持固定操作标识重试及明确新副本。恢复原版关闭导出设置后在编辑器上方确认的路线，并复查边框编辑在保存前后的保留。样式仍有字体字面宽度和 1–3px 位置差异，尚未完成全界面像素验收。

应用标识均为 `cc.huevia.next`。Android arm64 用于手机，最低 Android 8；x64 用于本轮 Android 12 模拟器验证。IPA 是 iPhoneOS ARM64 / iOS 16+ 未签名设备包，需自行签名安装，实体 iPhone 尚未验收。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| huevia-0.31.0-dev-208-android-arm64.apk | 51078214 | `ab9ac6c9e65f3fa9f3b6a364836a7c7ccd2f0c7886f5529ebe64ab5e99aa8071` |
| huevia-0.31.0-dev-208-android-x64.apk | 54449646 | `34b4a2d7fe95c006dc84d0899399f8de697e7dda16f85a0fe1391246c80346f1` |
| huevia-0.31.0-dev-208-ios-unsigned.ipa | 29462152 | `d484b57e1c5c8bee4a25d5231ca87183b09b7693a4b5d48763a59cb1c8fe495c` |

Apple [构建与验证](https://github.com/1162107757/nikon-camera/actions/runs/43192838801)已通过。验证范围及未完成项见 [冻结记录](../../docs/migration/validation/original-jpeg-208/README.md) 和 [功能清单](../../docs/migration/feature-parity.md)。`build-evidence.json` 记录包与证据文件的指纹；APK、IPA 为本地构建产物，不强制加入 Git。
