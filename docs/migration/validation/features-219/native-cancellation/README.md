# 219 原生相机取消边界

本目录记录 Windows 上实际完成的检查，源文件 SHA-256 见 [result.json](result.json)。这些检查不代表 iPhone 或 Z6II 实连验收。

证据已绑定冻结源 `4f9f1dc6d32d41f7b0179dac7436addc35ff6699`；16 个已记录源文件的实际字节 SHA 全部一致。Mac full `43448048561` 当时仍待结果，不将已选择的 5 项 XCTest 写作通过；本次只读复审没有重跑测试或修改产品源码。

当前源为 `e55414ad38ab04291313ddc1244a7ec778da659f`，主 ARM full `43482938724` 的[本轮原生证据](executions/43482938724/README.md)已确认：JVM实际309项/100轮竞争、UIKit5项（含新JSON类型断言）及完整native pipeline均通过。前台必经断言由严格机器结果证明，未观察到快照，记录snapshot为null，不编造计数。IPA独立最终验收由根代理负责。[旧 Intel full](old-full/43471565460/README.md)候选仍hold。原4f执行与16项指纹不改写；其中14项上下文未变、2项布尔修复输入单列，57份源检查的历史执行基线也保留。

最终[公开CI收据](../apple/ci-result.json)与[独立包验证](../apple/independent-verification.json)已完成，根代理实际验证器exit0，仅接受本地测试、未发布。UIKit本轮5项/0失败为14.001秒；`nativeForegroundSnapshot=null`、`nativeForegroundSnapshotEvidence=machine-test`、`nativeForegroundSnapshotFixturePassed=true`。原始[309项JVM日志](executions/43482938724/native-task-tests.log)保持原路径。

同91源的 [ARM诊断 `43479234183`](diagnostics/43479234183/README.md)取得5项 UIKit实际通过（0失败、13.195秒），但 native pipeline 在前台 DTO 检查中失败：布尔字段被返回为数字1，不能算完整原生或 IPA验收。随后修复绑定e554，总用例数仍5；旧91的通过不包含新增类型断言。

89c 的 Mac `43464094785` 在 Flutter 447项通过、2项旧测试失败，并发生 iPhone 生产编译只读属性写入错误；该次未取得5项 Foundation/UIKit成功收据。失败历史保留，不因本次绑定改写成通过。

历史失败分别保留：a54的 Mac `43458258245` 因 [avatar 夹具混编错误](fixture-fixes/avatar-a54-mixed-language/README.md)失败；同89c的旧运行 `43463073963` 因依赖 Git reset/early EOF（exit128）在后续门禁前失败。两次均未执行5项 Foundation/UIKit，不合并成新版测试失败或成功。

- Android 生产 `NativeTaskCancellation`：**309 项断言、exit 0**，含活动 I/O 唤醒、重复取消、已完成/未知任务、替代任务保留，以及 100 轮 finish/cancel 并发竞争。完整输出见 [JVM 日志](camera219-native-task-tests.log)，精确命令见 [命令收据](camera219-native-task-tests.json)。
- [平台源检查](camera219-native-source-check.log)：exit 0；934 个 UTF-8/配置文件、既有只读细节渲染 21 项边界。不是新增相机实机测试数。
- [Apple 脚本语法](camera219-shell-syntax.json)：`bash -n` exit 0。
- [新增前台 fixture Dart 分析](camera219-analyze.log)：exit 0，No issues found。

重跑 Android 生产状态类边界：

```text
python cross-platform/tool/native_task_check.py --build-dir .tooling/agent-camera/native-task-jvm
```

修复让未知、已完成和重复任务无法向相机继续发送取消；worker 在结果投递 UI 前结束任务的取消权限，真正活动任务仍能中断 I/O。iOS 后台保护每次 lease 使用独立 token，结束时先作废；迟到的旧 expiration 不能取消新的 lease。

**iOS Foundation/UIKit 尚未在本收据中运行，待 Mac 门禁。** `apple_integration.sh` 现选择 5 项 XCTest：原 PhotoKit 授权 1 项、当前场景/注册控制器恢复及排队取消 3 项、生产 Foundation 取消 token 1 项（包含旧 lease 作废后新 token 不受影响）。完整 native pipeline 另调用 `verifyCameraForegroundPresentation`，核对实际运行应用的活跃场景/窗口，不用注入窗口代替集成结果。

PTP 指令、相机 GUID 和设备 ID 未因本修复调整。218 已交付产物保持冻结。

对4f的历史只读复审确认 CoreToken、slot 原子移交/取消关闭屏障与 native 任务结束栅栏一致，并核对 [Dart 相机收据](../flutter-camera/result.json) 为9文件合计71项分批实际通过。该轮另报告了既有 `ConnectAttempt` watchdog 迟到关闭竞态，随后由核心负责人另行修复；其新执行证据由[核心会话收据](../camera-session/result.json)单独记录，不改写本目录原309项执行。
