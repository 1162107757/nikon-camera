# 224 冻结测试基线

源码为 `08f414c5b8baeb019acc6c634216cdbbdb44bf9e`，仅用于本地测试，未发布更新或商店版本。用户随后反馈的“修补或切换功能先糊后清”、相机 Wi-Fi 下公网访问、注册会话与输入保留问题，继续在 **225** 处理；224 不代表这些新增问题已完成。

[来源与完整边界](source.json)、[包与SHA](../../../../dist/migration224/ARTIFACTS.json)。Android 两架构的签名、16KiB ELF对齐和10张预览图校验通过；精确 x64 release 的[原生123项](android/release-runtime-result.json)及[返回键4个根页面与2个子页面](android/back-navigation-result.json)通过。

[Apple full 43597212999](https://github.com/1162107757/nikon-camera/actions/runs/43597212999) 同源完整通过：619 Flutter、5 UIKit、1真实原生流程；[IPA独立验证](apple/independent-verification.json)通过，未签名IPA为65,120,925字节。Mac core parity为1770；本地core目录保留此前真实执行与245项输入绑定，未把绑定冒称新JVM执行。

[实际GUI采样对比](gui/medium-zoom-density-comparison.json)记录24MP照片两倍放大时926×1000→1850×2000，约4倍采样像素，非“观感4倍”承诺；[原生tile](gui/native-tiles)和[字节归档清单](android-gui-byte-manifest.json)保留原件。[人像拖动](gui/optimized-pan-image-comparison.json)、[自动皮肤识别](gui/optimized-auto-skin.json)、[留白480px→0](gui/portrait-panel-spacing.json)均在实际安装的08 APK验证。

物理iPhone、自行签名、相机Wi-Fi/USB、真实QQ授权、蜂窝并行联网与16KiB实体设备仍需现场验证。222及223冻结记录不被本轮改写；223的604/2失败与224前批0c的616/5/1仅是各自来源的历史证据。
