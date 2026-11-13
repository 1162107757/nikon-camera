# 217 共享核心 JVM 验证

本记录是本地源码验证，不代表腾讯真实账号授权、iOS 设备安装或生产服务已更新。本次 JVM 命令未执行服务部署或安装包发布，216 归档未修改；后续服务状态单独记录在下方链接的 QQ 服务收据中。

在 `D:\dev\ai-project\nikon-camera` 使用 Java 17.0.19 执行：

```powershell
$env:JAVA_HOME = 'D:\dev\Java\jdk-17.0.19'
python cross-platform/tool/core_check.py
```

实际退出码为 0：共享边界 **1417** 项、氛围回归 **6** 项，合计 `golden.json.boundaryChecks = 1423`。其中新增 `QqLoginBoundaryTest.run(temporary)` **32** 项；原注册 **20** 项、资料及资料传输 **43** 项随完整入口通过。相对 216 增加 32 项，渲染指纹与 216 归档一致。

验证输入是 `cf8e62a9737d370b1f4e273b92b2331f6da12f36` 加本轮未提交的 217 QQ 补丁；`source-fingerprints.json` 绑定实际编译输入，`result.json` 记录运行环境、数量和摘要。251 个编译条目对应 238 个不同源文件，来自现有编译脚本的输入清单。

| 文件 | 内容 |
| --- | --- |
| [result.json](result.json) | 运行收据及 SHA-256 |
| [golden.json](golden.json) | 后续跨平台对照的 217 golden |
| [source-fingerprints.json](source-fingerprints.json) | 每个不同编译源文件的 SHA-256 |
| [sources.json](sources.json) | `core_check.py` 实际源文件清单 |
| [compile.log](compile.log) | 完整 Java 编译日志；仅有既有 unchecked 提示 |
| [run.log](run.log) | 完整核心边界和氛围执行日志 |
| [core-check.log](core-check.log) | 命令外层完整输出，PowerShell UTF-16 编码 |

`golden.json` SHA-256：`b5fdcc0ac1b3fb958d98bd9d2c68a4e288c39e36a4b1f4d3b225e5d5436cc923`。

QQ 回归覆盖无图片验证码交换、固定原生安装标识、腾讯校验后的账号会话、账号切换与失败隔离、旧验证码字段剔除和交换临时字节清理。`profileRequest` 的资料版本、安装标识、原始字节和响应完整委托；普通注册请求及验证码合同保留。本记录产生时尚未部署服务；用户随后授权的 QQ 窄范围补丁已另行部署，实际结果见 [QQ 服务收据](../qq-server/README.md)，不以 JVM 回归替代线上或设备验证。
