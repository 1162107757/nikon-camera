# RAW 底部按钮精修 · 159 / 0.30.5-beta

仅精修 RawDevelopActivity 底部“保存 PNG”和“编辑副本”。两颗按钮统一等宽、48dp 高、14dp 圆角，间距 10dp；保存沿用页面暖色强调，编辑采用深色底和细轮廓。文字统一 13sp / medium，显影前或处理中使用相同的中性灰底、轮廓及可读文字，不再依赖整颗按钮降到 0.4 透明度。保留原文案、可用条件、回调、PNG 输出及完整尺寸 JPEG 副本交接。

提供原生按压反馈和键盘焦点轮廓，沿用既有 RAW 暖色深色界面，没有修改其他编辑工具或全局主题。包含 158 的 Android 16 窗口初始化修复。

本地 APK：`dist/huevia-0.30.5-beta-debug.apk`，SHA-256 `4f9fe59059ed7515738e370a0662d6d8e975039a95dab3e71248e6d7c4035936`，34,581,880 字节；构建及 V2/V3 签名验证通过。未上传后台或发布官网，旧安装包保留。

验证使用 emulator-5588 / Android 17 API 37，不是实体手机：

- 实际 RAW 回归 128 项通过，包含选择器异常恢复、真实 Nikon Z6 NEF、PNG 保存和实际编辑副本交接。精确包记录位于 `../photo-image-suite/raw-development/4f9fe590/20261108-130244-7be19e5dbb/`。
- 从真实相册菜单进入系统文件选择器，实际选择本次唯一命名的 CC0 NEF，完成 6064×4040 显影。没有通过反射伪造本轮界面状态。
- 一轮批量检查五张原生截图：空白禁用、手机可用、深色及字号 1.3、横屏、平板。按钮文字未裁切，宽度相等（横屏像素取整差 1px），高度 48dp，间距约 10dp；无需第二轮修改。
- [phone-ready.png](phone-ready.png)、[phone-disabled.png](phone-disabled.png)、[phone-font1.3-dark.png](phone-font1.3-dark.png)、[landscape.png](landscape.png)、[tablet.png](tablet.png)；实际按钮边界、密度与字体参数见 [profiles.json](profiles.json)。
- 显示参数及飞行模式已恢复，应用停止；本轮 Downloads 夹具和设备端截图按精确路径移除，正常显影工作缓存保留。见 [cleanup.json](cleanup.json)。

本轮为局部外观精修；158 的 Android 16 故障复现及双系统结果仍属于其冻结包，不计为 159 重跑。来源样片 SHA-256 为 `c079345fc93f53a4f0d322f8ddaae505f920c36015f25b58befccaa61db1af31`，许可与来源保存在 `.tooling/raw-native/samples/SAMPLE.json`。
