# 148 · 导出只另存新副本

本轮回应“导出只能是另存新副本”，在现有原生导出流程内做局部 Operate 精简。每次新发起的编辑成品／照片版本导出都向手机相册生成新副本；高级设置不再提供保存方式、额外副本勾选或复用已保存照片的入口。本节取代 145–147 中关于可选复用的行为说明，历史版本记录保持原样。

## 已实施

- 移除高级导出的保存方式整行、展开内容、另存新副本复选框及对应说明，不增加替代信息卡。
- 移除高级导出的已保存文件可用性提供器、等待状态、状态说明及“查看已保存成品”结果复用路径。高级提交固定传递 `PHONE_ALBUM, true`。
- 在共享 `PhotoVersionExport.accept` 接受边界统一设定 `PHONE_ALBUM, true`，覆盖快捷／高级、单张／批量、已保存版本／当前编辑。调用方不再提供现有结果回调。
- 保留 147 的 UiPalette 浅深色角色、原生 sp 层级、16dp 设置卡、680dp 内容轨道、52dp 固定主操作及“原始文件”区。JPEG／NEF 的 48dp 格式按钮继续放在滚动内容中，保留下载图标、8dp 双格式间距和“不应用编辑”说明。

实现依据：[PhotoExportDialog.java](../app/src/main/java/cc/huevia/ui/PhotoExportDialog.java)、[PhotoVersionExport.java](../app/src/main/java/cc/huevia/ui/PhotoVersionExport.java)，调用边界为 [PhotoFilterEditor.java](../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) 与 [AlbumPanel.java](../app/src/main/java/cc/huevia/ui/AlbumPanel.java)。[方向契约](../.impeccable/review/export-new-copy148/contract.md)限定本轮表面与验收范围。

## 保留的行为边界

“每次新导出生成新副本”指重新发起的导出请求。同一失败任务的冻结请求、回执及 `publicationCompleted` 重试逻辑保持原样，重试仍使用该任务已有的发布身份，不对已完成项目重复发布。所选保存版本的源文件、明确“当前编辑”的内容快照、输出名称、账户／源身份校验及队列继续沿用既有实现。

JPEG 原始文件仍进入既有确认及源字节／哈希检查，NEF 保留既有回调；两者不应用当前编辑。原始文件夹具只验证生产按钮分发回调，没有执行或证明 JPEG／NEF 原始文件的实际存储。相机接收及接收时保存位置流程不在本轮变更范围。

## 冻结安装包

- 文件：[huevia-0.28.11-beta-debug.apk](../dist/huevia-0.28.11-beta-debug.apk)
- `versionCode`：148；`versionName`：`0.28.11-beta`
- 大小：33,585,623 字节
- SHA-256：`322c145964cbad9102172fc607f0f6c2a7ac2defbfaf69689aa2b792d5c6dd05`
- 构建完成，APK v2／v3 签名验证通过；模拟器已安装 APK 的哈希与冻结包一致。

## 验证与复核

最终包证据：[.tooling/export-new-copy148/](../.tooling/export-new-copy148/)；汇总：[validation.json](validation/export-new-copy148/validation.json)。原生截图及复核材料：[.impeccable/review/export-new-copy148/](../.impeccable/review/export-new-copy148/)。使用自有 Pixel 9、API 37.2 模拟器，复用 BatchQualityProbe 经过实际快捷／高级导出路径，并以隔离生产对话框夹具覆盖自定义校验和原始文件回调。

| 最终包配置 | 重复断言执行 | 当前结果 |
| --- | ---: | --- |
| 手机 | 92 | PASS |
| 字号 1.3 | 69 | PASS |
| 320dp 窄屏 | 69 | PASS |
| 深色 | 69 | PASS |
| 紧凑横屏 | 69 | PASS |
| 平板竖屏 | 69 | PASS |
| 平板横屏 | 69 | PASS |
| 合计 | 506 | 七配置全部 PASS |

手机实际对同一单张照片导出两次、对三张照片的批量选择导出两次，生成八个独立、已完成的 2400×1600 MediaStore JPEG；三个源文件哈希保持不变。这里的八个文件属于实际成品 JPEG 导出，与原始文件回调夹具分开记录。506 次是含配置重复的断言执行数，不是独立场景数。

[保存版本选择回归](validation/export-new-copy148/versions-regression.json)在同一最终 APK 上通过 45 次检查，覆盖所选保存版本的源文件身份和快捷／高级往返选择保留，没有新增导出。45 次选择回归与上表 506 次矩阵执行分开记录，实际 JPEG 发布总数仍为手机副本用例中的八个。

[必要截图清单](../.impeccable/review/export-new-copy148/required-captures.json)共九张：七配置各一张高级导出，加手机原始文件区与自定义设置各一张。[最终独立复核](../.impeccable/review/export-new-copy148/review.md)结论为 **SHIP**：九张必要截图全部有效，没有实质修改项。该复核完整覆盖本轮移除控件、固定新副本政策及直接相关布局，并确认当前 PRODUCT、DESIGN 附录和表面契约与 148 一致；不是全应用或硬件认证，也不借用历史 SHIP 或旧版本次数。

四档 JPEG 编码未重跑。不认证实体手机、相机／RAW、真实传输、TalkBack、OTA／下载安装、旧系统或性能。原始文件回调夹具不构成实际原始文件保存证明。

## 本地交付状态

本轮仅生成本地安装包及记录，未上传、未发布更新通道，未 Git 提交或推送。此前微信文件传输助手交付仍停留在“进入微信”认证界面；用户尚未完成手动认证，未发送文件。
