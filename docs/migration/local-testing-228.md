# Huevia 228 本地测试

Android 和 iOS 均已通过本地测试验证。最终产品源码 `734aa3b0f6687dda815af9e13070f0f3c463873c`，两端使用同一来源。本页保留本地验收记录。后续已按用户要求上传至既有beta公开下载渠道，见 [发布记录](../../dist/migration228/PUBLICATION.json)；主站独立首页的旧版选择器仍待服务器登录后更新。未上架应用商店。

- [Android 手机 ARM64](../../dist/migration228/huevia-0.31.0-dev-228-android-arm64.apk)
- [Android 模拟器 x64](../../dist/migration228/huevia-0.31.0-dev-228-android-x64.apk)
- [iOS 未签名 IPA](../../dist/migration228/huevia-0.31.0-dev-228-ios-unsigned.ipa)，安装时自行签名。

字节数、SHA 和分平台状态见 [ARTIFACTS](../../dist/migration228/ARTIFACTS.json)。227保留为历史测试记录。

本次更正用户实机反馈的两处样式：

1. 三个同步标签整体到下方滚动内容固定留白16dp；照片滚动到顶部经过12dp柔和渐隐，照片不会再贴住标签。渐隐层不拦截点击/滑动，不改变原ScrollController、PageStorageKey或连接状态。
2. 按批准图二使用56dp深色实心圆底与白色下载图标，张数角标保留；明暗主题、加载等待和禁用态都保留圆底，禁用态不触发下载。工具展开时保持原让位逻辑。

保留227的普通停止边拍边传/队列/单张下载先结束当前传输再停止、未连接Live标签与中央开始先连接、顶部不显示接收按钮、相机照片长按原地多选、队列操作间距和标签选中块动画。明确断开/重连仍可精准取消旧请求，原网络路由未改。

实际验证：format/analyze 0；带30张相机照片的真实CameraPage滚动回归及原连接回归整文件7项0；圆底明暗/冲突主题/启用/禁用/按压与原选择下载流程整文件4项0。Android两ABI签名与16KiB布局/各8Native库、10张样图逐字节保留、精确R8123、返回4+2、真实release导航GUI5通过。JVM复用227实际1885+6=1891检查：261编译输入/246去重输入全部未变并绑定228 Git；绑定没有重新执行测试。

[full/macOS26 43696814968](https://github.com/1162107757/nikon-camera/actions/runs/43696814968) 同源完整通过：Flutter 724 项、UIKit 5 项、Native pipeline 1 项；固定前台 fixture/source pins、schema2 公网隔离编译与运行、共享核心 parity、模型和10张样图、arm64未签名IPA均核验。

建议实机检查：滑动相机照片，让照片靠近顶部，确认标签下方始终留白且边缘渐隐；长按照片再点第二张，确认右下圆底、角标计数及真实下载目标选择；加载/传输等待时圆底仍在。JPEG和NEF各做一次边拍边传/队列/单张下载停止，等停止完成后确认连接仍可继续；明确断开后再点Live和开始应可进入连接页。

iOS QQ Universal Link/AASA仍未配置，可使用账号密码。实体Z6II Wi-Fi/蜂窝、USB、原生QQ、16KiB真机和用户自签iPhone仍需复测，主机与模拟器证据不替代实机。
