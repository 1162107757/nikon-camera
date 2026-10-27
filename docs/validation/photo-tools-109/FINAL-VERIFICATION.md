# 109 最终交付

应用 `cc.huevia`，versionCode 109，versionName `0.22.0-beta`。

- 安装包：`dist/huevia-0.22.0-beta-debug.apk`。
- 大小：9,478,052 字节。
- SHA-256：`a356ba5104699204c09c2ebfdd64e5ad4f903ed2cd80dbfd4bb392e144e64fb1`。
- 签名：v2／v3 通过，证书 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`。
- 四 ABI 均已入包；zipalign -P16 检查通过。32 位官方 libc++ 为 4KiB LOAD，64 位全库为 16KiB，按实际构建身份记录。
- 262 项生产、资源、原生库及构建输入无漂移，见 SOURCE-IDENTITY.json。

## 同一个最终 APK 的运行结果

| 专项 | 断言执行 | 证据 |
| --- | ---: | --- |
| 局部／修复／新调节／透视／草稿／细节，普通字体 | 184 | a356ba51/20261027-195639-phone-7175070d |
| 同上，1.3 字号 | 184 | a356ba51/20261027-195840-font1.3-75356dba |
| 同上，横屏 | 184 | a356ba51/20261027-200013-landscape-54b9357c |
| RAW 完整解码／显影／界面及真实返回编辑链 | 87 | docs/validation/photo-image-suite/raw-development/a356ba51/20261027-194820-e6ab31ca7d |
| 真实成品预览 | 55 | docs/validation/photo-export-preview/a356ba51/ed7359199300489bab77d70c2d3c428b |
| 相册编辑返回位置 | 47 | docs/validation/album-position-108/a356ba51/20261027-200333-phone-3a4ab7 |

合计 741 次断言执行，有配置间重复，非独立场景数量。报告实际路径及像素指标见 NATIVE-RESULTS.json。每份报告及 provenance 绑定最终安装包摘要；原生探针未链接生产类副本。旧候选和失败记录保留，不能混算为最终成绩。

局部工具验证真实 View 手势、跨过系统阈值的双指导航、取消不写、一次应用进入主历史、撤销重做、三类蒙版与克隆、四个新增全局参数、透视菜单、草稿切图恢复、完整参考／细节／独立 EXIF6 像素对照、账号保护及关闭释放。像素阈值保持零。

RAW 验证真实 14bit Nikon Z6 无损 NEF 及可审计 DNG。输出为 6064×4040 全尺寸 PNG；传感器显影、白平衡、曝光、高光、缓存隔离、取消和原图保护通过。UI 通过真实 MainActivity `startActivityForResult(7319)` 返回，核对进入相册和可编辑 JPEG、源／成品摘要与回执，以及已消费交接文件删除。完整输入 RAW 保持原字节。

成品预览复用完整导出编码前同一 Bitmap，实际 JPEG 的尺寸、质量、字节数及 100% 像素对照通过；预览不会将草稿标成已导出。数据链和图像处理主机验证见 IMPLEMENTATION.md 及各模块记录。

## 图审与范围

三配置 18 张新工具图逐张独立审看，RAW 三张普通字体图独立审看；无剩余需阻塞的换行、裁切、控件错位、间距或图片遮挡问题。实际目录与文件名为每个新工具目录的 `01-local-radial.png` 至 `06-real-local-detail.png`，RAW 三图为 initial、auto-wb、editor-return。成品预览沿用已审同一 UI 组件并做最终同包确认。

本轮没有连接实体手机。实际运行是一个独占 Android 模拟器；ARM ABI 为编译／ELF验证，未在 ARM 实体设备执行。RAW UI 未扩到全字号／横屏矩阵，不能推断所有手机、RAW 压缩格式或 16bit 线性编辑工作流已认证。当前 RAW 输出为 8bit sRGB PNG，进入现有编辑器使用 Q100 JPEG 副本，修复工具为明确取样的羽化克隆。

本轮测试包及夹具已清理、字体／飞行模式／全屏提示设置已恢复，无主 App 卸载或数据清空；模拟器结束状态见 CLEANUP-PROBES.json 和 CLEANUP.json。已有宿主 AVD／临时目录保留，没有重试历史拒绝的递归删除。

109 仅为本地可覆盖安装测试包；没有上传或更改线上更新。已发布 108、公开 390 款目录与强制策略均保持。
