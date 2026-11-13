# 217 QQ 服务窄范围部署收据

用户授权后已部署 `nikon-preset-library`，只删除首次 QQ 建号的应用图片验证码消费；100 MiB 基线与其余文件、权限和函数配置保留。`huevia-data-backup` 只读核对，没有部署。未执行 SQL、IAM、更新分发部署、草稿上传或安装包公开发布。

- [result.json](result.json)：汇总及证据文件 SHA-256。
- [approved-patch.json](approved-patch.json)：批准候选、回退包及唯一修改成员。
- [before-functions.json](before-functions.json)：部署前主 / 备函数的脱敏修改时间、代码摘要和基线一致性。
- [deployment.json](deployment.json)：实际主函数上传、Active 状态、读回与配置保留结果。
- [member-verification.json](member-verification.json)：读回 51 个成员与候选逐字节和 Unix 权限一致。
- [http-verification.json](http-verification.json)：最终 6 个有限探针全部通过；未使用真实 QQ 凭据、未建账号、未取得会话。
- [http-attempts.json](http-attempts.json)：误用后台账号路径的早期探针，失败如实保留，不算 QQ 或普通注册业务通过。
- [rollback.json](rollback.json)：本机保留的回退文件、摘要与使用前提；未执行回退。

正常原生账号路由为 `/preset-library/auth/qq` 和 `/preset-library/auth/register`。普通注册缺验证码返回 `428 CHALLENGE_REQUIRED`；QQ 格式错误返回 `400 qq_invalid_token`；专门生成的无效测试字符串返回 `401 qq_verification_failed`。无效 QQ 凭据不能建立会话，但这些拒绝探针不证明真实设备授权成功。Android 腾讯登记仍未设备核实，iOS Universal Link 未配置。

归档只保留脱敏结果，不包含环境配置、密钥、Cookie、用户令牌、签名下载 URL 或函数代码 ZIP。完整部署与回退说明见 [服务审阅记录](../../../qq217-server-review.md)。
