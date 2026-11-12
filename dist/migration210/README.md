# 210 相机与迁移进度包

修复独立 JPEG 目录、下载接收进度、iOS 本地网络授权说明与设置入口、底部标签保留相机会话，以及首页/编辑页预设预览。相机照片恢复原版三列方形缩略图，文件尺寸等详细行已移除，点击预览后再明确接收原文件。

并行补入本地项目预设与已保存成品闭环、RAW 外部 JPEG 参考匹配、稳定性诊断。项目暂为手动添加已保存 JPEG；系统后台自动接收、遥控拍摄等剩余工作见清单。

三个包的源码均为 `86211035f8eaa6e008e609b4b4b2496dd8b97b66`。Android ARM64 手机包最低 Android 8，x64 为模拟器包，标识 `cc.huevia.next`。IPA 为 iPhoneOS ARM64、iOS16+ 未签名设备包，需自行签名。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| huevia-0.31.0-dev-210-android-arm64.apk | 51225670 | `d404385705130d1e33541ea211d5b6bfc8863883243eb939f2fbfa24a5092831` |
| huevia-0.31.0-dev-210-android-x64.apk | 54662638 | `155f232d43e6aa42ca1b6473f5592b8517276a76f2a6f42733618b7a516a7422` |
| huevia-0.31.0-dev-210-ios-unsigned.ipa | 29575051 | `22fa4ffbdc8b47a30122f26ce42079ded551d8e0fb861ff96768280a384c5232` |

Android 安装控件/状态测试40项、实际原生综合流程1场景，以及交付release/自建PTP-IP检查通过。Apple 199项Flutter、690项共享核心、24项Wi-Fi流、38项原生头像和1个实际PhotoKit/图像/RAW/项目综合场景通过，见 [Actions](https://github.com/1162107757/nikon-camera/actions/runs/43225130892)。

原工程保留。整体迁移尚未完成，实体 Nikon/iPhone JPEG、标签切换、未知 NEF 高光、荣耀 Magic 闪退还需用此包验收。原始私人诊断文件未公开。详见 [210冻结记录](../../docs/migration/validation/camera-grid-projects-210/README.md) 与 [剩余工作](../../docs/migration/remaining-work-210.md)。`candidates/` 是早期候选，不是本轮交付。
