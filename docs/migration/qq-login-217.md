# 217 QQ 登录验证码调整

本轮按用户要求移除 QQ 原生授权前后的应用图片验证码。腾讯 SDK 授权、服务端腾讯凭据校验、用户同意、安装和来源限流仍保留。邮箱注册及账号密码登录的验证码规则不变。用户对窄范围更新回复「都更新吧」后，**QQ 服务补丁已部署并读回核验**；安装包仍仅供本地测试，没有公开发布。

## 实际改动

- `cross-platform/app/lib/qq_authorization.dart` 删除 QQ 页验证码请求、输入和刷新动作。同意后进入原生 QQ SDK，交回凭据完成服务交换；取消、离页或账号变更均拒绝迟到结果。
- `cross-platform/core/java/cc/huevia/shared/SharedQqLoginTransport.java` 只处理 `POST /auth/qq`：剔除旧图片验证码字段，使用持久化的原生安装标识。其他请求原样委托，资料专用 `profileRequest` 也完整委托。
- `SharedRuntime` 的 `account.qq` 使用无图片验证码的原有账号仓储入口，继续校验当前账号归属。
- `online-library/server/app.mjs` 只删除 QQ 首次建号分支的 `qq_register` 图片验证码消费。腾讯令牌验证、AppID/openid 验证、QQ/IP/安装及建号限流、原有会话签发流程均保留。本轮未修改已存在的旧版 APK 100 MiB 容量策略。

生产主函数已只删除首次 QQ 建号的额外图片验证码要求，其他 100 MiB 文件与函数配置不变，见 [实际服务部署记录](qq217-server-review.md)。普通注册仍要求验证码，无效 QQ 令牌仍被拒绝。客户端对旧服务的验证码错误仍保留“QQ 登录服务尚未更新，请稍后重试或使用账号密码登录。”提示，不会重新请求图片验证码或假装成功。

旧 Android 先进行单参数 QQ 凭据交换，仅在收到 `CHALLENGE_REQUIRED` 后进入历史验证码 fallback；迁移版此前则在进页时先要求验证码。本次按新要求彻底去掉 QQ 额外图片验证码，也覆盖首次建号，不表示旧版绝无条件验证。

## 已完成的本地验证

- Java 17 完整核心检查：1417 项共享边界和 6 项氛围回归通过；新增 QQ 32 项、原注册 20 项及资料 43 项均包含在内。收据与 golden 在 [features-217/core](validation/features-217/core/README.md)。
- Node 20.20.2、`TERM=dumb`、串行运行 QQ、社区、用户管理、密码及认证测试：48/48，通过且退出码 0。日志：`.tooling/agent-account/qq217-server-tests.log`。
- QQ Flutter 8 个用例均有实际通过记录，分两次运行完成：首次前 4 项通过后 Windows 测试宿主未完成退出；剩余 4 项定向运行全部通过并退出 0。未将首次整文件运行记为通过。日志：`.tooling/agent-account/qq217-flutter.log`、`qq217-flutter-remaining.log`。
- QQ Dart 源码及测试静态分析无问题；服务入口语法检查通过。

这些结果验证本地逻辑与安全边界，不等于真实腾讯账号实登成功。iOS QQ Universal Link 仍未配置，Android 新包名及签名的腾讯后台登记仍未实测确认；不以本轮回归替代这些外部条件或设备验收。
