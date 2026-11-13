# QQ Android 3.5.19 网络依赖

本说明只针对项目现有、未修改的 `open_sdk_3.5.19_r9483ffc7_lite.jar`，SHA-256 为 `9d57fe61ff9026d34ac84bc63dc719f61da6aa40533a299cc6f73d4ce9df7af8`。

腾讯[官方下载页](https://wiki.connect.qq.com/sdk下载/)当前列出 Android 3.5.19；[官方环境搭建](https://wiki.connect.qq.com/qq登录/)说明以本地 JAR 接入。[官方归档](https://tangram-1251316161.file.myqcloud.com/files/20260414/143310b667ece8922594fbe866dabdef.zip)的 SHA-256 为 `6272d4123d8327400a655c48f1fb7eb24b83fd5beeb527951ed100b219192b9b`。重新核对归档内容只有 SDK JAR 与 demo APK，没有依赖 POM 或指定 OkHttp patch 的说明，因此以下 patch 是项目明确选择的兼容版本，不声称腾讯指定了它。

## 实际二进制要求

SDK 的 `com.tencent.open.a.e` 初始化时调用 `okhttp3.internal.Version.userAgent()`，要求返回值以 `okhttp/3` 开头；不满足即抛 `NoClassDefFoundError`。它还直接调用 Cache、FormBody、MultipartBody、Request、ResponseBody、MediaType.get 等 API。仅 suppress R8 的 missing-class 警告无法提供这些实现；已有 OkHttp 4.12.0 缓存也不能满足这项运行时检查。

项目固定 `com.squareup.okhttp3:okhttp:3.14.9`，Gradle 使用 `strictly` 阻止被传递依赖升级到 4。该版本[官方 Version 模板](https://raw.githubusercontent.com/square/okhttp/parent-3.14.9/okhttp/src/main/java-templates/okhttp3/internal/Version.java)具有 SDK 所需方法，[官方父 POM](https://raw.githubusercontent.com/square/okhttp/parent-3.14.9/pom.xml)指定 Okio 1.17.2。

| 构建 | 固定依赖 | 原因 |
| --- | --- | --- |
| 新版 Android | OkHttp 3.14.9；Okio / Okio JVM 3.9.1 | `shared_preferences_android` 已依赖 DataStore 1.2.1，其 Google Maven `datastore-core-okio-jvm` POM 要求 Okio JVM 3.9.1。将 Okio 降为 1.x 会破坏 DataStore；同时留下 Okio 1.x 和 Okio JVM 3.x 会产生同名类。显式选定同一个 3.9.1 实现并验证旧 Java ABI。 |
| 原版迁出维护 overlay | OkHttp 3.14.9；Okio 1.17.2 | 原项目没有 DataStore，使用该 OkHttp 的原始 POM 组合。原 app 源码与 Gradle 均不改。 |

Square 的[Okio 2 发布说明](https://developer.squareup.com/blog/okio-2/)说明其与 Okio 1 的二进制兼容；[Okio 3.9.1 归档变更记录](https://raw.githubusercontent.com/square/okio/3.9.1/CHANGELOG.md)说明 3.0 对 2.x 的兼容范围，同时列出 `Timeout.intersectWith` 的特定不兼容变更。项目没有以概括性兼容声明代替验证：检查了 SDK 的所有 OkHttp 成员引用，以及 OkHttp 的所有 Okio 成员引用，包含完整 JVM 返回类型描述符和桥接方法。

## 已执行检查

`cross-platform/tool/qq_http_linkage_check.py` 不下载、不运行 Gradle；输入实际 JAR classpath 后，用 javac/java 完成：

- 每组 182 个实际二进制成员引用解析，以及精确 `okhttp/3.14.9` 检查。
- loopback GET、表单、multipart 实际读写，以及磁盘缓存写入/命中验证。
- Okio 1.17.2 与新版实际 Okio JVM 3.9.1 + Kotlin stdlib 2.2.21 两组均通过。

独立日志在 `.tooling/agent-account/qq-http/{legacy,next}-linkage.log`。Maven Central 原始 OkHttp JAR 为 430,488 字节，SHA-256 `2570fab55515cbf881d7a4ceef49fc515490bc027057e666776a2832465aeca0`；Okio 1.17.2 JAR 为 91,980 字节，SHA-256 `f80ce42d2ffac47ad4c47e1d6f980d604d247ceb1a886705cf4581ab0c9fe2b8`。未添加屏蔽必需 HTTP 类的 dontwarn，原官方 JAR 自带的可选平台规则保持。

这些检查不代表真实 QQ 授权验收。仍需匹配包名/签名的腾讯后台登记、真实客户端回调/取消和服务端换取应用会话；iOS Universal Link 仍按用户明确反馈保持“还未配置”。
