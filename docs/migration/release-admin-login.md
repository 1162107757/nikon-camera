# 发布管理员交互登录

现存 CLI 管理员会话只读检查为无效；项目中旧 initial-admin 凭据也不匹配当前生产密码，没有尝试这个旧密码。后台真实登录入口为 [Huevia 管理后台](https://nikon-d8girdjsr252fd90e-1252602548.ap-shanghai.app.tcloudbase.com/preset-library/admin/)。当前 Web 管理页面只有原 `/api/releases` APK 流程，不能上传 next Android 或未签名 IPA。

新增的 `online-library/scripts/login-release-admin.mjs` 使用同一后台的正常 `/api/login` 创建本 CLI 自己的管理员会话。它不提取浏览器的 HttpOnly cookie，不伪造数据库会话，不要求用户把密码发送到聊天，也不使用服务密钥代替管理员认证。

在用户可见的本机交互终端运行：

```powershell
Set-Location 'D:\dev\ai-project\nikon-camera\online-library'
node scripts/login-release-admin.mjs --login
```

用户本人输入当前管理员用户名与密码，两者均不回显；DEL（0x7f）和 BS（0x08）退格编辑可用，Ctrl+C 取消。输入使用公开 keypress 事件自行编辑，不依赖 Node readline Interface 的 TERM=dumb 分支，终止后恢复原终端模式。CLI 不接受用户名/密码参数、管道输入、环境变量凭据、目标 origin/path 参数，不读取旧 initial-admin 文件。密码只用于这一次固定 HTTPS 登录请求，不持久保存。

固定目标仅为真实生产 `/preset-library/api/login`，禁止重定向。收到合法的 Secure/HttpOnly/Path=/、SameSite=Strict 的 `__Host-nikon_session` 与 CSRF 后，继续 GET `/api/session` 核对同一账号和 CSRF，再 GET `/api/releases` 证明管理员访问有效。所有步骤成功后，仅把 cookie 与 csrfToken 原子保存到本仓库已忽略的 `online-library/.local/community-admin-session.json`；失败、字段异常、拒绝或取消均保留旧本地会话。错误只含固定通用代码，不输出身份、密码、Cookie、CSRF 或完整 HTTP 响应。

正常登录会在服务端建立管理员会话，这是已获授权的必要登录准备；该操作不修改密码、创建账号、部署函数、上传草稿或发布版本。会话准备与生产部署/公开发布审批分开。会话可能过期，应在实际执行前再只读确认。

模拟检查覆盖成功与原子保存、401拒绝、提交前/提交后取消、错误 CSRF/cookie/session/admin 字段、额外参数/字段拒绝、非交互输入拒绝、终端不回显/取消后模式恢复，以及完整两次输入至会话保存，共 10 项通过。在实际 Node v20.20.2 下显式设置 TERM=dumb 和 xterm-256color，各验证 DEL/BS；保留原 DEL 断言，修复前 dumb 失败、修复后两环境均通过。相同 `--experimental-vm-modules --test --test-concurrency=1` 的完整服务回归为 235 项，228 通过、7 跳过、0 失败，日志 `.tooling/agent-account/server-final-term-dumb.log`。

本代理没有实际登录或替用户输入密码。已经启动的旧 Node 登录进程不会热更新修复，必须由主任务取消并重新启动后使用，本代理没有操作该终端。审阅包中的 `tools/login-release-admin.mjs` 是源代码辅助材料，不能直接在 tools 副本登录；脚本强制从仓库 `online-library/scripts` 入口启动，确保使用原 `.local` 位置。

会话成功保存后，既有 `prepare-mobile-release.mjs` 可使用该会话执行已批准的私有 draft / 精确 SHA 确认发布；当前仅准备登录，不调用其上传或发布标志。
