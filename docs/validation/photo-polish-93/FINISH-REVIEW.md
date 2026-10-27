# 93 · 完成复核

2026-10-24。结论：**限定SHIP，可交用户审核。** 范围仅为本轮照片编辑／细节控件、全面文字及直接交互；不代表用户已接受审美或全App认证。

## 最终身份

最终93／`0.19.2-beta`，3,905,658字节，SHA-256 `378959346ea968f700841896253cddfada148256d449ec5506d59f0e167d12a6`；构建及v2／v3签名通过。[207项源码快照](source-snapshot.json)、[最终身份](FINAL-IDENTITY.json)、[同SHA矩阵](UI-MATRIX.json)分别固定输入、产物和设备证据。对初始d4b只改Histogram／Filter两项输入，205项保持；最终三配置是新执行，未沿用失败计数。

## 用户要求与真实修正

92用户指出的警示图标贴边、比较／缩放选中面间距与圆角不匹配、构图按钮过大，以及全面文字收短／对齐的要求为本轮范围。此前31图复核漏检这些问题，旧92不作为最终视觉满足的依据。

93初始d4b三配置分别执行487／487／497后在chip实际绘制像素0处FAIL，见[失败矩阵](initial-d4b43a9a-chip-scroll-fail/UI-MATRIX.json)。根因是TextView scroll偏移未由自绘补偿；另51张raw图首批审阅发现精确值／强度输入少20dp左距。两项合并修正，失败及其原阈值保留，不写初始PASS。

## 有界复核

| 证据 | 结论与适用范围 |
| --- | --- |
| 独立静态审阅 | root接收并转交callback／draft／touch范围限定PASS；来源是协作消息，本文件为汇总转录，没有声称另有独立原报告文件。 |
| 首批实际图 | 独立`polish_visual_verify`实际查看d4b的51张raw图，仅报chip绘制和输入左距两项material。该批属于旧SHA，未重标为最终图。 |
| 最终15张确认 | 同一独立复核查看378候选每模式的`histogram-chip-geometry-default`／`hero-editor-expanded`／`tool-parameter-exact`／`tool-strength-exact`／`hero-detail-fit`，共15图；确认修复、未见直接回归。root另确认最终phone4图。 |
| 同SHA原生矩阵 | phone635／实际1.3字号635／landscape647全部PASS，共1917次含配置重复的断言执行，非独立场景。97张raw PNG（32／32／33）不是97张逐图复核结论。 |
| 实际几何与像素 | exact／strength／recipe文字起点差0px；比较／缩放选中面四边11px等距；chip开／关真实framebuffer文字与斜纹通过原强阈值；每模式1:1的1849点最大差0、1848tile点错误0。 |
| 清理 | [CLEANUP](CLEANUP.json)的自有9JPEG／3draft、设置／权限恢复和探针卸载PASS；[模拟器清理](EMULATOR-CLEANUP.json)仅关闭自有5586／PID41356，serial／PID消失、无自有qemu残留。 |

首批51图中的未改部分，仅按205项输入相同及两处明确源码差异保留原复核范围；没有宣称最终全部97图逐张重审。私有草稿不存在由运行中instrumentation确认，非不可用的run-as；外部JPEG另核对不存在。以上共同形成限定SHIP，没有剩余本批必改项。

## 证据边界

原型v4冻结`c1728206c0a5d6185153728d3c2db259bb88326575023b6a2662d7a59370946e`，46项静态DOM与2组真实说明模态／焦点事件分别PASS，不证明浏览器布局、原生像素或用户视觉接受；导出HTML保持`9782fd02…`。

本轮不把91／92的backend／export／progress／dark旧记录算作93重测，不认证实体手机／相机、MediaStore公有副本完整生命周期、线上发布、生产账号／目录、tablet、FPS、色彩标定或TalkBack。用户最终视觉接受尚未记录；未commit或创建PR。

实施、截图入口与失败身份见[IMPLEMENTATION.md](IMPLEMENTATION.md)，用户要求见[BRIEF.md](BRIEF.md)。
