# 简化编辑 132 原生验证

探针对已安装生产 APK 使用反射和实际绑定控件，不将应用类打包进测试 APK。执行入口是 `compactFlow()`；沿用 131 的离线 NASA 照片、等待、截图和私有夹具清理脚手架。未调用的历史辅助流程不计入本轮断言。

在项目目录先运行 `tests/compact-editor-device-probe/build.ps1`。仅在本任务拥有的测试模拟器上预装最终主 APK，然后运行：

```powershell
$compactApk = 'D:/dev/ai-project/nikon-camera/dist/huevia-0.27.0-beta-debug.apk'
$compactSha = (Get-FileHash -LiteralPath $compactApk -Algorithm SHA256).Hash.ToLowerInvariant()
& './tests/compact-editor-device-probe/run.ps1' -CandidateApk $compactApk -ExpectedApkSha256 $compactSha -Mode phone -Scope full -Serial emulator-5588
```

`font1.3` 和 `landscape` 使用 `-Scope ui`。脚本核对实际安装字节、探针输入与 APK 哈希，保存每次探针源码，恢复字体/动画/飞行模式等设置并卸载测试包。不得对实体用户手机运行这些会创建私有夹具的脚本。

检查五个入口、快捷强度与一次手势撤销、重复效果恢复、基础调节的局部范围、常用工具的画布高度、直接进入/取消人像工具、自动人物识别、草稿保存和重新打开、重置/过期任务、保存规格及账号冻结。首屏还检查保存按钮实际像素已绘制。

完整流程暂时拦截最终导出回调，核对冻结的当前草稿、手机相册目标与新副本意图，再使用生产渲染器生成 JPEG 及编码前参考 PNG，与编辑预览逐像素比较。两项列表另验证批量保存面板的分享规格回调。本轮不把这些结果说成已执行实体手机 MediaStore 发布或百图压力测试。

夹具通过测试代码直接写入私有目录，因此打开列表后显式刷新扫描；这与用户从系统选择器导入后由正常导入流程刷新不同。所有私有源图和草稿均按唯一文件名清理。设备证据与本地逐项哈希核对后，才删除精确设备文件及其空目录，保留主应用和数据。
