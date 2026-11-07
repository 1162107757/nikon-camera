# 相册批量导出原生探针

在专属离线模拟器安装候选 APK 后运行。探针不打包生产类，仅通过已安装 APK 的 ClassLoader 反射调用原生界面和导出工作流；只创建自己命名的 JPEG/草稿/结果，并在结束时清理。

```powershell
./tests/batch-export-device-probe/build.ps1
./tests/batch-export-device-probe/run.ps1 -CandidateApk <apk> -ExpectedApkSha256 <sha256> -Mode phone -Scope full
./tests/batch-export-device-probe/run.ps1 -CandidateApk <apk> -ExpectedApkSha256 <sha256> -Mode font1.3 -Scope ui
./tests/batch-export-device-probe/run.ps1 -CandidateApk <apk> -ExpectedApkSha256 <sha256> -Mode landscape -Scope ui
```

`full` 覆盖两张独立参数、真实 App 内 JPEG 导出、故意缺失一个原图后的部分失败、冻结参数及只重试失败项。`ui` 只检查多选入口与导出设置。尺寸断言使用 EXIF 后的显示尺寸。原生窗口截图等待首次布局及进场动画完成。

运行器只接受 emulator-5586/5588 和模拟器硬件，验证 APK/探针来源，恢复系统字体、动画和飞行模式，卸载探针。由调用者关闭自己启动的模拟器；下载证据核对 SHA 后再清理对应远端目录。验证范围为合成照片、App 内保存，不代表真实手机发布或压力性能认证。
