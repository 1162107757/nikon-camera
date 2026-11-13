# A13 CAM 只读回退资料

用户已授权协助配置缺失的 CAM 只读能力；这不是数据库、IAM 存储策略、函数部署或公开发布批准。本次只准备候选文件与步骤，由主任务接管浏览器；本代理没有创建策略、绑定策略、创建账号/密钥或扩大任何权限。

## 优先使用已经登录的控制台读取

主任务已接管现有 Chrome 控制台，并直接只读取得两份策略的当前默认 version 1、完整策略 JSON、修改时间，以及两个角色的实际 ARN 和绑定关系。回退捕获已完成，无需给 CLI 委托角色追加长期权限，候选策略没有创建或绑定。

- 控制台：[CAM 策略](https://console.cloud.tencent.com/cam/policy)、[CAM 角色](https://console.cloud.tencent.com/cam/role)。主任务当前接管 tab `2020874512`；本代理先前临时 tab `2020874513` 只观察到登录页，已完成 CUA 总结，没有继续操作。
- 更新存储策略：`293055026` / `HueviaUpdatePackageStorage`，对应函数执行角色 `HueviaUpdatePackageRole`，已知执行角色 ID `4611686018450225576`。
- 备份存储策略：`293266107` / `HueviaDataBackupStorage`，对应函数执行角色 `HueviaDataBackupRole`。既有 `HueviaFunctionLogWrite` 日志策略不在本次修改范围。
- 控制台实际快照已保存到忽略目录 `dist/migration213/deployment-review/production-capture/iam-before.json`，SHA-256 `dceebce9f0b47c95b00623c82870c80208714beca220bb8eaf31b891decce0df`。更新策略 1 个 statement、备份策略 3 个 statements；备份原 GetBucket prefix 条件逐行确认保留。没有把当前仓库中已扩展 mobile 前缀的候选策略当作生产旧策略。

打包脚本期望的 `iam-before.json`：`schema=1`、实际 `capturedAt`，以及 `release` / `backup` 两个对象；每个对象包含真实 `roleArn`、字符串 `policyId`、字符串 `version` 和完整 `document`（含 `statement` 数组）。这些是公开资源标识和权限文档，不包括 Cookie、临时凭据、私钥或函数环境变量。

## 已核实的 CLI 身份

已通过腾讯官方 [STS GetCallerIdentity](https://cloud.tencent.com/document/api/1312/66098) 实际只读核对：当前 `Type=CAMRole`，所属主账号 UIN 为 `1162107757`，当前 CLI 委托角色 ID 为 `4611686018447956277`，ARN 为 `qcs::sts:1162107757:assumed-role/4611686018447956277`。它与两个函数执行角色不同。只读身份线索在忽略的 `production-capture/cli-caller-identity.json`，不含凭据。

当前 CLI 对两个 `GetRole`、两个已知 `GetPolicy` 均返回 `AuthFailure.UnauthorizedOperation`。CLI 的临时委托会话权限可能受上游会话策略限制；不能推断给主账号或某个子账号加策略会自动扩大这个已存在的会话。本次已通过控制台完成回退资料读取，未创建无必要的长期授权。

## 只有确需 CLI 读取时的最小候选

候选 [cam-readonly-policy.json](cam-readonly-policy.json) 可命名 `HueviaA13RollbackReadOnly`；它不含任何写操作或密钥读取权限。实际绑定目标必须在控制台确认是上述当前 CLI 委托身份/受其信任的操作者，不得给 `HueviaUpdatePackageRole` 或 `HueviaDataBackupRole` 两个运行时角色追加 CAM 权限。

- `GetRole` 精确限制两个已知 roleName 与实际 UIN。
- `GetPolicy`、`GetPolicyVersion`、`ListPolicyVersions` 精确限制两个 policy ID，采用官方公布的 `qcs::cam::uin/:policy/{id}` 格式。
- `ListAttachedRolePolicies` 单独一条 `resource=["*"]`。腾讯[接口授权粒度](https://cloud.tencent.com/document/product/598/69872)明确它为操作级，不能用特定 role 资源约束；该条只允许枚举角色的策略绑定元数据。其他四种读取动作均按资源限制，不额外加入 `ListPolicies`、`DescribeRoleList`、`cam:*` 或任何 Create/Attach/Update/Delete。

若主任务决定绑定，先审阅目标与这一个候选 JSON，再由其按已授权范围操作；本代理只准备。配置后用这五种读取动作复核两策略当前默认版本和两个角色绑定关系，保存实际旧策略，再继续最终部署审批；不能把用户授权配置只读能力视为发布批准。若控制台或委托会话要求更广权限，停止扩张并选择控制台直接读取。
