# 183 · 相册时间排序

183／`0.30.29-beta` 是现有原生相册的局部扩展，已完成本地构建、限定验证和独立完整复核，最终 [finish review](finish-review.md) 为 **SHIP**、无 material fixes。依据为用户确认的 [v2 上下箭头图](../../design-review/album-time-sort-20261109/approved.md)及[详细需求](../../design-review/album-time-sort-20261109/requirements.md)。未公开上传或发布，未 Git 提交、推送。

## 本地安装包

| 项目 | 精确值 |
| --- | --- |
| APK | [huevia-0.30.29-beta-update.apk](../../../dist/upload183/huevia-0.30.29-beta-update.apk) |
| 应用／版本 | `cc.huevia` · `183` · `0.30.29-beta` · minSdk 26 |
| 大小 | 31,411,478 字节 |
| SHA-256 | `6a50a4bebc1894cf535653b60d609ad273ab496fbf0399158ad5f34b59dbafdf` |
| 原签名证书 SHA-256 | `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31` |
| 完整构建 APK SHA-256 | `4cd12bf39fad9212b971b3bf14886e2e559b9e74cd610133a13f1eb751f4115b` |

[候选信息](package-candidate.json)、[backend inspectApk](backend-apk-inspection.json)和[负载溯源](payload-provenance.json)记录原签名、v2/v3 签名及 16KiB ZIP 对齐。交付包仅去掉四个旧 x86 库；ARM32／ARM64／x86_64 保留，89 个保留负载与完整构建包哈希一致。此处“本地安装包”不表示实体设备已安装或已对外发布。

## 当前行为与保留范围

- 张数行的“选择”之前为 ↑↓ 线图标，48dp 目标、8dp 间距，无常驻排序文案或额外状态行。无障碍名称包含当前依据／方向，多选或导入时不可排序。
- B 版纸白／炭黑玻璃短浮层提供拍摄时间／添加时间、新到旧／旧到新。打开复制当前条件；重置只改草稿，应用才保存并重排，关闭、返回和点外部丢弃未应用修改。两来源独立记忆，跨进程恢复。
- 原生标题／组标签／控件为 16／12／14sp，选中标签与勾一起居中。选项大字可换行，短横屏仅选项区滚动，关闭、重置、应用固定可达；支持真实窗口模糊与近不透明降级。
- 拍摄时间读取可信的私有 EXIF／MediaStore 日期，缺失或无效时回退添加时间。应用接收／导入单独记入 arrival journal；旧照片没有记录时使用现存文件修改时间，应用来源的“添加时间”草稿条件下显示对应说明。渲染缓存重建不替代原图入库时间。
- 手机相册在 album worker 完成完整可访问元数据快照，再按所选依据、方向和稳定 ID 排序后分页；不是只排已加载页，也不在主线程逐图解码。普通页上限 120；重排时首批可扩展到可见锚点。日期标题使用相同有效日期，跨年有年份，未知日期始终置后。
- 原图、别名及其效果版本仍成组，以原图日期排序；切换版本、生成效果不把组跳到最新。来源保留各自的排序与可见照片锚点，锚点恢复受实际滚动边界限制。新增、删除、权限变化和恢复时刷新元数据，多选期间延后 observer 更新。
- 保留 181 多选 A 的顶部取消／数量／全选与底部编辑／导出／删除，180 删除及 RAW 行为和 182 预设筛选。[preservation.json](preservation.json)逐项记录九个选择方法及三个 182 文件未改。此保留结论不扩大各旧版验证范围。

## 最终验证证据

[最终 capture index](capture-index.json)只选择同一交付 SHA 的四个成功 API36 原生运行，共 **977 条含重复的断言记录、35 张未编辑 PNG**。重复项包括启动、逐行唯一性及选择检查；977 不是独立场景数量。

| 配置 | 最终 run ID | 断言记录 | PNG |
| --- | --- | ---: | ---: |
| 手机 1080×2424 | `20261109-233453-phone-25d3e94d1b` | 648 | 13 |
| 窄屏／font 1.3，840×1890 | `20261109-232809-large-text-d3dfb126c7` | 109 | 7 |
| 平板 1600×2560 | `20261109-233527-tablet-857a221c07` | 110 | 7 |
| 深色短横屏 1890×840 | `20261109-232840-landscape-4568a7bf41` | 110 | 8 |

[Root verification](root-review.md)记录：135 条手机 JPEG 夹具在完整快照上按四种条件排序，以 70 条测试页跨界验证；拍摄／添加相反顺序、稳定同值、可见锚点反向前缀、DNG 元数据参与、私有 EXIF、arrival 回退、别名／版本成组及删除回归均有证据。70 是边界测试页大小，生产普通页上限为 120。夹具含故意不同的日期、张数及未来拍摄日期，不是用户设备实时照片。每个最终运行的 `process-restore.json` 均记录不同前后 PID，并读回 app=`added-oldest`、phone=`added-newest`。

Host 日志分别为 gallery **486**（250＋86＋47＋18＋58＋27 排序／arrival）、dates **122**（55 日期组＋67 EXIF reader）、library **59**（成组／版本）。原日志在 [.tooling/sort183](../../../.tooling/sort183/) 的 `host-gallery.log`、`host-dates.log`、`host-library.log`；这些计数保留各自范围，不与原生记录合称独立场景。

最终源码 [manifest](source-manifest.json)冻结 13 个生产文件及 2 个 host 文件；[final-source](../../../.tooling/sort183/final-source/)为逐字节对应快照，[source-changes.patch](source-changes.patch)保留实施差异。未从无关脏工作区或旧版本证据推导本次验收。

## 修正、重拍与复核范围

首批将选中勾画在胶囊边缘；一次生产视觉修正把勾放入居中标签，并为操作补齐原生 Button 角色。最终候选与全部最终截图均含该修正。初始 `5330875e` 候选和失败的 `6a50a4be` harness 运行仅作为历史保留，不进入最终索引。夹具路径、重复清理、harness 权限和过严锚点断言修正属于测试修复，详见 root record。

[首次重拍审查](finish-review-first-recapture.md)要求重新采集手机／平板选择态：250ms 延迟截到了之前 B sheet 的退出动画。随后对两配置重跑完整原生流程，增加 no-active-dialog 断言及 1200ms 稳定等待；APK SHA 和生产源码均未变。两张最终选择态已清楚显示完整 A dock。先前 [index](capture-index-first-recapture.json)及原运行目录保留，不能与最终统计重复累计。

重拍后重新进行完整 finish review，逐一打开 [.impeccable/review/sort183](../../../.impeccable/review/sort183/) 中全部 21 张必需、未编辑的复核图，核对索引哈希及尺寸。结论 SHIP 只覆盖批准的排序扩展及四配置可见回归，不是狭窄 verdict pass，也不是全应用或硬件认证。批准的局部扩展无新视觉世界，不要求 QUALITY BAR tournament；原生 Java 无 HTML／CSS detector 适用面。

## 清理与未验证项

每个最终运行的 `cleanup.json` 记录权限、字体、尺寸、飞行模式恢复，自有夹具及 probe 移除。[最终模拟器回执](emulator-cleanup.json)另记录应用强停、精确交付 SHA、恢复状态及 owned emulator 已关闭；以该回执的实际字段为准。

本次未重测实体 Samsung／其他 OEM、完整 TalkBack 操作、完整 RAW 解码／性能、相机交互或端到端导出。原生排序矩阵为查询夹具授予完整照片访问；部分／撤回权限沿用已有显式检查及 resume invalidation，不扩大为本矩阵对全部权限状态的验收。没有云上传、公开发布、Git 提交／推送或用户数据迁移。

`DESIGN.md` 沿用既有纸白／炭黑、native sans／sp 和自适应导航世界，SHA-256 仍为 `3257e70b6c05f01f7881134300c6f67e67aeff8bc83c361d5b894c12791a4a23`。本次只记录 surface 与 sidecar 的局部扩展，不新增全局 tokens、世界或生产栅格资源；[documenter receipt](../../../.impeccable/review/sort183/documenter.md)记录文档边界与核验。
