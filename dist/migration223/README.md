# 223 历史候选附件（未接受，已由 224 替代）

本说明保留 223 的历史失败与当时待办，已由 [224](../migration224/README.md) 替代，不再继续该候选验收。8db/43588426197 的 604 通过、2 旧 Crop IO 等待超时为完整 run 失败；04a 的 582/5/1 仅属前批历史源码。原始 core、RAW、平台日志不变。

当前新增同页工具与视口已冻结为 `8dbdd33337cecfef5da969920913e5c3c4c66f3d`。macOS 26 [Apple full 43588426197](https://github.com/1162107757/nikon-camera/actions/runs/43588426197) 已失败：Flutter 604 通过、2 个旧 Crop fixture 超时，后续 UIKit/native pipeline 未执行；成功 device build 不等于安装包验收通过。该候选已停止后续验收，未接受。`sourceFrozen=true`、`acceptedForLocalTesting=false`、`published=false`；[附件清单](ARTIFACTS.json)为空，当前没有新源安装链接。`04a4d18ea0109b095ba1f854ea7b9a778480bf03` 的 Apple `43577955414`（582 Flutter、5 UIKit、native pipeline 1）及 Android 精确 R8 123 项只验证同页修改之前的前批五项，不列为当前新源已验收附件。

本轮五项：已有照片连续预览不闪普通进度条；肤色色卡与强度常驻、取色直接暂存并统一人像应用/取消；Editor、颜色、人像修补、RAW、裁切及选区按需显示原图 ROI；可见同步页自动读图并退休旧错误，连接成功仍回原调用方；离线预设首页隐藏原始接口、保缓存并可重试或进入“我的预设”。

新增范围：工具同页只换下方面板，保留源焦点、放大密度和照片 bounds；自然精修与返回同步退休工作；人像、修补、区域与瑕疵候选复用同一照片及状态，逐层取消与确认事务；渐变取样修复显示当前局部效果高清细节；RAW 视口传递与已有照片重新显影内嵌。

见[223 指南](../../docs/migration/local-testing-223.md)与[验证索引](../../docs/migration/validation/features-223/README.md)。本地模型 6、新人像内嵌 5、skin 3、旧 Color 8、旧 Editor HD 3 各组有实际退出 0 记录，Editor 切换 4 等保留分单例通过限定；Windows 原生宿主中断的目标仍为未完成，不能据此称完整同源测试或新安装包已通过。各 attempt、源码与日志 SHA 均保留。前批 JVM 1770 的实际执行已通过 245 输入指纹绑定新 Git（193 原字节相同、52 仅换行差异），`testRerunForBinding=false`，不宣称重新跑 Java；43588426197 的 macOS parity 1770 收据已产出通过，但独立核对待 root，整体 run 仍失败。最终新源平台、包与 UI 验收仍待完成。[222 三包](../migration222/README.md)原样保留，其结果不继承为 223。

只用于本地测试，不发布商店、更新清单或草稿。真实 iPhone/Z6II Wi-Fi、离线现场、USB、QQ 授权、iOS QQ Universal Link 未配置及 16KiB 实体设备等限制保留。
