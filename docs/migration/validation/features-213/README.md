# 213 验证与交付证据

目标：跨端新版 Android / iOS。开发范围和外部验收事项见 [213 总表](../../remaining-work-213.md)，实际附件见 [交付目录](../../../../dist/migration213/README.md)。

用户已明确“暂不发布，我先测试”。当前范围仅交付本地测试包、继续 iOS 修复和完整验证；生产 022、IAM、函数部署、上传草稿及公开发布全部暂缓。A13 离线资料保留，不作为当前执行目标。

## Android

最终生产源码为 `3db73d2575fc93296e0995c5476c237397c2a1a7`。ARM64 与 x64 APK 的版本、摘要、大小、证书及 ABI 见 [安装包清单](../../../../dist/migration213/ARTIFACTS.json)与[原生验签和对齐证据](android-signing-alignment.json)。正式包的 ZIP 数据页与全部 ELF LOAD 均满足 16 KiB 对齐；这不代替实体 16 KiB 设备运行。

| 证据 | 实际结果与范围 |
| --- | --- |
| [原生 119 项](android/native-119.json) / [日志](android/android-native.log) | API 31 / x86_64 / 4096 字节页模拟器；原生媒体编解码、真实前台服务、Activity 关闭与同 engine 后台接管、旧宿主释放、快速停启代次及通知停止。绑定源码文件 SHA |
| [正式 R8 41 项](android/release-runtime.json) / [日志](android/release-runtime.log) | 最终签名 x64 APK；真实面部网格、语义皮肤、渲染像素变化、修补、取消、全新 RAW JNI 缩略回调和原文件保护。绑定实际 APK 与 R8 mapping SHA |
| [完整 Flutter/native 场景](android/native-pipeline.log) | 实际跨通道图像、原图、相册、项目、人像和修补；RAW 八方向、嵌入 JPEG 与 RAW 方向冲突、坏缓存重建与不生成全量编辑缓存 |
| [旧版资料实测](android/legacy-device-export.json) | 原 186 不卸载升级至同签名 194；原 launcher 与迁出 launcher 均可用，系统文档保存 ZIP，CRC/六份负载摘要验证；新版正式 APK 预检、迁入、保留五个既有文件及撤回完成 |
| [最终服务端收据](server-result.json) / [日志](server-final.log) | Node v20.20.2、`TERM=dumb`、串行 235 项：228 通过、7 项旧签名包夹具跳过、0 失败，exit 0；日志 SHA 与收据一致，来源 `3754f22458e5aca054d82f6a28cbc5d7e5cacd75`。[84 个 JavaScript 模块语法检查](../../../../.tooling/next213/server-final-check.log)通过。先前 [225 项记录](android/server-serial-test.log)保留为历史，跳过项不计通过；这些结果均不代表生产部署 |

41 是共同运行检查总数，不按每类功能重复累加。原生 119 项、正式 R8 检查与综合 Flutter/native 场景是不同安装包/入口的独立证据。

包含用户旧照片、预设和草稿的迁出 ZIP 仅存在忽略的本地目录，未收入仓库或审阅包。旧维护版 194 的实际版本名为 `0.30.34-migration-export`，支持原四 ABI，35,368,260 字节，超出旧更新渠道 32 MiB 预算，只作独立手动安装附件。

## Apple

完整执行 [43359970364](https://github.com/1162107757/nikon-camera/actions/runs/43359970364) 的来源为 `6c976ba2328cf854d04057694bb3325963807587`。实际通过设备 release `Runner.app` 编译（110.8 MB）、模拟器编译、全部 260 项 Flutter（含 batch 9 项）、1185 项 JVM / Objective-C 核心一致性及图像指纹、38 项头像、24 项 Wi-Fi 流，以及真实 PhotoKit 授权 XCTest `testPhotoLibraryConsent` 1 项（0 失败）。PhotoKit 授权通过不等于 NEF 或批量发布 / 删除通过。

完整 native pipeline 的[实际结果](../../../../.tooling/next213/apple-43359970364-artifacts/mobile-apple/simulator-result.json)为 `success=false`：`retouch_pipeline_fixture.dart:30` 要求内置人像 0 执行实际 face model 后非空，实际返回 `faces=[]`。模型准备及实际资源 SHA 均正确；摘要匹配不能替代推理、渲染和完整场景通过。

该轮生成的未签名 ARM64 / iOS16+ 候选为 64,591,343 字节、SHA-256 `edb81bdf47212da1fa098ff49394e3ef10496ae12ea630aebd15fd7c841b304f`，已独立核对大小 / 摘要，但只保存在忽略目录 `.tooling/next213/apple-43359970364-artifacts/mobile-apple/`，未移入 `dist`，不是 accepted IPA。不得用设备构建成功、候选结构核对或单独 PhotoKit XCTest 代替完整门禁。

当前 [43363664824](https://github.com/1162107757/nikon-camera/actions/runs/43363664824) / `75dad836c7dddf2ec7ac964ea7baaa2d78534204` 为 `native-diagnostic`，仅增加安全阶段数字以定位 Vision 候选 / mesh 输出；不构建或验收 IPA。修复后仍必须执行完整 `full` 门禁，并核对该次最终 IPA，才可讨论接受或交付。

已经修复实际构建发现的 Mac 路径重试、J2ObjC 可移植 API、干净模型准备、重复资源目录、primitive 数组写入及 QQ 常量词法问题；中间一次官方 QQ SDK 下载 TLS 超时增加了有限重试，仍校验证书和固定 SHA。iOS Limited 授权下删除重试在不可见时失败关闭，不能把未授权照片推断为已删除。

## 验收边界

没有连接实体相机、实体 iPhone 或实体 16 KiB Android 设备；Wi-Fi / USB 遥控、槽位、双卡、大库存、后台电池策略与有限相册权限切换仍需现场验证。iOS 后台使用系统有限收尾时间。QQ Android 登记仅收到用户“能”的答复，未验证生效；iOS Universal Link 用户明确未配置。

生产两函数 Active 回退代码及两份 IAM 当前版本的只读证据已抓齐，022 尚未应用。已发生的线上操作仅为只读捕获和用户正常管理员登录，未部署、上传草稿或公开发布。用户明确暂不发布，当前只交付本地测试包；[交互登录工具](../../../../dist/migration213/deployment-review/ADMIN-LOGIN.md)、235 项测试和离线审查包保留为资料，不构成继续生产操作的授权。

原工程冻结核对仍为 420 个文件：8 个批准修复、412 个其他文件不变。历史 211 / 212 记录按原样保留。
