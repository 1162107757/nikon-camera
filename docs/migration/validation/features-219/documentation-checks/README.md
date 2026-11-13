# 219 当前归档静态检查

本目录记录既有源码/清单命令原始快照及后续文档/JSON/链接扫描；不运行Flutter、Gradle、ADB或Apple测试。两条源码命令当时实际HEAD89c，日志/exit不改写为在e554执行。当前文档扫描绑定e554，ARM full43482938724/新增类型断言/完整pipeline已成功，IPA独立核验通过；真实设备仍未验证；新增原生与测试两文件通过Git内容绑定记录，旧native上下文14同/2变，不称全同。

source_check 实际覆盖 1032 个 UTF-8 / 配置文件与 21 项只读边界，exit 0；inventory verify 为 420 / 批准 8 / 其余 412，exit 0。各执行一次。之后新增归档另行校验 UTF-8 / JSON / 本地链接，不冒称源脚本重跑后的新数量。命令、时间、原始退出码与日志 SHA 见 [result.json](result.json)：

- `python cross-platform/tool/source_check.py`，原始输出 [source-check.log](source-check.log)，进程收据 [source-check-result.json](source-check-result.json)。
- `python cross-platform/tool/inventory.py --verify`，原始输出 [inventory.log](inventory.log)，进程收据 [inventory-result.json](inventory-result.json)。使用只读 `--verify`，没有重写冻结清单。
- 219 归档 Markdown 与两份测试指南的本地链接、UTF-8 / JSON 和差异检查，逐项范围与结果见总收据。历史记录和外部 URL 不冒称已在此重新执行或联网验证。

`camera-session/attempts/4f-core1535/archive-README.md` 是原根说明的逐字节历史快照，搬迁后保留了原相对路径，不能当作当前目录下的导航页。初次全量扫描发现其 18 个原上下文链接未在搬迁位置解析，见[初次扫描记录](attempt-including-raw-archive-result.json)；该快照原字节不改，目标列表和 SHA 单独记录，当前活跃文档链接另行核对，不把这些历史链接报为现行链接通过。

RAW 专项 `bindings/<源码SHA>/README.md` 是原叶目录完整文件集中的原字节快照。扫描逐份核对该目录 result 的源码身份，其相对目标同样单列保存，不改原文，也不把搬迁快照当作现行导航页。这些历史 README 仍做 UTF-8 检查；当前活跃文档链接与它们分开记录，数量和目标清单以总收据为准。

Android 已完成仅本轮 QA 夹具的精确清理，但既有 RAW 删除产品检查仍为失败，见 [Android 收据](../android/final-receipts.json)。核心 1629、相机 Dart 75 增量及其他已记录断言不因本次静态快照重复累加。
