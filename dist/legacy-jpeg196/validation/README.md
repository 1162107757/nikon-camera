# 旧版 196 状态恢复验收

最终交付 APK SHA-256：`95d84e38b098a0f948394bede12f16f4d209e6f3e30106946361a0c59babc612`。设备安装包的完整字节摘要与交付文件一致。包名 `cc.huevia`，版本 196，原证书 `04db…ae31`，四 ABI、16 个原生库与 195 字节相同。覆盖安装保留测试标记、原预设及已保存 JPEG。

独立 Instrumentation APK：`332d4aad07e7e274b5c4dfc265911ddaa0447be4d01dda6019ab560eb32d89ac`。同一测试程序加载已安装生产 APK 的真实 MainActivity、AlbumPanel、AlbumController 和 PtpIpClient；读取本地只读 TCP 夹具，未打包替代生产类或伪造 Controller 索引。

| 生产包与用例 | 结果 |
| --- | --- |
| 195，第二 Panel 接管并关闭监听器，原 Panel 快照为空，Controller 索引已就绪 | `STALE_PANEL_NOT_RECONCILED_resume`，303 个真实夹具索引、页面未连接、分页关闭，没有元数据请求 |
| 最终 196，相同陈旧状态后返回前台 | 页面快照恢复，扫描 301 个 NEF 后显示两张独立 JPEG，分页 cursor=303 |
| 最终 196，进入照片页面 | 恢复相同两张 JPEG，无需重新连接 |
| 最终 196，点击真实“重试读取照片” | 恢复快照并发起分页 |
| 同一快照重复进入或返回前台 | 保留已有 PhotoItem、已推进的 cursor 和列表，不重复从第一页开始 |
| 下载、导出、恢复任务、closed、本地编辑和 ownedConnecting | 跳过不属于当前页面的恢复；新连接地址、pending 回调及任务所有权保留 |
| 漏掉真实 Controller 断线通知后返回前台 | 清除连接快照、失效远程条目和陈旧忙碌标记，分页退休；已下载文件保留 |

最终 `case=all` 通过 **82 项断言**。`final196-result.json` 包含各阶段的 Controller/Panel 状态和 trace；`baseline195-result.json` 为同一测试 APK 对旧版的预期失败。两份 Instrumentation 结果均验证目标 APK 的明确 SHA 后才运行，且只允许运行于专用模拟器和 `10.0.2.2:15752`。

正常 Huevia 桌面入口也通过实际 UI 操作连接、进入同步页面并显示两张 JPEG 缩略图，见 `196-normal-jpeg-grid.*`。Package Manager 实际查询只返回 MainActivity，不再出现 LegacyExportActivity 桌面入口。最终 APK 实际冷启动正常，无本次启动崩溃记录。

纯 Java 回归另外通过 11 组、1130 项断言，实际编译生成后的 PhotoFormat 和新目录中的库存 helper。JVM runner 仅收集 `tests/cc`，Android Instrumentation 由 `build_probe.py` 独立使用 android.jar 编译，避免两类测试源互相混入。

本次用户诊断和截图只用于定位“共享索引已 ready 但页面未同步”的状态，未复制到此目录。夹具 JPEG、元数据、GUID 和文件名均为自制测试数据。这不是实际 Nikon、真实 NEF 色彩或手机 Wi-Fi 射频验收；用户的 Z 6_2 仍需验证。跨平台新版移植按用户要求延后。
