# 225 本地共享收据（保留冻结前执行事实）

本目录只按字节归档已存在的原始证据，没有运行 SDK、Git 或测试。当前产品源码已冻结为 `f11c4bff4d566f147094579d9b2d74bb5a4d8e6f`，Mac full 待验收；`accepted=false`、`published=false`、附件为空。

[case-matrix.json](case-matrix.json)逐项映射 72 个观察到通过的 Flutter case：controller 35、注册 12、工具切换 9、旧 Color 8、sharp 6、旧 orphaned 夹具修复回归 2。其中 70 个来自退出 0 的命令；sharp 主流程与账号两项来自 `sharp-ui4.log` 内已推进的通过计数，该命令整体退出 1。取消、几何、同配方 Apply 与 source-positioned Apply 分别有独立 +1/退出 0 收据。不能声称 switching、Color 或 sharp 整文件通过，不能把重叠尝试重复累计。

两项 no-op 使用最终日志；原 no-op/Cancel fixture 失败、controller 真失败和 Windows did-not-complete 记录保留在 attempts 与原始索引中。文件名里的 final 不表示源码已冻结。旧 attempt 的 Flutter build number 可能仍为 224；这是开发过程收据，不是将 224 安装包重命名为 225 验收。

checks 包含静态分析、18 文件零变更格式检查、420 原文件保全（12 项批准修复 / 408 未变）、公网及只读任务源码检查、密码策略和 host/VPN 23 项。host 心跳是 loopback，不代表实体相机。helper-selftests 的 11+9 项是合成验证器测试，不计作 Apple runtime 或 Flutter 项数。

[byte-manifest.json](byte-manifest.json)为每份原件及生成索引提供 SHA-256/字节数；每份原件保存 source 路径并在复制前后核对字节。manifest 自身的哈希位于私有 `.tooling/next225/shared-archive-receipt.json`，避免自引用。Java 输入已另行绑定最终 Git；本目录历史 Flutter 执行不追溯改称冻结源码全套通过，完整平台验收仍由后续独立步骤完成。

追加 Apply 的 source-plane 首轮 Windows AccessViolation 原样保留，仅 retry1 算通过。两个新 case 使用真实 PNG 的 widget 绘制、桥接配方和生命周期断言；不代表设备或真实 native 身体塑形像素验收。追加的格式日志为 2 文件 / 1 changed，不能写成零变更格式检查。

JSON 的 sourceCommit=null/sourceFrozen=false 描述历史本地执行时的状态；currentFrozenProductSourceCommit 与 currentProductSourceFrozen 单独标明当前最终产品来源。这里没有重建历史每次 Flutter 编译的输入哈希，也没有重跑测试。

`checks/final-frozen-analyze.log` 是两项最终 Apply/source-plane 修改完成后的完整分析：eab 冻结源、实际退出 0、2.7s。旧 `checks/final-analyze.log` 保留为前批历史，不冒称最新分析。本次仅复制 98 字节原日志，没有执行 analyze。

新增 orphaned 夹具回归整文件 2/0，仅补真实1×1预览 DTO 尺寸及源文件，保留全部 UI/业务断言；format 是1文件/1changed且exit0。原eab完整 run659/2仍为失败，不把这次本地通过回写为旧run通过。旧原件/source字段均保留原样。
