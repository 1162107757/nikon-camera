# 225 Android 本地测试收据

最终来源 `f11c4bff4d566f147094579d9b2d74bb5a4d8e6f` / version225。两 ABI release 构建、静态与十图、精确 x64 R8 123、Back4+2 及相关模拟器 GUI 已通过，Android 两包可供本地测试；iOS 与跨端整体验收另行等待，未发布。

本目录仅归档现有执行日志与 JSON，没有执行 SDK、构建、ADB 或测试。原文件直接按字节复制；两个 ABI 的 R8 mapping 完全相同，保留一份 XZ 无损压缩，已核解压字节与运行收据的 mapping SHA。

[result.json](result.json)关联 APK/testAPK SHA、运行 source、Back 的 PID/Activity 及 [GUI 收据](../gui/result.json)。GUI 168 帧在约 2fps 采样下检查连续性，不是每显示帧证明；无实体相机或移动数据现场声明。主任务已逐项解包核 GUI 原帧，本次只重新核 tar.xz 哈希，不重复执行 GUI。

[byte-manifest.json](byte-manifest.json)列原件、压缩 mapping 和生成索引的 SHA/字节数；manifest 自身哈希保存在私有 `.tooling/next225/android-archive-receipt.json`。空 stdout 也原样保留，成功退出以 pipeline/result JSON 为证据。

当前来源的 build/static/123R8/Back6 为真实重新执行。GUI 原始执行来源仍是 eab；依据 source-input-equivalence.json 的10组Git产品输入与每ABI428个解压payload同一性复用。APK容器哈希不同，没有把GUI改标成当前包重跑。
