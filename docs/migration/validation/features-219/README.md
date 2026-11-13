# 219 验证记录

最终平台源码 **`e55414ad38ab04291313ddc1244a7ec778da659f`** 已完成三包本地测试验收，ARM full **`43482938724`** 真实success、IPA独立核验通过。[附件清单](../../../../dist/migration219/ARTIFACTS.json)为 `acceptedForDelivery:true / scope:local-testing-only / published:false`。Android78/冷启动与a54功能UI来源仍分列，旧失败史不改写；这不是商店/更新清单公开发布。

f3 候选实装发现 RAW 显影返回后相册点击失效，已暂扣、未交付；其静态与 R8 78 项结果仍仅属历史，[f3 暂扣记录](attempts/f3/result.json)固定证据。a54 只新增 RAW 返回修复 / 回归和可选 Intel 执行器工作流三个文件；两条真实路由回归各自通过，不继承 f3 的安装包验收。

旧快照 `4f9f1dc6d32d41f7b0179dac7436addc35ff6699` 和运行 `43448048561` 属于[未交付旧候选](attempts/4f/result.json)：核心 parity 通过，后续头像取消夹具编译失败，且另有看门狗 / 显式断开竞争修复。旧构建或旧门禁结果不继承为新源码验收；历史记录原样保留。

## 本地实际验证

| 范围 | 实际结果 | 证据与限制 |
| --- | --- | --- |
| 共享 Java 17 核心 | **1629 项，exit 0** | **1623 共享 + 6 氛围**，实际全量编译执行产生 golden；后按未变输入纯绑定最终源码，不重跑。[完整日志](core/core-check.log)、[结果](core/result.json)、[golden](core/golden.json)。会话 167 / 连接 65 已包含，不额外相加。 |
| Dart 相机流程 | **75 个独立用例，9 文件增量验证** | 最新 intent15 替换原 intent11；其余为控制 4、Live 17、队列 12、保护 9、相机页 6、导航 1、预览 5、传输 6。[最终归并结果](flutter-camera/final-result.json)明确不是一次同进程 / 同源完整 75 项运行；[旧71](flutter-camera/result.json)与 [新增断开4项](flutter-camera/supplements/scoped-disconnect/result.json)分别保存真实日志、源指纹和失败历史。最终同源Flutter全套449项已实际通过。 |
| 照片格式标签 | **6 项，exit 0** | 新格式与卡片至编辑器 4 项、既有相册 1 项、既有编辑菜单 1 项。[专项说明](flutter-format/README.md)、[结果](flutter-format/result.json)。当前 JPG 与 NEF 来源分开显示；没有更换原文件或修改解码、显影与像素处理。 |
| RAW 返回相册 | **2 条真实 GoRouter 用例，各自 exit 0** | [专项说明](flutter-raw-return/README.md)、[结果](flutter-raw-return/result.json)。手机导入与相册选择分别验证 RAW → JPG 编辑器 → 返回后解除交互锁；既有 format4 再次通过，不重复累加为新的格式用例。初始锁断言 / 夹具杂错及宿主未完成记录保留。 |
| 生产 Android Java 取消门控的宿主检查 | **309 项断言，含 100 次 finish / cancel 竞争** | [独立记录](native-cancellation/result.json)、[原始日志](native-cancellation/camera219-native-task-tests.log)。单独列出，不并入共享核心 1629，也不等同 APK R8 实装结果。 |
| 旧连接fixture补充 | **完整6+2，分别exit0** | [8项补充](flutter-camera/supplements/legacy-fixture-contract/README.md)含7相机+1个人同步，保迟到status/独立cancel断言，不合并成原75的一次运行；基线89+未提交fixture，纯绑定e554。 |
| iOS取消API静态迁移 | **57源码检查，actual0** | [实际记录](native-cancellation/api-consumer-migration/README.md)：2消费者/2guard SHA绑定e554，执行基线89+未提交补丁保留，新消费者随e554完整门禁已通过，真实设备仍未验证；不并入Java309或核心1629。 |
| iOS UIKit / XCTest | **新5case/0fail，14.001s** | [真实输出](apple/simulator-tests.log)、[CI结果](apple/ci-result.json)对应e554新RunnerTests，实际含5布尔/2计数字段原值/JSON往返CFType断言；旧91两次5case历史不混入当前结果。 |
| 只读源码与原工程清单 | **89时真实静态记录保留** | [原快照](documentation-checks/README.md)：source_check1032+21、inventory420/8/412均actual0；本次不重跑。新4输入另有57项Apple API静态检查，按SHA绑定e554；不是iOS运行通过。 |

[相机会话专项](camera-session/README.md)记录实际 PTP/IP 状态机与合成 socket 字节、会话移交、已知响应恢复、关闭屏障和未知写入保护；[watchdog 专项](camera-watchdog/README.md)补充暂停时钟恢复、原子成功退休与超时关闭竞争；[显式断开专项](camera-disconnect/README.md)记录原会话 token 与实际断开的同锁校验。它们没有宣称真实 Z6II 或 iPhone 现场连接已验证。格式专项的初次分析为 exit 0、1 条 info，历史保留；最终目标文件分析为 No issues。

## 运行输入与冻结源绑定

新一轮完整核心运行开始前实际 Git 基线为 `323a92a09049620f15d2a52f38ee63fdf7038af3`，当时带有尚未提交的看门狗 / 显式断开补丁；[执行前记录](camera-watchdog/execution-base.json)、[239 个独立输入指纹](core/source-fingerprints.json)和 [252 个编译条目](core/sources.json)保留该上下文，不改写成当时已执行最终源码 Git checkout。当前新 golden SHA-256 为 **`358c02ec990fe2d903f827f8b15ed963550eb231d0d01360f61c00f2196bfdd5`**。旧 1535 / ae856 与 1572 等中间结果分别保存在会话、看门狗的历史子目录，不累加为最终通过数。

本次[聚合绑定](final-source-binding.json)仍为 **290源：225原字节同Git、65仅CRLF/LF、全部LF后同e554，vGit内容差异0**；相对91有 **288原字节未变、2个既有输入确变**（前台快照与RunnerTests），不称allrawsame。原native16上下文14同/2变，实际Java309两个producer未变。核心1629/原75/补充8的基线不重写。新[e554 Android限定证明](android/source-e554-android-ui-equivalence.json)仅证明lib/Android/core/原app相对a54/89/91相同，iOS原生与测试树均确变；旧91与89证明原字节保留。

## Android 平台状态

当前[Android说明](android/README.md)与[精确收据](android/final-receipts.json)绑定e554新两包；R8 78/code-1/exit0与[新冷启动](android/final-e554-exact-apk-cold-launch.json)实际通过2·50·19。完整[18图UI](android/final-ui-result.json)仍为a54/旧SHA，按Android限定证明引用，不冒称新包复跑全部UI。旧91精确收据已[封存](attempts/91/README.md)；4KiB模拟器/16KiB静态不代替ARM64或16KiB实体设备。

实装用 DNG，未用真实 NEF；NEF 标签由独立控件用例覆盖，不等同 NEF 实装通过。没有真实 Z6II 连接结论。QA 删除中 JPG 成功，DNG 先被版本变化保护、以新范围再次删除仍报“项目照片文件名无效”；**RAW 删除不计为通过，既有边界未在本轮修复**。该唯一 QA DNG 后经[独立精确清理](android/cleanup-own-dng/README.md)与 [Download SHA 守卫清理](android/own-download-cleanup.json)完成：20→19，原 19 条记录字节与其余 637 个资料文件 SHA 保留，可回退备份留设备私有目录、产品 APK 不变。最终 UI 为应用 19 / 手机 50 / 预设 2，已恢复原手机来源与预设首页；这不是产品 RAW 删除验收。

f3 的 [签名 / 静态记录](attempts/f3/android-signing-alignment.json)、[10 图记录](attempts/f3/preset-preview-assets.json)、[R8 日志](attempts/f3/release-runtime.log)与 [R8 结果](attempts/f3/release-runtime-result.json)已固定：`checks=78 / PASS 78 / INSTRUMENTATION_CODE:-1 / accepted:true / exit:0` 只代表该候选 R8 门禁。其 RAW 返回 UI 失败仍成立，不能移作 a54 的交付接受结论。

旧 4f 的 [签名记录](camera-session/attempts/4f-core1535/android-signing-alignment.json)及 [图片记录](camera-session/attempts/4f-core1535/preset-preview-assets.json)保持历史归属，不与当前包混用；旧运行 / 反射夹具重试也不移作新源码门禁。218 已交付文件未被覆盖。

## Apple 及真实设备状态

当前e554 [ARM full43482938724](apple/ci-result.json)实际449 Flutter全过、Core parity1629、当前Java cancellation309（含100race）、新5UIKit/0fail14.001s及schema1唯一whole native testcase成功。[独立核验](apple/independent-verification.json)verifiedtrue，实际IPA64,890,557B/SHA`368f299c53ac8b0a8f9e4bcdaec02ac17a1ca14229f8630416b0af95e338580f`已复制dist并按iPhoneOS/arm64/build219/minOS16/unsigned核对。Native foreground snapshot为null、evidence=machine-test、FixturePassedtrue：stdout marker未被Flutter binding日志通道捕获，严格必经fixture源及机器成功结果已验证，未编造窗口/scene计数，未跳过或放宽Dart断言。原IPA核验中的fullParityComplete:false保持原值，accepted只限本次CI/验包后的本地测试，不代表实体设备和外部配置完备。WiFi actual34来自source.json所列本run job132083848480原始GET日志line268/SHA37b44c7cd043395b8cff30c8e1af1659c345a33e6762cec16e2fd5c55e841ec4；未重跑Mac。

f3 候选运行 [43453345679](https://github.com/1162107757/nikon-camera/actions/runs/43453345679)为 completed / failure，但 `apple-app` job cancelled、`runner_name` 空、steps 空。[原始 annotations](attempts/f3/apple-capacity-annotations.json)与 [job 摘要](attempts/f3/apple-job-summary.json)已解析并绑定摘要，确认未获 hosted runner 和 3 条 arm64 容量通知。**该运行没有执行 Mac 产品测试，不能记成测试失败或通过**；f3 另因 Android RAW 返回 UI 问题暂扣。旧 4f 的失败和共享核心 parity 成功也只作为各自历史。

用户为 Nikon Z6II（“Z62”）+ 相机 Wi-Fi，真实 iPhone 前台连接尚未验证；前台窗口、取消与连接生命周期的代码 / 测试修复不等于实体相机成功。未签名 IPA 需用户自签安装。真实 QQ 授权、Android 腾讯登记、iOS Universal Link（尚未配置）、USB 与存储权限、16 KiB Android 设备仍待各自条件验证。QQ 既有后台更新不代表客户端公开发布。

## 保留的清理审批记录

[清理审查记录](flutter-format/cleanup-review.json)确认遗留物仅为已结束菜单测试创建的 **7 个 70B 固定一像素 PNG**。原递归清理请求与随后逐文件 `LiteralPath` 非递归方案均被自动审批拒绝，唯一返回理由为 **`blocked by policy`**，没有更详细原因；这两份后续清理请求未执行，也未继续尝试删除。目录保留不影响产品数据、应用修复或安装包生成。
