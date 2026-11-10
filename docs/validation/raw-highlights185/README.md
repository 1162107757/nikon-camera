# 185 / 0.30.31-beta：默认 RAW 高光偏粉排查

2026-11-10。用户确认问题发生在刚打开 NEF、尚未调整参数时，相机型号未知。用户本次原 NEF 尚未取得；本次修复确认的是默认相机 JPEG 色彩匹配中的高光缺陷，不能据现有样本断言用户原片的所有偏色均已归因。

## 最终安装包

- 路径：`dist/upload185/huevia-0.30.31-beta-update.apk`
- 包名 `cc.huevia`，versionCode **185**，versionName **0.30.31-beta**。
- SHA-256：`c1142e440a9bb38afde54ce922a10e273ef5154cd1899ea5a3827ef4773a302a`
- 31,419,670 字节。完整构建 SHA-256：`d8c7746d92e07d9358b39bbfe2aca7ceea8e76c4b7985daa390345347fba6222`。
- 签名证书 SHA-256：`04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`；v2/v3、ZIP 16 KiB 对齐校验通过。
- 本地候选，未提交、推送或线上发布。184 冻结包与证据保留。

## 排查结论

默认流程先进行 LibRaw 相机白平衡、H2 高光混合及 sRGB 显影，再根据同帧内嵌相机 JPEG 学习近似色彩。本次把两步分开检查。

1. 生成了有不等传感器通道灵敏度、逐通道饱和的 DNG 白阶。184 默认 H2 中性显影的过曝白区为 RGB **225/225/225**，没有产生粉色；H0/H1/H2/H3 各自行为明确区分。高光模式的含义与 [LibRaw 参数文档](https://www.libraw.org/docs/API-datastruct.html) 一致，185 沿用原默认模式。
2. 原 `RawJpegColorMatch` 在拟合时排除了接近过曝的 JPEG 像素，包括已知的白色区域；随后却把三次多项式 LUT 应用于这些区域，既没有固定显示白点，也没有检查高光是否折返变暗。中间调平均验证误差很好，仍可能接受高光有问题的模型。
3. 受控同帧色彩样本中，参考图的高光是白色。实际安装的 184 接受拟合并通过原生 LUT 处理后，白区的最大偏粉量 `min(R,B)-G` 为 **57**。最终 185 在相同 API31 环境为 **0**，API36 也为 **0**。
4. 工作区两份真实 NEF 分别来自 Nikon Z6 和 Z6II。这两张实际默认预览没有复现用户所述的明显粉白，因此没有把它们写成“用户原片已复现”。但 Z6II 学到的旧模型在更亮的中性灰阶上明显折返：输入 RGB255 的预测为 **94/122/121**；该模型不适合继续外推到高光。

基线是未修改的 184 APK，SHA 为 `2ab445a72700385b5ba95fb51d8ee130f2df751c59e4723e1d2572ac7cf72776`。原生基线报告位于 `device/2ab445a7/20261110-095556-92b4a802/`。主机的独立反例见 [white-fit-baseline.txt](white-fit-baseline.txt)；各次探索报告保留，最终通过证据仅采用 [final-results.json](final-results.json) 中列出的运行。

## 最终修改

生产逻辑集中在 `RawJpegColorMatch.java`，另更新版本号和 APK 内随附的该文件源码。

- 接近中性白的 JPEG 高光参与训练及独立空间验证，另行检查白色验证样本的误差。
- 用 12 个在 RGB(1,1,1) 处为零的基函数拟合色彩偏移，保证接受的 LUT 在显示白点没有色偏。
- 对 LUT 中性高光轴检查亮度递增及明显的红蓝偏移，拒绝折返或染粉的拟合。检查在处理照片前完成。
- 不安全时返回 `UNSAFE_HIGHLIGHTS`，走现有的中性色彩回退，显示已有的「JPEG 色彩匹配不可靠 · 已用中性色彩」。该文件的色彩可能不再接近相机 JPEG，但保留实际中性显影结果，不使用不可靠的映射。
- 将色彩匹配模型标识推进到 `same-raw-jpeg-crop-ridge-cubic-lut17-white-v2`。现有工作 PNG、RAW 转编辑 JPEG 及内存拟合缓存的身份都包含此标识，重新打开原 NEF 会重新显影，避免复用旧结果。

没有增加全图去粉、自动涂白或替换照片细节的后处理。LibRaw 参数、白平衡、曝光、高光默认值、去马赛克、8-bit sRGB PNG 编码均保持原样。已验证的 Z6 相机色彩拟合继续应用；Z6II 不安全模型回退后的 PNG 与其中性显影 PNG **逐字节相同**。

## 验证

主机检查共 **16,117** 项：299 项设置/合法 DNG、15,575 项既有色彩拟合、243 项新增高光回归。新增回归覆盖已知白色高光不染粉、回退原像素、白点/透明度、亮度递增，以及普通色彩近似仍可接受。日志见 [host-regressions.log](host-regressions.log)。

最终选定 8 轮设备运行共 **511** 项检查，全部通过，清理与设置恢复记录均通过机器复核。

| 范围 | 检查数 |
| --- | ---: |
| Android 12：生成白阶、原生色彩路径反例、两份真实 NEF、白点与高光轴 | 25 |
| Android 16：相同高光专项 | 25 |
| Android 12：既有 RAW 原生解码、RAW Activity、真实 NEF 色彩与原件保护 | 160 |
| Android 12：真实 NEF 编辑 | 15 |
| Android 12：导出预览、缩放平移、裁剪边框、取消及线程清理 | 55 |
| Android 12：应用切换、导出、文件选择器故障、184 闪退修复回归 | 77 |
| Android 12：大字体、深色及关闭模糊 | 77 |
| Android 16：应用与导出回归 | 77 |

同一 API31 上与 184 比较，**7 组**无 JPEG 色彩处理的完整 PNG 哈希逐字节一致，包括 H0/H1/H2/H3、无 JPEG 参考时的默认模式，以及两份 NEF 的中性显影；它们的缓存身份已改变，证明新模型不会误复用旧缓存。完整关联和 SHA 见 [final-results.json](final-results.json)。

两个隔离 AVD 的崩溃缓冲均为空，运行时安装包 SHA 都与最终交付包一致；已恢复设置并关闭，见 [runtime-final.json](runtime-final.json)。模拟器运行页大小为 4096；16 KiB 是包对齐校验，没有声称在 16 KiB 或荣耀真机上验证。

## 证据、原件与后续复核

- [raw-color-vs184.patch](raw-color-vs184.patch)：最终算法对照真实 184 源码的差异。
- [source-manifest.json](source-manifest.json)：348 个源码/资源/测试文件的冻结哈希，快照在 `.tooling/raw-highlights185/final-source/`。之后的 186 开发已另行接管，复核 185 应使用冻结快照与固定 SHA 包。
- [preservation.json](preservation.json)：相对 184 的 APK 有效载荷变化只有 manifest、DEX 和随附的 `RawJpegColorMatch.java`。全部资源、模型及保留 ABI 的 native 库字节一致；RAW JNI、开发器和设置源码哈希也保持不变。
- [payload-provenance.json](payload-provenance.json)：交付包只从完整构建移除 4 个 x86 库，89 个保留条目与完整构建逐项一致。
- [package-candidate.json](package-candidate.json)、[apk-signature.txt](apk-signature.txt)、[apk-alignment.txt](apk-alignment.txt)、[SHA256SUMS.txt](SHA256SUMS.txt)：包、证书与对齐证据。

QA 使用已有 CC0 Z6 样本 `c079345f…` 和工作区 Z6II 本地参考 `142656e3…`，原件哈希校验通过。QA APK 仅本地使用，交付 APK 中没有 NEF/DNG 测试照片。早期 ADB 暂存文件在应用视图中不可见的诊断失败保留；最终 QA 从已校验的测试资产复制到应用自己的缓存，既有 RAW 套件的测试文件也通过应用 UID 暂存，运行后删除。本次没有把测试文件访问问题归为产品问题。

用户应安装 185 后重新打开原 NEF 复测。若原片仍偏粉，需要该原 NEF 继续核对其相机型号、白点、内嵌 JPEG 和中性显影，不能用现有两张样本代替用户原片的结论。
