# 人像精修 131 原生探针

探针通过反射调用已安装应用的生产类，不把应用类打包到探针。使用项目本地 NASA 公共领域测试照片 `.tooling/portrait-qa/astronaut.png` 和合成图案，禁止放入用户照片或生产 APK。

在项目根目录用 PowerShell 执行：

```powershell
& './tests/portrait-upgrade-device-probe/build.ps1'
& './tests/portrait-upgrade-device-probe/run.ps1' `
  -CandidateApk 'D:/dev/ai-project/nikon-camera/dist/huevia-0.26.0-beta-debug.apk' `
  -ExpectedApkSha256 'd8c84b7b1b65ca9768ebe3f44b2441744f129ebd764affa75384620d16ea72ae' `
  -Mode phone -Scope full -Serial emulator-5588
```

只对本任务拥有的测试模拟器运行，预先安装候选主应用。脚本核对模拟器硬件、实际安装 APK 和探针输入哈希；恢复系统设置，移除探针，保留拉取的证据。`font1.3` / `landscape` 配合 `-Scope ui` 检查对应布局。

探针使用实际绑定控件与手势验证皮肤、五官、补光、祛痘确认、自动身体范围、草稿与导出；完整流程还验证双图独立定位和批量撤销保护。祛痘正向 UI 流程用合成候选，真实照片的无候选结果允许保留原图。

设备端证据需逐项与本地哈希一致后再删除精确文件及空目录；不要清空主应用数据。最终冻结报告和已归档探针源码见 `docs/validation/portrait131`。
