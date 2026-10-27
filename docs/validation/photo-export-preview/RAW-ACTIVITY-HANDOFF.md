# RAW 显影工作区接入

`cc.huevia.RawDevelopActivity` 独立全屏界面，由根任务接私有 manifest、RAW 文件入口及 MainActivity 返回处理。界面不写原始 RAW；调用同一 `RawDeveloper` 完整显影链，显示受限尺寸的界面概览，输出仍为完整尺寸。

入口为 `RawDevelopActivity.intent(Context, File source, String owner)`；没有 source 时打开系统文件选择器，`Intent.data` 也可提供用户已选文档。现有私有 RAW 路径必须处于 App 自身 files／cache／external-files 内；外部文档复制到自有 UUID 缓存后读取。复制上限与解码器一致为 1GB。

支持 RAW 曝光、相机／自动／自定义白平衡、自定义色温与色调、三种高光方式以及线性／AHD 去马赛克。控制紧凑，竖屏使用照片上方／底部浮层，横屏工具放右侧；预览标明最终为 8-bit sRGB，不声称 Java 编辑链为 16-bit。

“保存 PNG”使用 ACTION_CREATE_DOCUMENT；写入前核对原 RAW 和工作 PNG 的 SHA。“编辑副本”按完整工作 PNG 生成 Q100 sRGB JPEG，校验尺寸／文件结束标记／SHA 后放到 files/raw-developed-handoff 中，Activity 成功返回后保留此独立交接文件，由宿主导入后清理。

返回 extras 固定：

- `EXTRA_DEVELOPED_JPEG_PATH` → `raw_developed_jpeg_path`
- `EXTRA_RAW_SHA` → `raw_developed_source_sha`
- `EXTRA_JPEG_SHA` → `raw_developed_jpeg_sha`
- `EXTRA_WORKING_IDENTITY` → `raw_developed_working_identity`
- `EXTRA_OWNER` → `raw_owner`

账号（包括现有匿名 scope）与 `PhotoFilterEditor.accountOwner` 对照；源文件／设置／后台／关闭通过代次取消旧工作。保存中断不报成功。原 RAW、已有缓存、其他账号及已交给宿主的 JPEG 不由 Activity 删除；只清自己的输入缓存和未交付的 UUID 文件。旋转保留参数及源路径，已有完整工作文件由 RawDeveloper 缓存管理。

本子任务已单独编译 Activity＋RawDeveloper＋Settings，通过真实 API；最后统一源码验证交给根任务。第一次编译修正了包私有 JPEG 验证器的引用，改为本类的完整尺寸／SOI／EOI 验证。最后重验碰到根任务重建共享 manual/classes 时基线类暂缺，未改共享输出、未将该次中断当成通过。

`RawActivityChecks.run(Instrumentation, Context, File source, JSONArray checks)` 追加到 RAW 底层反射探针，使用同一个无嵌入 JPEG 的 96×64 Bayer DNG，已 Android-only 编译通过。检查真实滑杆、自动白平衡、PNG 字节、完整 JPEG 交接、源保护及精确缓存清理；两张截图写入主探针 output。此子任务没有运行 ADB，最终 APK 原生结果由根统一归档。
