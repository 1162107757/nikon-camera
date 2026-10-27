# 108 源码独立复核

2026-10-27。由未编写细节组件及 decode 补丁的 image_perf_render_108 代理只读复核，结论 scope clear。此记录不代表原生视觉、实机性能或全 App 验收。

检查范围：PhotoDetailView、PhotoDetailDialog、PhotoGlassDrawable，以及 PhotoFilterEditor.decode。

- requestSerial 隔离换模式、暂停及关闭后的回调；视口 revision 允许同模式中间帧显示，最新覆盖未完成时保留 loading，防止错误认证完整像素。
- PhotoDetailSource 缓存淘汰不 recycle 正被 Frame 引用的 tile，视图继续持有旧帧时引用有效。
- 毛玻璃仅在采样成功后交换双缓冲；尺寸变化回收备用图，清透明和 Canvas save/restore、detach 防止残影和累积变换。
- decode 只释放当前仍自持或已被替代的中间图，相同实例与异常路径处理正确。

107 原生基线已通过 54 项检查：持续 90 次 MOVE、松手前新瓦片 0 次，五个按钮的背景全部被重建；解码与真实显示像素对照误差为 0。108 原生结果另记，不以源码复核代替执行。
