# 147 · 导出更多设置整理

本轮是原生 Android 导出流程的局部 Operate 调整，回应“导出的更多设置美化下，特别是按钮下面的保存 JPEG/NEF 原始文件很难看”。沿用现有暖白／石墨 UiPalette、系统 sp 字体、原生 Views、AppIcon 与平面 Ripple，不建立新视觉体系。

## 已实施

- 将原先主操作下面的长文字原始文件按钮移入滚动内容，归入“原始文件”区，配“不应用编辑”说明。JPEG、NEF 使用各 48dp 高的柔和底色下载按钮，双格式间距 8dp；只显示调用方提供的格式。
- 格式按钮用紧凑单行格式名、现有下载图标和完整无障碍名称“保存 JPEG／NEF 原始文件，不应用编辑”。保留足够点击范围，减少原始文件动作与编辑成品导出的竞争。
- 成品尺寸、JPEG 格式及质量放入同一 16dp 圆角卡组，副本选项使用独立卡组。标题 18sp、文件摘要 14sp、单张成品尺寸 20sp、细节与格式 12–13sp、主操作 14sp。
- 固定底栏仅保留 52dp 主导出操作；正文与底栏使用同一最大 680dp 内容轨道，并保留系统栏／刘海安全区。短横屏中内容可滚动，主操作保持可达。
- 常规快捷保存的“更多设置”改为带箭头的柔和底色入口；紧凑横屏沿用标题行入口。快捷画质与高级设置仍相互独立。
- 最终包修正首轮复核发现的两处垂直对齐：原始文件标题与说明均居中，自定义 JPEG 质量标签与输入框居中对齐。

实现依据：[PhotoExportDialog.java](../app/src/main/java/cc/huevia/ui/PhotoExportDialog.java)、[PhotoQuickSaveDialog.java](../app/src/main/java/cc/huevia/ui/PhotoQuickSaveDialog.java)、[UiPalette.java](../app/src/main/java/cc/huevia/ui/UiPalette.java)。[方向契约](../.impeccable/review/export-settings147/contract.md)限定本轮表面与验收范围。

## 保留的行为边界

编辑成品固定导出到 `PHONE_ALBUM`，每次打开高级设置默认勾选“另存新副本”；取消勾选才进入显式复用路径。保存版本与“当前编辑”的身份、内容快照、预览、校验、队列及重试边界沿用原实现。

JPEG 原始文件仍进入既有确认及源字节／哈希检查；NEF 保留既有回调。两类原始文件均不应用当前编辑。本轮夹具只验证生产对话框的原始文件按钮分发回调，没有执行或证明 JPEG／NEF 原始文件存储。实际成品 JPEG 导出与原始文件回调证据分开记录。

## 冻结安装包

- 文件：[huevia-0.28.10-beta-debug.apk](../dist/huevia-0.28.10-beta-debug.apk)
- `versionCode`：147；`versionName`：`0.28.10-beta`
- 大小：33,589,719 字节
- SHA-256：`efb8ee80416a36af4c0f2d91c0ea0bb48953965b6959ab55bded78604d5a24c7`
- 构建完成，APK v2／v3 签名验证通过；最终代码包含两处对齐修正。

## 验证与复核

最终包证据：[.tooling/export-settings147/final/](../.tooling/export-settings147/final/)；汇总：[validation.json](validation/export-settings147/validation.json)。原生截图及复核材料：[.impeccable/review/export-settings147/](../.impeccable/review/export-settings147/)，29 张必要截图均已替换为最终包捕获，并由最终复核重新打开、确认为有效：七配置各四张，加手机副本选项一张。使用自有 Pixel 9、API 37.2 模拟器，复用 BatchQualityProbe 经过真实快捷／高级批量路径，另以隔离生产对话框夹具覆盖自定义校验和原始文件回调。

| 最终包配置 | 重复断言执行 | 当前结果 |
| --- | ---: | --- |
| 手机 | 76 | PASS；实际生成两个独立、已完成的 2400×1600 MediaStore JPEG，源文件哈希不变 |
| 字号 1.3 | 69 | PASS |
| 320dp 窄屏 | 69 | PASS |
| 深色 | 69 | PASS |
| 紧凑横屏 | 69 | PASS |
| 平板竖屏 | 69 | PASS |
| 平板横屏 | 69 | PASS |
| 合计 | 490 | 七配置全部 PASS |

首候选 `5699d997…` 的七配置共 490 次重复断言执行属于修正前证据；上表为最终 `efb8ee80…` 包重新执行的结果，两轮不合并计数。重复断言执行数不等于独立场景数。

[最终修正复核](../.impeccable/review/export-settings147/review.md)结论为 **SHIP**：M1 原始文件标题／说明对齐、M2 自定义质量标签／输入对齐均为 resolved，未观察到直接回归，remaining 为 clear，最终 APK 哈希已核对。该 verdict-pass 只对这两项修正评分，不构成整个导出表面或全应用批准；29 张重新打开的有效截图不扩大该评分范围。

最终轮手机完成后，字号配置在 instrumentation 启动前遇到 ADB daemon 连接失败。保留[中断日志](../.tooling/export-settings147/device-final.log)，执行 start-server 恢复连接，未停止共享 daemon；其余六配置随后全部通过。该基础设施中断未记为界面通过，最终矩阵来自实际重跑结果。

四档 JPEG 编码未重跑。不认证实体手机、相机／RAW、真实传输、TalkBack、OTA／下载安装、旧系统或性能。原始文件回调夹具不构成实际原始文件保存证明。

## 本地交付状态

本轮仅生成本地安装包及记录，未上传、未发布更新通道，未 Git 提交或推送。此前微信文件传输助手交付仍停留在“进入微信”认证界面；用户尚未完成手动认证，未发送文件。
