# 221 本地测试说明

**221 三个同源安装包已通过本地测试交付验收，未公开发布。** 固定源码 `d22ec09eb7b10eb1e2e8812ff9b04e30c87dbd2d`；Apple [full 43535636225](https://github.com/1162107757/nikon-camera/actions/runs/43535636225)实际通过 494 Flutter、5 UIKit 和 1 个完整 native pipeline，核心一致性 1770 项匹配，IPA 独立验包 exit 0。

| 平台 | 已接受本地测试的附件 |
| --- | --- |
| Android ARM64 | [ARM64 APK](../../dist/migration221/huevia-0.31.0-dev-221-android-arm64.apk) |
| Android x64 测试环境 | [x64 APK](../../dist/migration221/huevia-0.31.0-dev-221-android-x64.apk) |
| iPhone 自签 | [未签名 IPA](../../dist/migration221/huevia-0.31.0-dev-221-ios-unsigned.ipa)，iOS16+，需自行签名；实际手机安装未验证 |

三包实际字节数、SHA-256 和同源信息见 [ARTIFACTS.json](../../dist/migration221/ARTIFACTS.json)。同包 `cc.huevia.next` 会升级既有 next 安装，先保留重要资料；无需卸载原版。[220 三包基线](../../dist/migration220/README.md)继续保留，不覆盖其文件或结论。

**221 沿用 220 界面；新设计仍在独立会话审核，未接入本轮。** 本轮仅覆盖下述遥控和 Android 返回修复，不扩大实体设备或完整功能验收声明。

## 本轮复测

1. **遥控静默刷新。** 进入遥控页，连续观察数个状态刷新周期。未操作时，“就绪”与快门不应反复闪烁、重建或显示忙碌；只读刷新不能触发拍照。
2. **拍照安全串行。** 单次按快门后等待结果。状态刷新与拍照重叠时，旧刷新不能提前恢复可拍状态、覆盖拍照结果或追加拍摄；重复点击不能并发发出多次拍照。结果未知时先核对相机，不连点补拍。再检查关闭面板、账号变化和迟到回调不会操作新会话。
3. **Android 内层返回。** 打开工具面板、设置弹层或内页，再按系统返回，应先返回上一层；忙碌操作仍按原确认/退出保护处理，不直接把内层返回变成退后台。
4. **Android 根页面返回。** 在主标签根页面记录当前页和滚动位置，按系统返回，应将应用放到后台并保留 Activity/页面。短时从最近任务回到应用，应回到原页，不因这次返回冷启动。需要核对 Activity 生命周期，不能仅以 PID 仍存在认定成功；划掉任务、强制停止或系统回收属于不同场景。

220 已在 API31 环境复现“根返回销毁 Activity、PID 仍在”；221 精确 x64 APK 在同类 API31/4KiB 环境实际通过四个根标签和两个内层返回用例：根返回退后台、恢复同 Activity/同 PID/原页，连接页与队列返回同步。相机切后台后的接收/连接继续遵循既有后台保护规则，不因保留页面就承诺永久连接。

## 证据与边界

[验证索引](validation/features-221/README.md)保留本地新6项遥控与旧迟到打开1项实际 exit 0，以及原始未提交补丁的执行基线；最终四个输入已绑定到冻结 Git。Android 两 ABI 验签、各8个ELF的16KiB静态对齐、10张模板图通过，精确 x64 在 API31/4KiB 环境 R8 78 项通过。全应用分析 exit 0，source check 与原工程 inventory 核对通过。

本地核心 golden 仍引用 220 真实收据，`freshRunClaimed=false`；243 个 Java 输入未变、最终 221 绑定已完成。本次 Apple 运行独立重新执行核心一致性 1770 项并通过，不把参考 golden 冒称为本地 221 新 JVM 执行。

仅本地测试，不发布商店、更新清单或草稿。实体 Z6II Wi-Fi、iPhone 安装/连接、USB、QQ 真实授权和 16KiB 实体设备限制继续按 [220 指南](local-testing-220.md)保留；iOS QQ Universal Link 未配置，既有 RAW 原图删除限制仍保留。六项 Android 返回验证不等于所有实体设备均已实测，后台连接仍遵循既有保护规则。
