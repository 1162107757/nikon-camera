# 来源61423d6：Mac full695/2失败原件

此目录仅属于 `61423d6b144229e3113edd54da6597177efc0555` 的 [full/macOS26 run43660752971](https://github.com/1162107757/nikon-camera/actions/runs/43660752971)。结论为 **failure，未接受IPA**，不是后续修复来源的结果。

真实Flutter结果为695 passed / 2 failed。两个失败均是camera_live_panel_226_test.dart的确认就绪等待：line172与225在点击初始开始后调用pumpAndSettle，而checking动画会持续到真实确认弹窗返回，所以全局无动画等待超时。后续RAW格式冻结、bounds、真图解码等业务断言未在这两case走到，不能宣称已通过。主任务后续只修等待真实FilledButton“开始拍摄”可命中的predicate，原始业务断言全部保留；修后结果另行记录。

- [诊断](DIAGNOSIS.md)、[机器结论](diagnosis-result.json)。
- [完整Flutter原log](diagnostic-artifact/mobile-apple/flutter-tests.log) 164,524B，摘要见原清单；其他695个通过不抵消两个失败。
- [workflow原ZIP](workflow-logs.zip) 27,376B；[diagnostic原artifact](diagnostic-artifact.zip) 36,984B，SHA与[GitHub artifact收据](diagnostic-artifact-receipt.json)完全一致。
- 原生准备/Objective-C1865 parity、unsigned Runner.app build、analyze及公网schema2的个别原件均保留。它们不代替失败的全Flutter门禁，未到成功UIKit/native integration/IPA接受。
- [原41份字节清单](diagnosis-byte-manifest.json) 与 [本次复制收据](archive-receipt.json)：41份必要原件355,383B，加原manifest共42份，逐字节一致。没有移动、覆盖或修改旧原件。

归档时未GET/POST、未启动SDK或重跑、未改产品/测试/门禁、未碰Android目录或五份候选文档，也未复制或促进任何安装包。后续最新来源与平台状态由上级文档及独立新run收据说明。
