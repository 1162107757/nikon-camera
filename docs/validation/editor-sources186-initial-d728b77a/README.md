> 历史初始候选，用户随后发现F1按压矩形底，已由最终ca6262e5修正；本记录仅保留当时结果。

# 186 / 0.30.32-beta · 编辑器来源与横滑分类

本地安装包：[huevia-0.30.32-beta-update.apk](../../../dist/upload186/initial-d728b77a/huevia-0.30.32-beta-update.apk)，31,411,279字节，SHA-256 `d728b77adba6062e0cb34e5325df219f3c9089a5abf68b27e58864cad4c0f2a2`。原签名保持，v2／v3与16KiB对齐检查通过。完整构建SHA-256 `7de15d81065f013116f0356bbc5829e7d157aa6d0aed0b51abf3cfaf7ba0a068`，没有公开上传／发布、Git提交／推送或微信发送。

## 实现

用户已确认[固定来源／横滑分类设计](../../design-review/editor-preset-sources-20261110/README.md)，并特别要求选中背景与边框圆角对称。原来来源选择只在“更多 → 全部滤镜”中可用；本次将主编辑页原分类行左侧的来源控件常显，按我的／在线排序，中部分类独立滑动，网格入口固定右侧。复用现有 `setOnlineSource`、目录、下载与筛选能力，不新建另一套预设库。默认与1.3倍字仍使用原48dp行和原工具区，照片区域没有因这项入口增加而缩小。

`PhotoPresetSourceTabs` 将外轨、内选中框和两文字槽统一在同一几何里。默认104dp宽、48dp触摸高，3dp内距；轨绘制高至少32dp，内圆角等于外圆角减内距，外描边内收半个笔画宽度，选中框上下居中、两端留白相等。按压与焦点复用内框，12sp随系统缩放。大字减少可见分类而不压缩来源标签；完整列表仍由网格和原有菜单打开。

保留当前默认来源和切换时重置分类／搜索的既有行为。切来源只影响浏览，不改变当前应用效果、强度、渲染栅格、撤销或草稿；完整列表中的来源选择也同步主行。原提案中额外的每来源独立分类位置记忆没有引入，原因是这次明确限定为入口及排版改动，详见[实施范围](../../design-review/editor-preset-sources-20261110/approved-implementation.md)。

## 验证

[原生矩阵](native-matrix.json)绑定同一最终交付APK：

| 平台／配置 | 检查次数 | 原生截图 |
| --- | ---: | ---: |
| API37 手机，1170×2532／480dpi | 41 | 5 |
| API37 窄屏1.3倍字，960×1920／480dpi | 41 | 5 |
| API37 平板，1600×2560／240dpi | 41 | 5 |
| API37 深色横屏，2532×1170／480dpi | 41 | 5 |
| API31 Android12 手机 | 41 | 5 |
| API37 既有编辑继续／草稿基线回归 | 9 | 0 |

合计205次含重复来源检查、25张原生图；另9项编辑回归单列。覆盖两状态几何和实际绘制角部、48dp目标、标签宽度、按压／键盘焦点、真实触摸切换与分类滑动、网格同步、工具往返、当前照片栅格／强度／历史不变及源文件保留。数据是使用真正生产模型类的受控本地／在线元数据夹具，网络关闭；不将其称为真实线上下载测试。初始JSON数值类型诊断发生在UI断言前，未计为产品失败或通过范围；API31测试驱动改用其实际支持的存储权限，不涉及App权限实现改动。

本轮采用一次原生四配置检查和API31补充确认，没有生产界面修正后反复抛光。手工打开了手机我的、窄屏在线、横屏分类滑动和API31焦点原图；其余以断言和原图限定证据。[图片清单](capture-index.json)逐张保留哈希与尺寸，[限定完成复核](../../../.impeccable/review/editor-sources186/review.md)由同一实施者执行，不宣称独立评审或全应用验收。

## 完整性与边界

[185保留检查](baseline-preservation.json)确认：既有生产文件只改 `PhotoFilterEditor.java` 和版本号，新增 `PhotoPresetSourceTabs.java`；185 RAW高光修复未改。与185交付APK相比只有AndroidManifest.xml与classes.dex不同，全部原生库及assets逐字节相同。只移除旧x86四库，89个保留payload与完整构建一致，见[payload记录](payload-provenance.json)、[包信息](package-candidate.json)、[后端离线检查](backend-apk-inspection.json)及[签名](signature.txt)。

三个生产文件冻结于 `.tooling/editor-sources186/final-source/`，[源码清单](source-manifest.json)保存哈希；[探针来源](probe-provenance.json)和[测试源码清单](test-source-manifest.json)不混入生产包。178–185冻结产物没有覆盖。[completion.json](completion.json)记录设备设置恢复和关闭结果。

未连接实体手机或相机，未做完整TalkBack、真实在线下载、FPS或全编辑功能矩阵。线上目录／下载算法没有改；实体手机操作手感与网络环境仍待用户复测。185 RAW验证保留其原有归属，不把此次来源UI检查扩大为新的RAW或相机认证。
