# 93 · 照片编辑控件与文字收紧

2026-10-24。当前状态：**最终378候选同SHA三配置PASS，限定SHIP，可交用户审核。** 用户视觉接受尚未记录，原型v4与初始失败身份分列。

用户在92原生图中指出四类问题：直方图警示图标贴边；比较分段和缩放分段的选中面没有等距内缩、圆角不匹配；构图按钮过大。随后补充要求“其他也全部检查文字，不要大字／不对齐，可短／一行／删不必要文字”。这轮把照片编辑器、细节、构图及其实际选择框／弹窗一起检查，保留真实功能，收紧常显文字与几何。

92 的功能矩阵与59项单点确认仍保留原SHA；用户没有接受92视觉。此前31图复核漏检用户指出的四类问题，不能据该复核宣称已满足视觉要求，7b69不作为最终交付。

## 本轮具体要求

- 比较与缩放的外壳、选中面按同一4dp间距关系计算；设置玻璃背景后恢复原padding，不能让drawable默认内距覆盖显式几何。视觉面与48dp触达分开。
- 直方图每个chip的8dp斜纹图标、4dp间隔与11sp文字作为整体居中；两chip保留6dp间隔、28dp视觉面／48dp触达，亮度／RGB仍靠短线表达。
- 构图显示单行真实几何摘要，打开／重置同排，34dp视觉／48dp触达；删除常驻草稿解释，取消／应用真实语义保留。
- 编辑、细节、五工具、完整选择框、构图和边框设置统一较小字号、单行或明确省略；长说明移到现有帮助、tooltip或辅助描述。不删除失败原因、校验、不可恢复原因或实际动作。
- 原生二级AlertDialog统一标题14sp、正文13sp、按钮12sp、输入13sp；只改排版，不改提交／取消／重试回调。
- 主原型同步为v4并保留交互；导出HTML不改，原生导出／批量后端不在本轮扩展范围。

## 候选与验证边界

初始候选93／`0.19.2-beta`、3,905,658字节、SHA-256 `d4b43a9ad502a332cc0f1cdc52e859e0b981197730d827dcf38a5fb9290aa02c`，phone487／font1.3 487／landscape497执行后在chip真实像素为0处FAIL，非通过计数；[失败矩阵](initial-d4b43a9a-chip-scroll-fail/UI-MATRIX.json)及原207项输入保留。chip自绘补偿TextView scroll偏移，精确值／强度输入补20dp对齐，只有Histogram／Filter两项输入改变；修正后最终378959346ea968f700841896253cddfada148256d449ec5506d59f0e167d12a6（同93版本、3,905,658字节）的完整新矩阵phone635／font1.3 635／landscape647均PASS，1917为含重复执行次数，非独立场景；[最终身份](FINAL-IDENTITY.json)与[矩阵](UI-MATRIX.json)保留。

原生owner在独占只读Pixel_9 `emulator-5586`完成最终候选phone／实际fontScale1.3／landscape完整矩阵；独立复核只对最终15张修正与直接回归图作有界确认，首批51图其余范围按205项输入相同保留，不宣称最终97图逐张审阅。自有夹具／草稿、设置与权限恢复及5586关闭已完成。原型v4已冻结SHA-256 `c1728206c0a5d6185153728d3c2db259bb88326575023b6a2662d7a59370946e`、155,003字节；[46项静态DOM](../../design-review/photo-detail-glass-redesign-20261024/EDITOR-PROTOTYPE-V4-VALIDATION.json)与[2组说明入口事件](../../design-review/photo-detail-glass-redesign-20261024/EDITOR-PROTOTYPE-V4-DISCLOSURE-VALIDATION.json)分别PASS，只认证无网络事件／模态／焦点，不证明布局。旧92截图、46项v3静态检查和91后端结果均不能重标为93通过。

不操作实体手机或真实相机、不发布MediaStore文件、不公开发布；全App、dark完整矩阵、tablet、生产目录、FPS、色彩标定或TalkBack不在本轮证据范围。实施及最终复核分别见[IMPLEMENTATION.md](IMPLEMENTATION.md)与[FINISH-REVIEW.md](FINISH-REVIEW.md)。
