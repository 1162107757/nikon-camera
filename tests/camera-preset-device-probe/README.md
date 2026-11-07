# 统一预设导入原生界面检查

仅限自有模拟器。探针通过反射操作安装 APK 的真实 MainActivity，注入合成预设、槽位和空连接，不调用相机写入入口。生产代码不包含 QA 路由。

先运行 `tests/run-probe.ps1`、`tests/camera-preset-host/run.ps1`，再运行本目录 `build.ps1`。探针仅对 Android API 编译，生产类由已安装应用的 ClassLoader 获取。

安装已冻结的候选 APK 和 `.build/preset-import-probe.apk` 后执行：

```powershell
adb -s emulator-5588 shell am instrument -w -e mode phone -e run review cc.huevia.presetimportqa/.PresetImportProbe
```

分别检查 `phone`、`font1.3`（先设置系统字体比例 1.3）、`landscape`。检查完恢复字体比例。

报告及截图位于模拟器 `/sdcard/Android/data/cc.huevia/files/preset-import137/<run>/<mode>/`。必须检查 report.json 的 pass，不能只看 adb 命令退出码。导入按钮的启用只通过视图状态验证，不点击实际导入。
