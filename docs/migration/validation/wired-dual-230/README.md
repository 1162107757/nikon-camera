# 尼康 Z6 II 有线边拍边传双端联调

用户已确认 Android 与 iPhone 都要测试，相机为 Nikon Z6 II。创建日期为 2026-11-16（Asia/Shanghai）。相机固件、手机型号、系统版本和 iPhone 接口仍待实测时记录。

## 当前交付与源码范围

Android 230 的已交付 ARM64 包 SHA-256 为 `d9f71ece2806c684906905fe73664f9360bc1eb0a8cd87cd57940407eced0145`，保持原包及其验收记录不变。其 263 项产品文件在冻结前逐字节匹配 `dist/migration230/SOURCE-INPUTS.json`，本次仅在隔离分支固定相同产品文件及必要专项测试；Git 的文本行尾转换另以规范化摘要和 Git blob 记录。

iOS 同功能组合已完成完整构建与自动化验证，实际构建源码为 `d4276fb57918af3433cca6cc4d16e1c4445da9c6`。其 263 项产品输入与上述 Android 快照相同，另固定 20 项专项测试输入。[Apple 完整构建记录](https://github.com/1162107757/nikon-camera/actions/runs/43766051626)成功，不能将此前独立 USB live 分支的通过记录替代本次验收。

本地安装包：

- Android：`dist/migration230/huevia-0.31.0-dev-230-android-arm64.apk`，保持既有文件不变。
- iPhone：`dist/migration230-ios/huevia-0.31.0-230-unsigned.ipa`，65,281,795 字节，SHA-256 为 `0ba9408c5c9b90ba4a8adfcdb0bb380d5dd89f64fdec817d461e9781086bae9f`。

IPA 是 iPhoneOS ARM64 真机包，最低 iOS 16.0，未签名，需要用户使用自己的签名方式安装；它不是模拟器包或已签名直装包。本次只交付本地开发候选，没有发布到公开更新渠道。`fullParityComplete` 仍为 false，不宣称整个历史版本迁移已完成。新增 iOS 交付记录位于 `dist/migration230-ios/ARTIFACTS.json`，不修改旧 Android 交付记录中当时的 iOS 状态。

本目录不记录虚构的真机通过结果。模拟器、协议夹具及原生编译均属于软件验证。

## 已完成的软件验证

| 检查 | 实际结果与证据 |
| --- | --- |
| 共享核心 | 本地 2003 项边界与 6 项 atmosphere 通过；其中有线 live 为 97 项。见 `jvm.log` |
| 原项目保护 | 420 项清单、14 项已批准更新与其余 406 项保护验证通过。见 `inventory.log` |
| Apple 共享核心 | Objective-C 运行时 2009 项一致性检查通过；iOS 静态运行时独立构建。见 `apple/core-ios/parity.json` |
| Flutter | 完整 746 项测试通过，静态分析无问题。见 `apple/mobile-apple/flutter-tests.log` 与 `analyze.log` |
| iOS 原生 | 5 项 XCTest 通过，零失败；原生图片/RAW 管线成功。见 `apple/mobile-apple/simulator-tests.log` 与 `simulator-result.json` |
| 原生任务取消 | 309 项取消与竞态检查通过。见 `apple/mobile-apple/native-task-tests.log` |
| 安装包 | ZIP 完整性、ARM64 Mach-O、iPhoneOS 平台、版本、摘要与未签名状态均核对。见 `result.json` 和 `apple/mobile-apple/ipa-verification.json` |

`apple/` 保留本次运行元数据与原始短日志。6 MB 的完整模拟器编译日志保留在经摘要验证的本地 CI 压缩包 `.tooling/wired-dual230/ci-artifact-14183701162.zip`；本目录仅留有线适配器编译摘录及证据索引。照片分块读取 API 自 iOS 13 可用，与此包 iOS 16 下限相容，源码未作额外平台修补。[Apple API 文档](https://developer.apple.com/documentation/imagecapturecore/iccamerafile/requestreaddata(atoffset:length:completion:))

Android 的既有验证限制仍以 `../features-six-230/` 原记录为准。本次 Apple 全绿不能替代 Android 完整联合套件复跑，更不能替代 Z6 II 实拍。

## Z6 II 连接设置

Android 先使用 MTP/PTP 模式（机身固件提供该选项时）和能传数据的 USB 连接。尼康说明中的 iPhone 选项专用于通过 USB-C 转 Lightning 线使用 NX MobileAir，不能据此推定其他应用也使用该模式。[尼康 Z6 II 固件说明](https://onlinemanual.nikonimglib.com/z7II_z6II/en/17_changes_made_via_firmware_updates_04.html)

本应用的 iOS 实现使用 ImageCaptureCore/PTP 通道，因此先按 MTP/PTP 测试是实现推断，仍需通过 Z6 II 实机确认。USB-C iPhone 可测试直接的数据连接；Lightning iPhone 需测试相机转接器连接路径。连接形式参考苹果相机导入说明，不代表 Huevia 的持续收片已经获得硬件兼容认证。[苹果相机连接说明](https://support.apple.com/en-ie/118280)

两端先保持应用前台，只让一个应用持有相机会话。在 Huevia 中检测并选择 USB 相机后，先确认能浏览相机照片，再进入同步页的拍摄接收。记录机身在 USB 会话期间能否正常按快门；若不能拍摄，保留提示和诊断信息，不将等待新照片误记为收片成功。

## 两端相同的真机场景

| 场景 | 操作与预期 | Android | iPhone |
| --- | --- | --- | --- |
| 基础识别 | USB 连接后能识别 Z6 II、浏览既有照片并手动接收一张原文件 | 待测 | 待测 |
| 开始基线 | 卡中保留旧照片，开始拍摄接收；旧照片不会自动补收 | 待测 | 待测 |
| JPEG 单拍 | 选择 JPEG，在机身新拍 3 张；项目增加 3 张且重复刷新不重复入库 | 待测 | 待测 |
| NEF 单拍 | 停止后切换 RAW（NEF）再开始，新拍 3 张；接收 NEF 原文件 | 待测 | 待测 |
| 格式与连拍 | 相机拍 RAW+JPEG，应用选一种格式，连续拍 5 张；仅收所选格式、无重复或半文件 | 待测 | 待测 |
| 软停止 | 传输期间停止，当前传输有明确结果，停止后仍可浏览和手动接收 | 待测 | 待测 |
| 拔线恢复 | 传输时拔线，状态明确暂停；重连核对原相机后手动继续，已收照片不重复 | 待测 | 待测 |
| 身份与重启 | 重开应用或更换相机时不得直接合并旧会话；不能确认身份时开始新任务 | 待测 | 待测 |
| 项目处理 | 无默认预设时只保留原图；有默认预设时另存成品，原文件保持不变 | 待测 | 待测 |

每次记录手机与系统、Z6 II 固件、连接线/转接器、接收格式、开始前旧照片数、新拍数量、实际接收数量和异常提示。后台与锁屏另记暂停、收尾和回前台恢复结果，不承诺 iOS 长期后台持续接收。
