# eab / 225 Apple full 43611891603 失败原件

本次完整 run 对应 `eab42304d0c1c2360ef50cf1b7e9261c714d24ce`，Flutter 实际 659 通过 / 2 失败；设备 Runner.app 编译退出 0，但全套门禁失败，所以没有打包 IPA，也未进入 5 UIKit/真实 native 集成。不能继承旧 Apple 通过，不接受本次 iOS 附件。Android 独立本地测试接受状态由主清单保留。

两个失败均在旧 editor_test.dart 的大字竖屏/横屏 case：真实点击“重置通道”前找不到控件。冻结夹具 DraftCore 仅返回 path，省略实际1×1 PNG 的 width/height；生产 accepted-frame 合同据此得到 null 尺寸，补 render 后仍拒绝进入曲线。这不是按钮改名，也不是增加固定等待能修复。生产按钮文字仍存在；最小修复仅补真实尺寸和真实 source 文件，保留真实 UI 入口及业务断言。后续夹具修复及新 full run 不回写本次失败。

original 包含 GitHub digest 已核的原 ZIP、完整解包日志、job console 和 API；冻结失败夹具通过 GitHub contents 的精确 eab ref 读取，Git blob hash 已独立复算，没有把工作区新修夹具冒充旧输入。必经 Foundation 公网 fixture 和 JVM1788 parity 的实际通过收据保留，但不覆盖全套失败结论。原件逐项 SHA/字节数见 byte-manifest.json。

Windows private diagnostic 输出因 GBK 无法打印设备日志的 ✓ 而报编码错误，属于本地显示问题；真实 CI 的659/2、device exit0 和原日志与此独立。归档未运行 SDK、构建、测试或 Git 仓库命令，只有只读 API 与文件哈希。
