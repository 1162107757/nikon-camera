# 181 — 相册多选 A 方案

`0.30.27-beta`（181）按用户批准的 [A图](../../design-review/album-selection-20261109/A-balanced-toolbar.png)落地。顶部为取消、实时已选数量、全选；底部只保留等宽的编辑／导出／删除，24dp 同族图标、12sp 标签，白色／深色 24dp 圆角容器。常规高度76dp，紧凑横屏64dp，目标均不少于48dp，随大字号继续增长。手机来源按既有能力仅提供批量编辑。

短横屏选择态收起已锁定来源及重复统计，在顶部注明当前来源；退出即恢复。来源锁、分组／版本、选择上限、编辑／导出回调、删除确认与删除中返回守卫沿用180，四个关键方法逐字相同，见 [行为保护](behavior-preservation.json)。没有改 RAW 或相机协议。

## 精确本地包

[签名安装包](../../../dist/upload181/huevia-0.30.27-beta-update.apk)：31,403,286 字节，SHA-256 `66eb368ef073a5b29502d3ce57935366c883f0d155cf38f59fa14099be91102c`；完整构建 `2213ec8ed742a18bc71ed72104266e1fe466bddb8feb156bffc4523c32140f52`。原签名 v2／v3、16KiB 对齐、实际后台 `inspectApk` 离线检查通过；只移除四个旧 x86 库，保留89项 payload逐字一致及ARM32／ARM64／x86_64。[包身份](package-candidate.json)、[签名检查](backend-apk-inspection.json)、[payload](payload-provenance.json)。未上传、未发布、未Git提交。

## 原生范围

API36 自有模拟器四配置：phone、窄屏1.3倍字、tablet、dark/landscape。最终同SHA共173条含启动／重复检查、24张原始PNG。覆盖真实缩略图 View 长按监听、三选数量、全选与取消、顶部状态位置、三动作顺序／等宽／24dp图标／文字高度不裁切、100张数量排版、手机选择态仅批量编辑、照片视口空间；删除回归覆盖整组及版本／别名、二次快照变化、互斥、确认取消、删除中Back及实际MediaStore原图和其他照片保留。100张仅为文本压力，并非创建100份照片。

[图和报告索引](capture-index.json)、[摘要](summary.json)、[源身份](source-candidate.json)、[相对180的四文件差异](source-diff.patch)、[设备还原](device-cleanup.json)、[实施者有界复核](../../../.impeccable/review/selection181/review.md)。仅 `native/66eb368e` 为当前验收。`7a889c74`初版虽通过功能检查，但短横屏压缩照片空间；`9ae3b95e`又暴露紧凑标签底部裁切，已分别修正并增加视口／文本高度断言，旧包和证据保留于各native目录、first-candidate与intermediate-candidate，排除最终计数。

截图使用既有授权摄影资产生成自有测试照片，无新增生产摄影资产。源清单同时记录全量编译可能包含的182未接入独立筛选类／资源；181未将其接入预设首页，不把本轮当作筛选验收。未重测完整编辑／导出、RAW速度、相机、实体手机、完整TalkBack或FPS，不声明独立评审／全应用验收。178–180安装包及证据保持冻结。
