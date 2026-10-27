# 真实导出成品预览

本组件已接入源文件、冻结效果及导出规格的真实渲染 API。根任务负责将编辑器／批量入口接到 `setPreviewRequest(s)` 并统一构建、原生验收及发布；本记录不代表最终 APK 已运行通过。

## 实现与接入

- `PhotoExportDialog.setPreviewRequest(PhotoExportPreview.Request)`：单张照片；`setPreviewRequests(List<Request>)`：与设置页照片按序一一对应，批量先选择预览哪一张。
- Request 构造：`(Context, File source, String expectedSha, String frozenIdentity, PresetPreviewProfile, BooleanSupplier stillValid)`。所有效果、账号及源代次由调用方冻结；账号／源代次／效果发生变化时 `stillValid` 必须失效。
- `PhotoPresetRenderer.renderWithReference` 由根任务提供：同一个完整成品 Bitmap（构图、边框和最终尺寸完成后）先输出无损 PNG，再按实际质量输出 JPEG。来源 SHA 在渲染前后核对，预览不写草稿或发布回执。
- Source 用真实 JPEG 文件显示；编码前 PNG 只作同构图对照。完整尺寸失败明确报错，不降采样冒充。全局预览渲染许可限制为一个，换规格关闭旧任务；原图不覆盖。
- JPEG95 完整尺寸保留 EXIF 方向时，JPEG 和编码前 PNG 在 JPEG 解码后以相同方向无损归一，保持同尺寸对照。额外完整 PNG 磁盘预算单独检查。
- 成品页以照片为主体，浮层显示实际尺寸、JPEG 质量和字节体积；支持 JPEG／编码前、适应／100%／200%、双指缩放、拖动和定位缩略图。100% 使用完整区域像素，不以概览图认证。
- 关闭、账号失效、切源、规格变化取消旧任务。后台暂停释放区域解码和位图，返回重新读取；只清理自己的 UUID 缓存目录及已知临时文件。点击返回不发布照片。

## 已执行验证

- 隔离 javac 编译 source、dialog、设置入口及根的真实 `renderWithReference` API 通过，输出在 `.tooling/photo-export-preview-impl/`，不改共享 manual／dist。
- 独立反射原生探针已编译签名；只链接 Android API，不打入生产类。入口和验证范围见 `tests/export-preview-device-probe/README.md`。
- Runner PowerShell 语法解析通过，已有修改文件 `git diff --check` 通过。

子任务没有启动模拟器、运行 ADB 或发布。最终制品原生结果由根任务归档。探针覆盖真实编码差异、尺寸／质量／字节／摘要、100% 瓦片像素、200% 与实际平移、EXIF6、裁剪／边框、账号失效和在途关闭清理；这些测试不认证 RAW 解码或实体手机性能。
