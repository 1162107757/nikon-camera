# 下载进度避让与 App 内删除

2026-10-25。此记录仅覆盖本轮相册两项修复；最终 APK 和原生截图由主任务统一验证。

- 原因：下载进度和多选动作位于 `AlbumPanel` 根布局末端，未扣除悬浮导航占用的区域，文件大小、取消以及多选动作可能被遮挡。
- `AlbumPanel.Host.bottomNavigationInset()` 返回导航遮挡的像素高度。下载进度整体额外保留该高度和原有 12 dp 下内边距；多选条保留该高度和原有 8 dp 下内边距。根窗口的系统栏 inset 已由宿主处理，不重复计算。手机宿主应传入实际导航高度与下方 14 dp 间距之和；侧边 rail 返回 0。
- 已下载多选动作分为“数量 / 删除”和“批量导出 / 套用效果”两行；单图仍使用原有更多菜单。长按选择、日期全选、选择取消、确认与部分失败回执继续沿用。
- 新增 `AlbumController.deleteDownloadedAppCopies`，复用删除任务的独占租约、传输 / 保存 / 编辑处理互斥、版本依赖检查和项目引用清理。仅移除 App 私有 `camera-album` 中完成的 JPEG 及所选依赖效果，保留相机文件与手机系统相册。确认文字明确范围。既有 `deleteDownloadedPhotos` 仍保留先前行为。
- 原图完成索引保留其历史证据；找不到 App 文件时返回未完成，显式再次接收会重建有效原图。落盘接收历史保持记录，读取已移除文件时返回 `saved=null` 与“本机原图已移除。”，不返回不存在文件的已保存对象。旧失败回执没有被删除。

宿主测试使用独立临时 JPEG / 项目 / MediaStore facade / 合成相机；没有操作用户照片、实体设备或真实相机。

| 验证 | 通过 |
| --- | ---: |
| 相册保存 | 250 |
| 手机导入来源 / 发布 | 86 |
| 本地删除（含新增 11 条 App-only） | 47 |
| 原图身份 | 18 |
| JPEG 验证 | 58 |
| 定向 Controller 删除 / 租约 / 接收历史 | 23 |

命令：`tests/run-gallery.ps1` 和 `tests/run-album.ps1 -LocalDeletionOnly`，均使用独立 `.tooling/album-progress-delete-100/` 类目录。日志 `gallery.log` / `album-local.log` 位于该目录。

待主任务确认：MainActivity 的实际导航 inset 接线，以及普通 / 1.3 字号手机和侧栏布局中的字节、取消、删除按钮边界。可用 tag：`album-transfer-panel`、`album-transfer-bytes`、`album-selection-actions`。
