# 213 集成与剩余验收

目标为新版 Android / iOS；iOS 继续交付未签名 IPA，自行签名安装。唯一工作目录为 `D:\dev\ai-project\nikon-camera`。211、212 的冻结资料及原工程不回写。

用户已明确“暂不发布，我先测试”。当前目标仅为交付本地测试包及继续本地 iOS 修复 / 验证；生产 022、IAM、函数部署、上传草稿和公开发布全部暂缓。A13 离线审查资料保留，不是当前执行目标。

首个开发快照为 `37afaf2d6919556af2ea1de20ee1fb137a321ffa`。最终 Android 开发包来源为 `3db73d2575fc93296e0995c5476c237397c2a1a7`；Apple 完整执行 `43359970364` 来源为 `6c976ba2328cf854d04057694bb3325963807587`，编译成功但原生综合场景失败。当前 `75dad83` 只运行 `native-diagnostic`，不构建或验收 IPA。各平台按独立源码 / 产物记录，不能用部分通过代替完整门禁、生产部署或实体设备验收。

| 类别 | 已接入的开发范围 | 当前验证与剩余事项 |
| --- | --- | --- |
| A2 后台与恢复 | Android connected-device 前台服务、通知停止、引擎与原生任务复用；iOS 有限收尾到期暂停；持久下载记录恢复 | [119 项 Android 原生检查](validation/features-213/android/native-119.json)通过，含真实服务、快速停启代次、同 engine 接管、重开复用 runtime、旧 Activity 迟到释放和通知停止；Queue / Protection 16 项检查通过。iOS 完整执行及两端实体断网、系统终止、电池策略待验 |
| A3 遥控拍摄 | 实时取景、对焦、快门、原机身参数读取、写入不确定状态的持久记录 | 与 A5 共 76 项核心检查通过；页面已接同步入口。相机实际授权、取景、对焦与拍摄待实体机；参数按原协议只读权限开放 |
| A5 Wi-Fi / USB 槽位 | 列表、明确选择目标、写入/删除前快照、一次性操作、结果回读与不确定状态恢复 | 核心及真实 Android SDK 编译通过；实体双传输切换、机型权限和实际回读待验 |
| A6 多选下载与目标 | 最多 100 张，应用/系统/文件夹目标，原生先持久化接收收据，目录描述恢复与逐项去重 | 53 项共享队列检查通过；Android/iOS 平台全链路与文件提供者故障待验。系统保存必须读回 SHA/字节并绑定操作和目标；损坏日志隔离保留 |
| A7 相邻浏览与本地 RAW 缩略图 | 相邻预览、分页、邻图缩略预取、当前照片接收；嵌入 JPEG 或半尺寸中性 RAW 解码、独立有界缓存 | Viewer 6 项控件通过；[Android 完整 Flutter/native 综合场景](validation/features-213/android/native-pipeline.log)与[41 项实际 R8 检查](validation/features-213/android/release-runtime.json)通过，含新鲜 RAW JNI 缩略图及原文件保护。实际相机缩略图、未知 NEF、iPhone 和 16 KiB 设备仍待验 |
| A8 人像推理 | Android 原 LiteRT 模型；iOS 同一 468 点网格和语义模型的 TensorFlowLiteC CPU 推理；人脸/皮肤/身体工具、撤销和确认应用 | 共享边界、Android 完整 Flutter/native 综合场景及最终 R8 41 项通过。Apple 模型实际 SHA 正确，设备 / 模拟器编译和 260 Flutter 通过；完整 native pipeline 在 `retouch_pipeline_fixture.dart:30` 的内置人像 0 返回 `faces=[]` 失败。当前仅诊断 Vision 候选 / mesh 输出，不能认定 iOS 人像综合流程通过 |
| A9 自动修补 | 原修补算法、涂抹路径、取消、撤销/重做及独立入口 | 共享边界、Android 完整 Flutter/native 综合场景及最终 R8 41 项通过，含实际修补、渲染、取消和原图保护；实际照片极端情况及完整 iOS 流程待验。41 是共同总数，不按各行重复累加 |
| A10 配对与 NEF 原件 | 完整库存核对、歧义显式选择、唯一来源证据才关联 JPEG；NEF 原字节保存到系统/Files | 28 项 RAW 配对/发布、21 项描述恢复及 15 项 Flutter 检查通过；原 JPEG 28 项回归通过。真实 PhotoKit NEF 支持、SAF/Files 与相机样本待验 |
| A11 批量编辑与删除 | 顺序进入编辑器、可恢复批量发布、应用原图/成品/系统副本明确删除范围和系统确认 | 本地 batch [9/9 检查](status-editing-lifecycle-213.md)及 Apple 全部 260 项 Flutter（包含 batch 9 项）通过；删除重试修复已进入 1185 项核心通过记录。1 项 PhotoKit 授权 XCTest 通过，不代表真实系统相册批量删除 / 发布或完整 native pipeline 通过 |
| A12 原生 QQ | 两端官方 SDK、同意、验证码、取消/迟到结果、账号所有权保护及后端会话交换 | 定向 8 项账户/更新检查通过。Android 登记仅收到用户“能”的答复，实际新包名 / 证书配置尚未核实；iOS Universal Link 明确未配置，不能认定真实 QQ 登录通过 |
| A13 更新与旧资料 | 新包签名/ABI隔离更新、iOS 未签名 IPA 核验与下载；旧 Android 同签名 194 维护版追加迁出入口；预检/事务迁入/撤回；旧 iOS 预设文件导入 | [旧 186→194 无卸载升级迁出及新版迁入记录](validation/features-213/android/legacy-device-export.json)通过，保留既有 5 文件及旧安装。两份 213 APK 已构建并验签 / 对齐；最终 [TERM=dumb 服务端收据](validation/features-213/server-result.json) / [日志](validation/features-213/server-final.log)为 235 项：228 通过、7 项旧夹具跳过、0 失败；84 模块语法检查通过。历史 225 项记录保留。Apple 候选隔离，未验收；生产只读函数 / IAM 已抓齐。用户明确暂不发布，部署、上传草稿及公开发布全部暂缓，离线审查资料仅保留 |

## 已知执行边界

- Android `dist/migration213/` 的 arm64 / x64 开发 APK 均已[验签、ZIP 16 KiB 对齐及 ELF LOAD 对齐](validation/features-213/android-signing-alignment.json)。[实际 R8 日志](validation/features-213/android/release-runtime.log)确认来源 `3db73d2` 的 x64 APK 41 项通过；[原生 119 项日志](validation/features-213/android/android-native.log)和完整 Flutter/native 综合场景分别独立记录，不把它们合并称为实体接机通过。
- Apple [43359970364](https://github.com/1162107757/nikon-camera/actions/runs/43359970364) / `6c976ba`：设备 release `Runner.app`（110.8 MB）和模拟器编译、260 项 Flutter、1185 项核心、38 项头像、24 项 Wi-Fi，以及 1 项真实 PhotoKit 授权 XCTest 通过；完整 native pipeline 因内置人像 0 的 `faces=[]` 失败，模型实际 SHA 正确。64,591,343 字节、SHA-256 `edb81bdf47212da1fa098ff49394e3ef10496ae12ea630aebd15fd7c841b304f` 的候选仅在 `.tooling` 隔离，未移入 `dist`，不是 accepted IPA。当前 [43363664824](https://github.com/1162107757/nikon-camera/actions/runs/43363664824) / `75dad83` 仅以 `native-diagnostic` 安全阶段数字定位 Vision / mesh，不构建或验收 IPA；后续必须通过完整 `full` 门禁。
- Windows 默认 Impeller 下曾有控件宿主退出；Viewer / Live 及批量测试使用 `--no-enable-impeller`。批量完整 9/9 已取得实际 exit 0 / All tests passed，先前“三项未完成”的记录保留为历史，不再作为当前结果；此宿主参数不等于实体 Android / iOS 图形问题全部解决。
- Android 当前实测为 API 31 / x86_64 / 4 KiB 页模拟器。实体荣耀 Magic、物理 16 KiB 页设备、iPhone、Nikon/Fuji、双卡和大库存不在模拟器证据内。
- iOS 后台时间由系统决定，不承诺无限后台相机传输；未知快门或槽位变更结果不自动重发。
- Universal Link 需真实 HTTPS 域名/路径、签名 Team ID、Bundle ID、Associated Domains 与 AASA 一致。自签名渠道也须满足这些条件；不能用虚构地址完成配置。
- Android QQ 新包名 / 证书登记尚未核实生效，iOS Universal Link 用户明确尚未配置；定向 SDK / 后端检查不代表真实 QQ 登录通过。已发生的线上操作仅为只读证据捕获和用户正常管理员登录：两函数 Active 回退代码、数据库 022 未应用的前置证据及两份 IAM 当前版本 1 已取得，没有为 CLI 新增权限，也未部署、上传草稿或公开发布。用户明确暂不发布，当前仅本地测试；[离线部署审查方案](../../dist/migration213/deployment-review/PLAN.md)和[交互登录工具说明](../../dist/migration213/deployment-review/ADMIN-LOGIN.md)保留为资料，不作为继续发布的授权或当前下一步。

相机组细项见 [213 相机状态](status-camera-213.md)，编辑 / 批量检查见 [编辑与生命周期状态](status-editing-lifecycle-213.md)，账户/迁入/发布规则见 [账户与交付开发记录](account-delivery-development.md)。Android 源码、摘要、签名和各自运行证据已经分项记录；Apple 最终产物及剩余平台 / 外部 / 实体设备结果待完成后另归档。
