# 212：置顶、RAW、账号与 USB 照片传输

用户明确本轮验收范围为跨端新版 Android / iOS。原生 Android 193 和既有 iOS 工程保持，原版库存核对仍为 420 文件、8 项已批准旧修复、412 项未改动。

## 行为

- 我的预设长按菜单及详情页提供置顶／取消置顶；允许多个，最近置顶的排前，未置顶的保留原排序。置顶记录按本机账号／游客隔离、原子保存，筛选沿用此顺序。置顶偏好读取失败不阻塞预设库。
- 注册和密码登录在取得有效会话后立即更新应用账号状态。刷新预设库失败不会把成功认证显示成失败。验证码错误／过期通过两端桥保留服务错误码，换图后明确说明原因，保留用户名和密码、清空旧验证码答案，并将错误移到可见范围。
- 两端共享 `HueviaRawSafety.h`。LibRaw 0.22.3 H2 在灰色饱和像素上可能计算零色度能量之比 `0/0`，随后转整数导致黑点。迁移专用子类回调保留零色度极限，并限制输出范围；关闭自动白点调整，用户 EV 只在输出变换应用一次。缓存身份更新，重新打开原 RAW 不复用旧显影结果。原版 LibRaw 库和 JNI 源未改。
- 设置中的 USB 数据线连接可发现和选择尼康 PTP/MTP 相机。Android 使用系统 USB 权限及 MTP 读取，iOS 使用 ImageCaptureCore 发现、授权、会话和分块读取。JPEG／NEF 复用共享目录、缩略图、原文件长度／描述／格式／摘要校验和本地入库。取消或中断清理未完成文件，不写入或删除相机卡。当前 USB 入口用于手动接收照片；边拍边传沿用既有 Wi-Fi 流程。

## 协调

211 的边拍边传任务先冻结 `db8e2ef3766a228bd2dd93f6e1e139b697d3ff18`。212 使用独立索引和 `codex/features212` 候选准备，保留 211 的连接状态、重连和卡片修复，不切共享 HEAD 或占用其构建输出。待 211 明确释放后再合入和构建。

## 验证范围

- 隔离 JVM 回归通过：921 项共享边界（其中包含新增注册桥 20 项、置顶 15 项、有线流程 14 项），以及既有图像、JPEG 色彩、高光、相机下载和边拍边传回归。协议夹具属于共享边界验证。
- Windows 单文件 UI：账号场景 4 项、有线入口 2 项、预设置顶 1 项、既有账号资料 6 项通过。Windows Flutter 宿主发生过无断言堆栈的未完成退出；这些尝试保留，不计为通过，采用明确 exit 0 的单文件结果。
- 212 Dart 静态分析、Android USB SDK 编译、隔离 RAW JNI 编译及两端权限配置解析通过。
- 已安装 Android debug 包通过 101 项原生媒体检查，包含 -2/-1/0/+1/+2/+3/+5 EV 阶梯、白色高光及原件保护；独立的未修改 LibRaw 反例输出饱和灰色为 `0/0/0`，共享安全回调保留 4096 级灰阶，12,389 项原生采样／EV 参数检查通过。
- 既有 Z6 与 Z6II 两份 NEF 在原生中性流程的 0/+1/+3 EV 下均完成全分辨率解码，尺寸保持 6064×4040，平均亮度递增；原始文件摘要保持。此项是 LibRaw 中性流程验证，不包含 JPEG 色彩拟合或用户原片。
- Android ARM64 / x64 release 已完成签名、16 KiB ELF/ZIP 对齐和 R8 后 RAW JNI 映射核验；x64 release 已安装并通过 USB 空设备状态实际系统桥验证。模拟器运行页大小为 4096，未声称真实 16 KiB 设备验证。
- Apple 实际编译及未签名 IPA 仍在远端验证，待结果补齐。

## 尚需实体设备确认

目前没有连接可用于本任务的实体 USB 相机／iPhone。模拟器、协议夹具和编译结果不代表实体相机吞吐、USB 转接器供电兼容或特定机型目录行为已通过。现有 RAW 反例也不等价于用户未提供的原片全部问题均已归因。

## 平台依据

系统接口参考 [Android MtpDevice](https://developer.android.com/reference/android/mtp/MtpDevice)、[Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore)、[Apple PTP 查询](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand(_:outdata:completion:)) 和 [LibRaw 参数](https://www.libraw.org/docs/API-datastruct.html)。

## 当前 Android 安装包

[ARM64 手机包](../../../../dist/migration212/huevia-0.31.0-dev-212-android-arm64.apk)与 [x64 测试包](../../../../dist/migration212/huevia-0.31.0-dev-212-android-x64.apk)的完整摘要、字节数和源码匹配清单见 [android-artifacts.json](android-artifacts.json)。未发布公开更新通道。
