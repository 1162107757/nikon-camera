# 219 验证记录

连接 watchdog 的确定竞争窗口已补齐，**修复后整源提交待主任务重新冻结**。[源码记录](source.json)区分本轮照片格式、连接导航、会话所有权、原生取消 / 前台呈现与最后 watchdog 检查。旧快照 **`4f9f1dc6d32d41f7b0179dac7436addc35ff6699`** 的 Mac 运行 **`43448048561`** 已失败并 held：核心 parity 通过，后续 avatar fixture 编译失败，见[白名单阶段摘要](camera-watchdog/source-binding-pending.json)。它不替代修复后新源验收，尚无本轮验收 IPA。Android 也需以新源重建并完成最终 R8 / UI，本页不将构建成功或局部测试替代完整平台门禁。

## 本地实际验证

| 范围 | 实际结果 | 证据与限制 |
| --- | --- | --- |
| 共享 Java 17 核心 | **1572 项，exit 0** | **1566 项共享边界 + 6 项氛围**，本轮全量新编译和执行，未复用旧 golden。[完整日志](core/core-check.log)、[结果](core/result.json)、[golden](core/golden.json)。其中 110 项会话、65 项连接检查均已包含在总数中，不再累加。 |
| Dart 相机流程 | **71 项，9 个文件全部最终 exit 0** | 意图 11、控制 4、Live 17、队列 12、保护 9、相机页 6、导航 1、预览 5、传输 6。[归档结果](flutter-camera/result.json)、[全 App 分析](flutter-camera/all-app-analyze.log)。保留早期 fixture / OOM 尝试，不将未完成运行记作通过。 |
| 照片格式标签 | **6 项，exit 0** | 新格式与卡片至编辑器 4 项、既有相册 1 项、既有编辑菜单 1 项。[专项说明](flutter-format/README.md)、[结果](flutter-format/result.json)。当前 JPG 与 NEF 来源分开显示；没有更换原文件或修改解码、显影与像素处理。 |
| 生产 Android Java 取消门控的宿主检查 | **309 项断言，含 100 次 finish / cancel 竞争** | [独立记录](native-cancellation/result.json)、[原始日志](native-cancellation/camera219-native-task-tests.log)。这组检查单独列出，不并入共享核心 1572，也不等同 APK R8 实装结果。 |
| iOS UIKit / XCTest | **5 个用例待 Mac** | [计划与当前状态](native-cancellation/result.json)包含前台呈现、取消退休与相册授权；尚未记作通过。 |
| 只读源码与原工程清单 | **exit 0** | [最新源码检查](camera-watchdog/source-check.log)：969 个 UTF-8 / 配置文件、21 项只读细节渲染边界。[原工程清单](camera-watchdog/inventory.log)：420 项保留、8 项批准修复、其余 412 项不变。 |

[相机会话专项](camera-session/README.md)记录实际 PTP/IP 状态机与合成 socket 字节检查、会话移交、已知响应恢复、关闭屏障与未知写入的保护边界；[watchdog 专项](camera-watchdog/README.md)补充暂停时钟恢复、原子成功退休与超时关闭的 latch 竞争。两者没有宣称真实 Z6II 或 iPhone 现场连接已验证。格式专项的初次分析为 **exit 0、1 条 info**，原日志保留且不记作干净分析；最终目标文件分析为 No issues。

## 运行输入与冻结源绑定

新一轮完整核心运行开始前实际 Git 基线为 **`323a92a09049620f15d2a52f38ee63fdf7038af3`**，当时包含尚未提交的 watchdog 补丁；[执行前记录](camera-watchdog/execution-base.json)和 [239 个独立输入指纹](core/source-fingerprints.json)、[252 个编译条目](core/sources.json)绑定当时的工作树。新 golden SHA-256 为 **`1ded5867901a5ea5dc622b58ebfc1613d472a315829bd00e093d101771cbc7a8`**。旧 1535 项运行时的 `ae85652ab10e0aba4fa06c070d7363671aaeac51` 基线及原指纹完整保留于[旧候选记录](camera-session/attempts/4f-core1535/result.json)，没有改写成新一轮执行。

watchdog 补丁已完成本轮新的 JVM 执行；随后的归档只复制记录、核验哈希，没有再跑 Flutter 或二进制构建。当前 **239 / 239 个 Java 原始文件 SHA**与新运行收据一致，格式修复 **5 / 5 文件**也仍与其原收据一致。修复后新提交的绑定待主任务重新冻结；[旧 4f 绑定证明](camera-session/attempts/4f-core1535/archive-final-source-binding.json)仅记录当时 244 个文件中 189 个原始字节相同、55 个仅 CRLF / LF 差异，不能代替当前新源绑定。原始运行指纹与 Git 字节哈希分别保留，不冒称二者全都逐字节相同。Dart 相机流程的独立 16 文件及换行差异证明保存在其自身元数据中。

## Android 平台状态

修复后新源的两 ABI APK 与最终混淆 R8 / UI 尚待主任务重建、验收并归档。下表及[签名静态记录](camera-session/attempts/4f-core1535/android-signing-alignment.json)只属于 **旧 4f 候选**，不能作为修复后交付证据：每个 APK 的 8 个 ELF 静态检查当时通过，但没有宣称 16KiB 页大小设备运行，也不预填安装链接。

| ABI | 字节数 | 静态验证对应 APK SHA-256 |
| --- | ---: | --- |
| arm64 | 52,723,506 | `8424789885091ef85800e4cddb4cc14d8ef9ff52c83a5f0f773cd0866d8a9333` |
| x64 | 56,226,010 | `e2c8cb3ffd2580856e87d0d978e9b6784821f0ecd387cf9b63fed0803231cb11` |

[旧候选内置预览图片证明](camera-session/attempts/4f-core1535/preset-preview-assets.json)绑定 4f：10 张图片在原仓、217 与该候选 Android 两 ABI 中逐字节保留，继续用于预设卡片预览；修复后新包仍需同样的验收。图片没有因移除设置页的独立样片浏览而被删除。已交付 218 安装包和文档未被本次归档覆盖。

## 保留的清理审批记录

[清理审查记录](flutter-format/cleanup-review.json)确认遗留物仅为已结束菜单测试创建的 **7 个 70B 固定一像素 PNG**。原递归清理请求与随后逐文件 `LiteralPath` 非递归方案均被自动审批拒绝，唯一返回理由为 **`blocked by policy`**，没有更详细原因；这两份后续清理请求未执行，也未继续尝试删除。目录保留不影响产品数据、应用修复或安装包生成。
