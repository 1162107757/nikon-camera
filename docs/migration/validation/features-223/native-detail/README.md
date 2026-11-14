# 223 原生高清裁片：局部验证归档

当前源码绑定为 root 提供的冻结提交 `04a4d18ea0109b095ba1f854ea7b9a778480bf03`。已按当前工作区的真实字节计算 [源码 SHA-256](source-sha256.json)；本次归档没有运行 Git、SDK、CI 或发布操作，也没有重新执行下列历史命令。

实际保留的局部验证为：独立 JVM **39 项通过**、Android 原生及 Instrumentation 的独立 `javac` 编译退出码 **0**、源码边界门禁 **43 项通过**。这不是完整 Android 安装包、R8 或 Apple 设备验证。JVM 编译和独立 Android 编译使用了既有构建产物作为 classpath，未在这里冻结其全部历史传递输入；最终完整核心及两端构建绑定由 root 的新收据负责。

| 原始证据 | 结果 |
| --- | --- |
| [JVM 编译日志](logs/jvm-compile.log) | 退出码 0；原始日志为空文件 |
| [JVM 边界日志](logs/jvm-boundaries.log) | 39 项通过，包含真实 JSON 数字解析、EXIF 0 归一化和严格 Plan 拒绝裸 0 |
| [Android 独立编译日志](logs/android-compile.log) | 退出码 0；保留原弃用 API 提示 |
| [源码门禁日志](logs/source-boundaries.log) | 43 项通过 |
| [原始结果记录](result.original.json) | 保留原状态，未经改写 |

[命令记录](commands.json) 根据已经执行的工具调用重建，明确注明没有在归档时重跑。[复制清单](copy-manifest.json) 记录每个原始文件的字节数和 SHA-256，并逐字节核对源、目标一致；未转换日志换行。

旧源 `68579a5` 的真实 R8 验证在第 68 项后、首个 tile 处失败，不算通过。隔离 `app_process` 诊断尝试也没有取得有效运行结果，不作为证明。本次仅归档必要的小日志和结果，没有复制设备崩溃、完整环境或巨型日志。

内存结论限于裁片计划的 **2048 边长、4,194,304 输出像素**上限及原生读取路径的源码检查。设备实际 `decodedBytes` 断言仍待 root 最终 R8 收据；**没有测量或宣称整进程 RSS**。

最终源的 **123 项 R8** 与 **Apple** 验证仍等待 root 新收据，本目录不据旧结果宣称最终安装包通过，也没有发布安装包。汇总状态见 [result.json](result.json)。
