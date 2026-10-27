# 96 遥控识别、图标及保存设置

本轮延续用户的三个请求，版本 96 / 0.20.1-beta，候选身份见 CANDIDATE-IDENTITY.json，交付身份以最终 FINAL-IDENTITY.json 为准。

## 遥控识别

用户截图的具体错误来自 PtpIpClient.openRemoteOperations 的身份门槛，而非一次快门或取景传输失败。旧实现仅接受 vendorExtensionId=10；NikonRemoteCamera 又重复相同限制。

新增的两个回归用例先在旧生产代码上重现了相同拒绝，原始结果保留在 core-before-fix.txt / transport-before-fix.txt。修正后两处共同调用 PtpDeviceInfo.isNikonCamera：要求 NIKON 制造商的完整名称边界，并允许已知 Nikon、Microsoft、MTP 扩展标识（10、6、0xffffffff）。不改写原始设备字段，不仅凭型号或用户所选协议获得权限。其它制造商、名称中偶然含 Nikon 的公司及未知扩展标识继续拒绝。

操作能力仍逐项由相机广告决定；通用相册接口不能读取实时帧、发送快门或写参数，遥控授权可撤销，拒绝后物理相册连接保持。新增纯 Java 回归覆盖身份兼容、制造商边界、未广告快门拦截及撤销权限。44 项遥控核心和 5035 项 PTP/IP 检查通过。上游身份处理依据见 BRIEF.md；这不能证明用户实际 DeviceInfo 的字段值。

## 四方块图标

保留 PhotoFilterEditor 的 19dp AppIcon.GRID、原背景和 48dp 触点；移除空文字按钮左侧 compound drawable 及其定位内边距，把同一矢量图放进 Gravity.CENTER 的背景图层。AppIcon 本身和其它编辑器行为不变。

原生探针在未修改的 95 APK 上重现居中断言失败，记录在 cb4d685b 历史 cohort 和 icon-before-fix.txt。96 用真实生产 PhotoFilterEditor.createDock 的组件测试容器验证：四种界面配置及三种 Nikon 标识运行中，LTR / RTL 白色图标像素边界中心偏移均为 [0,0]。这是一项组件对齐证据，不代表重新测试整个照片编辑流程；截图没有绑定用户照片或在线滤镜。

## 齿轮收纳

用户在前一候选验证后明确要求节省底部空间。当前版本移除底部保存说明／传入开关行，直方图左侧增加小齿轮，去掉右上重复三点。齿轮内的第一项是「照片保存位置：相机存储卡」只读说明，第二项是「拍后传入 App」开关；之后保留实时取景、网格、机身参数和断开连接设置。

保存到相机和可选 JPEG 传入的控制器逻辑保持不变；主界面释放出的高度交还取景区域。探针通过原生点击验证开关打开／关闭、弹层重开保持选择，确认底部不再有保存项，并检查齿轮位于直方图左侧。此项用户指令覆盖旧原型的底部保存行，属于有意变更。

## 证据与范围

最终 cohort 为 2bcb395d，6 次原生运行共 622 次配置检查（四配置 MTP 标识 + 竖屏 Microsoft / Nikon 标识），79 张截图，完整索引为 UI-MATRIX.json。既有确认拍摄、RAW 延迟 JPEG、直方图、AF、断线未知结果、恢复及离线传入限制等原生断言一同通过。每种配置的四次快门命令只到内存夹具，三次模拟曝光与一次明确拒绝，不操作实体设备。

全部生产输入 214 项；相对 95 只改版本、PtpDeviceInfo、PtpIpClient、NikonRemoteCamera、PhotoFilterEditor、RemoteCaptureView 六个文件。未改原图解码、保存和照片加载链；94／95 安装包保留。新安装包通过 v2/v3 签名验证，未含模拟相机类、测试标记或示例取景资源，见 PACKAGE-BOUNDARY.json。

8e61d0e0 为用户新增收纳要求前的通过候选，元数据及安装包已归档，未计入最终布局证据；cb4d685b 是旧 95 的故意失败回归。截图来源扫描 162 份栅格资源（含历史）均有来源信息。

实际 Nikon Z6II 的 DeviceInfo、固件互操作、Wi-Fi 性能和实机恢复尚未验证。测试证据是自有隐藏只读 Pixel_9 模拟器和内存 PTP/IP 字节夹具；不能宣称用户相机已恢复。未操作实体手机／相机，未上传发布。最终独立审核只应按本轮三个请求的实际证据范围给出结论。
