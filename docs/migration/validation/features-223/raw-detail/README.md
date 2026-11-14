# 223 RAW 高清宿主：测试证据归档

当前源码绑定为 root 提供的冻结提交 `04a4d18ea0109b095ba1f854ea7b9a778480bf03`。本次只归档已有证据，没有运行 Git、SDK、CI 或发布操作。

当前 canonical 修正后的完整 `raw_editing_detail_test.dart` **3 项实际通过，退出码 0**，格式化和单文件分析均为 0。其记录的测试文件及 RAW 宿主 SHA 与当前冻结源码逐字节核对一致：

- 测试：`7430bd91de4215b1d5766716e7b55f77e1963824aafc78985750f7e0501ec6ad`
- RAW 宿主：`3ae3b8a37e1b3a29feb3117d42d678678c974b5e8785814bdf424e79976992cc`

修正的是测试夹具和完成条件：模拟 native 的 canonical 根目录；等待新的 32 倍 ROI 真正安装；等待旧账号迟到文件删除且拥有文件计数归零。原有 **ROI 宽度 < 0.06、账号隔离、不显示迟到 tile、文件确实不存在**的断言均保留。RAW 产品宿主没有在这次夹具修正中改变。

| 证据阶段 | 实际结果 |
| --- | --- |
| [历史 6 项合跑](historical/tests-final2.log) | 5 项通过、末项 did-not-complete，退出码 **1**；不算完整合跑通过 |
| [历史 owner 单例重跑](historical/owner-single.log) | 1 项通过，退出码 **0** |
| [当前 canonical 整文件](canonical/tests.log) | 3 项通过，退出码 **0** |
| [当前单文件分析](canonical/analyze.log) | 无问题，退出码 **0** |
| [当前格式化](canonical/format.log) | 退出码 **0** |

历史新旧 RAW 测试共 6 个不同用例分别有通过证据；不能把合跑退出码 1 改写为 0，也不能把历史测试源的哈希倒填成当前源哈希。[历史 tests.log](historical/tests.log) 是共享 API 修改过程中的加载失败，**执行 0 项，不计通过**。先前 Apple 的两个失败也不计通过；新的 Apple 全套仍待 root 收据。

[当前原始结果](canonical/result.json)、[历史原始结果](historical/result.json)、原 `.exit` 文件均原样保留。[复制清单](copy-manifest.json) 给出原始路径、字节数和 SHA-256，并逐字节核对副本；日志换行未转换。[命令记录](commands.json) 根据已执行调用重建，没有在归档时重跑。[源码清单](source-sha256.json) 绑定当前实际源码字节。

这些 Widget 测试运行真实 RAW 页面、预览队列、变换和共享高清 controller，**原生图像结果由夹具模拟**；不能用它宣称原生像素、最终安装包或整进程 RSS 已验证。最终 **123 项 R8** 与 **Apple** 结果等待 root 新收据，本目录不代替最终验收或发布。汇总见 [result.json](result.json)。
