# Huevia 跨端开发版 219 · 本地测试包

**219 三个同源安装包已通过本地测试交付验收，源码 `e55414ad38ab04291313ddc1244a7ec778da659f`，仅本地测试，未公开发布。** [ARM full 43482938724](https://github.com/1162107757/nikon-camera/actions/runs/43482938724)实际449项Flutter、5项UIKit（含新增布尔/计数原值与JSON往返类型断言）及完整native pipeline通过，设备IPA独立验包已成功。iOS包为iPhoneOS/arm64、需iOS16+并自行签名；真实iPhone安装、QQ授权和Z6II连接仍未验证。

f3 候选因 RAW 显影返回相册后点击失效暂扣、未交付；新源码已补返回流程，两条真实路由回归分别通过，a54 x64 包也已完成同进程返回 / 重开验证；此完整功能 UI 保留 a54 来源。f3 的两 ABI 静态与 x64 R8 78 项结果仅作[历史证据](../../docs/migration/validation/features-219/attempts/f3/result.json)；其 Mac 未获托管执行器，没有执行产品测试，不替代本轮门禁。

旧候选 `4f9f1dc6d32d41f7b0179dac7436addc35ff6699` 已暂扣、未交付，旧 Mac 核心一致性虽过但头像夹具编译失败，随后还补看门狗 / 显式断开归属。[旧候选记录](../../docs/migration/validation/features-219/attempts/4f/result.json)不替代后续最终源码门禁。当前状态见 [ARTIFACTS.json](ARTIFACTS.json)，候选文件不等于可安装结论。

| 平台 | 当前状态 |
| --- | --- |
| Android ARM64 手机 | [ARM64 APK](huevia-0.31.0-dev-219-android-arm64.apk)，已接受本地测试 |
| Android x64 测试环境 | [x64 APK](huevia-0.31.0-dev-219-android-x64.apk)，精确R8 78/冷启动通过 |
| iPhone 自签测试 | [未签名IPA](huevia-0.31.0-dev-219-ios-unsigned.ipa)，独立验包通过；iOS16+，需自签，未实测手机安装 |

本轮重点：

- **工作 JPG 与 NEF 来源分开。** 显影 JPG 主标签显示 `JPG`，关联原片另列 `来源 NEF`；同基名文件仍分别打开，不改变照片像素或把 JPG 变成 RAW。
- **iOS 当前前台窗口。** 针对 217 / 218 已知的真实前台连接被旧页面引用拒绝问题修复；UIKit已5项通过，真实iPhone/Z6II仍未验证，不能宣称已连接 Z6II。
- **连接只完成当前目的。** 导入预设连接成功后直接继续所选预设槽位，照片仅在用户主动进入「同步 → 相机照片」时读取；正确区分健康照片 / 槽位连接与尚未读目录。
- **取消与后台只作用于正确任务。** 已完成任务、旧页迟到回调和过期后台许可不能结束新任务；权限弹窗临时遮挡不误停接收，真正后台仍按原保护策略和系统时段清理。手动断开入口保留。

218 的长按多置顶、原删除确认、模板选图 / 恢复及十张预设预览图继续保留；独立大样片浏览仍已移除。QQ 免应用验证码继续保留，注册验证码及腾讯身份校验不变。真实 QQ 设备授权未验收，iOS Universal Link 尚未配置。

本地已有 [相机75项独立增量](../../docs/migration/validation/features-219/flutter-camera/final-result.json)、[旧fixture补充8项](../../docs/migration/validation/features-219/flutter-camera/supplements/legacy-fixture-contract/README.md)（完整6+2独立进程，含1项个人同步）、[核心1629](../../docs/migration/validation/features-219/core/result.json)、格式6、原生Java309与RAW返回2例。原始执行基线保留、按内容纯绑定e554，不合并为一次总运行；失败/OOM/未完成历史不计通过。iOS取消接口另有57个静态检查，新消费者已完成e554全门禁，真实设备仍未验证。

实装 RAW 样本为 DNG，NEF 标签另有控件覆盖；没有真实 NEF 实装或 Z6II 连接成功结论。应用内删除本轮 QA DNG 仍显示“项目照片文件名无效”，既有 RAW 删除边界未修，不计为通过；该 QA 记录与 Download 副本已另按精确守卫清理，原 19 条记录及 637 个其他资料文件完整保留，不能把专门清理算产品删除通过，详见 Android 收据。

按 [219 测试指南](../../docs/migration/local-testing-219.md)复测。已知用户为 Nikon Z6II（“Z62”）+ 相机 Wi-Fi；实体 iPhone 前台连接仍未验，等验收后的 219 专项 IPA 再测，不用旧 218 重复验证该修复。未签名 IPA 需自签，设备权限和 USB 行为分别实测。

保留 [218 三份已验收附件](../migration218/README.md)和此前基线。安装 next 新版会覆盖同包 `cc.huevia.next`，先保留重要资料和旧版导出 ZIP，无需卸载原 `cc.huevia`。4 KiB 模拟器与 16 KiB 静态对齐不等于 16 KiB 实机验证。

本轮仅本地测试，不公开发布、不上传发布草稿。既有服务后台已单独更新，不等于客户端上架或授权其他生产部署。
