# Android 16 RAW 入口闪退修复 · 158

用户补充环境：Android 16、Huevia 0.30.1，点击“RAW 显影”立即退出。已在独立 Android 16 / API 36 模拟器上，用冻结的 155 / 0.30.1-beta 安装包，从实际“相册 → 更多 → RAW 显影”入口复现同样的退出。

实际堆栈见 [155-crash.txt](../raw-picker157/android16/155-crash.txt)：

```text
Unable to start activity ... RawDevelopActivity
Caused by: java.lang.NullPointerException:
  DecorView.getWindowInsetsController() on a null object reference
  at PhoneWindow.getInsetsController(PhoneWindow.java:4136)
  at RawDevelopActivity.buildUi(RawDevelopActivity.java:106)
  at RawDevelopActivity.onCreate(RawDevelopActivity.java:97)
```

原因是 RAW 页在 `setContentView` 之前读取 `Window.getInsetsController()`，此时 Android 16 的 PhoneWindow 内部还没有 DecorView；对返回值判空无法捕获发生在调用内部的空指针异常。修复为先调用 `getDecorView()` 创建窗口视图，再配置系统栏，沿用 MainActivity 已有的初始化顺序。保留 157 的系统文件选择器异常处理。

同类检查覆盖 MainActivity、RemoteCaptureActivity、PhotoDetailDialog、PresetSelectionPage、PhotoExportDialog、PhotoExportProgressDialog 及 PhotoExportPreviewDialog。前六者在控制器读取前已创建 DecorView、设置内容或显示窗口；PhotoExportPreviewDialog 的成品预览存在相同顺序问题，155 的真实窗口探针也复现相同空指针，已一并修复。前次 157 的选择器修复不覆盖本次实际根因，157 APK 和原有验证记录保留。

158 / **0.30.4-beta** 修复包：`dist/huevia-0.30.4-beta-debug.apk`，34,581,880 字节，SHA-256 `31a5be2a9818fa1b859753d702078ec0a13d8971a274b08d5446c538f8767971`。V2/V3 签名有效，签名证书与 155 相同；保留四种原有 ABI。仅本地产物，未发布到更新后台或官网，线上 156 和下载预算保持原状。

实际验证共 **380 项通过**：

| 环境 | RAW 实际 Activity / 引擎 | 成品预览窗口 | 实际相册菜单 |
| --- | ---: | ---: | ---: |
| Android 16 / API 36，4 KB 页面 | 128 | 55 | 14 |
| Android 17 / API 37，16 KB 页面 | 128 | 55 | — |

RAW 覆盖新建空白窗口、系统文件选择器缺失/权限拒绝/取消/重试、全尺寸显影、PNG 保存、JPEG 副本进入实际编辑器，以及真实 Nikon Z6 NEF（6064 × 4040）。成品预览覆盖实际 JPEG/编码前对照、100%/200% 和拖动、EXIF 方向、裁切/边框、账号失效与待处理工作关闭。

Android 16 实际菜单验证不注入选择器，也不通过反射启动 RAW：连续两次从菜单进入真正的 DocumentsUI，取消后回到 RAW 页面，再返回相册；进程始终为同一 PID，没有新的主线程崩溃。见 [manual-entry.json](manual-entry.json)、[158-raw-after-cancel.png](158-raw-after-cancel.png)。已检查截图，标题、返回、选择及底部控件可见。

证据目录：

- 155 成品预览故障：`../photo-export-preview/b7d39e49/0224608aefdf4b71905f2874ad8e0fa2/`，明确报告同样的 DecorView 空指针。更早 `b133e127b7cb43b3bf9eacb81d53b8cf/` 保留了尚未展开异常包装的失败记录；不计入通过项。
- Android 16 RAW：`../photo-image-suite/raw-development/31a5be2a/20261108-124456-23d411bb8e/`。
- Android 17 RAW：`../photo-image-suite/raw-development/31a5be2a/20261108-124521-99ed1dc066/`。
- Android 16 成品预览：`../photo-export-preview/31a5be2a/e8d966dedcd540bf81b7beee404e286e/`。
- Android 17 成品预览：`../photo-export-preview/31a5be2a/152f84cfe1b4483db880619095c971b7/`。

探针只安装自己的 instrumentation，生成的照片和缓存均按本次唯一标识清理，未接触相机或用户照片。Android 16 使用当前工作区内新建的隔离 AVD，验证完成后关闭；已有 Android 17 模拟器保留，安装 158 并停止应用。没有连接实体手机。
