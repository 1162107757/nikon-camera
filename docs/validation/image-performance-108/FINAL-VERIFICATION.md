# 108 最终包验证

- 应用：`cc.huevia`，108／`0.21.9-beta`。
- APK：`dist/huevia-0.21.9-beta-debug.apk`，3,938,426 字节。
- SHA-256：`995b33c82c9f2b72835ad6a2a194a2db8fae50caebfca860f8af2e8dc3a089f1`。
- 签名：v2／v3 通过，证书 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`。
- 构建及验证后：221 项源码、3 项构建输入无漂移，详见 SOURCE-IDENTITY.json。

## 图片处理

主机渲染逐像素及原有编辑／空间／视口回归见 RENDER-PERFORMANCE.json、viewport-host.log。最终 APK 原生 58 项通过：`995b33c8/e20554a9b79b40a9892784933617fe9d/report.json`。旧版使用同一个反射探针，摘要与新旧观察见 NATIVE-COMPARISON.json。

独立检查最终三张 PNG，另与 107 的拖动后图片对照；未见本轮新增的按钮尺寸、文字基线、内外圆角间距、裁切、选中位置或玻璃残留问题。原有亮背景下“完成”文字对比偏弱记录在 IMPLEMENTATION.md，不属于本轮回归。

## 相册与目录容量

最终同一包相册原生 47 项通过：`docs/validation/album-position-108/995b33c8/20261027-123311-phone-e4db7c/`。3 回合均验证原照片身份和像素偏移；包含编辑期间新增照片／刷新和来源切换。定向组件测试包的成绩不代替此最终包报告。

OnlinePresetRepository 与容量任务交接源码摘要一致；其主机／服务验证和线上导入、发布属于协作任务职责，见 INTEGRATION.md。此文档不把待发布状态当成发布成功。

## 范围与收尾

这是普通字体、单个 Android 模拟器配置的原生运行；图片夹具明确为生成的 12MP／24MP JPEG。未连接实体手机，不认证手机帧率、峰值内存、相机传输、相机待机断连和真实导出总耗时。局部蒙版、降噪、导出成品预览仍未实现。

5586 和本轮启动 PID 16640 已退出；两个测试包卸载、照片夹具清理、字体／飞行模式设置恢复，见 CLEANUP.json。已有宿主 AVD／临时文件目录保留，没有重试历史上被拒绝的递归删除。

NikonPC 协作聊天（01a15ceb-c0f6-7990-b475-87e67a89b6ae）已于 2026-10-27 统一发布 beta 强制更新，release ID 为 5e6fe107-06f3-4eed-a4cc-36ab4cf6cdfc。107 查询需要更新，108 自身不重复提示。主任务另行读取公开 APK，确认 3,938,426 字节及 SHA 与最终受测制品一致；回执及独立下载核对见 PUBLICATION.json。新增 149 款 NikonPC 预设已分类上架，公开目录共 390 款，旧 241 款保留。
