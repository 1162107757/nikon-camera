# RAW 编辑返回相册回归

最终源码：`89c1393272f2164594f9eecc30df7d1f65153d01`。测试命令未记录当时的 Git HEAD；[source-fingerprints.json](source-fingerprints.json) 对测试文件内容和最终 Git 内容作独立绑定，明确记录 CRLF/LF 差异，不把后续绑定说成重新执行。

应用相册的原生文件选择及手机相册导入原先一直持有 `importing`，直到 `context.push` 返回。真实 RAW 自动显影以 `context.replace` 替换路由后，原 push Future 可能不再完成，导致回到相册后仍拒绝照片点击。修复仅把锁限制在选择/导入/登记阶段，进入编辑器前释放；路由错误仍由独立打开方法接收并报告。等待导入时继续阻止重复导入。

实际结果见 [result.json](result.json)：

- [原生 picker 用例](fixed-picker.log)：1/1、exit 0。
- [手机相册导入用例](fixed-phone.log)：1/1、exit 0。两项分别在独立进程执行，不声称该文件曾整套单进程跑完。
- [原有格式回归](original-format4.log)：原测试文件未改，4/4、exit 0。
- [定向分析](analyze.log)：exit 0，No issues found。

新用例使用真实 GoRouter、PhotosPage、RawDevelopPage 的自动替换及 EditorPage 返回按钮，并验证返回后可重复打开 JPEG。原生文件选择、导入及 RAW 转 JPEG 的边界由测试替身驱动；这些记录不代表真实平台 RAW 解码或硬件验收。实际 Android 同流程复验和 Apple 完整门禁由交付主流程记录。核心 1629 没有因本次 UI 修复重跑或改动。

[修复前日志](attempts/before-fix.log) 已命中返回相册后点击无效的锁断言，同时夹有尚未完善的 picker 动画和事件通道测试配置，因此不声称是干净的红测。[首次路由运行](attempts/before-fix-route.log) 在加载 suite 前断开，[verbose 重试](attempts/before-fix-clean-verbose.log) 为 Windows engine access violation / exit 79，均保留为宿主未完成记录，不计产品通过或失败。

通过日志中两个 `FIXTURE_CLEANUP_AFTER_PROCESS` 指向测试自建临时目录。Windows 图片解码器仍持有文件时测试清理延期；本次归档未再次删除，目录不属于产品或安装包。

本次仅更新源码绑定，没有重跑测试。与 a54 相比只变更 Apple 验证脚本，应用 Git 树及下列测试文件内容相同。[a54 完整归档快照](bindings/a54af6c6e7bb1e78737c70715645084e709901c5/README.md) 保留原始绑定、日志与哈希。最新 Apple 完整门禁为 `43464094785`，此叶记录不宣称其通过；同源前一轮 `43463073963` 因依赖 Git 网络 reset / early EOF（exit 128）终止，属于依赖获取失败，不归类为产品断言失败。
