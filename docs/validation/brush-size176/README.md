# 176 修补大小居中反馈

仅修改 `PhotoEraseDialog.java` 的显示反馈，并将版本提升为 176／0.30.22-beta。拖动大小滑条时，窗口正中心显示随实际笔刷投影尺寸缩放的空心圆及数值；松手、失焦或关闭立即隐藏。提示放在窗口根 ViewOverlay，照片像素、修补模型和历史不参与绘制。175 实时无高亮涂抹、每笔撤销、v8 草稿语义及 174 兼容修复保留。

## 本地交付

- 完整包：`dist/huevia-0.30.22-beta-debug.apk`，SHA-256 `e7d2438ccdec191a53ff45f84d5c312c7d6cbf0209d58eda986d0467667d0330`。
- 上传用包：`dist/upload176/huevia-0.30.22-beta-update.apk`，31,374,525 字节，SHA-256 `9d307254e007cc6272c1b2f7f653c0f685bd6de9eb6d637498481d07aedaca3c`。
- 版本、包名、签名和 32 MiB 后台限制由实际 `inspectApk` 离线检查通过；v2/v3 签名与 16 KiB 对齐检查通过。精确上传包用于以下全部原生验证。
- 只移除 4 个过时 x86 库，88 个保留负载逐字节一致，ARM32/64 和 x86_64 保留。见 [包身份](package-candidate.json)、[负载来源](payload-provenance.json)、[后台检查](backend-apk-inspection.json)、[源文件身份](source-candidate.json)。
- 未上传或发布；168–175 包和冻结证据保持原归属。冷启动及进程存活通过，见 [冷启动](cold-launch.json)；设置恢复且本任务拥有的模拟器已关闭，见 [清理](device-cleanup.json)。

## 原生验证与视觉查看

API36 模拟器四种配置：phone 1080×2424、font1.3 840×1890、tablet 1600×2560、landscape/dark 2424×1080。每种配置 52 条含启动与重复断言、4 张原始 PNG，合计 208 条／16 图；覆盖大小变化、窗口实际中心、松手与失焦隐藏、照片和历史不变。窗口根边界在四种配置均与实际物理屏幕一致。四张状态联系图已一次批量视觉检查，之后没有视觉改动。

逐图路径、尺寸和 SHA-256 见 [capture-index.json](capture-index.json)。捕获器复用既有 175 原生夹具，176 原图位于 `docs/validation/live-erase175/native/9d307254/` 独立包哈希命名空间，未改写冻结 175 原图。`.tooling/size176/capture/` 是忽略的捕获辅助器，不新增产品测试或生产素材。

同一最终签名包另跑既有 175 原生 phone 流程，157 条／7 图通过，目录 `docs/validation/live-erase175/native/9d307254/20261109-154901-phone-6a7beaa3/`。该结果只代表手机配置中的既有实时修补、合并、失败恢复、历史和草稿流程；未声称本次重跑 175 全部四配置或 host 算法套件。175 算法未改，原有独立证据仍见 [175](../live-erase175/README.md)。

证据来自原生模拟器，不认证实体 S24+／鸿蒙、FPS、任意照片修补质量或全应用。大小提示不会绘入照片；175 原有限定质量边界继续有效。
