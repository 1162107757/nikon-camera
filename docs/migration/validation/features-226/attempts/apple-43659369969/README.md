# 旧0bf来源的Apple失败原件

本目录只属于 `0bf8da5d55996aa4aa0e3a70301f37a88f0eba7b` 的 [full run43659369969](https://github.com/1162107757/nikon-camera/actions/runs/43659369969)，结论为 **failure，未接受**。它不代表新61423d6来源的结果，也没有安装包。

真实首错为JVM准备中的 `Live ingest boundary 120`，位于LiveIngestBoundaryTest.java:108第二个返回路径相等断言。此前NEF提交、原始字节和photoCount断言均已过。fixture使用非canonical临时路径，而生产返回canonical文件路径；macOS `/var` 与 `/private/var` 别名是源码合同推断，实际比较字符串未在原日志打印。两处expected canonicalPath的修正后，新来源须独立完整验证，不能把旧失败改写成通过。

- [完整诊断](DIAGNOSIS.md)、[机器结论](diagnosis-result.json)。
- [原始21行失败步骤](<workflow-logs/apple-app/6_Verify core parity and prepare native runtimes.txt>) 与 [workflow原ZIP](workflow-logs.zip)。
- [原始artifact收据](diagnostic-artifact-receipt.json) 与 [原ZIP](diagnostic-artifact.zip)：2486B，SHA与GitHub digest相同，仅bootstrap/version，未到Flutter/UIKit/native/IPA验收。
- [冻结源证据](frozen-source-evidence.json)：五份来源0bf的精确GitHub blob与内容摘要，后续工作树修改不改变证据。
- [原始字节清单](diagnosis-byte-manifest.json)、[本次复制收据](archive-receipt.json)：29份必要诊断原件200,846B，加原清单共30份206,472B，复制未移动，逐字节一致。

本次归档没有重新GET、重跑测试、触发构建、修改源码/门禁、复制旧APK或发布。新来源状态由上级候选文档与独立当前run收据维护。
