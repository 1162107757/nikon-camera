# 177 · 电影裁切比例

`0.30.23-beta`（177）在构图快捷横轨追加 `2.35:1`，精细构图追加“电影 · 2.35:1”，两处数值均为 2.35。快捷六项采用 56dp 最小宽度与可横向滚动的 fillViewport 轨道，延续现有比例图标、黄色选中反馈和 Prisma 材料。

快捷选中识别使用归一化裁切范围乘完整 `frameWidth/frameHeight`，避免较小竖图经输出整数取整后丢失选中状态；原有 0.01 容差保留。`PhotoGeometry` 与实际裁切／导出算法未改，不据此声明新的算法质量。

## 最终本地交付包

- [签名更新包](../../../dist/upload177/huevia-0.30.23-beta-update.apk)：31,374,525 字节；SHA-256 `f972d48b012545e4f3a4f8de53bbefe48151e6b9d133f38ac587553adec037e8`。
- 完整构建包 SHA-256：`2a9064e9b1f080369711dcf3d013ab91cf05fc86c93bbdcb31cf7c0e9905dbca`。更新包仅移除四个旧 x86 库；其余 88 项 payload 与完整包逐项一致，保留 ARM32、ARM64 与 x86_64。
- v2／v3 签名、16KiB zipalign 及后端 `inspectApk` 均通过。所有当前原生捕获均使用上述最终签名字节；包、签名及体积见 [package-candidate.json](package-candidate.json)、[backend-apk-inspection.json](backend-apk-inspection.json)，裁剪来源见 [payload-provenance.json](payload-provenance.json)。

## 验证范围

API36 模拟器四配置：phone、font1.3／窄屏、tablet、landscape／深色；每配置 73 条记录（含启动和重复断言）、4 张原始 PNG，共 292 条／16 图。原始图、尺寸、哈希、报告与 provenance 入口见 [capture-index.json](capture-index.json)，范围摘要见 [summary.json](summary.json)。这些记录数不等于独立场景数。

已验证横竖两种输入的快捷比例持续选中、精细构图电影比例与捕获时活动窗口、既有可访问缩放动作、原生框内移动、应用后的父几何、实际草稿保存读回，以及原始文件字节不变。输出尺寸仍按既有整数规则取整；记录中的最大宽度残差为 2.1px，不以整数宽高商精确等于 2.35 作为选中条件。

生产输入限定为版本号、`PhotoFilterEditor.java` 与 `PhotoCropDialog.java`；最终输入哈希、176 基线与未改几何源哈希见 [source-candidate.json](source-candidate.json)，差异见 [source-diff.patch](source-diff.patch)。设备配置已恢复；自有 emulator-5586 已关闭，5588 未操作，见 [device-cleanup.json](device-cleanup.json)及索引内各次 cleanup。

未认证边角拖动手势、完整 TalkBack、实体手机、FPS、全应用或完整导出流程。原生 Android Views 未运行 HTML／CSS detector。未上传发布或改动云端；176 及更早包和验证记录保持冻结。

## 有界复核与审计

[最终 reviewer 结论](../../../.impeccable/review/crop177/review.md)为 **ship**，仅关闭竖图选中状态与证据范围两项评分修正，以及直接观察到的回归；不构成独立全表面批准。

首次捕获目标错误已重录，随后复核发现竖图失选与继承的陈旧 helper 范围描述；一次源代码修正批次后重建并重跑四配置。旧候选 `4dd38a90…` 的捕获保留在 `native/4dd38a90`，首次复核的包／源／索引快照及 [修正记录](first-review/review-fix.md)保留在 `first-review/`，均排除当前验收。当前唯一验收证据为索引列出的 `native/f972d48b` 记录，含专属范围及匹配的报告哈希。
