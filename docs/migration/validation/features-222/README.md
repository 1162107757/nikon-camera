# 222 验证索引

冻结源码 `9559591734f8cc07a8b9dcc1cf5ca596020904b5`。**三个同源安装包已接受本地测试交付，`acceptedForLocalTesting=true`、`acceptedForDelivery=true`、`published=false`。** Apple [full 43560076101](https://github.com/1162107757/nikon-camera/actions/runs/43560076101) success，独立IPA验收exit 0；原始收据见[ci-result.json](apple/ci-result.json)和[independent-verification.json](apple/independent-verification.json)。

| 范围 | 已有实际执行与尚待完成项 |
| --- | --- |
| 滤镜可见中心线 | 最终同源Mac全套通过，包含10项滤镜回归；实际测量文字glyph矩形与19dp网格图标中心，不以外层Row/48dp框代替，容差1.5dp；含普通、1.3倍字号、短屏、横屏及选中下划线 |
| 滤镜完整流程 | 最终Mac全套覆盖取消/账号变化/失败重试。更早Windows8通过/2语义失败、后续整文件退出79且0完成仍保留为历史，不改写旧执行结果 |
| Slider模态关闭 | 根代理修复Flutter193706相关语义时序：enabled KeyedSubtree与关闭路由后复核再安装。旧portrait完整编辑流程1项实际exit 0，未将其冒称为滤镜10项通过 |
| 连续预览 | Windows调度6项、Editor控件3项、既有局部范围撤销1项实际通过；首轮Mac新RAW3项及人像4项全部通过，补足此前Windows人像1项未完成。均非新实体设备像素证明 |
| 旧版调色 | 独立控件7项本地通过，最终同源Mac全套覆盖原式工作区及修正后的等待fixture。旧Windows通过/未完成与旧Mac失败历史保留，不累加成额外测试数 |
| 首轮后定向修复 | 曲线取消、连续预览、局部HSL、菜单调色、菜单RAW五目标各1项、各exit 0，具体私有日志列于下文；原执行基线保留 |
| 跨账号氛围背景 | Editor与Retouch目标各1项实际exit 0，且最终同源Mac全套通过；旧账号迟到背景不安装、不清掉新请求的loading，原执行基线保留 |
| 连接会话 | session_race整文件2项实际exit 0，私有日志`.tooling/next222/session-race-final2.log/.exit`；连接流程本身不读图，用户进入“同步→相机照片”即可读取，不要求额外点击浏览，晚到旧状态与同session保护保留 |
| 本地静态 | [analyze-refined.log](local/analyze-refined.log)全应用分析exit 0；[source-final.log](local/source-final.log)为1285/21/57，[inventory-final.log](local/inventory-final.log)为420/8/412，实际exit 0 |
| 核心参考 | [reference.json](core/reference.json)、[golden.json](core/golden.json)为既有真实golden引用；243个Java输入未变并已绑定最终222，`freshLocal222JvmRunClaimed=false` |
| Android两ABI | [result.json](android/result.json)、[签名对齐](android-signing-alignment.json)、[10图收据](preset-preview-assets.json)：两包验签、各8ELF16KiB静态、10图通过；精确x64/API31/4KiB环境78 R8通过，4根/2内页返回共6项通过 |
| Android最终实装 | [ui-result.json](android/ui-result.json)及10张实际截图绑定最终x64 SHA。原图SHA前后相同；分类行触摸中心一致、视觉已核对，glyph矩形专项另有首轮Mac证据，不将48dp框冒充glyph测量 |
| 五工具持续拖动 | [曝光](android/final-exposure-live-result.json)、[曲线](android/final-curve-live-result.json)、[HSL](android/final-hsl-live-result.json)、[调色盘](android/final-palette-live-result.json)、[去灰](android/final-cleanup-live-result.json)：各7秒，每项两帧采样前后pointer命令仍运行、照片区域均已变化 |
| Apple全套 | [ci-result.json](apple/ci-result.json)：实际541 Flutter、5 UIKit（含PhotoKit）、完整native pipeline1；[core-parity.json](apple/core-parity.json)实际1770项一致 |
| IPA独立验包 | [independent-verification.json](apple/independent-verification.json)、[ipa-verification.json](apple/ipa-verification.json)：同源build222、iPhoneOS/arm64、iOS16+未签名设备包，模型/字体/10图核对通过；[simulator-result.json](apple/simulator-result.json)记录唯一完整场景success |

[source.json](source.json)记录来源及历史尝试，[指南](../../local-testing-222.md)含10张实际Android截图链接，[ARTIFACTS.json](../../../../dist/migration222/ARTIFACTS.json)记录三包实际字节/SHA。首轮Mac与旧Windows日志、旧portrait通过及五个首轮后目标的原执行基线保留，不覆盖为新运行。前台fixture实际通过，证据为machine-test、snapshot=null，不捏造额外次数。

历史尝试及其结果只在[source.json](source.json)分列。首轮Android截图/QA仅作历史参考；本次Android实际证据为上表最终955源、精确x64 APK收据和截图。背景竞态原始私有执行基线保留，不把旧源码目标当成最终整套执行。

本轮包含旧Android滤镜/调色恢复、连续预览及已批准连接/遥控/同步dock与时间/文件名排序。旧版视觉依据见 [Prisma151](../../../prisma-editor151.md)和 [固定来源条批准记录](../../../design-review/editor-preset-sources-20261110/approved-implementation.md)。保留 [221验收](../features-221/README.md)，不覆盖其三包或历史收据。

实体相机、iPhone安装/连接、QQ授权与16KiB设备仍待验证；QQ iOS Universal Link未配置，RAW原图删除限制保留。仅本地测试交付，不公开发布客户端或服务。

实时预览进度条闪动、皮肤选色冗余确认已转223处理，不声称222已解决；223独立源码不属于本次验收。
