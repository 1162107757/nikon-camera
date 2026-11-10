# RAW 系统文件选择器兼容修复 157

本地修复候选：0.30.3-beta / versionCode 157，尚未发布到官网或更新后台。

用户反馈 RAW 显影打开闪退。连接设备只有 emulator-5588，没有实体手机；156 在正常系统文件选择器下可打开，原有 87 项回归通过，包含真实 Nikon Z6 NEF。因此尚不能认定用户手机的实际根因。

发现并复现的兼容漏洞：RawDevelopActivity 在主线程直接启动系统文件选择器，未捕获 `ActivityNotFoundException` 或 `SecurityException`。系统文件应用缺失、被禁用或拒绝启动时，异常会逃出主线程。通过实际安装 APK 的“选择”按钮注入框架异常，156 在 `missing-open-document-does-not-escape-main-thread` 检查失败。

修复包括：打开文档不受支持时尝试系统内容选择器；两种入口都不可用、系统拒绝启动或 PNG 保存入口不可用时保留页面并提示恢复方法；释放选择中和待保存状态，允许重试；防止重复打开选择器。保留原 RAW 和已显影的预览、参数与结果。

验证：

- 156 正常基线：`../photo-image-suite/raw-development/9223d32f/20261108-112804-8f51b9612c/`，87 项通过。
- 156 故障注入：`../photo-image-suite/raw-development/9223d32f/20261108-113250-ae299b9a3d/`，预期失败，证明异常未处理。
- 157 修复回归：`../photo-image-suite/raw-development/5d6658fb/20261108-113531-5b6ae2b28a/`，128 项通过，包含空白入口、选择器缺失/拒绝/取消/重试、完整尺寸显影、PNG 写出、实际编辑副本交接，以及真实 NEF。夹具与探针清理成功。
- `tests/run-raw-development.ps1`：281 项通过。
- 正常系统路径手工复核：从真实“相册 → 更多 → RAW 显影”进入 DocumentsUI，取消后返回 RAW 页面，保存按钮保持禁用，返回相册正常。没有新的 AndroidRuntime 崩溃记录。
- APK 通过 V2/V3 签名验证，项目签名 SHA-256 为 `04db0f9d3d76c9831a0778cfabc1a0aaab984e05398da16eb644950ccfa0ae31`。

另有一次未执行有效测试的 runner 失败：`../photo-image-suite/raw-development/9223d32f/20261108-113226-04a25005e5/`。原因是可选样本参数为空时 adb shell 参数丢失，已修复 runner 参数构造；该记录不计入产品回归成绩。退役目录默认样本路径也已改为当前项目根目录。

产物 `dist/huevia-0.30.3-beta-debug.apk`：34,581,880 字节，SHA-256 `5d6658fbf916fde9566870ec7f6d83932f05ebff917357c47125d586e1773e1b`。保留四种原有 ABI；156 安装包和线上发布记录未改动。

限制：尚未拿到用户手机型号、系统版本、准确触发步骤或设备崩溃日志。本次证明并修复了系统选择器失败路径，不能据此宣称用户手机上的闪退已确认解决。未覆盖所有 RAW 格式、实体手机性能和厂商文件选择器。后续应按手机端实际日志继续定位。
