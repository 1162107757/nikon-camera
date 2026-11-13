# 213 验证与交付证据

目标：跨端新版 Android / iOS。开发范围和外部验收事项见 [213 总表](../../remaining-work-213.md)，实际附件见 [交付目录](../../../../dist/migration213/README.md)。

## Android

最终生产源码为 `3db73d2575fc93296e0995c5476c237397c2a1a7`。ARM64 与 x64 APK 的版本、摘要、大小、证书及 ABI 见 [安装包清单](../../../../dist/migration213/ARTIFACTS.json)与[原生验签和对齐证据](android-signing-alignment.json)。正式包的 ZIP 数据页与全部 ELF LOAD 均满足 16 KiB 对齐；这不代替实体 16 KiB 设备运行。

| 证据 | 实际结果与范围 |
| --- | --- |
| [原生 119 项](android/native-119.json) / [日志](android/android-native.log) | API 31 / x86_64 / 4096 字节页模拟器；原生媒体编解码、真实前台服务、Activity 关闭与同 engine 后台接管、旧宿主释放、快速停启代次及通知停止。绑定源码文件 SHA |
| [正式 R8 41 项](android/release-runtime.json) / [日志](android/release-runtime.log) | 最终签名 x64 APK；真实面部网格、语义皮肤、渲染像素变化、修补、取消、全新 RAW JNI 缩略回调和原文件保护。绑定实际 APK 与 R8 mapping SHA |
| [完整 Flutter/native 场景](android/native-pipeline.log) | 实际跨通道图像、原图、相册、项目、人像和修补；RAW 八方向、嵌入 JPEG 与 RAW 方向冲突、坏缓存重建与不生成全量编辑缓存 |
| [旧版资料实测](android/legacy-device-export.json) | 原 186 不卸载升级至同签名 194；原 launcher 与迁出 launcher 均可用，系统文档保存 ZIP，CRC/六份负载摘要验证；新版正式 APK 预检、迁入、保留五个既有文件及撤回完成 |
| [服务端串行测试](android/server-serial-test.log) | 225 项：218 通过、7 项因旧签名包夹具缺失跳过、0 失败；另有 83 模块语法检查通过。此结果不代表生产部署已执行 |

41 是共同运行检查总数，不按每类功能重复累加。原生 119 项、正式 R8 检查与综合 Flutter/native 场景是不同安装包/入口的独立证据。

包含用户旧照片、预设和草稿的迁出 ZIP 仅存在忽略的本地目录，未收入仓库或审阅包。旧维护版 194 的实际版本名为 `0.30.34-migration-export`，支持原四 ABI，35,368,260 字节，超出旧更新渠道 32 MiB 预算，只作独立手动安装附件。

## Apple

最新候选为 `8d4a0d06fe95ad35dbb0a96c81487d40178e147d` / [运行 43357541556](https://github.com/1162107757/nikon-camera/actions/runs/43357541556)，最终设备编译、模拟器原生流水线及 IPA 独立核验仍在进行。先前两轮已实际通过全部 260 项 Flutter 检查；1185 项 JVM / Objective-C 核心一致性及图像指纹、38 项头像、24 项 Wi-Fi 流检查和 clean checkout 模型精确摘要也已通过。它们不能代替尚未取得的本轮完整成功凭据。

已经修复实际构建发现的 Mac 路径重试、J2ObjC 可移植 API、干净模型准备、重复资源目录、primitive 数组写入及 QQ 常量词法问题；中间一次官方 QQ SDK 下载 TLS 超时增加了有限重试，仍校验证书和固定 SHA。iOS Limited 授权下删除重试在不可见时失败关闭，不能把未授权照片推断为已删除。

## 验收边界

没有连接实体相机、实体 iPhone 或实体 16 KiB Android 设备；Wi-Fi / USB 遥控、槽位、双卡、大库存、后台电池策略与有限相册权限切换仍需现场验证。iOS 后台使用系统有限收尾时间。QQ Android 登记仅收到用户“能”的答复，未验证生效；iOS Universal Link 用户明确未配置。生产更新服务尚未部署或发布。

原工程冻结核对仍为 420 个文件：8 个批准修复、412 个其他文件不变。历史 211 / 212 记录按原样保留。
