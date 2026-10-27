# 遥控拍摄原生验证

仅在任务自建的隐藏只读 Pixel_9 模拟器 `emulator-5588` 运行，不连接实体手机或相机。测试 APK 与生产 APK 分开构建。`FakeNikonPeer` 是内存中的 PTP/IP 字节协议夹具，生产 APK 没有此类、示例素材或演示开关。

探针已增加 96 的 MTP 身份、图标居中及齿轮收纳回归；旧 95 APK 在新增回归上失败是预期。先构建当前生产 APK，再运行（显式传候选与证据目录）：

```powershell
./tests/remote-capture-device-probe/build.ps1
& 'D:/dev/Android/Sdk/platform-tools/adb.exe' -s emulator-5588 install -r dist/huevia-0.20.1-beta-debug.apk
& 'D:/dev/Android/Sdk/platform-tools/adb.exe' -s emulator-5588 install -r tests/remote-capture-device-probe/.build/remote-capture-probe.apk
foreach ($captureMode in @('phone','font1.3','landscape','dark')) {
    ./tests/remote-capture-device-probe/run.ps1 -Mode $captureMode -CandidateApk dist/huevia-0.20.1-beta-debug.apk -EvidenceGroup remote-capture-96 -VendorId 4294967295
}
foreach ($vendorId in @('6','10')) {
    ./tests/remote-capture-device-probe/run.ps1 -Mode phone -CandidateApk dist/huevia-0.20.1-beta-debug.apk -EvidenceGroup remote-capture-96 -VendorId $vendorId
}
node ./tests/remote-capture-device-probe/collect-96.mjs
```

每次运行校验安装 APK 的完整 SHA-256，按候选 SHA 前缀／模式／独立运行 ID 保存原生截图与 `report.json`，保留失败历史。运行结束恢复字体、方向、深色模式和动画设置；`run-identity.json` 保存恢复回执。夹具下载文件在探针结束时删除。汇总只接受当前候选每种模式最近一次 PASS，横屏还需原生方向断言。

覆盖：同步入口、能力与授权边界、当前参数、完整取景帧和同帧直方图、拖动／收起／RGB、原生 AF 与坐标、防重复快门、原图保存复用、RAW 先到及延迟 JPEG、取景关闭／恢复、断线未知结果及显式核对。补充验证 AF 与快门拒绝提示跨轮询可读、离线未传入 JPEG 的禁用入口，以及横屏亮画面下的工具组对比度。

96 还覆盖三种 Nikon/Microsoft/MTP 身份、PhotoFilterEditor 真正组件的 LTR／RTL 图标像素中心、保存项退出底部、齿轮位于直方图左侧、保存位置说明、传入开关的原生点击与弹层重开状态。图标画面是组件测试容器，不是绑定完整照片的编辑流程。

每种模式发出四次显式测试快门命令：三次夹具曝光和一次明确拒绝；没有自动重发。截图中的机型、读数与电量来自测试夹具。亮画面对比图由纯色 Bitmap 编码，常规取景复用已注明来源的合成样片。

这些检查验证生产解析器、控制器和 Android 界面之间的行为，不能证明 Z6II 固件互操作、真实 Wi-Fi 路由／吞吐、持续帧率或实体设备辅助功能体验。必须另行进行真机联调。
