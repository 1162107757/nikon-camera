# 215 人像入口及修补交互验证

仅用于跨端新版 Android / iOS 本地测试，不部署服务、不修改生产策略、不上传发布草稿或公开发布。214 二进制保留。

本轮产品改动为：直接进入原版样式人像精修、同排新增修补、双指导航取消未完成修补、画笔大小实时预览。原始照片、原版 Android 冻结参考和原生图像处理算法均不因此更改。

冻结源码：`950926c408f81d27db7fa46fb6335579d0459c4c`。同源 [Apple 完整验收](https://github.com/1162107757/nikon-camera/actions/runs/43395276337)已成功；[350 项 Flutter 与原生验收收据](apple/ci-result.json)、[共享核心逐项对比](apple/core-parity.json)和[未签名 IPA 独立核验](apple/independent-verification.json)已归档。Android 两 APK 与 IPA 均可本地测试；新增 216 需求另行实现，不覆盖本轮文件。

## 已执行专项

- 指针状态机新增 3 项：第二指取消整笔，缩放/移动与残指锁，旋转后残指锁及新手势恢复。
- 预览组件 15 项：与实际图像共用画框、画笔真半径、缩放/平移、可视圆环、画面裁剪与指针透传，实际 RGBA 像素验证。
- 修补整合首轮 5 项：完整精修/塑形状态合并、取消与迟到结果、双指零提交、画笔拖动/取消及窄屏大字体可达。
- 最终源码新增的跨控件指针 4 项、工作区尺寸/撤销/对比防误触 3 项，以及人像直接入口 1 项均实际通过，见 [定向结果](flutter/local-results.json)。
- Windows 完整 25 项工作区套件发生 `flutter_tester` 访问冲突而未完成，[首轮](flutter/windows-full-workspace-first.log)与[重跑](flutter/windows-full-workspace-verbose.log)保留；未完成项目不计为通过，由同源 Mac 全量门禁验证。
- UTF-8 / 平台配置检查通过；冻结原版 420 项，其中已批准修复 8 项、其余 412 项保持不变。

最终 Android 两 ABI 的签名、包名/版本及各 8 个 ELF / ZIP 静态对齐均通过；x64 实际混淆 Release 的 [54 项运行检查](android/release-runtime.log)通过。[实际页面与像素核对](android/release-ui.json)确认直接入口、同排修补、圆环拖动显示/松手收起、大小调节后照片 ROI 全像素不变、单笔修补/撤销/重做及父子取消。

Mac 同源全量 350 项通过，含 Windows 未完成的整套人像测试；实际 iOS 原生综合场景及 [PhotoKit XCTest](apple/simulator-tests.log)通过。IPA 核对 arm64、最低 iOS 16、215 版本、原模型/字体与框架，以及未签名状态。最终文件、摘要和各平台状态见 [ARTIFACTS.json](../../../../dist/migration215/ARTIFACTS.json)。

Android 模拟器使用 API31 / 4096 字节内存页；静态 16 KiB 对齐检查不表示已经通过 16 KiB 真机验证。iOS 未签名 IPA 需安装时自行签名。相机与 iPhone 的实际传输、RAW/PhotoKit 和 QQ 平台配置仍需对应设备或外部配置验收。
