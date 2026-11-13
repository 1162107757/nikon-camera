# 219 Dart 相机流程回归

[75项原独立覆盖](final-result.json)的增量执行基线不改；[另8项](supplements/legacy-fixture-contract/README.md)仍按原6+2文件执行记录保留。最终e554/ARM full43482938724的449项Flutter全套实际通过，两份旧fixture已在新全套覆盖，不将各组重复相加。[CI](../apple/ci-result.json)与[IPA核验](../apple/independent-verification.json)已成功，三包仅本地测试/publishedfalse；旧91及其他候选失败史继续分列。

只读复查随后找到显式断开等待旧任务停止后可能误关新连接的漏项，已获准仅补 `camera.dart` 及其测试。[显式断开增量](supplements/scoped-disconnect/result.json)记录最新 intent15 整文件实际通过，其中 11 项已含在旧 71 中，新增独立场景为 4 项；不将 15 再全数加到 71，也不把跨阶段覆盖称为一次同源完整 75 项运行。新旧输入按 [最终源绑定](../final-source-binding.json)核对至e554，原始执行上下文不改写。

## 实际通过记录

以下 **9 个文件、71 个独立用例**均取得各自进程 `All tests passed / exit 0`，不把重复尝试累加。

| 测试文件 | 通过数 | 原始日志 |
| --- | ---: | --- |
| camera_intent_test.dart | 11 | [日志](logs/camera219-final-camera_intent_test.log) |
| camera_controls_test.dart | 4 | [日志](logs/camera219-single-camera_controls_test.log) |
| camera_live_test.dart | 17 | [日志](logs/camera219-single-camera_live_test.log) |
| camera_downloads_test.dart | 12 | [日志](logs/camera219-single-camera_downloads_test.log) |
| connection_protection_test.dart | 9 | [日志](logs/camera219-single-connection_protection_test.log) |
| camera_test.dart | 6 | [日志](logs/camera219-final-camera_test.log) |
| camera_navigation_test.dart | 1 | [日志](logs/camera219-final-camera_navigation_test.log) |
| camera_previews_test.dart | 5 | [日志](logs/camera219-final-camera_previews_test.log) |
| camera_transfer_test.dart | 6 | [日志](logs/camera219-final-camera_transfer_test.log) |

覆盖导入连接成功返回所选预设槽位且不读照片、已连接时直接继续、失败 / 取消 / 换账号与迟到结果、健康槽位模式不假报断线或零照片、只在显式同步照片页读取、完成连接不被离页取消，以及槽位 / 遥控晚到打开结果只回收自身资源。权限 `inactive` 不误停接收，真实后台仍按保护策略暂停；前后台指令串行，最新恢复状态最终生效。手动断开入口保留。平台调用由测试桩隔离，不代表真实相机连接、槽位写入或手机系统授权已通过。

[结果元数据](result.json)保存每份日志 SHA-256；[原始本地收据](original-local-results.json)按其生成时的 base commit 和未提交状态原样保留。[源指纹](source-fingerprints.json)将当时 16 个实际输入绑定到旧候选 4f：12 个与 Git 内容原字节一致，4 个仅工作区 CRLF 与 Git LF 不同，16 个统一 LF 后全部一致。没有把不同的原始摘要写成相同；后续显式断开补丁的两个新输入另在增量收据中记录。

主任务的既有全 App 静态分析为 **No issues / exit 0**，原始 [日志](all-app-analyze.log)与 [结果](all-app-analyze-result.json)已复制；其后显式断开两个目标文件也取得 No issues。最终 Dart 独立覆盖 75、[当前共享核心](../core/result.json)和 [Android 原生取消 JVM 309 项](../native-cancellation/result.json)分别记录，不构造一个重复计数的总和。iOS UIKit / Foundation 与 PhotoKit 共5项已在本轮ARM full实际通过，新增类型断言和完整pipeline均成功；真实设备仍未验证。

## 失败与未完成历史

| 尝试 | 实际情况及后续处理 |
| --- | --- |
| [首轮连接 / 保护合组](attempts/camera219-intent-protection.log) | 两个用例使用不识别原式 HueHeader 的 `tester.pageBack` 而失败；后续三个用例未完成。改用真实系统返回后，最终 intent11 单文件通过。首轮整组不算通过；[原退出收据](attempts/camera219-intent-protection-result.json)保留。 |
| [首轮导航 / 生命周期](attempts/camera219-navigation-lifecycle.log) | 遥控测试错误假定经过一段时间只能收到 1 帧，实际收到 2 帧。改为验证临时遮挡期间帧数继续增长、真正后台后不再增长；最终 controls4 通过。[原退出收据](attempts/camera219-navigation-lifecycle-result.json)保留。 |
| [大组内存失败](attempts/camera219-dart-regression.log) | intent10 后，加载下一文件时 Dart `allocation.cc:30` 报 `Out of memory`，该批未完成并被停止，没有生成该批退出 JSON。未执行部分不计通过；随后采用每文件新进程取得上述实际结果。 |
| [相机页首轮](attempts/camera219-single-camera_test.log) | 测试复用连接页 State，没有像真实流程那样先离开再进入照片页。修正页面生命周期后，最终 camera6 全部通过。[原分文件退出收据](attempts/camera219-single-file-results.json)仍含该次失败，未覆盖改写。 |

完整原生与设备门禁由主任务统一执行。以上历史失败不被归因成已验证的相机硬件故障，也不抹去或假记为通过。
