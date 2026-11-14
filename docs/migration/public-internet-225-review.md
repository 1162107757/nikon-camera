# 225 公网服务与相机 Wi-Fi 路由核对

用户报告 QQ 登录“账号服务返回异常”、检查更新“无法检查更新”，并补充“可能是相机的 wifi”，同时要求不能因此断开相机。相机 Wi-Fi 没有公网是当前较可能的触发条件，**没有用户手机的现场响应，不能认定为已确认根因**。

## 只读线上证据

2026-11-14 从开发机以原生路径、无账户或管理员凭据查询现用 HTTPS 服务：

- `/preset-library/health`：200，JSON，`ok=true`、`configured=true`。
- `/preset-library/releases/latest`，真实包名 `cc.huevia.next`、224、stable/beta：均 200、合法 JSON，`release=null`、`reason=no_release`。新包尚未公开发布，此响应应显示此通道暂未发布版本。
- `/preset-library/auth/qq` 的 GET：404、合法 JSON `NOT_FOUND`，符合该端点只接受 POST 的合同。没有冒用 QQ 凭据，也没有通过此次排查创建账户或会话。
- `/preset-library/catalog.json`：200，391 项；当前样片 URL 均为空，现用样片主要走本地配方生成。

这些证据排除了查询时整个域名不可用，但不能证明用户手机网络或真实 QQ 授权交换成功。

## 实现范围

Android next 的 `PublicInternetConnections` 优先使用已验证可上网的默认网络，再查现有已验证蜂窝或其他可用网络。必要时仅为该 HTTPS 连接申请最长 5 秒的蜂窝网络租约；请求失败或 HTTP 关闭时，仅注销该次请求自己的 callback。

使用 `Network.openConnection(URL)` 选择每条连接的 DNS/TCP 路由。没有切换、断开或重连 Wi-Fi，没有进程网络绑定，没有改动 `CameraWifiNetwork`、PTP socket 或相机保活租约。保留系统 TLS/主机名验证与原有重定向规则。

纯 Java 公共 HTTPS opener 由 Android next 适配层挂接；账户、社区、在线目录、预设文件和原生样片缓存均复用它。旧版及 Apple 默认 opener 仍使用原系统 HTTPS 实现。QQ/注册/刷新/退出和只读在线加载分别进入专用 I/O 队列，不占用相机串行命令队列，也不在等待网络期间持有 SharedRuntime 全局锁。库写入、相机命令和 owner guard 保留原顺序。

在线样片经原生图片校验与缓存返回本地文件，Flutter 以 `Image.file(gaplessPlayback:true)` 展示。内存 future 按目录、owner、账号图片 generation 和 URL 区分，最多 96 项并共享正在进行的请求；原生回包前后验证 owner/账号 generation。路径与 URL query 不写入诊断日志。

账户 HTTP 的 401/403/429/5xx 失败即使网关返回 HTML，也保留真实状态分类。畸形成功会话仍严格拒绝。诊断仅记录受控 stage、HTTP 状态、错误类别；不记录令牌、密码、用户资料、响应内容或 URL。

iOS 的 HueviaCorePlugin 原先也只有一条串行队列。现按同一 SharedRuntime 明确白名单，把账号与只读公网请求分别交给 2/3 并发 I/O 队列并调用 requestPublic；相机与其余操作仍走原串行队列。公网任务不消耗相机任务的 9 个槽位，取消只使用 readonly HueviaTask 的 cancelIfActive/finish，公网取消不调用相机取消。迟到的已取消公网结果不会交付。

iOS 更新使用 Dart HttpClient，未发现显式禁止蜂窝的 URLSession 配置；没有增加自定义 TLS 或强迫离开相机 Wi-Fi。无网络/超时给出可同时开启移动数据的提示。

## 注册表单、会话安装与简单密码

用户另报注册后输入清空、仍未登录。现行注册表单只在更换验证码时清空验证码，不主动清空用户名和密码；但 UI 会话刷新缺少 revision 防护，迟到的匿名 account.current 能覆盖刚安装成功的会话，失败登录也会额外刷新会话。现为会话/库快照增加请求与账号 revision 检查，并移除失败登录的隐式刷新；过期验证码在等待新图片前立即显示原错误及账号密码已保留，空成功响应仍拒绝，退出页面后的成功响应不安装会话。

密码现行前端、Java 与服务端合同本来就是单纯 8–128 长度，无大小写、数字、符号混合要求，服务端使用 scrypt，不是 bcrypt。保持现有上下限，UI 明确可只用数字或字母；密码原样传送及哈希，不 trim。此次没有改变 Java/服务端密码规则，也不需要密码规则部署。

## 回归与限制

- `tests/run-public-internet-host.ps1`：离线 Android 网络对象配合真实 loopback socket；蜂窝回调等待、HTTP 连接和租约释放期间持续相机心跳，并核对仅释放自己 callback、无移动数据错误、网关错误分类和公共客户端路由共用。
- `PublicInternetBoundaryTest`：延迟 QQ 网络时，runtime owner guard/本地库读取仍可执行；并行退出使迟到登录失效并撤回新会话；旧 owner 与错误队列操作仍拒绝。
- `public_internet_queue_apple.m`：Foundation 级生产 I/O 队列 fixture，在两类请求均阻塞时验证原串行相机心跳及 2/3 并发界限。Python 架构检查和 readonly-task 检查已通过，Apple fixture 执行以根任务收据为准。
- `registration_submit_test.dart`：受控注册成功、失败、空响应、过期验证码慢刷新、离页/旧页迟到响应、失败登录表单保留，以及迟到会话/库快照的账号隔离；Flutter 执行以根任务收据为准。
- 本地 `user-password-policy.test.mjs` 已通过：纯数字、纯字母、原样空格、短/超长边界，无服务请求或真实账户创建。
- 全部测试执行状态以根任务新一轮 225 收据为准。离线回归与模拟器不能替代物理相机、真实蜂窝网络和真实 QQ 授权验证，不能据此声称硬件不掉线已实测。

此次工作没有部署服务、更新公开清单、发布商店或分发安装包。
