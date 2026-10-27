# 93 · 实施与候选记录

2026-10-24。状态：**最终37895934候选的phone／实际1.3字号／横屏完整矩阵PASS，限定完成复核SHIP，可交用户审核。** 原型v4冻结，用户视觉接受尚未记录。初始失败与复核边界保留，不以功能通过代替审美接受。

## 为什么继续修正

用户否定92截图中的警示图标贴边、两处分段选中面不等距／圆角不匹配、构图按钮过大，并要求全面检查文字大小、对齐和冗余。92功能PASS没有证明这些视觉问题已解决；此前31图复核漏检，旧7b69不作为最终交付。92的[矩阵与候选历史](../photo-prototype-92/IMPLEMENTATION.md)保持原范围。

## 实际改动

| 表面 | 本轮接入 |
| --- | --- |
| [细节与玻璃分段](../../../app/src/main/java/cc/huevia/ui/PhotoDetailDialog.java) | `glass()`在设置背景后恢复原padding。比较外宽184dp、外视觉40dp／选中32dp、4dp等距，圆角20→16dp；缩放宽216dp（大字232dp）、外48dp／选中40dp、4dp等距，圆角18→14dp；真实触达保留48dp。当前效果短为“当前”，删除底部常驻hint，真实像素／历史版本说明移至可点击尺寸标签；历史原因短为“调色前不可用”，保留白字阴影和完整辅助说明。 |
| [直方图](../../../app/src/main/java/cc/huevia/ui/PhotoHistogramPanel.java) | 8dp斜纹图标＋4dp间隔＋11sp文字自绘整体居中；chip28dp视觉／48dp触达／间隔6dp，模式仍用短下划线；常显底注缩为“8位sRGB”，详细统计保留在说明及辅助描述。 |
| [五工具](../../../app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java) | 构图摘要单行、打开／重置同排34dp视觉／48dp触达、去常驻草稿说明；调节帮助改为撤销／精确值同排的参数ⓘ，删除长caption；配方改“保存当前”“暂无配方”和单行列表，去常驻footer与重复报错。GRID固定36dp视觉，搜索13sp、空态居中、真实零结果显示0款、仅异常显示状态；来源外34／内28dp、3dp等距、圆角10→7dp。 |
| [编辑chrome](../../../app/src/main/java/cc/huevia/ui/AlbumPanel.java)／[比较](../../../app/src/main/java/cc/huevia/ui/HoldToCompare.java) | 文件名13sp、导出12sp，两侧使用相等占位（竖屏68／横屏60dp）使标题对中；细节入口11sp；比较按钮清理Start／EndMargin，修正左侧裁切。保留真实insets和stage锚点。 |
| [构图窗口](../../../app/src/main/java/cc/huevia/ui/PhotoCropDialog.java) | 移除图标和常驻手势hint，11sp单行摘要；比例、拉直、旋转／重置、四角触摸及取消／应用回调保持。 |
| [边框](../../../app/src/main/java/cc/huevia/ui/PhotoBorderPanel.java) | 标签固定、值右对齐；来源移tooltip，缺值“未记录”使用常规字重；设置／机型标题与说明收短、独立32dp视觉面，真实48dp触达及实际字段／外观功能保留。 |
| [二级弹窗文字](../../../app/src/main/java/cc/huevia/ui/PhotoEditorTypography.java) | 统一原生AlertDialog标题14sp、正文13sp、按钮12sp、输入13sp；接已有对话框，不另造业务回调。 |

本轮字号仍用sp，系统大字照常生效；单行只对可省略的标题、摘要、列表及状态使用。校验错误、失败原因、不可恢复版本原因与帮助保持可达。没有以示例值替代真实计数、EXIF、几何或像素统计。

## 身份

| 对象 | 当前记录 |
| --- | --- |
| 最终APK | [huevia-0.19.2-beta-debug.apk](../../../dist/huevia-0.19.2-beta-debug.apk)；93／`0.19.2-beta`，3,905,658字节 |
| 最终SHA-256 | `378959346ea968f700841896253cddfada148256d449ec5506d59f0e167d12a6`；[最终身份](FINAL-IDENTITY.json) |
| 初始SHA-256 | `d4b43a9ad502a332cc0f1cdc52e859e0b981197730d827dcf38a5fb9290aa02c`，实际三配置FAIL，不能作为最终交付 |
| 构建／签名 | 构建与v2／v3签名通过；同SHA完成5586三配置验证，实体手机未操作，未公开发布 |
| 构建输入 | [source-snapshot.json](source-snapshot.json)固定207项；与初始d4b相比仅Histogram／Filter两项改变，其余205项相同；未以旧快照吸纳新改动 |
| 主原型 | v4已冻结SHA-256 `c1728206c0a5d6185153728d3c2db259bb88326575023b6a2662d7a59370946e`，155,003字节；46项静态DOM与2组说明入口事件分别PASS，不沿用v3身份，不证明浏览器布局 |
| 导出HTML | `9782fd02d20fac6800f32b9c46c80fb55b056b0f9ac72b8e3592af00845a400c`保持；本轮未改原生导出／批量后端 |

## 初始失败与一次修正

初始d4b的[三配置失败矩阵](initial-d4b43a9a-chip-scroll-fail/UI-MATRIX.json)保留：phone487／font1.3 487／landscape497次是在chip真实像素为0处停止的执行次数，非PASS，也不计入最终1917次。根因为TextView scrollX524235／524244，chip自绘未补偿；实际修复为Canvas save／translate(scrollX,Y)／restore，保留原像素判定阈值。独立首批51张raw图另发现精确值／强度输入比标题／正文少20dp左距，已补form20，与配方一致。两项合并修正，只有Histogram／Filter构建输入变化。

## 最终同SHA完整矩阵

[UI-MATRIX.json](UI-MATRIX.json)固定最终`378959346ea968f700841896253cddfada148256d449ec5506d59f0e167d12a6`。三配置均使用独占只读Pixel_9 `emulator-5586`的自有JPEG／草稿夹具，真实原生触摸与framebuffer；没有把d4b失败次数、旧92结果或原型DOM检查搬入最终计数。

| 配置 | 原始报告 | 断言执行 | raw PNG | 真实1:1 |
| --- | --- | --- | --- | --- |
| phone | [report.json](phone/report.json) | PASS635 | 32 | framebuffer1849点最大差0；tile1848点、错误0 |
| font1.3 | [report.json](font1.3/report.json) | PASS635 | 32 | framebuffer1849点最大差0；tile1848点、错误0 |
| landscape | [report.json](landscape/report.json) | PASS647 | 33 | framebuffer1849点最大差0；tile1848点、错误0 |

合计**1917次含配置重复的断言执行**，非1917个独立用户场景。97张raw PNG是产物数量，不表示最终逐张视觉复核97次。

- 精确值／强度／配方命名的实际文字起点相差0px，form左右53px（20dp四舍五入）；不是只检查容器左边。实际选中面相对玻璃外面四边均11px（4dp取整），圆角按外减内距计算。
- chip关闭／开启两态，真实framebuffer内斜纹与文字均通过原强阈值检查；TextView实际scroll仍存在，但自绘补偿后图形落在正确位置。没有降低阈值或以View存在代替画出。
- 五工具、参数说明／精确值／撤销、真实638B Bluesky.NCP强度未改不重写、构图取消／应用／撤销及横屏上角真实拖动、边框设置／信息／机型、配方入口和完整选择框的直接交互保持。
- 细节保留真实100%物理像素、200%、适应、定位窗、同构图比较、完整保存版本与不可恢复原因、尺寸标签48dp触达、source／owner生命周期守卫。警示开／关的私有JPEG字节相等；没有新增MediaStore发布或重测未改后端。

示例实际图：[手机编辑](phone/hero-editor-closed.png)、[手机直方图](phone/hero-editor-expanded.png)、[手机细节](phone/hero-detail-fit.png)、[大字细节](font1.3/hero-detail-fit.png)、[横屏编辑](landscape/hero-editor-closed.png)。

## 限定复核与来源

root接收并转交的独立静态callback／draft／touch审阅为限定PASS，来源是协作消息，没有冒称独立原报告文件已保存。独立`polish_visual_verify`先实际查看d4b批51张raw图，仅报上述两项实质问题；修正后再看最终378候选15张实际图，每模式五张：`histogram-chip-geometry-default`、`hero-editor-expanded`、`tool-parameter-exact`、`tool-strength-exact`、`hero-detail-fit`，确认修复且未见直接回归。root另看最终phone4图确认。

最终没有逐张重审全部97张PNG。首批51图中未改部分只按205项构建输入相同及明确两处差异保留原复核范围，不称新图逐张通过。上述有界复核、同SHA完整三配置及清理共同支持本次限定SHIP，可交用户审核；不代表用户已接受审美，详[FINISH-REVIEW.md](FINISH-REVIEW.md)。

## 清理与边界

[CLEANUP.json](CLEANUP.json)确认9份自有JPEG、3份草稿移除，源JPEG删除前SHA不变；App外观与系统字号／旋转／夜间模式／原权限三模式恢复，专用探针卸载且包不存在。私有draft不存在由运行中instrumentation finally确认；包不可调试，`run-as`退出1没有用作文件不存在证据，外部JPEG另以shell确认不存在。细节资源的close／owner守卫属于已测生命周期，不外推为私有缓存目录逐文件审计。

root仅关闭自有5586／PID41356，[EMULATOR-CLEANUP.json](EMULATOR-CLEANUP.json)为PASS，serial与启动PID消失、无自有qemu残留；实体手机与5582未操作。

v4原型冻结为155,003字节、SHA-256 `c1728206c0a5d6185153728d3c2db259bb88326575023b6a2662d7a59370946e`。[46项静态DOM](../../design-review/photo-detail-glass-redesign-20261024/EDITOR-PROTOTYPE-V4-VALIDATION.json)与[2组说明入口事件](../../design-review/photo-detail-glass-redesign-20261024/EDITOR-PROTOTYPE-V4-DISCLOSURE-VALIDATION.json)分别PASS，只认证无网络事件／真实模态／状态及焦点，不证明浏览器布局或原生像素。此前file预览被拒后没有换服务器／浏览器绕过。导出HTML`9782fd02…`与21组旧静态检查保持；不与v4或native计数相加为独立场景。

92的f919完整矩阵729次重复执行、7b69横屏保存版本59次单点及91后端／进度／dark继续属于各自历史SHA。93不认证实体手机／相机、MediaStore公有副本完整生命周期、线上发布、生产账号／目录、dark完整矩阵、tablet、FPS、色彩标定或TalkBack；本轮未commit、PR或公开发布。
