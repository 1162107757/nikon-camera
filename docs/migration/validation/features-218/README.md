# 218 本地验证记录

最终冻结产品源码：`a86b4f6d4facd3cb2be9876f9e47961fdaf19433`。本轮将预设长按操作收为紧凑的“置顶 / 取消置顶”和“删除”面板，沿用已有删除确认与账号校验。设置中的预览模板页只保留模板状态说明、“从手机选择模板图”和“恢复内置摄影样片”两个操作，移除独立样片大图、名称、署名与浏览内容，也不再为此设置页请求单张样片；原有 **10 张内置图片完整保留，继续用于预设卡片效果预览**，底层 `gallery.preview` 生成管线未改。模板页增加安全区，确保系统导航、横屏及大字情况下恢复按钮可完整滚入可视区域。

Android 最终双 ABI APK 和同源 iOS 未签名 IPA 均已接受用于本地测试 / 自签测试，`published:false`。最终 Mac 全套 **`43431433303`** 已成功，实际 IPA 独立验证和十图门禁均通过，下方记录绑定最终源码与实际文件。旧候选 `27bfc5b2c4ab9769181b664e2277033a26202506` 未交付，旧运行 `43427475083` 虽成功但仅作为 [隔离候选历史](apple-attempts/43427475083/README.md)，不能代替最终源码通过；其 Android APK 与记录也已隔离。局部通过、旧组件结果与 JVM 输入复用不替代本次实际平台门禁。

**已知问题未在 218 修复：** Android 相册 JPEG 进入编辑器可能因 `rawSource` 标签来源误显示 NEF；iOS 217 的真实前台连接在 2–6ms 内被缓存 registrar 控制器检查拒绝，218 相机插件未改，继承该问题。219 正分别处理格式标签与 scene / key-window 宿主查找；不把其修复代码或尚未完成的验收写入本版。**不建议用户用 218 重复测试相机连接，等待 219 专项 IPA。**

## 最终 Android 平台验证

[工件清单](../../../../dist/migration218/ARTIFACTS.json)记录 `0.31.0-dev (218)`、包名 `cc.huevia.next` 与最终源 `a86b4f6d4facd3cb2be9876f9e47961fdaf19433`。补充文档时独立重算实际文件的字节数和 SHA，均与清单一致；未改写已交付 APK。

| ABI | 字节数 | 实际 APK SHA-256 |
| --- | ---: | --- |
| arm64-v8a | 52,723,506 | `6d42627b6f754decd7d98f4e56a72ab8a57b715e7c81050618a374d16ebd2287` |
| x86_64 | 56,160,474 | `f61f23e4dc96be57e886b2d4c3aa2ed6ffea3a8c84a557dcc2ff202ab0fd75d6` |

[签名及对齐记录](android-signing-alignment.json)确认两 ABI 均通过签名验证、16KiB ZIP 对齐及各 **8 个 ELF** 的全部 LOAD 段静态对齐检查。实际运行设备为 x64 Android API 31、**4KiB 页大小**；静态检查不代表已在 16KiB 页大小设备运行。

[R8 原始日志](android/release-runtime.log)包含 `checks=78`、`PASS 78 R8 release runtime checks` 和原始成功码 `INSTRUMENTATION_CODE: -1`；[结果](android/release-runtime-result.json)为 **`accepted:true`、`exit:0`**。这是真实混淆 release 的模型、皮肤语义、渲染、完整尺寸只读细节、修补、取消和 RAW JNI 回调路径。[实装 UI 摘要](android/release-ui.json)与[逐项事件](android/ui-events.json)绑定相同源和真实 x64 APK SHA。

| 实装行为 | 最终截图与证据 |
| --- | --- |
| 置顶不再额外确认；多项置顶在进程冷重启后保留；取消一项不影响另一项 | [两项置顶](android/ui/final-two-presets-pinned.png)、[冷重启后](android/ui/final-pins-after-cold-restart.png)、[取消一项后](android/ui/final-unpin-keeps-other-pin.png)。 |
| 删除仍进入原确认，取消后预设保留 | [删除确认](android/ui/final-delete-confirmation.png)、[取消后保留](android/ui/final-delete-cancel-keeps-preset.png)。 |
| 明暗主题菜单与真实中文预设标题 | [明色菜单](android/ui/final-menu-light.png)、[暗色中文标题](android/ui/final-menu-dark-cjk.png)。 |
| 模板设置仅状态与两个操作，无独立大图、样片浏览或摄影署名 | [最终设置页](android/ui/final-template-settings-only-two-actions.png)。两按钮各高 **126px**，下边界最大 **853px**，完整位于系统导航起点 **2214px** 上方。 |
| 正向从手机选择 JPEG 成功，并可恢复内置模板 | [自选状态](android/ui/final-custom-template-state.png)、[恢复后](android/ui/final-builtin-template-restored.png)。 |
| 10 张内置图片继续用于预设卡片效果 | [预设照片效果仍在](android/ui/final-presets-keep-builtin-photos.png)；[逐图资产证明](preset-preview-assets.json)将原仓图片、217 及最终 218 两 ABI 中的 10 图逐字节 SHA 对齐。 |

实装后已恢复原有 **2 个预设**的可见名称、分类和置顶状态，并恢复外观跟随系统；仅自建 QA 预设及本次导入、下载夹具被清理，原 portrait 文件的 SHA 保留在 UI 摘要。[复原后的预设](android/ui/final-original-presets-restored.png)及事件记录保留清理结果。极端长名、两倍字号属于上面的 Flutter 控件验证，不冒称原生实装结果。

## 最终 Apple 门禁与 IPA

最终同源 [运行 43431433303](https://github.com/1162107757/nikon-camera/actions/runs/43431433303) 实际通过 **421 项 Flutter、golden 1423 项 Objective-C / JVM 一致性、1 个原生流水线场景和 1 项 PhotoKit XCTest**。见 [CI 结果](apple/ci-result.json)、[完整 Flutter 日志](apple/flutter-tests.log)、[核心一致性](apple/core-parity.json)、[原生流水线结果](apple/simulator-result.json)、[原生 / PhotoKit 日志](apple/simulator-tests.log)及 [Photos 初始访问记录](apple/simulator-initial-access.json)。旧候选的 420 项和 217 的 404 项均不移作本次计数。

实际 `apple-app` job `131905633452` 的完整 prepare 日志明确输出 **PASS 34 Apple Wi-Fi stream checks**；[收据](apple/prepare-wifi-result.json)及 [原始行短摘](apple/prepare-wifi-excerpt.log)绑定 run、job、源 SHA、完整日志摘要及原始 273–276 行。没有重跑 Mac，也没有将其他版本计数移入本次。这些流与等待 / 取消夹具不验证 UIKit 宿主窗口选择，不能覆盖本版已知相机入口问题。

| 实际附件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| [218 未签名 IPA](../../../../dist/migration218/huevia-0.31.0-dev-218-ios-unsigned.ipa) | 64,868,359 | `e53ca64f5f7fbbf8f5b035875558a9b9f30a6cf28eebbf5c01f88a1eb44b6b7f` |

最终 IPA 已重新读取大小并计算上述摘要，与 [构建收据](apple/ipa-verification.json)和 [独立验证](apple/independent-verification.json)一致：版本 `0.31.0 / 218`、Bundle ID `cc.huevia.next`、arm64 iPhoneOS、最低 iOS 16.0，未签名且未嵌入 provisioning profile，需用户自行签名。独立验证中的 `presetPreviewAssets` 确认 **10 张独立图片**完全保留；本次又直接读取 217 / 218 实际 IPA 的 **20 个图片条目**（每张两套打包副本）并逐一计算 SHA，均与仓内和两 ABI APK 对照相同，结果加入 [预设预览图片记录](preset-preview-assets.json)的 iOS 条目。尚未验证 iPhone 实机安装，`fullParityComplete:false` 等范围标记保留。

## 本地专项及输入复用

| 本地检查 | 实际结果 | 范围与原始记录 |
| --- | --- | --- |
| 最终菜单组件 | **13 项通过，exit 0** | [最终 guard 日志](flutter/component-final-guard13.log)。包含同帧两次关闭、系统返回后迟到的置顶 / 关闭回调、外点 / 返回取消、删除意图、明暗主题大字及短横屏。 |
| 最终组件静态分析 | **No issues，exit 0** | [组件分析日志](flutter/component-final-analyze.log)。 |
| 最终模板设置回归 | **2 项通过，exit 0** | [新版日志](flutter/preview-settings-final2.log)、[实际退出码](flutter/preview-settings-final-test-exit.txt)。确认无独立样片图片或浏览请求；选图取消不更新，自选与恢复仍通过真实 `HueviaCore.call` 通知 `previewRevision`，恢复后显示 10 张状态且恢复按钮禁用。另在 400×333 逻辑像素、1.5 倍文字、46.67dp 底部系统安全区下真实滚动到底，验证完整恢复按钮在系统导航上方且可点击。 |
| 最终模板页静态分析 | **No issues，exit 0** | [分析日志](flutter/preview-settings-final-analyze.log)、[实际退出码](flutter/preview-settings-final-analyze-exit.txt)。 |
| 全 App 静态分析 | **No issues，exit 0** | [完整分析日志](flutter/all-app-analyze.log)、[退出状态](flutter/all-app-analyze-result.json)。 |
| 旧模板页用例 | **历史 1 项通过，exit 0** | [旧日志](flutter/preview-template1.log)、[旧输入元数据](flutter/local-results-attempt-27bf.json)。当时只移除下一张入口，仍保留大图；不覆盖最终移除独立大图与安全区修复后的行为。 |
| 旧组件专项 | **10 项通过，exit 0** | [先前日志](flutter/component-earlier10.log)。不是最终 guard 组件输入，不冒充最终 13 项记录。 |
| 旧组件上的页面集成 | **3 项通过，exit 0** | [verbose 日志](flutter/integration-earlier3-verbose.log)、[退出状态](flutter/integration-earlier3-result.json)。基于组件 SHA 前缀 `cbc2` 的较早快照；覆盖置顶立即变化且保留其他置顶、删除确认取消、旧账号弹层不得修改新账号。最终同源 421 项完整 Mac 门禁已另行通过，不改写这份旧快照记录。 |
| 同一较早快照的置顶回归 | **1 项通过，exit 0** | [verbose 日志](flutter/pins-earlier1-verbose.log)、[退出状态](flutter/pins-earlier1-result.json)。不计作最终组件的新验证。 |
| 首轮 Windows 合并运行 | **未完成，exit 1，不记通过** | [完整原始日志](flutter/windows-first-incomplete.log)、[退出状态](flutter/windows-first-incomplete-result.json)。日志标记 `did not complete`；后续分别完成的局部运行如上，不抹去首轮记录。 |
| UTF-8 / 配置及只读细节渲染边界 | **904 个文件；exit 0；只读边界 21 项通过** | [源码检查日志](source-check.log)。本次仅执行静态检查。 |
| 原工程冻结清单 | **420 项保留，8 项批准修复验证，其他 412 项不变** | [inventory --verify 日志](inventory.log)。未重新捕获或改写原工程基线。 |

最终组件实际 SHA 仍为 `dbfde2228bf18d24266c3930f16084e074c8890769cd0711cc836c0537099e60`，测试文件 SHA 仍为 `5f5666a9ddcd685a803877a9cf42587ca529ccbd921e6529eb444824508db1d2`。最终模板页 SHA 为 `f868a3c3e9476e7b1b29aa86de65c7b9b1a1091050197246bbb2ced43aab910a`，测试 SHA 为 `d9afae6f07f9b968b6e51acdde3d1f1e2a2c5c7ca0127442a9dfcad03e5855c2`。[本地结果元数据](flutter/local-results.json)保存每份日志的 SHA、最终源码指纹及较早运行的限制；[静态检查元数据](static-results.json)记录执行命令。归档任务仅重跑只读源码检查和原工程清单核验，没有再次运行 Flutter、JVM、Gradle、ADB 或任何二进制构建。

`core/golden.json` 是 **217 已通过 golden 的字节原样复用**：本次逐个重算当前 **238 个独立 Java 输入**的 SHA，均与 217 一致；当前 **251 个编译条目及顺序**也与 217 完全相同，没有新增、遗漏或变化。先核对 217 原始 golden、源码列表与指纹文件的 SHA，再复制 [golden](core/golden.json)、[源码列表](core/sources.json)和[源文件指纹](core/source-fingerprints.json)。[逐项复用证明](core/reuse-inputs.json)记录全部 238 项比较及 `freshLocalJvmExecutionPerformed:false`。

该 golden 的 **1423** 项由既有 **1417 项共享边界 + 6 项氛围检查**组成；它不是本机新执行的 218 JVM 结果。原执行依据仍是 [217 的结果](../features-217/core/result.json)。218 Mac 工作流已独立重新编译并运行冻结源，与此未变输入的 golden 比较通过，见本次 [core-parity.json](apple/core-parity.json)。

本次证据归档未覆盖 217 交付包，未修改已冻结的 218 版本、源码、图片或已交二进制，也未执行发布。两平台按本地测试范围验收，QQ 服务既有六项线上拒绝 / 容量探针保持通过，真实 QQ 设备授权、Android 腾讯登记、iOS Universal Link、Z6II 实连、iPhone 自签安装和 16 KiB Android 设备仍未完成验证。上述两项已知问题由 219 另行修复，不因 218 CI 成功标为解决。
