# 99 · 自动提示与强制更新完成复核

2026-10-25。结论：**本地实现及本轮专项验证通过，可交付安装包；后台尚未上线。** 未对任何线上版本启用强制更新。

## 产物

99／`0.21.0-beta`，3,901,562字节，SHA-256 `cc3a7cfcdb04dc54054ec7446cc3d5f8d2cbe0f495c6c8367e7d2a89d8fabb7f`。构建及v2／v3签名通过；[214项原生输入、4项后台输入](FINAL-IDENTITY.json)固定。相对98仅gradle、MainActivity、UpdatePanel、AppUpdateManager及UpdatePolicy五个原生输入变化，98诊断、94照片修复和既有安装包保持。

[最终核对](FINAL-VERIFICATION.json)确认生产输入零漂移、dist与不可变候选一致、94–98安装包原SHA保持，结果为LOCAL_PASS；部署完成标志为false，与线上状态分开。

## 已完成

- 前台自动检查，普通新版本弹窗、8小时去重，测试／正式默认通道跟随当前安装包且不覆盖手选偏好。
- 按版本配置强制，客户端不可跳过；服务端可解除／撤回，已装版本达到目标后自动解除。下载／校验中仍能重查，制品身份变化不能安装旧APK。
- 沿用下载、完整SHA／签名／包名／版本／SDK验证、未知来源授权、安装前任务与相机断开确认；安装仍需用户通过Android系统确认。
- 后台管理员策略入口、确认／revision并发控制／审计及迁移014；旧行默认普通。旧客户端忽略新字段，需先升级客户端才有强制能力。

## 证据

| 检查 | 结果与范围 |
| --- | --- |
| 客户端核心 | [CORE-REVIEW](CORE-REVIEW.md)记录最终66项策略、37项真实生产manager的离线host检查及SDK35编译通过。Android／JSONObject为host夹具，不声称真实DownloadManager或系统安装器完成。 |
| 后端 | [13项Node测试](backend-tests.txt)、[隔离PostgreSQL迁移／权限／撤销验收](database.txt)、[64模块语法](syntax.txt)通过。独立只读审查未发现本轮权限、CSRF、revision、撤回优先或兼容阻断。 |
| 最终原生组件 | [最终汇总](cc3a7cfc/COMPONENT-UI-RESULT.json)：普通字号244／实际1.3字号245，共489次含配置重复的检查；10张原生PNG。强制Back／外点／返回、普通去重与忙碌状态、长说明、进度／错误、生命周期、取消强制／撤回及过期按钮均覆盖。 |
| 视觉确认 | 探针代理逐张查看最终10图，root另看最终1.3字号普通／强制两图。圆角、文字、固定动作与滚动内容正常；10次实际decor记录背景颜色#FFFFFFFF／alpha255及clipToOutline=true。截图等待窗体动画500ms后采集，没有禁用动画或调整生产alpha。 |
| 清理 | 最终组件探针Guard任务0，未HTTP、下载、启动安装器或退出应用；偏好恢复、夹具删除、测试包卸载通过。[模拟器记录](EMULATOR-CLEANUP.json)只关闭自有5586／PID18776，serial／PID与该端口自有进程均消失。 |

原生探针替换启动Activity，使用真实生产UpdatePanel、Release构造器及manager读取，注入合法状态且禁止任何后台任务。它证明组件界面与状态，不证明MainActivity完整布局／路由、真实网络、相机、系统授权或安装器集成。截图背景未模拟主Activity的完整insets，不作为主页面布局批准。

## 中间记录与未上线范围

523bd07f的组件检查已通过，root随后补圆角及不透明窗口背景；其[旧身份](523bd07f/APK-IDENTITY.json)与全部记录保留。最初13MB夹具超过既有4MiB安全上限、fullScroll动画未结束的两次探针失败分别保留，未更改生产上限或降低文字／按钮阈值。cc3a7cfc首轮150ms截图有窗体过渡帧，随后仅把采图等待改500ms并增加只读背景观测，使用新probe SHA `8450ab751dce5f6a0e55f0dbc9ad2760f49859f93745c7997e1111340ef5db47`重新执行最终两配置；未混算旧489次。详[全部尝试](cc3a7cfc/COMPONENT-ATTEMPTS.md)。

后台需先应用014迁移，再部署对应服务及管理页，在线开关才生效。本轮未执行远程SQL、部署、上传、上架、启用强制或实体手机操作。部署说明见[APP-UPDATES.md](../../../online-library/APP-UPDATES.md)。

另：早期host测试因Windows只读属性留下两份各24字节假APK，最终host运行本身已修正清理并通过；对旧残留的两次清理被工具自动审批以 `blocked by policy` 拒绝，无进一步原因，未换方法绕过。准确路径、属性及时间见[核心记录](CORE-REVIEW.md)。它们位于系统Temp而非交付包，此清理残留单独列示，不写成全部host临时文件已清空。
