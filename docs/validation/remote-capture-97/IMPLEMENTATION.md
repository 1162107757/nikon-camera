# 97 实现与验证边界

本轮基于已交付 96，生产输入仍为 214 个，修改仅三处，详情和哈希在 FINAL-IDENTITY.json：

- app/build.gradle：97 / 0.20.2-beta。
- RemoteCaptureView：九宫格及直方图工具未选中不再降到 0.55 透明度；完整亮度的白色表示可操作，现有桃色表示选中。同步 selected 状态；Android 30+ 增加网格“已开启／未开启”和直方图“已显示／已收起”的 stateDescription。点击目标、图标绘制、布局和齿轮位置保持，实际不可用控件的禁用样式保持。
- AlbumController：边拍边传预览完成即让原图就绪，事务间按真实就绪状态重新排队；有事件时及时唤醒。保留单线程 PTP、原图顺序和 busy/metadata 退避时间。详见 PERFORMANCE.md。

原生验证使用自有、隐藏、只读 Pixel_9 emulator-5588，不接触实体手机或相机，不发快门。四配置 phone、font1.3、landscape、dark，每次执行同样 45 项工具栏及初始连接夹具检查，共 180 次检查执行，不是 180 个独立场景。每次采集 entry、ready、grid-on、grid-off、histogram-off，共 20 张 PNG。图像区域在切换后保持；直方图恢复到新帧；相机属性和画面都是既有合成夹具。UI-MATRIX.json 包含原生方向、证据路径和截图 SHA，run-identity.json 含配置恢复记录。

97 测试工具只增加 toolbar 定向模式，full 模式保留。PROBE-PROVENANCE.json 记录实际测试 APK、源码和参考图来源哈希；测试工具未打进生产包。没有为透明度赋值写实现镜像单元测试，而是点击生产 View 并检查真实截图。最终界面截图已在本轮一次批量检查中人工查看，未进行第二轮微调。

生产构建成功，APK v2/v3 签名验证通过。控制器完整回归及比较基准通过；本轮未改协议、相机身份识别和存储算法，所以不重复 96 全套协议／快门矩阵，不以旧结果冒充 97 全套实测。编译保留既有注解缺失、过时 API、unchecked 三类警告，无新增编译失败。

AF-S 是单次自动对焦，与快门单张释放是独立概念，本轮未改相机参数映射。用户实机连接、相机写卡时间、真实 Wi-Fi 吞吐及遥控拍后导入速度仍未测量。见 FINISH-REVIEW.md 的实际审核范围；本轮原生跳过 HTML/CSS detector。
