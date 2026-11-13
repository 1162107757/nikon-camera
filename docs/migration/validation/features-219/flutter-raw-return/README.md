# RAW 编辑返回相册回归

最终源码：`e55414ad38ab04291313ddc1244a7ec778da659f`。测试命令未记录当时的 Git HEAD；[source-fingerprints.json](source-fingerprints.json) 对测试文件内容和最终 Git 内容作独立绑定，明确记录 CRLF/LF 差异，不把后续绑定说成重新执行。

应用相册的原生文件选择及手机相册导入原先一直持有 `importing`，直到 `context.push` 返回。真实 RAW 自动显影以 `context.replace` 替换路由后，原 push Future 可能不再完成，导致回到相册后仍拒绝照片点击。修复仅把锁限制在选择/导入/登记阶段，进入编辑器前释放；路由错误仍由独立打开方法接收并报告。等待导入时继续阻止重复导入。

实际结果见 [result.json](result.json)：

- [原生 picker 用例](fixed-picker.log)：1/1、exit 0。
- [手机相册导入用例](fixed-phone.log)：1/1、exit 0。两项分别在独立进程执行，不声称该文件曾整套单进程跑完。
- [原有格式回归](original-format4.log)：原测试文件未改，4/4、exit 0。
- [定向分析](analyze.log)：exit 0，No issues found。

新用例使用真实 GoRouter、PhotosPage、RawDevelopPage 的自动替换及 EditorPage 返回按钮，并验证返回后可重复打开 JPEG。原生文件选择、导入及 RAW 转 JPEG 的边界由测试替身驱动；这些记录不代表真实平台 RAW 解码或硬件验收。实际 Android 同流程复验和 Apple 完整门禁由交付主流程记录。核心 1629 没有因本次 UI 修复重跑或改动。

[修复前日志](attempts/before-fix.log) 已命中返回相册后点击无效的锁断言，同时夹有尚未完善的 picker 动画和事件通道测试配置，因此不声称是干净的红测。[首次路由运行](attempts/before-fix-route.log) 在加载 suite 前断开，[verbose 重试](attempts/before-fix-clean-verbose.log) 为 Windows engine access violation / exit 79，均保留为宿主未完成记录，不计产品通过或失败。

通过日志中两个 `FIXTURE_CLEANUP_AFTER_PROCESS` 指向测试自建临时目录。Windows 图片解码器仍持有文件时测试清理延期；本次归档未再次删除，目录不属于产品或安装包。

89c 这次历史绑定仅更新源码绑定，没有重跑测试；89c 与 a54 相比只变更 Apple 验证脚本，当时应用 Git 树及所绑定测试文件内容相同。[a54 完整归档快照](bindings/a54af6c6e7bb1e78737c70715645084e709901c5/README.md) 保留原始绑定、日志与哈希。该次绑定记录的 Apple 完整门禁为 `43464094785`，不宣称其通过；同源前一轮 `43463073963` 因依赖 Git 网络 reset / early EOF（exit 128）终止，属于依赖获取失败，不归类为产品断言失败。

91ae 历史上仅作后续源码绑定：[89c 完整快照](bindings/89c1393272f2164594f9eecc30df7d1f65153d01/README.md) 与 a54 快照均保留。绑定的 RAW 页面、RAW 回归和格式回归三个文件的原始/最终 Git 哈希均不变；core、Android app、app/lib 的 Git 树也与 89c 相同。两个 iOS 消费者及两个相机测试已修改，因此不宣称整个 iOS/native 或 app 树相同。该次绑定的 Apple 完整门禁引用 `43471565460`，由主流程核验；本次没有重跑测试或修改产品。

当前 e554 仅作源码绑定：[91ae 完整快照](bindings/91ae4b6b7352eba4c6d116cd4afee2334ffd742c/README.md) 与此前 89c/a54 记录均保留。三个已绑定 RAW/格式文件与 239 个核心输入未变；core、Android app、app/lib 树不变。iOS UIKit 布尔装箱及对应类型测试已修改，不能据此推断整个 native/iOS 树等价。最新主 ARM 完整门禁为 `43482938724`，本叶尚不宣称门禁通过，也没有重跑任何测试。
