# 旧91 Intel完整运行历史

GitHub运行 `43471565460` 的实际 head 为 `91ae4b6b7352eba4c6d116cd4afee2334ffd742c`，最终结论 **failure，非 cancelled**。本目录只读取该运行的真实产物，未用ARM结果代推，未重新执行测试。

- [Flutter实际449项全部通过](flutter-tests.log)。
- [设备构建日志](device-build.log)记录 Runner.app 111.6MB；私有 IPA候选为 **64,890,419字节**、SHA-256 `efa30a2ec5ccb3c79095f4dbaf8f9b5daea88462a2466225026721fa0194ae59`，与原 [IPA检查](ipa-verification.json)核符。该原收据明确 `fullParityComplete:false`，候选保持 hold，未复制到公共资料或接受交付。
- 实际 x86_64模拟器 [5项UIKit全部通过](simulator-tests.log)，0失败、56.134秒。该次为旧91断言，不含后续新增JSON类型断言。
- [native pipeline实际失败](simulator-result.json)在 `camera_foreground_fixture.dart:18`：期望布尔 `true`，实际数字 `1`。前台 marker尚未打印，后续人像/RAW检查未完成；不是从测试名推断出的codec或RAW失败。

完整来源、原始日志SHA和 e554两份修复源仍保持原冻结哈希的核对见 [result.json](result.json)。当前 e554 ARM full `43482938724` 属独立新运行，本历史不改变其验收状态。
