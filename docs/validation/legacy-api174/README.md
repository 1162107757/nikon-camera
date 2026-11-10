# 174：旧安卓兼容运行环境的在线页签闪退

本地版本 `0.30.20-beta`，包含171全库搜索、172可选切页截图保护和173最终修补流程。未上传或公开发布。

用户提供鸿蒙4.3.0.208，触发点是顶部“在线预设”页签，暂未取得实体机型号、Android SDK值或原始崩溃栈。

## 已确认的原因与修复

`OnlinePresetRepository.fetchPage` 与 `CommunityRepository.encode` 调用了 `URLEncoder.encode(String, Charset)`。该重载[从Android API33提供](https://developer.android.com/reference/java/net/URLEncoder)，实际172安装包仍直接引用它，并未被D8降级。

在独立Android12／API31模拟器上安装同一个172交付包：直接接口对照8项通过；随后从实际页面点击顶部在线页签，产生真实未捕获的 `NoSuchMethodError`，崩溃栈位于 `OnlinePresetRepository.java:84`。见 [实际点击崩溃日志](baseline-online-tab-crash.txt)；这是正常点击，不是注入该错误。初始只打开默认“我的预设”时不会触发，单独保留了启动记录。

174将两处调用改为同样UTF-8的编码名称重载，保留中文、空格、加号、路径符、emoji及null名称规则；没有用广泛捕获LinkageError来隐藏实现问题。[最终DEX检查](final-dex.json)确认不再引用Charset重载。

## 精确包与验证

完整包 SHA-256：`22deacb8e5f386f72186a34234421c07ffb38ba1b59cc769a881f151059f9077`。

交付包：`dist/upload174/huevia-0.30.20-beta-update.apk`，31,370,429字节；SHA-256 `527191606cc678c0e1076f42f96036160f8886aa586243e22ede06b402ce904c`。原证书v2/v3签名、16KiB对齐、后台APK离线检查及88个保留payload比较通过，仅移除4个旧x86库。

- 最终同一交付包：API31和API37各20项原生检查，覆盖实际平台编码、请求参数、页结果、社区文件名和MainActivity来源切换。元数据HTTPS使用明确夹具，不认证真实样片渲染。
- API31同包全库搜索37项直接回归通过，目标在390条夹具的最后一条；171四配置和172切页保护保留各自版本的证据，不重复计为174全量验收。
- 主机回归：社区33／分页46／回复94／收件人9；预设库548／编辑目录53／图片缓存36，分别记录。

API31镜像从Google官方仓库下载、核对官方大小与SHA1，使用项目内独占AVD／5584，验证后已关闭。共享5588曾因Android系统服务死亡无法安装，保留Broken pipe诊断；正常退出并重启原Pixel_9、没有清空数据后，同一个APK成功安装并完成API37检查，设置已恢复、App停止。详 [summary.json](summary.json)。

这些结果证明旧运行环境存在且已修复一个能复现用户触发路径的缺陷；仍不能代替鸿蒙4.3.0.208实体机验收，也不宣称其所有闪退只有这一原因。未上传、发布、提交、推送或发送微信。
