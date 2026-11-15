# 229 测试候选验收

冻结产品源码：`4ec25b757ada7715b250226cb6b258231fbae8eb`。用户已确认 A 方案并要求自动化测试后先交付双端测试包；未发布 229，原 228 发布记录未改。

- Android arm64／x64 release 构建成功；包名、229 版本号及 Huevia 显示名均核对。两个包的签名、8 个 native 库的 16 KiB ZIP／ELF 对齐通过，预设预览 10 张图片保持逐字节一致。
- emulator-5584 安装真实 x64 release：同步入口默认 Wi-Fi，USB 标签可切换并自动枚举，空设备状态、重试检测及固定底部按钮正常；返回原同步页和边拍边传连接入口检查通过。截图是实际安装包，USB 空列表来自模拟器无相机的真实结果。
- Android-independent USB helper 新鲜 JVM 执行通过 124 项检查。原片 `readTo` 方法与 228 文本逐字节一致（统一 UTF-8／LF 后比较）。这些不是硬件 USB 下载证明。
- macOS 完整构建 run 43713253104 成功，严格核对冻结源码、完整工作流、artifact API digest 和包内 provenance 后通过：731 项 Flutter 测试、5 项 UIKit 检查、1 个原生场景、SharedCore parity、主线程前台快照、公共互联网隔离、原片与模型／图片资产检查。IPA 未签名，须用户自行签名安装。

Windows 全量检查在冻结前曾以 exit 1 结束，多个测试进程未完成，其中一次 suite 载入前连接关闭；该次运行不作为全量通过依据。随后独立复测 19 个受影响文件，15 个 invocation 通过，4 个仍以进程提前结束返回，未报告测试断言错误。相机相关分组 57 项成功、1 项未完成，该完整连接 suite 独立复测 6 项通过，按规范化源路径及精确用例名合并为 58 个不同用例；见 camera-regression.json。完整冻结源码全量通过的结论仅来自成功的 macOS 731 项执行，不把 Windows 重试次数累加为测试数。

Z6 II USB 实机、真实数据线和读卡行为尚未验证。229 的主要用户复测范围：目录及缩略图、JPEG／NEF 下载、导入预设后回原功能、取消枚举／切换连接方式不误断开，以及重连失败后状态是否准确。

ARTIFACTS.json 与 dist/migration229/ARTIFACTS.json 绑定相同产品源码和包 SHA-256。raw-checks.zip 保存本轮原始本地日志及执行脚本（脚本原始执行位置为 .tooling/next229，归档副本仅供审计），raw-checks-manifest.json 记录其大小与摘要。Apple 原始产物下载、报告及严格核对回执见 apple/。旧版验证记录和安装包未覆盖。
