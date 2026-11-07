# 全图皮肤磨皮原生探针

只在指定的隔离 Android 模拟器运行。独立测试 APK 仅通过反射使用实际安装的生产类，附带项目已有的公有领域 NASA 宇航员 QA 图片，不把夹具放入生产 APK。

```powershell
./tests/skin-smoothing-device-probe/build.ps1
./tests/skin-smoothing-device-probe/run.ps1 -CandidateApk <apk> -ExpectedApkSha256 <sha256> -Mode phone -Scope full
./tests/skin-smoothing-device-probe/run.ps1 -CandidateApk <apk> -ExpectedApkSha256 <sha256> -Mode font1.3 -Scope ui
./tests/skin-smoothing-device-probe/run.ps1 -CandidateApk <apk> -ExpectedApkSha256 <sha256> -Mode landscape -Scope ui
```

实际调用附带模型识别皮肤，确认无需选脸；原生滑杆手势、区域外像素、撤销/重做。full 继续检查应用、实际草稿读写、重开恢复与取消、原图保护、完整尺寸 JPEG/PNG 参考和预览一致性。ui 范围不执行完整导出与草稿事务。

探针清理自己创建的源图和草稿，运行器恢复字体、动画、飞行模式并卸载探针。调用方核对下载证据 SHA 后移除对应远端文件，并关闭自己启动的模拟器。没有实体手机、100 张压力、真实用户照片美学验收或完整手机相册发布认证。
