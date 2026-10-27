# 核心集成只读复核

日期：2026-10-27。没有修改生产文件、运行 ADB 或主构建。所需 `tests/run-photo-editor.ps1`（pwsh）已运行，通过 34,780 + 644,888 + 1,158 + 29 + 11,796 + 32 = 692,683 项检查；这是含现有回归的断言执行数，不是独立用户场景。日志：`.tooling/photo-local-109/editor-integration-review.log`。

## 发现项已关闭

1. `PhotoEditStore.markExported` 已改为 `same(live,frozen)` 完整状态比较，避免旧导出误标后来修改的零效果／停用蒙版草稿。最终只读确认第 139 行使用完整比较；`PhotoToolsPersistenceTest` 第 48 行新增 neutralA／neutralB 同像素身份、不同形状时旧导出不能标记新草稿的回归。根任务已交接新版持久化组 33 项通过。前述本代理 692,683 成绩是修正前的历史执行，不合并冒充新回归成绩。
2. `AlbumPanel.java` 第 3205 行批量边框 usable 分支已完整传入 `saved.localEdits`；第 3206 行使用 `store.replace(sha,saved,next)`，不会覆盖后来独立编辑的草稿。
3. 同文件第 3300 行批量套滤镜 usable 分支已完整保留目标 `previous.border/localEdits`；第 3301 行以完整旧 Draft 做 CAS。未 usable 的原图／保存版本行为沿用既有明确策略。

最终只读确认三项修正均已落地。配方批量应用第 3232–3233 行同样保留 restore 分支的 border/localEdits，并使用 `store.replace(sha,stored,next)`。本轮指定集成范围 **scope clear，无剩余必修项**。

## 已确认范围

- PED6 按新 magic 写入 17 个手动参数、透视字段及 local；PED1–5 兼容读取补 neutral 参数与空 local，仍校验摘要、数量和未知尾部。
- PCR3 保存全局手动调节和曲线／HSL，照片坐标蒙版及构图按设计不进入可复用配方。单图 Editor.applyRecipe 只替换滤镜／全局参数，保留现有 local；批量配方重建已传目标 local。
- PhotoAdjustmentCopy 使用可见目标 Draft 的 border/localEdits，复制与回滚经完整 `store.replace` CAS；其 same 比较包含 local.equals，零效果模型也受冲突保护。
- Editor 快照、比较、撤销／重做、保存、冻结、刷新已导出状态和 matches 都包含完整 local；主图、局部／构图工作区、滤镜缩略图及 draftThumbnail 经同一局部 profile。
- profile 顺序为全局／细节参数 → local → Geometry → Border。局部坐标处在 EXIF 归一且用户构图之前，主预览 Pixels 默认为 1；完整导出、renderDetail、DetailSource 早期预览的 raw Pixels 均覆写真实 EXIF。
- currentUnchanged 检查有效 local；空参数／停用模型仍可共用原像素，非零 local 不误走原图路径。细节排除边框属于既有行为。
- 开启工作区与提交回调保护账号／代次及完整 starting 快照；`PhotoFilterEditor.valid` 第 184 行额外校验 `scope.equals(owner)`，与全局 accountOwner／generation 一起保护当前照片绑定。最终三个模式均通过模拟 editor owner 不匹配时拒绝提交的原生检查。Dialog 的新渲染位图与工作线程由其 close 处理，借用的初始图由 Editor.onDismiss 释放。

## 最终同包原生证据

只读核对根任务运行的最终 APK `a356ba5104699204c09c2ebfdd64e5ad4f903ed2cd80dbfd4bb392e144e64fb1`，反射探针为 `35049c8ef8aa729ce71c91be8d7160f8f81317923a591f57f2ec3dbe239af407`。phone／1.3 字号／横屏各 184 项通过、各 6 张 PNG：

- `docs/validation/photo-tools-109/a356ba51/20261027-195639-phone-7175070d/20261027-195639-phone-7175070d/report.json`
- `docs/validation/photo-tools-109/a356ba51/20261027-195840-font1.3-75356dba/20261027-195840-font1.3-75356dba/report.json`
- `docs/validation/photo-tools-109/a356ba51/20261027-200013-landscape-54b9357c/20261027-200013-landscape-54b9357c/report.json`

三份 report／provenance 的制品及探针身份一致；完整 PNG 参考／真实细节、独立 EXIF6 定向及真实 sample-1 瓦片对照均为零像素差异，阈值没有弱化。原生范围包含真实局部／修复手势、系统阈值以上的双指缩放、取消／应用／历史、四个新全局参数、原生透视菜单、PED6 与切图恢复、模拟绑定 owner 失效、工作区及细节关闭释放和原图 SHA 保护。

编码前 PNG 参考按输出 JPEG 的实际 EXIF 无损定向后再比较；full/Q95 的旧存储方向及制品身份保持。早期探针的小跨度手势、SystemUI 全屏教学遮挡、空值清理及参考方向契约失败均保留在原证据目录，未被当作最终通过成绩。最终 262 项构建输入零漂移由根任务统一记录。本次收尾只读源码／报告并更新本文，没有再次构建、运行 ADB 或扩大测试范围。

本复核不覆盖 RAW 解码器、后端、相机连接或最终 APK 性能认证。
