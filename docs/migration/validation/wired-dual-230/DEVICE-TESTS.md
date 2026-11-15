# Z6 II 有线边拍边传真机测试

Android 安装 `dist/migration230/huevia-0.31.0-dev-230-android-arm64.apk`。iPhone 使用 `dist/migration230-ios/huevia-0.31.0-230-unsigned.ipa`，要求 iOS 16 或更新系统，使用自己的签名方式安装后再开始。两个平台分别测试、分别记录，软件编译通过不代表真机通过。

1. 记录手机型号、系统版本、Z6 II 固件、数据线和转接器。iPhone 另记 USB-C 或 Lightning。
2. 用数据连接将 Z6 II 接到手机，保持 Huevia 在前台。Android 使用 MTP/PTP（相机有此选项时）；iPhone 先按本应用 PTP 通路测试。Lightning 与 USB-C 的接线方式分别记录。
3. 在应用中检测并连接 USB 相机，先浏览相机照片并手动接收一张。确认连线期间仍可在机身上按快门。
4. 卡中保留旧照片，到“同步 → 拍摄接收”选择项目和 JPEG，点击开始。旧照片应保持不自动补收。
5. 在机身新拍 3 张，确认项目只增加 3 张，重复刷新不重复收片。
6. 停止后改选 RAW（NEF）再开始，新拍 3 张，确认接收 NEF 原文件。相机拍 RAW+JPEG 时，应用只接收本次选中的格式。
7. 连续拍 5 张，核对新增数量、文件大小和格式，确认没有重复或半文件。
8. 收片过程中点停止，确认当前传输有明确结果；停止后仍可浏览和手动接收。
9. 传输中拔线，确认应用明确暂停；重连并核对原相机后手动继续，已收照片不得重复入库。身份无法确认时开始新任务。
10. 有默认预设时确认成品另存，原文件仍保留；无默认预设时确认只保存原图。

结果请按“Android / iPhone、步骤编号、拍摄数量、接收数量、提示文字”记录。某一步失败时先保留提示与诊断报告，再继续定位。

Z6 II 的“iPhone”USB 选项是尼康针对 NX MobileAir 的专用说明，本应用兼容性须单独验证。[尼康说明](https://onlinemanual.nikonimglib.com/z7II_z6II/en/17_changes_made_via_firmware_updates_04.html)；iPhone 接线形式可参考[苹果相机转接器说明](https://support.apple.com/en-ie/118280)。
