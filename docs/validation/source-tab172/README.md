# 172：来源切页截图失败保护

用户报告鸿蒙4.3.0.208点击顶部“在线预设”闪退，未提供实体设备或原始崩溃栈。没有把该系统版本等同于某个Android API。

查到共享 `SubcategorySwipeLayout` 在切换前对旧页面做软件Canvas截图，原来只处理内存不足。实际 `Bitmap.Config.HARDWARE` 放入页面后，会产生 `IllegalArgumentException: Software rendering doesn't support hardware bitmaps`，中断真正的来源变更。受控模拟器对照在171包上复现了共享组件和实际MainActivity顶部按钮路径；23项基线检查确认旧页仍未切换。该夹具证明存在这一缺陷，不证明就是用户那次鸿蒙崩溃的唯一原因。

172仅保护可选截图：捕获RuntimeException及原有OutOfMemoryError、释放临时图、记录日志并继续页面变更；正常可截图页面保留既有动画。没有针对品牌跳过校验，没有吞掉真正页面变更自身的异常。图片处理、原照片和预设数据未修改。

最终原生报告、精确包身份与配置恢复见 `summary.json`。验证使用真实硬件位图，以及明确注入的仅软件Canvas异常／OOM夹具；普通软件位图是动画保留对照。缺少实体鸿蒙设备与原始崩溃栈，仍需用户用修复包复测；未公开发布。
