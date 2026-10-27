# v3 原型先行与原生集成 · 时点记录

2026-10-24，v3 原型收口时点。**用户先要求按本目录原型实现编辑页／查看细节，随后说“可以先完善原型”，是顺序调整，没有取消两页原生实现授权。** 当前先完成原型交互与记录，然后继续已授权的编辑页／细节页原生实现；不以原型“待视觉审核”额外制造实现许可门槛。

## 原型收口前：暂存草稿（历史时点）

在用户调整为原型先行之前，已有三处原生草稿；原型整理阶段暂存，没有将它们构建成 v3 候选或判定验收通过：

| 文件 | 协作归属与当前含义 |
| --- | --- |
| [PhotoFilterEditor.java](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) | root 的编辑工具区草稿；尚未随 v3 完整原型形成统一原生验证结论 |
| [PhotoHistogramPanel.java](../../../app/src/main/java/cc/huevia/ui/PhotoHistogramPanel.java) | histogram owner 的原型对齐草稿；不能以旧91统计／framebuffer证据认证新布局 |
| [PhotoBorderPanel.java](../../../app/src/main/java/cc/huevia/ui/PhotoBorderPanel.java) | 同一 owner 的边框工具区草稿；现有真实字段／二级功能需后续集成验证 |

此时点 `PhotoDetailDialog`／`PhotoDetailView` 没有随新原型修改；`AlbumPanel`／`HoldToCompare` 也尚未按 v3 改动。这里描述原型收口前的协作状态，不约束 root 后续继续已授权的实现，也不替代后续源码快照。

导出设置／批量进度／结果汇总的 HTML 原型已补齐，但**不在本次原生重设计范围**。编辑页原生导出继续接已有真实规格与保存流程，不能因原型链接而扩大改造。

## 原型整理阶段：包与验证身份（历史时点）

在该原型整理时点，没有构建或安装新 APK，也没有操作 adb 或设备。`dist/huevia-0.19.0-beta-debug.apk` 仍是旧91已验证候选：

- SHA-256：`f717151b99bb70d75a8038acb5f8e04f3ea28e121891ddf1fd8bdf73d47ea7a8`。
- 大小：3,893,370 字节。
- 其限定结论、历史候选、清理和各配置身份继续见 [91实施记录](../../validation/photo-image-upgrade-91/IMPLEMENTATION.md) 与 [最终身份](../../validation/photo-image-upgrade-91/FINAL-IDENTITY.json)。

该包不能代表 v3 原型或三处暂存草稿的实际效果。旧 phone／字号／横屏、dark、backend、progress 等证据保持原 SHA 与范围，不重标为新草稿通过；不修改旧 `source-snapshot` 或 `FINAL-IDENTITY` 以吸纳未测改动。

在原型整理时点，v3的46项主原型DOM检查与21组导出静态检查仅属于HTML，见 [PROTOTYPE-REVIEW.md](PROTOTYPE-REVIEW.md)；当时没有新原生截图、布局像素、物理像素1:1、真实相册／MediaStore或实体手机结论。该时点和旧91成果保留；随后统一实现的实际证据见下一节。


## 原型补齐后：92 原生集成（历史，视觉未获用户接受）

两套 HTML 补齐后，root 继续此前已授权的两页原生实现。`AlbumPanel`、`PhotoFilterEditor`、`PhotoCropDialog`、`PhotoBorderPanel`、`PhotoHistogramPanel`、`HoldToCompare` 及 `PhotoDetailDialog`／`PhotoDetailView` 已进入统一候选；上面的三处暂存表只描述此前时点，不再表示当前只有三处草稿。

92／`0.19.1-beta` 的三个候选均为3,905,658字节，按先后保留各自结果：

- 初始 `a1498dae0cfd59ebef831a5ea4e4fd25b532ba58d8702f55e92c68294c4ce0dc` 因真实布局请求循环中止，只留部分phone证据，不写三配置通过。
- 修正后 `f919bd9821634e31c52d6e8cb7661810d07fd6796b27d5abcc6488022ce41379` 的phone239／实际1.3字号239／landscape251均PASS；729为含配置重复的断言执行，非独立场景数。每配置1849个framebuffer对照点最大差0，tile错误0。
- 当前 `7b69df3e8ceb7cb018fff1a3553e9dfbc99d4a25a0c4c9ce5b8fd79837e380c8` 仅将横屏历史已保存版本原因文字改为白字＋黑影，未改位置／尺寸；206项构建输入中其余205项与f919一致。v2／v3签名通过；该横屏已保存版本单项后来完成59次断言PASS，仍只属于7b69，f919完整矩阵不转记为7b69全量直接重测。随后用户指出新的控件与文字问题，92未作为最终视觉交付。

实际映射与后续最终候选证据统一见 [92 实施记录](../../validation/photo-prototype-92/IMPLEMENTATION.md)和[完成复核](../../validation/photo-prototype-92/FINISH-REVIEW.md)。导出仍只完成 HTML 原型，本轮没有扩为原生导出页重设计。实体手机安装、线上发布与用户视觉接受不能由此推定。


## 用户新反馈后：93 控件与文字修正（当前）

用户指出92警示图标贴边、比较与缩放选中面不等距／圆角不匹配、构图按钮过大，并追加全面检查文字大小、对齐、可缩短／单行／删除不必要说明。此前31图视觉复核漏检这四类问题；功能矩阵或限定复核不能代表用户视觉接受，7b69不作为最终交付。

93初始候选`d4b43a9ad502a332cc0f1cdc52e859e0b981197730d827dcf38a5fb9290aa02c`（93／`0.19.2-beta`，3,905,658字节，207输入）三配置实际FAIL：phone487／font1.3 487／landscape497是在chip真实像素0处停止的执行次数，非PASS。TextView scrollX偏移524235／524244未由自绘补偿；已加save／translate(scrollX,Y)／restore。独立51张raw图首批另发现精确值／强度输入比标题正文少20dp左距，已统一form20。只有Histogram／Filter两项输入改变，另205项保持；最终378959346ea968f700841896253cddfada148256d449ec5506d59f0e167d12a6（93／0.19.2-beta，3,905,658字节）已重新完成同SHA完整三配置：phone635／实际1.3字号635／landscape647均PASS，1917是含重复断言执行、非独立场景，未转用失败计数。

v4主原型已冻结`c1728206c0a5d6185153728d3c2db259bb88326575023b6a2662d7a59370946e`，155,003字节；46项无网络静态DOM及2组说明入口事件分别PASS，只认证事件／模态／焦点。v3历史与导出SHA保持，不能由静态检查推定native93通过。

最终独立有界确认查看15张修正／直接回归图；首批51张其余范围仅按205项输入相同保留，不声称最终97图逐张审阅。限定SHIP，可交用户审核；9JPEG／3draft、设置／权限恢复、探针卸载和自有5586关闭均完成。最终实施、范围和证据见[93实施记录](../../validation/photo-polish-93/IMPLEMENTATION.md)与[93完成复核](../../validation/photo-polish-93/FINISH-REVIEW.md)。导出HTML保持原身份，原生导出／批量后端不扩大；实体手机未操作，最终视觉接受尚未记录。
