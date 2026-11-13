# 旧 Android JPEG 修复维护包 195

本目录与 194 资料迁出 overlay 组合构建旧版 `cc.huevia`。原 `app/` 源码、194 overlay 和新版 213 冻结包均不改写。构建时复制原 Java 树到 `app/build/generated/legacy-jpeg195/java`，调用本目录 `patch_sources.py --source <生成树>`，只编译修复后的生成树、194 迁出入口、共享核心和本目录 `src`。保留原主入口与“旧版资料迁出”入口。

版本固定为 `0.30.35-beta-jpeg-fix` / `195`，minSdk 26、targetSdk 35，保留 arm64-v8a、armeabi-v7a、x86、x86_64 四种 ABI。该维护包用于同签名覆盖安装 193/194，保留原资料；不替代新版 `cc.huevia.next`。

在唯一项目根目录 `D:/dev/ai-project/nikon-camera` 执行：

```powershell
python legacy-android/jpeg-195/build.py
```

默认使用本机已验证的 Gradle 8.11.1、JDK 17.0.19、Android SDK/build-tools 36.1.0，并以离线方式运行根工程 `:app:assembleRelease`。可通过 `--gradle`、`--java`、`--sdk` 和 `--build-tools` 指定路径。`--online` 允许补齐依赖；存在 Maven init 时沿用该回环代理配置，脚本不自动启动或改写代理。

签名仅使用根 `.tooling/debug.keystore` 的 `androiddebugkey`，构建前核对真实公开证书 SHA-256 为 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`，签名后再次验签与 16KiB ZIP 对齐。不会创建新密钥，也不会使用新版 Flutter 的签名。

输出位于 `dist/legacy-jpeg195/`：APK、短 `receipt.json`、`SHA256SUMS.txt` 与 `build-evidence/` 日志及原源码摘要。已有不同字节的同名 APK 不覆盖，需先保留为候选。四 ABI 包按手动安装附件交付，不改变旧更新渠道的 32MiB 规则。

此脚本负责构建与静态身份/签名校验；相机 JPEG 行为、覆盖安装后的数据保留及实际页面仍须另行验证。

## 本次修复范围

- JPEG 格式过滤成功却返回空数组时，回退读取该卡完整目录；不再立即认定卡内没有 JPEG。
- 全目录中仍按元数据区分 JPEG、NEF、目录和其他对象。标准 JPEG，以及以通用对象类型上报的独立 `.JPG` / `.JPEG` 可浏览、预览和下载；NEF 内嵌预览不会充当独立 JPEG。
- 单页扫描只遇到非 JPEG 时，继续有界分页；取消、过期会话、索引数量与停滞保护仍生效。
- 全卡不可读保留相机会话并显示读取错误；部分卡不可读时，在有照片和零照片两种页面都提示读取范围不完整。

私人诊断只用于定位，未复制到补丁、夹具或交付目录。诊断显示 Wi-Fi 会话和心跳正常，目录包含 `0x2013` 存储卡不可用及空索引；后续完整目录中的对象类型没有记录，因此不能认定那些对象一定是 JPEG，也不能仅凭报告判断 JPEG 所在卡是否可读。

## 验证与后续

`python legacy-android/jpeg-195/test.py` 使用 JDK17 编译实际生成的 PhotoFormat、补丁 helper 和原 PTP 类，运行 11 组行为场景、1130 项断言。它覆盖回退、错误、取消、边界和格式分离；模拟器验收另见交付目录。

受控 PTP/IP 相机运行入口见 `tests/camera-peer.md`。它使用自绘 JPEG 和合成元数据，不替代真实 Nikon、真实 NEF 或手机系统网络验证。

按用户要求，本轮只交付旧版。等待用户使用 Z 6_2 验证 JPEG 列表、缩略图和下载后，再对跨平台新版检查并移植所需差异。
