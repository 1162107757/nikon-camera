# Huevia 226 本地测试

Android 与 iOS 已接受为本地测试包，产品来源统一为 `ed48347f1b3e6c92492207259cf24d1613ea12e3`。仅交付测试，不发布到商店或更新渠道。

- [Android 手机 ARM64](../../dist/migration226/huevia-0.31.0-dev-226-android-arm64.apk)
- [Android x64 模拟器](../../dist/migration226/huevia-0.31.0-dev-226-android-x64.apk)
- [iOS 未签名 IPA](../../dist/migration226/huevia-0.31.0-dev-226-ios-unsigned.ipa)，安装前自行签名。

实际字节/SHA 见 [清单](../../dist/migration226/ARTIFACTS.json)。正式显示名为 **Huevia**，应用 ID `cc.huevia.next` 不变。

采用用户批准的 [A 方案](../design/live-transfer-review-20261115/approved-a.png)：接收预览框中央的大号开始按钮，JPEG / RAW 原片互斥选择。RAW 指 Nikon NEF；NRW 不在此次支持范围。同一 RAW+JPEG 拍摄只接收所选的一份，原片加入现有项目/应用相册，保留预设处理和持久恢复记录。RAW 缩略预览失败时仍保留原片，不将 NEF 当 JPEG 展示。

接收记录从根导航弹出，覆盖底部四个标签并保留安全区。显式连接入口不再被旧 busy/session/job 状态卡住，成功后返回上一页；预设导入保留复用当前连接的意图。失效传输按旧会话退休，保留原片及收片记录；只有用户明确重连才取消捕获的旧相机 RPC。未切换系统 Wi-Fi、绑定整个进程网络或修改相机专用路由。绑定/跳过下载的迟到回复核对账号、代次与当前队列后才能显示。

建议复测：

- 同步→边拍边传，选择项目，分别选择 JPEG 与 RAW 开始，确认 RAW+JPEG 同拍只接收所选一份，接收中格式锁定。
- 打开接收记录并滚动到末尾，确认无遮挡；点击照片可打开，返回仍留在原记录/同步页。
- 相机持续亮屏且 Wi-Fi 开启，分别在空闲、收图及离开子页后断开再重连。连接页若仍显示旧连接，明确点“重新连接相机”；已有原片和队列应保留。连接成功直接返回。
- 返回桌面再打开，确认原进程/页面状态；切换账号后旧账号的迟到下载回复不得重现。

[完整 Mac full/macOS26 43663233293](https://github.com/1162107757/nikon-camera/actions/runs/43663233293) 成功，独立验包 exit 0：697 Flutter、5 UIKit、1 原生流程，前台快照与公网隔离 schema2/六份精确来源通过。IPA 实为未签名 arm64，正式名 Huevia，模型与 10 图资源完整。

Android 同源新构建通过两 ABI 签名/16KiB 文件布局、10 图字节保留、精确 release R8 123、返回 4+2 与三项实际 GUI；JVM 真实新执行 1859 boundary + 6 atmosphere = 1865，261 编译项/246 去重项精确绑定最终 Git。下载队列整文件 19/0、最终 A 六项 6/0，format/analyze 0。早期 Windows AV 和 Mac 失败 attempt 按原资格保留，不能算通过或与最后全套盲加，见 [原始验证](validation/features-226/README.md)。

iOS QQ HTTPS Universal Link/AASA 尚未配置，使用账号密码。实体 Z6II Wi-Fi/蜂窝回退、USB、原生 QQ、Android 16KiB 真机及自签 iPhone 仍需实测；主机/模拟器结果不替代这些验证。
