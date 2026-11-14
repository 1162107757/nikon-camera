# 222 本地测试附件

**三个同源安装包已接受本地测试交付，未公开发布。** 冻结源码 `9559591734f8cc07a8b9dcc1cf5ca596020904b5`；Apple [full 43560076101](https://github.com/1162107757/nikon-camera/actions/runs/43560076101) success，IPA独立验包exit 0。`acceptedForLocalTesting=true`、`acceptedForDelivery=true`、`published=false`。

| 平台 | 可本地测试附件 | 字节数 |
| --- | --- | ---: |
| Android ARM64 | [ARM64 APK](huevia-0.31.0-dev-222-android-arm64.apk) | 52,985,650 |
| Android x64测试环境 | [x64 APK](huevia-0.31.0-dev-222-android-x64.apk) | 56,488,154 |
| iPhone自签 | [未签名IPA](huevia-0.31.0-dev-222-ios-unsigned.ipa) | 65,057,023 |

SHA-256：

- ARM64：`e2c7a0582c0a4963d1169e83c27a0eef5138df04210abc0cfde5f79bcfbdd442`
- x64：`8b6ebca45a22bab29e753ffdb7c828c3e902cf674e9dff9cf906a7a05c8a8220`
- IPA：`5676e27acfeeb1eb995f49aa08973be6396f07c70602cb7fd60e95fc12357252`

本轮重点：旧Android滤镜条与三列搜索picker；“我的｜在线”、分类文字、右侧全部滤镜图标的可见中心对齐；旧版曲线/调色工作区；编辑器、RAW和人像连续预览；已批准连接/遥控/同步工具dock及相机照片时间/文件名排序；跨账号迟到氛围背景保护。

Android实际验签/各8ELF16KiB静态/10图通过；精确x64在API31/4KiB环境实际通过78 R8、四根与两内页返回共6项。曝光、曲线、HSL、调色盘、去灰各7秒拖动中两帧照片已更新，测试原图SHA前后相同。Apple实际541 Flutter、5 UIKit、1个完整native pipeline、核心一致性1770通过，模型/字体/10图及同源IPA独立验包通过。本地243个Java输入沿用参考golden并绑定最终源，不冒称本地222新JVM执行。[指南](../../docs/migration/local-testing-222.md)提供10张真实Android实装截图；4KiB模拟器不等于16KiB实体设备。

[ARTIFACTS.json](ARTIFACTS.json)记录三包精确收据；[测试指南](../../docs/migration/local-testing-222.md)和 [验证索引](../../docs/migration/validation/features-222/README.md)列范围与设备边界。[221三包](../migration221/README.md)继续保留，不覆盖旧附件。

仅本地测试，不公开发布、更新分发清单或上传草稿。IPA为iOS16+未签名设备包，需自行签名；实际iPhone安装、Z6II Wi-Fi、USB、QQ授权及16KiB设备尚未验证；iOS QQ Universal Link未配置，RAW原图删除限制保留，不承诺实体相机已连接成功。

已知后续：实时预览进度条闪动、皮肤选色冗余确认已转223处理，并非222已修复项；223独立工作不纳入本次源码和附件。
