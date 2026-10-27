# App 内相册返回位置修复

用户报告：相册滚动到下面，打开照片套滤镜，再返回列表会跳顶。本任务只修改 `LocalAlbumPanel.java`，由协作聊天并入统一108，不自行改版本号、编辑器性能文件或线上发布策略。

修复保存每个来源的可见照片锚点、行号和像素偏移，同时保留已有Parcelable状态。进入照片/版本编辑前、滚动和移除视图时记录实际可见位置；隐藏列表、等待恢复和空列表不覆盖历史位置。缓存视图复用不重新构造全部行。恢复安排在ListView重新挂载后执行，并在实际布局完成前保护锚点，避免原生挂载过程覆盖同步位置。数据发生插入、分组或列重排时优先找到同一照片所在行；缺失时按原行号就近恢复。App内/手机两个来源独立记录，旧请求不覆盖新来源，新来源无历史时从顶部开始。

## 原生验证

同一已发布107 APK与独立的107字节码加本组件补丁作对照。测试使用真实MainActivity、LocalAlbumPanel、PhotoFilterEditor和原生返回路径，90张自有JPEG、真实NCP渲染和草稿保存；没有替代Activity、相机操作或MediaStore写入。

最终组件补丁测试47项通过：连续3次在列表下方选图、套滤镜并返回，检查原照片仍在相同可见行偏移；另检查App/手机来源切换。第3次编辑时新增18张照片并刷新列表，锚点照片从行12变为行19，返回后仍显示该照片且偏移保持−97px。

基线107的前两次简单往返在该合成夹具中保留位置，未必现用户所见的“跳到顶部”；第3次新增/刷新后保留旧行12但丢失原照片锚点。`Baseline`模式的42项PASS仅表示测量流程和基础检查通过，不能当作位置保持通过。报告保留`sameAnchorAndPixelOffset=false`。最终47项则严格断言位置保持。

生产组件SHA `127feb93cc5e9376fec9da91013603d461410e8ac6c913d12d9f1ae2d4f4c6e3`；定向测试APK SHA `3581f527a1e1dde80b775692bf84ee1fac470e8fd88a14125d5bfda04c6ca101`。精确路径与测试输入见[COMPONENT-IDENTITY.json](COMPONENT-IDENTITY.json)。该APK不是统一108发布包，最终包需要协调聊天复验。

最终包最小复验（已安装同一APK，且该模拟器由运行者拥有）：

```powershell
pwsh -NoProfile -File tests/album-position-device-probe/run.ps1 -CandidateApk <最终108绝对APK路径> -Mode phone -Serial emulator-5586
```

runner按实际安装包SHA和versionCode记录身份，支持自有5588或5586。输出每组的报告、前后截图、证据SHA和清理记录。probe SHA `1d13f26083fd597a48550f7c8110eca6c810016451c55bacdee4b6096856e491`。

仅使用自有只读Pixel_9/5588（PID36120），已清除probe、全部自有照片与草稿、恢复字体并停止模拟器；serial和PID确认消失。其他聊天5586及实体设备未操作。没有新增视觉样式或改写根设计文档。
