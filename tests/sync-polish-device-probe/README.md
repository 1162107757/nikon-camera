# 同步页与页内切换探针

仅限自有模拟器。针对已安装 APK 的真实 MainActivity／AlbumPanel，通过反射驱动现有来源按钮、同步模式和照片详情；生产代码没有 QA 入口。

`build.ps1` 仅对 Android API 编译，生产类由安装应用的 ClassLoader 解析。样本来自本项目已有 astronaut.png，生成三个独立测试 JPEG，结束后删除。拍照、连接、相机写入和服务端发布不会触发。

运行：

```powershell
adb -s emulator-5588 shell am instrument -w -e mode phone cc.huevia.syncpolishqa/.SyncPolishProbe
```

分别检查 `phone`、`font1.3`（运行前设系统字体比例 1.3）和 `dark`。探针保存并恢复应用外观和旧筛选偏好；运行完恢复系统字体比例。只应安装并测试经过校验的候选 APK。

报告与截图位于 `/sdcard/Android/data/cc.huevia/files/sync-polish138/<mode>/`。必须检查 report.json 的 pass，不以 adb 进程退出码判定成功。

断言覆盖旧星标筛选迁移、即时页内切换、主题底色、简短张数、下载列表及详情星标移除，并检查其他项目星标上下文仍可用。界面截图会先关闭系统首次全屏教学。
