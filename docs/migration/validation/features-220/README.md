# 220 验证索引

固定源码 `780376ec1017357fd152adbdd1b5bc71c39a6bf6`。**三包已接受本地测试交付，`published=false`。** Apple [full 43529742646](https://github.com/1162107757/nikon-camera/actions/runs/43529742646) success，独立 IPA 验收 exit 0；220 保持冻结，不混入 221 源码或结果。

| 范围 | 实际证据 |
| --- | --- |
| 共享核心 | [core/result.json](core/result.json)：1764 + 6 = 1770、exit 0；243 个 Java 输入绑定最终源码，191 raw / 52 LF-only，原执行基线保留 |
| Android 两 ABI | [android/result.json](android/result.json)：构建、验签、各 8 个 ELF 16KiB 静态对齐及 10 张图片通过；精确 x64 在 API31/4KiB 环境 R8 78 项通过 |
| Android 最终界面 | [android/ui-result.json](android/ui-result.json)：冷启、紧凑空队列、仅同步页浮动工具、手机50/应用19原位选择与取消、毛玻璃和恢复首页；未执行导入/删除/相机写入，截图私有保留 |
| 本地静态/专项 | [local/result.json](local/result.json)：分析 exit 0；同步8项、网格夹具1项、原生取消309项实际通过；sourceCheck 1212/21/57、inventory 420/8/412 均 exit 0，各体系不合并累加 |
| Apple 全套 | [apple/ci-result.json](apple/ci-result.json)：488 Flutter、5 UIKit（含 PhotoKit）、完整 native pipeline 1，通过；[core-parity.json](apple/core-parity.json)核心一致性1770通过 |
| IPA 独立核对 | [independent-verification.json](apple/independent-verification.json)、[ipa-verification.json](apple/ipa-verification.json)：同源 iPhoneOS/arm64、build220、iOS16+、未签名；10张模板图原字节保留；[simulator-result.json](apple/simulator-result.json)唯一完整场景 success |

[source.json](source.json)为汇总绑定，[ARTIFACTS.json](../../../../dist/migration220/ARTIFACTS.json)记录三包实际字节/SHA与本地交付状态，[测试指南](../../local-testing-220.md)列出八项复测。Windows 旧 intent 全套只记录前8通过后宿主 `-1073741819`，未算15全过；最终完整门禁由本次同源 Mac488通过覆盖，旧失败不重写。

**已知新反馈：遥控快门/就绪状态闪烁、返回退到桌面/退出，正在221处理中，未记为220已修复。** 真实 Z6II Wi-Fi、iPhone 安装/连接、USB、QQ授权及16KiB实体设备仍未验证；iOS QQ Universal Link 未配置，既有 RAW 原图删除限制保留。raw 元数据的 `fullParityComplete=false` 保留其原义，不改成全部设备/功能已验收。

私有假相机两图仅作结构对照，按钮有测试字体限制，不作完整视觉/真机/写入证据。Android 实装 UI 的公开收据只绑定私有截图摘要，未外发用户照片。

旧 [d554](attempts/d554/result.json)、[8c19330](attempts/8c19330/result.json)、[db6b172](attempts/db6b172/result.json)候选均未交付，按原记录保留。不改 [219 收据](../features-219/README.md)，不部署服务或公开发布客户端。
