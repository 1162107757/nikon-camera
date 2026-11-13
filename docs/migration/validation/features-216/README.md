# 216 本地测试验证记录

本页对应 `e8f78a766f839f27ca5e244fcfae404f6898f9b3`、`0.31.0-dev / 216`、包名 `cc.huevia.next`。Android 两份 APK 可用于本地测试；iOS 尚未验收，暂无可交付 IPA。本轮不部署生产、不上传发布草稿、不公开发布，214 / 215 附件保持不变。安装与入口说明见 [216 本地测试指南](../../local-testing-216.md)。

## Android 附件与运行边界

以下大小和 SHA-256 已从现有附件重新计算，与 [附件清单](../../../../dist/migration216/ARTIFACTS.json) 一致。

| 附件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| [ARM64 APK](../../../../dist/migration216/huevia-0.31.0-dev-216-android-arm64.apk) | 52,657,970 | `9038bc0ee4a986761556ab7df2f52272fe767e1bba7a3c77091575371cb2a328` |
| [x64 APK](../../../../dist/migration216/huevia-0.31.0-dev-216-android-x64.apk) | 56,160,474 | `5c117b50893ae689e754cefe8cc67cd947557edb441e218e2736d9bb5b0df50e` |

两 ABI 的 APK 验签通过，证书 SHA-256 均为 `76398947a8b493df81ebf2e90ad7b62e3eefee5fcf6cf865feaaa9bef8127b75`；ZIP 16 KiB 对齐及每 ABI 8 个未压缩 ELF 的 LOAD 段静态对齐通过。原始记录：[签名与对齐 JSON](android-signing-alignment.json)、[ARM64 验签](../../../../.tooling/next216/arm64-apksigner.bat-final.log)、[x64 验签](../../../../.tooling/next216/x64-apksigner.bat-final.log)。静态对齐不代表已经在 16 KiB 实体设备运行。

**78 项 R8 运行检查来自最终 x64 APK，环境为 API 31、4096 字节页模拟器。** [原始 instrumentation 日志](android/release-runtime.log)明确记录 `checks=78` 和通过结果；[结果收据](android/release-runtime-result.json)为 `exit:0 / accepted:true`，[混淆映射收据](android/release-runtime-mapping.json)保留实际字段、方法及 mapping SHA。覆盖真实 mesh、语义皮肤、渲染、修补、取消与 RAW JNI；全尺寸只读细节实际返回 `1600×1200`，并核对持久状态未改变。不能据此认定 ARM64 手机、实体相机或 iPhone 已完成相同运行检查。

## 已安装界面证据

[界面收据](android/release-ui.json)绑定最终 x64 APK 摘要与 `emulator-5584`。最终安装包实屏观察到原式照片菜单 13 项、全尺寸细节 `640×960` 以及 100% / 200% 控件。菜单中的“继续编辑”等按实际状态出现，13 项观察值不代表所有条件项同时存在。

- 原式照片菜单：[最终安装截图](android/ui/photo-actions-final.png)、[早期截图](android/ui/original-photo-actions.png)。
- 只读细节：[已载入截图](android/ui/full-details-ready.png)、[细节页截图](android/ui/full-details.png)。界面样片小于 1280，单凭截图不能证明全尺寸能力；大于预览上限的原生证据见上述 R8 日志。
- 调节图标：[前段](android/ui/adjustment-icons-front.png)、[中后段](android/ui/adjustment-icons-later.png)、[末段](android/ui/adjustment-icons-end.png)。
- 人像返回及自动祛痘：[返回后界面](android/ui/portrait-after-menu-back.png)、[分析界面](android/ui/blemish-analysis.png)。

部分早期截图来源为 `8ced1d6d282a4d8fdaa46a954e43965266f3de8f`。已核对它与最终 `e8f78a7` 仅差 `camera_test.dart` 和 `editor_readonly_test.dart` 两个测试文件，产品代码相同，具体来源仍保留在界面收据中。内置样片未检出疑似瑕疵，且外部测试副本字节未改变；不能把该截图算作原生阳性候选标记验收。候选定位、勾选与确认的 Flutter 交互证据另列如下。

## 核心与 Flutter 收据

[JVM 日志](core/jvm.log)记录 shared boundary **1385** 项和 atmosphere **6** 项通过；[核心结果](core/result.json)为 `exit:0`。[golden JSON](core/golden.json)的 `boundaryChecks:1391` 是两者相加，定义见 [CoreParity.java](../../../../cross-platform/core/test/cc/huevia/shared/CoreParity.java)，不是另一次 1391 项 shared boundary 运行。新增连接阶段、总时限、阻塞 I/O 取消和 job 所有权的 **26** 项属于上述核心回归，见 [连接边界日志](core/camera-connection.log)。

[全应用静态分析](flutter/analyze.log)为 No issues；[源码检查](source-check.log)记录 829 个文本 / 平台配置检查及只读 detailRender 的 21 项边界检查。[原版清单检查](inventory.log)确认冻结原工程 420 文件、8 个既有批准修复及其余 412 文件不变。

下表是各份已完整结束的定向日志，不能相加当作全量或唯一用例总数；最后一行包含重复复验的既有测试。

| 定向范围 | 单份日志通过数 | 实际收据 |
| --- | ---: | --- |
| 17 个参数与 6 个工具的独立图标像素 | 1 个 raster 用例，覆盖 23 个图标 | [日志](flutter/icons-raster.log) |
| 自动祛痘候选可视化、定位、勾选、返回与权限状态 | 13 | [日志](flutter/blemish-review.log) |
| 直方图数据、警示像素与控件 | 12 | [日志](flutter/histogram.log) |
| 相机连接进度、取消与迟到结果 | 6 | [日志](flutter/camera-connection.log) |
| 候选使用真实源坐标并仅提交选中项 | 1 | [日志](flutter/blemish-coordinate.log) |
| 取消候选不安装暂存蒙版 / 编辑 | 1 | [日志](flutter/blemish-cancel.log) |
| 菜单已有页面、RAW 来源与账号边界 | 6 | [日志](flutter/editor-pages.log) |
| 收藏、调色重置、快速优化与只读入口 | 4 | [日志](flutter/editor-actions.log) |
| 原版菜单顺序、锚定、窄屏和失效关闭 | 4 | [日志](flutter/editor-menu-layout.log) |
| 全尺寸细节、重复关闭、解码失败释放、迟到结果与直方图只读 | 6 | [日志](flutter/editor-readonly.log) |
| Apple 首轮暴露的两组测试依赖修复后复验 | 12 | [日志](flutter/test-dependency-fixes.log) |

[分批结果索引](flutter/local-results.json)保留上述数量和 Windows 未完成状态。Windows 图标首轮 [未完成日志](flutter/icons-first-engine-exit79.log)与自动祛痘整组 [未完成日志](flutter/blemish-workspace-windows-incomplete.log)继续保留，均不计为整组通过。菜单日志中的 `FIXTURE_CLEANUP_AFTER_PROCESS` 是 Windows 图片 codec 持有临时映射时的清理延后；外层进程退出后的 [菜单页清理收据](../../../../.tooling/agent-camera/menu216-pages6.json)和 [动作清理收据](../../../../.tooling/agent-camera/menu216-actions4.json)均逐项记录 `removed:true`，产品断言未删除。

## Apple 尝试与当前阻断

- `43412448770 / 8ced1d6`：Flutter 390 通过、12 失败；设备 app 编译成功仍未验收 IPA。保留 [失败结果](apple-attempts/43412448770-result.json)、[Flutter 日志](apple-attempts/43412448770-flutter-tests.log)、[设备编译日志](apple-attempts/43412448770-device-build.log)。
- `43416796573 / e8f78a7`：主线程已核定 Flutter **402/402** 通过、PhotoKit XCTest **1** 项通过；设备 release 编译生成 Runner.app。原始收据已归档为 [Flutter 日志](apple-attempts/43416796573/flutter-tests.log)、[PhotoKit XCTest 日志](apple-attempts/43416796573/photokit-tests.log)、[设备编译日志](apple-attempts/43416796573/device-build.log)。
- 同一运行的完整 native pipeline **未通过**：[结果 JSON](apple-attempts/43416796573/simulator-result.json)为 `success:false`，失败在新 detail fixture 的 `reviewPreview` 步骤，错误为“编辑数组长度无效”，尚未进入 `detailRender`。夹具已在后续 217 按当前参数 schema 修正，217 完整门禁仍待通过；402 项 Flutter 和 PhotoKit 单项通过不能替代完整门禁。

因此当前不接受、不链接隔离候选 IPA。[归档汇总](apple-attempts/43416796573/summary.json)和附件清单均明确未验收；216 已交付 APK 保持不变，后续 217 验证不追溯为 216 IPA 验收。watcher 的退出码不单独用作 CI 或 IPA 验收结论。

实体 Nikon Z6II 的 iPhone Wi-Fi 连接、USB / 实体相机写入回读、16 KiB Android 设备及 iPhone 自签 / 真实权限流程仍需现场验证。QQ Android 登记未核实、iOS Universal Link 未配置；这些外部条件没有被本页定向测试视为通过。
