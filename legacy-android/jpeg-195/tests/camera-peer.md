# 195 旧原生 JPEG 受控相机端

依赖 Python 3.11+ 和 Pillow。代码独立于私有 211 夹具；JPEG 像素及小尺寸 TIFF/CFA 字节均由本脚本生成，不含真实相机照片或传感器 RAW。

在项目根目录启动新标签：

```powershell
python legacy-android/jpeg-195/tests/camera_peer.py legacy195-ui1
```

模拟器填写 `10.0.2.2:15752`。主机控制接口为 `http://127.0.0.1:15753`。运行日志、夹具 SHA 清单、ready 和 Ctrl+C 后的 summary 全部写入 `.tooling/legacy-jpeg195/peer/<标签>/`；已有标签拒绝覆盖。

| 场景 | 卡 1 | 卡 2 | 预期 JPEG |
| --- | --- | --- | --- |
| `mixed`（默认） | 返回 `0x2013` | `0x3801` 筛选成功空；全目录返回 301 个 NEF，再返回 JPEG 302、303 | 先跨过 300 元数据扫描上限，再显示 2 张；仍提示部分卡不可读 |
| `empty-partial` | 返回 `0x2013` | 筛选成功空；全目录只有 301 个 NEF | 0 张 JPEG，空态仍应说明部分卡不可读 |
| `all-unavailable` | 返回 `0x2013` | 返回 `0x2013` | 显示存储卡不可读，不把失败当作成功空相册 |
| `healthy` | 可读且为空 | 筛选直接返回 302、303 | 显示 2 张，不需要全目录扫描卡 2；无不可读卡提示 |

JPEG 302 使用标准 `0x3801`，文件名 `QA195_STANDARD.JPG`；303 使用通用 `0x3000`，文件名 `QA195_GENERIC.JPEG`。1–301 均为 `.NEF`，不能混入 JPEG 网格。每个对象有独立 ObjectInfo，支持相机预览及 GetObject。RAW 仅为小尺寸自制 TIFF/CFA，不能用于证明真实 NEF 显影效果或 LibRaw 兼容性。

切换场景后在应用重新连接或刷新目录：

```powershell
Invoke-RestMethod -Method Post -Uri http://127.0.0.1:15753/action -ContentType 'application/json' -Body '{"action":"set","scenario":"empty-partial"}'
Invoke-RestMethod -Uri http://127.0.0.1:15753/status
```

状态保留全程累计及每个场景 epoch 的操作/响应、按卡和格式的目录查询、metadata、普通/大缩略图、原片接收尝试/完成/字节/SHA 计数。只浏览时 GetObject 应为零；显式下载后应与 JPEG SHA 清单一致。场景切换不主动断开已有连接，避免替应用执行连接操作。

协议包含标准命令/事件初始化、设备能力、会话、目录、元数据、心跳、缩略图及原片读取。未提供预设、属性写入、上传或拍摄能力，未知操作返回不支持。此夹具用于复现协议及界面流程，不能代替实体 Z 6_2 的验证结果。
