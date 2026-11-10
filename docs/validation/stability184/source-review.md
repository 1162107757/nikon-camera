# 184 代码与兼容性复核

## 确认范围

- 导出：所有效果标识校验统一，保留完整身份和原有缓存键；恢复 UTF 记录的字节上限覆盖合法多字节字符，先打开 AtomicFile 再检查实际流大小，处理备份恢复，读取后核实 EOF。688+95 项主机回归与实际 Android JPEG 导出通过。
- 预览闪退：只替换接口默认方法中的数组复制操作。实际 183 的 API 31 异常、第一版 184 的后台线程致命异常，以及最终 DEX 调用变化均有记录。没有广泛捕获 Error 来隐藏渲染故障。
- 记录器：optional install/record/snapshot 失败与原故障隔离；原处理器收到同一 Thread/Throwable，至多写一份有界本地记录。后台收集退出历史，guarded Api30 独立类仅在 SDK >=30 调用。正常启动不查询系统退出历史。
- 系统交接：在启动边界处理缺少 Activity 和拒绝权限，回退 Intent 为副本；不声称 GET_CONTENT 有持久 URI 授权。失败的预设/样片选择会清理临时状态。现有内部 Activity 跳转、RAW 处理和相册删除协议保持原样。
- `main-vs183.patch` 和 `local-album-vs183.patch` 对照的是同一新工作目录内冻结的真实 183 源码；没有从退役目录复制文件。

## Lint 33 项的解释

最终 `lint-audit-final.xml` 是 minSdk 26 的全源码局部规则审计，不是以 Android 12 为 minSdk 隐藏警告。

| 报告组 | 数量 | 核查结果 |
| --- | ---: | --- |
| API 33 返回回调：NewApi 5 + InlinedApi 1 | 6 | `SelectionBackApi33` 独立类，注册入口 SDK <33 直接返回；回调以 Object 保管，注销仅对已成功注册的非空实例进行。API 31 不进入该实现。 |
| GlassBar 的 API 31 RenderEffect | 2 | 独立 Api31 helper 的调用有 SDK >=31 判断，低内存/禁用模糊走已有降级；API 31 支持该 API。 |
| CameraConnectionService 的 startForeground 与类型常量 | 7 | 普通路径按 SDK >=29 分支；唯一未就地检查的三参调用处在平台 API35 `onTimeout` 回调中，平台低版本不会调用该回调。Android 12 已支持三参方法。 |
| PhotoLiveGallery / RawPhotoPublisher 的 MediaStore | 9 | publish/delete 外层按 SDK <29 走 legacy 路径。API 31 支持此组方法与字段；本次未改动相册发布/删除代码。 |
| 资源主题的 API27/29 属性 | 5 | 低于 Android 12；旧系统不识别的主题属性不会作为 Java 方法被调用。本次资源条目与 183 字节相同，未扩展低版本主题适配。 |
| AlbumSortSheet.ALIGN_CENTER 常量 | 1 | API29 内联常量，Android 12 已支持；沿用已冻结 183 排序实现。 |
| receiver flags | 2 | MainActivity / DiagnosticsActivity 的 >=33 分支使用带 flags 的 overload，旧 overload 位于 else。不能按警告数量认定 API31 缺 flags 崩溃。 |
| openRawResource(R.drawable.preset_template) | 1 | 现有 PNG drawable 通过 raw stream 读取原始图片数据；资源实际存在，两个系统启动/预设预览回归通过。属于该规则资源分类提示。 |

上述数量合计 33，没有通过 SuppressLint 或改动旧模块来消除输出。主机 API 检查不能代替 ART 运行验证：例如源代码 `String.isBlank()` 的平台版本看似偏新，但冻结 183 的实际 DEX 已调用 D8 backport，API31 专项也正常执行；因此没有把它冒认为已确认的闪退根因。相反，数组 `clone()` 在实际 API31 上抛出的错误才作为已确认问题修复。

## 验证边界

最终选定 8 次运行共 615 项检查通过，自动复核清理 JSON 无未解决错误。第一次发现的真实后台崩溃由记录器完整写入，证明实际安装包已安装并正确串联未捕获异常处理。最终 API31 崩溃缓冲只包含此前废弃候选的旧崩溃；API36 缓冲为空。后续失败的测试工具步骤均保留并在 README 中单列，未计入成功检查。

没有荣耀 Magic 真机日志，因此不能承诺该机型所有闪退已经消失。新增诊断入口为后续真实 Java/native/ANR/低内存退出提供可导出证据；仍需要用户在该手机上复测。
