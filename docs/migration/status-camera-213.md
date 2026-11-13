# 213 当前相机组状态

对应 212 后仍列为开发缺口的 11 类工作，本组负责 A3 / A5 / A10，并补 A6 的共享队列、相机身份和收据边界。本次文档复核基线为 `8d43086119fc88eb97e8157be44d76b6ac917c26`；下列验证各自绑定实际源码和产物，不将该提交自动视为所有安装包的来源。212 冻结包和历史清单保持原样。

| 清单项 | 本轮实际开发状态 | 明确保留的限制 |
| --- | --- | --- |
| A2：后台保护与恢复（主任务集成、本组复核） | Android connected-device 前台服务、通知停止、同一 Flutter engine / 原生任务接管；服务代次、同 engine 校验和旧 Activity 所有权保护已修复。独立 `stopRevision` 使前台 Live / Queue 也真正停止。iOS 接入有限后台收尾、到期取消与前台继续。 | Android 生命周期检查在 API 31、x86_64、4 KiB 模拟器通过；没有实体相机、厂商电池策略、16 KiB 设备或实体 iPhone 证据。iOS 到期回调的关闭路径经源码复核不等待网络 / USB 回调，尚不能算实机期限、锁屏或系统终止验收。 |
| A3：遥控拍摄、实时取景、对焦与参数 | 新增实际 Nikon Wi-Fi 遥控页和原协议授权，取景帧、暂停/继续、AF/可信坐标点按 AF、单次快门、拍摄库存核对、返回相册资源释放；拍摄意图先持久保存，未知响应不重拍。应用退后台停止轮询。 | 机身参数沿用原版和既有授权的只读范围；未虚构 USB / Fuji 遥控或新增参数写入。实体画面、点焦、模式限制与断线恢复待验。 |
| A5：Wi-Fi / USB 优化校准槽位 | 实际 C1–C9 页、NCP 原转换器、适配说明与参数、复制、覆盖和删除。写前完整能力/来源/目标核对，单次预算，写后全槽回读；活动槽拒删；响应丢失保持待核对。Android 原始 bulk PTP、Apple ImageCaptureCore outData 已接入。 | Android SDK 编译和受控协议边界已通过；本专项尚未取得 213 Apple SDK / IPA 通过证据。不同机型的写入/删除、占用、拒绝、拔插及物理回读待验；不能用协议测试或模拟器代替实体结果。 |
| A6：相机批选与持久队列 | 主任务已接最多 100 张、应用 / 系统 / 文件夹目标、明确继续和逐项状态。本组提供标准序列号或 GUID 的独立下载身份、完整描述符、每次 128 个对象的只读恢复；下载前核对队列，原文件原子保存后先持久 native 收据；已完成项不倒退，收据绑定账号/操作/源 SHA/字节/目标；损坏日志隔离。保留 A1 原 GUID 信任规则。 | 53 项共享边界及 Queue / Protection 调度测试通过，不能当作相机到 SAF / PhotoKit 的平台全链路通过。进程被系统终止、长时间后台、真实传输/发布中断、空间不足与授权变更仍待平台实测。未做缺少活动租约证明的孤儿相机临时文件删除。 |
| A7：相邻查看与本地 RAW 缩略图（主任务 / 编辑组集成） | 相邻导航、分页去重、仅缩略图预取、当前照片接收与旧会话回调隔离已接入；本地 RAW 使用嵌入 JPEG 或中性半尺寸解码和独立缓存。 | Viewer 6 项控件检查通过；119 项原生检查含 RAW / 几何 / 原文件保护，41 项实际 R8 检查含新鲜 RAW JNI 缩略图。它们分别验证 UI 调度和 Android 夹具，不是实体相机缩略图、全部 NEF 型号或 iPhone 解码验收。 |
| A10：原始 NEF 保存目标与配对 | 相机 JPEG 入口只读核对全卡库存，复用原保守匹配规则；歧义须明确选择，确认后接收实际 NEF。JPEG / NEF 原字节可保留应用、发布系统相册、选择持久 SAF / Files 文件夹；保存后实际 SHA/长度读回，重试复用操作收据。只有完整相机来源证据唯一匹配才持久关联已有应用 JPEG。 | 共同目标发布明确覆盖 JPEG / NEF；其他 RAW 格式仍走原文件分享，未标记全面格式兼容。Apple RAW 类型与实际 PhotoKit 资源、iCloud / 第三方 Files、真实 Nikon 双卡和未知 NEF 仍待验。 |

本组独立通过 76 项遥控/槽位、28 项 RAW、21 项相机描述符恢复、53 项持久队列检查及原有 28 项 JPEG 发布回归；15 项 Flutter 专项通过，相关 Dart 分析零问题。Android 原始 PTP / Files / NEF 适配已对实际 Android SDK 36 和 Flutter jar 编译通过。主任务随后完成 Android 构建、安装和下列独立验证：

| 平台证据 | 已核对的范围 | 不能据此推导 |
| --- | --- | --- |
| [119 项 Android 原生检查](validation/features-213/android/native-119.json)与[日志](validation/features-213/android/android-native.log) | API 31 / x86_64 / 4096 字节页模拟器；含真实服务启动、快速停止再启动、关闭 / 重开 Activity、旧宿主迟到释放和通知停止。记录的四个源码 SHA 与本次复核基线一致。 | 整条 Flutter 相机接收流水线、真实 Wi-Fi / USB 相机或实体设备已通过。 |
| [41 项 R8 release 检查](validation/features-213/android/release-runtime.json)与[日志](validation/features-213/android/release-runtime.log) | 来源 `3db73d2575fc93296e0995c5476c237397c2a1a7` 的真实 x64 优化 APK，API 31 模拟器；真实模型 / 渲染 / 修补 / 取消，以及新鲜 RAW JNI 缩略图与原文件保护。 | 41 项全部属于相机检查，或其他 ABI / 新提交 / 实体设备均已运行通过。 |
| [Android 签名与对齐检查](validation/features-213/android-signing-alignment.json) | 对已记录 arm64 / x64 APK 的签名、ZIP 16 KiB 对齐和 ELF LOAD 对齐作静态核验。 | 已在 16 KiB 页大小设备上启动、执行 JNI 或接机传输。 |

开发证据：[遥控与槽位、后台复核及查看器边界](validation/camera-controls-213/README.md)、[RAW、保存目标、来源关联与队列](validation/raw-original-targets-213/README.md)、[编辑组的 Viewer / Queue / Protection 专项](status-editing-lifecycle-213.md)。213 Apple SDK / IPA 结论以主任务后续同源码记录为准，不沿用 212 的通过结果；本表不宣称整体迁移或端到端实机验收完成。
