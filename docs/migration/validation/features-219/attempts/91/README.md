# 91未交付候选：旧5通过但pipeline失败

源码`91ae4b6b7352eba4c6d116cd4afee2334ffd742c`的Android精确门禁78/冷启动2·50·19通过，[索引](result.json)保留14份小快照、[Android收据](android-final-receipts.json)/[冷启动](final91-exact-apk-cold-launch.json)/[R8](release-runtime-result.json)。旧两APK与完整记录只属91，不公开复制二进制，不移作e554附件。

Intel full43471565460实际GitHub结论failure（非cancelled），真实Flutter449全部通过、旧5UIKit/0fail56.134s，但严格foreground检查expectedtrue/actual1，nativepipeline及后续Retouch/RAW未完成。[独立核实记录](../../native-cancellation/old-full/43471565460/README.md)含旧候选IPA源91/64,890,419B/SHA efa30…，fullParityCompletefalse、未接收/未复制/未交付。

独立ARM诊断43479234183同源旧5UIKit/0fail13.195s，随后同strict foreground line18错误，marker未出、后续pipeline未完成、无IPA，见[诊断记录](../../native-cancellation/diagnostics/43479234183/README.md)。两次旧5分列，不相加为10，不算新增断言通过；actual1表明presenter已找到，错误是JSON类型。

新e554只改前台快照两C比较为真布尔，并在原同5case加入5布尔/2计数字段原值及JSON往返CFType断言，strict Dart保持原字节；见[修复](../../native-cancellation/bool-contract-fix/README.md)。新ARM full必须跑新断言、完整pipeline与IPA，旧候选均hold禁止交付。原19照片/637文件受保护，QA清理与RAW产品删除失败边界仍分开。
