# f3 候选：暂扣，未交付

源码 `f3b6eeca671cd0336dd75f5862129d59364b1e76` 的 Android 实装 QA 发现 RAW 显影返回相册后点击失效，冷重启恢复，因此候选在交付前暂扣。[结果记录](result.json)及本目录原始快照保留其两 ABI 静态检查、x64 R8 78 项通过与真实包摘要；这些通过不抵消该 UI 问题，也不继承到后续修复源码。

Mac 运行 [43453345679](https://github.com/1162107757/nikon-camera/actions/runs/43453345679)最终为 completed / failure。[原始 check annotations](apple-capacity-annotations.json)与 [job 摘要](apple-job-summary.json)已封存并绑定 SHA：`apple-app` job 为 cancelled，`runner_name` 为空，没有 steps；原因是 `The job was not acquired by Runner of type hosted even after multiple attempts`，另有 3 条 arm64 runner 容量通知。该 job 没有获得执行器，没有执行 Mac 产品编译或测试，不能记为产品测试失败或通过。

既有本地 Dart 75 项增量、核心 1629 项、原生 JVM 309 项与格式 6 项证据仍按各自实际执行范围保存，不因执行器容量问题改写。此候选没有接受的 IPA，没有交付附件。后续修复源码与新运行见 [总记录](../../README.md)，其验收不会回写本候选；客户端仍仅本地测试、不公开发布。
