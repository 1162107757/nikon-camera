# 遥控拍摄 · 95 原生实施

Operate 模式，严格继承用户已批准的 [原型](../../design-review/remote-capture-20261024/prototype.html) 与 [局部约定](../../design-review/remote-capture-20261024/IMPLEMENTATION-CONTRACT.md)。保留现有同步页及四个根导航，进入独立近黑工作区。

关键承诺：小机型与紧凑图标、完整画面、只读当前参数、对焦、单次存储卡快门、确认结果及可选 JPEG 传入；亮度／RGB 直方图与显示帧成对更新，可拖动、收起、放大；旧帧明确暂停。横屏机型位于右上、工具覆盖画面、右侧 217dp 控制区；系统字号使用 sp，交互目标至少 48dp。

与另一任务明确交接：保留 94 / 0.19.3-beta 的全部照片加载与边拍边传更名，仅改版本、manifest、AlbumPanel 入口、AlbumController 显式占用与复用下载、PtpIpClient 独立可撤销授权，并新增 remote 与原生 Activity/View。未改 MainActivity、CameraConnectionRuntime/Service 或照片编辑、JPEG 读取链。94 APK SHA 保持 `35426c2001892979cd793ae71c9eea282f6e33eed0255113876b1af0403bf555`。

## 证据范围

独占 emulator-5588（自建隐藏只读 Pixel_9 模拟器）。测试 APK 内的内存 PTP/IP 字节夹具响应真实生产传输、控制器与原生界面；生产 APK 不含模拟相机或样片演示模式。样片逐字节复用既有合成 PNG，测试时编码成预览 JPEG。快门仅发送到测试夹具，不操作实体手机或相机，不上传发布。

检查包括：默认只读 API 不获得拍摄／属性写入权限、撤销授权、同一队列、帧统计、原生点击与 AF 坐标、快门防重、确认及原图传入、RAW 先到而 JPEG 延迟、取景中断与关闭／重开、断线未知结果、重连保留限制及显式核对。连接路由、真实无线吞吐与固件互操作仍需 Z6II 真机联调；本轮不能据此认证硬件支持、帧率、低延迟或完整 TalkBack。

初始 `2c2a2784` 的 phone/font1.3/dark 为历史；其 landscape 方向未正确应用，不能作为横屏证据，且发现取景结束分支失败。`5a1a6709` 确实进入横屏，但 ready 捕获命中系统旋转动画，且快速重开因缓存 LiveViewStatus 失败；这些均保留 FAIL，不混入最终。后续探针显式核实 Activity 方向并在截图期间关闭系统动画，逐项恢复原设置。

最终候选 `cb4d685b…` 已通过四模式 372 次配置检查（92 / 92 / 96 / 92），49 张当前原生截图由 UI-MATRIX 索引。初审 FINISH-REVIEW 为 fix，收尾后 FIX-VERDICT 的 M1–M4 均 resolved，disposition 为 ship，范围仅覆盖四项修正；不扩大为整表面重新认证或 Z6II 真机认证。生产输入最终校验 214 项、漂移 0，原 94 APK 未变。交付身份以 FINAL-IDENTITY 为准；CANDIDATE-IDENTITY 保留为修正复核前的冻结快照。

当前模拟器及测试探针已清理，字体、方向、夜间模式、动画设置恢复。此前已退出的本地原型服务恢复至原地址 127.0.0.1:57599，供用户继续查看。未操作实体手机／相机，也未上传发布。具体实现、验证边界、设计系统和清理回执见本目录其他记录。
