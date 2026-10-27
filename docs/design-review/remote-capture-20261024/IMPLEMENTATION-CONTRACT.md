# 遥控拍摄 · 原型实施约定

用户于 2026-10-24 明确要求「严格按照原型执行实现，你和另一个任务沟通解决」。该授权接受本目录原型作为本次原生实现的视觉与交互依据；既有内部设计审核记录保留为历史。

## 本轮范围

- 同步页相机入口；专用深色遥控拍摄工作区，小机型与小图标。
- 完整实时取景、机身只读当前参数、点按／按钮对焦、单次遥控快门、最近拍摄与可选 JPEG 传入 App。
- 同一当前预览帧产生的亮度／RGB 直方图；小图拖动、收起和放大；过期／关闭／断线时明确暂停。
- 横屏右侧 217dp 控制区；系统字号、安全区、系统返回与弹层。
- 快门持久化核对记录、未知结果阻止重发、重连与手动核对。

代码接入必须由相机实际广告能力开启。Wi-Fi 已连不等于开放取景、对焦或快门；不使用照片 EXIF 填充当前参数。参数设置、视频、B 门、连拍和定时器不在原型范围。

## 并行协作

与「按参考风格设计 App」任务直接协调。其 94 / 0.19.3-beta 照片载入优化保留；其完成候选确认并释放生产文件前，本任务只在 `.tooling/remote-capture-95/src` 准备代码与新测试，不修改 `app/src/main`、版本或运行全量构建。释放后本任务接 95，避开其 5586 模拟器及实体手机，不发布远程更新。

## 协议事实与证据边界

协议码、属性单位与目标参数参考上游 [libgphoto2 PTP 头文件](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/ptp.h)、[Nikon 操作路径](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/library.c) 和 [digiCamControl Nikon 设备实现](https://github.com/dukus/digiCamControl/blob/master/CameraControl.Devices/Nikon/NikonBase.cs)。本轮独立编写 Java 实现，不复制这些项目的实现代码。

主机合成数据与 Android 测试相机夹具验证代码、状态和原生布局，不能替代 Nikon Z6II 固件真机联调。最终交付须标明实际验证环境和未验证项。
