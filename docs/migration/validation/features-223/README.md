# 223 历史验证索引（未接受，已由 224 替代）

本说明保留 223 的历史失败与当时待办，已由 [224](../features-224/README.md) 替代，不再继续该候选验收。8db/43588426197 的 604 通过、2 旧 Crop IO 等待超时为完整 run 失败；04a 的 582/5/1 仅属前批历史源码。原始 core、RAW、平台日志不变。

当前新增同页工具与共享视口已冻结为 `8dbdd33337cecfef5da969920913e5c3c4c66f3d`。macOS 26 [Apple full 43588426197](https://github.com/1162107757/nikon-camera/actions/runs/43588426197) 已失败：Flutter 604 pass / 2 旧 Crop fixture 超时（`editor_workspace_test.dart:181`），device build 成功，后续 UIKit/native pipeline 未执行。原始日志与 SHA 见 [失败 run 原始收据](attempts/8db-full-43588426197/outcome.json)与[字节清单](attempts/8db-full-43588426197/byte-manifest.json)；不能把604项或成功构建写成 full 通过。该候选已停止后续验收，未接受。`sourceFrozen=true`，所有最新交付接受状态为 `false`，`published=false`，附件清单为空。前批五项冻结源码 `04a4d18ea0109b095ba1f854ea7b9a778480bf03` 已有 Apple `43577955414`（582 Flutter、5 UIKit、native pipeline 1）与 Android 精确 R8 123 项实际通过收据，仅适用于同页修改前源码。

本轮五项：连续预览进度反馈；常驻肤色色卡/强度与直接暂存；所有编辑界面按需原图 ROI；可见同步页自动读图及旧错误退休；离线预设首页友好提示、保缓存、重试与“我的预设”。[复测步骤](../../local-testing-223.md)与 [source.json](source.json)记录当前范围。

新增范围：工具同页更换控件，保源焦点、放大密度与固定照片 bounds（含 cropped-fit 与近方屏）；自然精修同步返回；人像、修补、区域选区和瑕疵候选复用同一照片视口与状态、逐层取消与事务撤销；渐变取样修复当前 accepted localView 的高清；RAW 视口传递及已有照片重新显影内嵌。下表前批记录保留历史来源；新增工作树证据单独列出，不替代最终同源平台与包验收。

| 范围 | 实际证据与仍待事项 |
| --- | --- |
| 共享高清、裁切、选区 | controller 13 项整文件通过；宿主 4 项及旧裁切 2 项有实际通过证据，共 19 unique。宿主首轮未完成及分组补跑保留，不冒称全部同进程通过 |
| RAW | 6 unique 有通过证据；合跑 5 项后 Windows 退出 79，剩余 owner 单例补跑退出 0；不声称合跑退出 0 |
| 人像/修补/肤色/Editor | Retouch HD 4、repair 1、skin 4、Editor HD 3 unique 均有实际目标通过记录；Editor HD 分跑，不冒称整套通过 |
| 相机同步与错误状态 | 11 项实际专项通过；实体 Z6II/iPhone 相机连接未测 |
| 离线首页 | 新离线 6 项加原分页 1 项，同命令 7/7 通过、退出 0；覆盖 URL 不进页面、保留列表、重试、账号隔离与分页保护 |
| 静态检查 | 全 App analyze 0；source check 1329 text / 41 只读 / 57 Apple；inventory 420 原输入 / 8 既有修复 / 412 保留，退出 0 |
| 已实际执行的本地 JVM 与新源绑定 | [result.json](core/result.json)：260 输入、245 不同输入，1764+6=1770，退出 0；[golden.json](core/golden.json)与基线相同。245 个输入已逐一绑定 8dbdd333：LF 归一化全匹配，193 原字节相同、52 仅换行差异。`testRerunForBinding=false`、`freshRunAlreadyExecuted=true`，不声称重新执行 Java；43588426197 已产出 macOS parity 1770 pass 收据，独立核对待 root，整体 run 仍失败 |
| 原生高清（前批） | [native-detail](native-detail/result.json) 独立 JVM 39、source guard 43、独立 javac 0；仅所绑定历史源码，不是本轮 Flutter 新工作树的整包验收 |
| Android（前批） | 04a 双 ABI 构建完成，精确 release R8 实际 123/123、exit 0；当前 inline 新源已冻结、双 ABI 构建中，R8 与相关 UI 验收待最终结果 |
| Apple（前批） | [CI 收据](apple/ci-result.json)：04a full 43577955414 success，582 Flutter / 5 UIKit / native pipeline 1；[IPA 独立核对](apple/independent-verification.json)保留历史绑定。当前新源无最终 full/IPA 接受结论 |
| 新共享视口/Editor glue | `.tooling/next223/viewport/root-result.json`：whole analyze 0、模型 6/6 exit 0；Editor 切换整文件 exit 79、零完成，随后 4 个单例分别 exit 0（`switch-single-result.json`），不声称整文件通过 |
| 新 Crop/Selection/RAW/Legacy 宿主 | `.tooling/tool-viewport-hosts/result.json`：新 9 unique 分次通过，最终整文件 exit 79/零完成；旧 25 unique 已完成 19，原 Editor 6 未完成。Legacy 最终单例使用真 1600×1200 原图/full、800×600 ordinary 与 16×12 tile，验证 accepted localData/localView、同 plane、双指、梯度坐标、Apply 和清理；不称原生像素算法或 RSS 验证 |
| 旧 Color/Editor HD | `.tooling/next223/viewport/old-editor-result.json`：Color 8 与 Editor HD 3 各整文件 exit 0；Editor workspace 6 整文件 Windows AccessViolation、零完成，不计通过 |
| 新人像内嵌与兼容回归 | `.tooling/next223/retouch-compat/result.json`：共享修正后的 embedded 5/5 整文件 exit 0、skin 3/3 整组 exit 0；旧 patch 确认、standalone checkbox 与修正后的候选 accepted-profile 各单例 exit 0。review 3 个纯模型完成，余 widget 中仅 checkbox 补跑完成，其余 9 未完成；patch 取消/多指及 busy Back 共 4 项仍未完成。候选旧 fixture 的新预览假设与非中性 body 缺失 sourcePositioning 已按真实 DTO 修正，neutral/beforeBody/一次 heal 等原断言保留。B 早期记录与所有失败、中断原件不覆盖 |

专项私有原始收据在 `.tooling/agent-account/detail223/`、`.tooling/next223/raw-hd/`、`.tooling/retouch223-hd/`、`.tooling/retouch223/`、`.tooling/editor223-hd/`、`.tooling/camera223-sync/`、`.tooling/agent-account/presets-offline223/`。保留当时工作树基线及失败/未完成尝试，不伪造冻结源码时重新执行。

新增 attempt 与 SHA 在 [source.json](source.json) 的 `currentInlineEvidence`：root 的逐文件 hash 在 `root-result.json`，D 宿主 hash 在 `source-manifest.json`，最新人像兼容快照在 `retouch-compat/source-after.json`，B 早期快照继续保留。各 receipt/log 也记录 SHA。源码已冻结，历史工作树目标仍保留当时输入及后续修改限定，最终同源平台结果以新 run 和新包收据为准；失败、AccessViolation、Connection closed 与 did-not-complete 均不计通过，不把重叠单例重复累计，也不把分次通过写成一次整套通过。

[ARTIFACTS.json](../../../../dist/migration223/ARTIFACTS.json)仍为空的待验收清单。[222 收据](../features-222/README.md)的 541 Flutter、5 UIKit、native pipeline 1、core parity 1770 仅为已验收基线，不继承为 223 通过。真实 iPhone/Z6II、离线现场、USB、QQ 与 16KiB 实体设备仍有边界，iOS QQ Universal Link 未配置；不发布。
