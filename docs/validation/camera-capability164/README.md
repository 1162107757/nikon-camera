# 尼康机型误拦修复 · 164

用户实际相机为 Z7II（设备型号 Z7_2）。旧 PictureControlReadSession、PictureControlImportSession、NcpTransferSession 将型号归一化后只接受 Z6II/Z62；无线与 USB 共用前两者，因此在 CameraModelCheck 阶段错误拒绝 Z7II。普通 USB 设置还复用了完整预设扫描，此入口的拆分由同版本连接修复处理。

三个协议 session 现在按设备声明的尼康身份、必需操作与真实数据检查，不按机型字符串建立准入名单。原有 capability/data 解析、转换参数边界、来源槽验证、目标槽复查、显式覆盖确认、单次写入与精确读回、协议失步停止和资源清理保持。非尼康身份在专用命令或文件写入前拒绝，并显示实际制造商和型号。尚未支持的数据格式继续报告具体失败，不能以识别到型号宣称完整支持。

脚本化 USB/PTP-IP 响应覆盖 Z 7_2、Z7II、NIKON Z 7II 等型号，含能力缺失、数据损坏、槽位竞态、协议中断、失败写入及读回差异。13,316 项专用 host 检查通过，详见 protocol-summary.json 和 protocol-tests.txt；这属于生产代码在模拟传输中的验证，没有连接实体 Z7II，不等于实机导入成功。

原厂 [Z7II/Z6II 管理优化校准说明](https://onlinemanual.nikonimglib.com/z7II_z6II/en/09_menu_guide_03_13.html)确认两机型提供自定义优化校准管理；[Picture Control Utility 2 格式说明](https://nikonimglib.com/npcu/onlinehelp/en/pc007500.html)描述 NCP/NP2/NP3 文件类型。它们不能单独证明手机 PTP 直写成功。上游 [libgphoto2 PTP 操作定义](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/ptp.h)记录 Nikon GetPictCtrlData/SetPictCtrlData/GetPicCtrlCapability 命令，实际运行仍须通过 App 现有操作声明和数据验证。
