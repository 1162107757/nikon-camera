# 207 开发验证包

源码：`38594afc49c9deae79e14b46f147bf45d0936225`。原工程与历史包保留，完整迁移仍在进行。

恢复原版导出设置、多版本选择、只读成品预览和可重试的系统相册保存。验证范围及剩余事项见 `docs/migration/validation/export-settings-207/README.md`；本目录 `build-evidence.json` 记录所有包与冻结证据的指纹。

应用标识均为 `cc.huevia.next`。Android arm64 包用于手机，最低 Android 8；x64 包用于本次 Android 12 模拟器验证。IPA 为 iPhoneOS ARM64 / iOS 16+ 未签名设备包，需自行签名安装，实体 iPhone 尚未验收。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| huevia-0.31.0-dev-207-android-arm64.apk | 51078214 | `19b8c2c61c5bc804851ca31ec273d8a04344f792c35d6c99cab22da862d06f5d` |
| huevia-0.31.0-dev-207-android-x64.apk | 54449646 | `b477ee3ea64804b9bcf172c2f6ad1843aefc537008d1d9ed26aaaf3866013291` |
| huevia-0.31.0-dev-207-ios-unsigned.ipa | 29443534 | `64642d4a6e515537e92fca229e1ad1501e363677903f21f2ea61b87be1fabcf2` |

Apple 构建：https://github.com/1162107757/nikon-camera/actions/runs/43178284420 。APK、IPA 为本地构建产物，不强制加入 Git。
