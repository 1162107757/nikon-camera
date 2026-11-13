# 旧连接与会话夹具按仅连接合同适配

Mac `43464094785` 的 Flutter 全套实际为 447 通过、2 失败：旧夹具仍断言配置页连接后自动读首屏，并依赖已移除的连接状态文案。此处只改 `camera_connection_test.dart` 与 `session_race_test.dart`，九个产品 Dart 源的原始 SHA 全部未变。生产行为仍为连接成功返回调用方，照片只在用户显式进入同步照片页时读取。

[结果](result.json)与[最终内容绑定](final-source-binding.json)已纯绑定`e55414ad38ab04291313ddc1244a7ec778da659f`，11个夹具/产品输入未变、没有重跑。实际执行HEAD仍89c、两个fixture当时未提交；原91绑定和结果在bindings/，原始未绑定结果也保留，不倒写为在e554执行。两个完整文件在独立进程中实际通过：

| 完整文件 | 实际结果 | 原始证据 |
| --- | --- | --- |
| `camera_connection_test.dart` | 6/6，All tests passed，exit 0 | [日志](camera_connection_test.log)、[退出收据](camera_connection_test-result.json) |
| `session_race_test.dart` | 2/2，All tests passed，exit 0 | [日志](session_race_test.log)、[退出收据](session_race_test-result.json) |

这 8 项包括 7 项相机断言和 1 项原个人同步 owner / 既有预设选择断言，单列补充，不把它们混写为原 75 项的一次完整重跑。目标两文件 [分析](target-analyze-final.log)为 No issues / exit 0，[差异检查](diff-check.log)为 exit 0。[输入指纹](final-inputs.json)保留最终两个夹具和九个未变产品源的摘要。

连接专项保留权限阶段、准确 job、取消确认阻塞、迟到结果、超时、USB 授权等待与 dispose 边界。成功路径使用真实 `connectCamera` / Navigator 返回 `true`，连接页不发 page / preview，不在 dispose 取消已完成握手；显式 Sync 才以同一 session 发起 page。取消只针对 page job，不发 `camera.disconnect` 或取消已完成握手，Fake native status 保持该 session。会话竞争仍先挂住旧 status，连接成功后再完成旧“未连接”回包，验证它不能覆盖新状态；随后新照片页才显式以 `new-session` 分页。个人同步原断言保留。

初次适配 [5 过 1 失败](attempt-first-route-frame/camera_connection_test.log)为新路由 / status 的首帧夹具等待不足。其后一次 [5 过、最后未完成](attempt-pending-native-and-route/camera_connection_test.log)及实际 exit 1 均保留，未计为通过，也不定性为宿主崩溃。最终夹具立即终结取消 job 对应的 native page Completer，pending IO 期间只做有界 pump，状态先 dispose 再关闭事件流，并移除额外第三次导航；最终完整 6 项实际通过。

原 [Mac 失败摘录](mac-43464094785-failure-excerpt.log)与[修前记录](before.json)保留完整 Mac 日志摘要。此处使用 Fake native IO / 状态 / 进度流，不能证明实际相机、系统权限或新 IPA 通过；核心、原生与完整 Apple 门禁由根代理另行执行。

最终e554/ARM full43482938724的449项Flutter和完整平台门禁现已成功，原6+2分文件基线和失败/未完成历史保持原样，不重复累加。
