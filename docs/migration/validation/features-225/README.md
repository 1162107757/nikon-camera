# 225 验证索引（双平台本地候选通过，未发布）

225 范围为清晰画面受控替换、同配方 handoff 与无修改复用；公网选路及独立账号/公共读取队列；online.preview 缓存；注册 session revision、输入保留与 8–128 位密码文案。没有新增相机协议改动。最终来源 `f11c4bff4d566f147094579d9b2d74bb5a4d8e6f` 的 Android 两包及未签名 IPA 已本地验收；[Apple full 43615396238](https://github.com/1162107757/nikon-camera/actions/runs/43615396238)为 661 / 5 / 1，且 IPA 已独立核验。整体及两平台 `acceptedForLocalTesting=true`，`acceptedForDelivery=false`、`published=false`；旧 GUI 不改写执行来源。

| 范围 | 实际证据与限制 |
| --- | --- |
| 上一完整基线 | [224](../features-224/README.md) / `08f414c5…` 三包、619 Flutter / 5 UIKit / native 1 保留原样；不算 225 通过。当前本地接受候选为 225，JSON 旧项名为 previousAcceptedBaseline |
| eab 完整静态分析 | [final-frozen-analyze.log](shared/checks/final-frozen-analyze.log) 两项 Apply/source-plane 完成后完整 analyze 实际 0、2.7s，保留 eab 来源；不是将旧分析改标为 f11，归档未重跑 |
| 高清 controller | `controller35-fixed.log` 实际整文件 35/0；首轮 34 pass / 1 真失败及删除等待竞态修复记录保留 |
| 注册 | `registration-ui.log` 12 项实际通过；integrated analyze 0。最终平台与后端现场仍待本次包 |
| 旧 Color / 工具切换 | Color 8 项独立运行全部 0；工具切换 7 项已有独立通过，另两项 no-op 的 `noop-debug-apply-final.log` / `noop-debug-cancel-final.log` 各实际 +1、退出 0，SHA 见 source.json；原失败保留，不声称整文件 9/0 |
| Sharp UI 历史本地资格 | 主流程与账号项是在 `sharp-ui4.log` 整体失败尝试内通过的两个 case，不声称独立进程0；取消、geometry及两项Apply后续各独立通过。首次source-plane Windows AV保留，仅retry1算通过。本行不回写历史计数，最终新源全套以661收据为准；widget桥接证明不冒充实体设备或native塑形像素 |
| 本地共享归档 | [result.json](shared/result.json) / [逐项矩阵](shared/case-matrix.json)：72 个不同 case 观察到通过，70 来自退出 0 命令、2 来自混合失败 attempt。65 份原件共 1,549,740 字节按 [manifest](shared/byte-manifest.json)逐份核 SHA；新增旧 orphaned 夹具整文件 2/0，format1文件/1changed/exit0，原 raw 来源不重标，未声称完整 Flutter 通过 |
| 公网 host/VPN | `public-internet-host-vpn-quoted.log` 23/0，loopback 相机心跳持续；不代表实体相机或 iPhone 现场通过 |
| 新本地 JVM | [result.json](core/result.json) 新实际执行：261/246 输入、1782+6=1788、编译/执行 0；[copy-manifest.json](core/copy-manifest.json)逐字节核对 8 份执行收据，非 224 复制重命名。[source-binding.json](core/source-binding.json)已逐项匹配最终 `f11c4bff…`，绑定没有重跑测试 |
| 前次 Apple 失败 | [eab full 43611891603](attempts/eab-full-43611891603/result.json) 实际 Flutter659/2、device build0；旧夹具缺预览宽高使真实曲线入口校验失败。27 原件及 ZIP/digest/API/冻结夹具全保；后续本地修复2/0不回写旧 full，也不继承旧 Apple pass |
| Apple 新公网 gate | [实际原生验证](apple/public-internet/independent-verification.json)：schema2 source=f11，编译0/执行0/队列隔离通过，6输入 Git pins 全匹配，四份原日志齐全。范围为 macOS Foundation，非实体相机+蜂窝；9项合成verifier测试另计，不冒充runtime |
| Apple 完整来源 | [full-source-verification.json](apple/full-source-verification.json)确认冻结双端/run同源、macos-26完整准备与设备构建成功、artifact对应此job；原API保留。11项合成来源自测不加runtime计数 |
| 最终 Apple 与 IPA | [ci-result.json](apple/ci-result.json)：661 Flutter / 5 UIKit / 1模拟器原生流水线、前台fixture、1788 parity均通过；[独立IPA验证](apple/independent-verification.json)通过未签名/真机arm64机型与版本/模型/十图/digest门禁。未声称实际iPhone安装 |
| Android 与交付 | [当前 f11 收据](android/result.json)：两 ABI 重新构建、静态/照片、精确新 x64 R8 123 和新包 Back4+2 实际全0，安装 SHA 与运行收据一致，两个新 APK 已可测。[eab 首批原件](attempts/eab-android-first/)原样保留；当前22原件及无损 mapping 按manifest核SHA |
| GUI 复用资格 | [source-input-equivalence.json](source-input-equivalence.json)：新旧容器 SHA 不同，10 组产品 Git 输入相同，两 ABI 每个428解压payload字节完全一致、timestamp变化0；GUI 原执行仍 eab，明确据此复用，没有声称 f11 GUI 重跑 |
| GUI 无损原件 | [result.json](gui/result.json)关联 `raw-frame-captures.tar.xz`：13,154,448 字节，168 帧及 XML/timings 的原字节已由主任务逐项解包核 SHA；约 2fps 模拟器采样，不代表每显示帧或实体相机现场 |
| 最终安装包 UI 烟测 | [注册页](gui/registration-installed.json)：8–128 数字/字母提示及验证码显示，未填或提交账号；[在线预设](gui/online-presets-installed.json)：普通模拟器 Internet 列表 391 与内置模板预览正常。6 份 JSON/XML/PNG 哈希见 source.json；未独立覆盖 remoteCoverImagePath 或相机 Wi-Fi+蜂窝选路，不增加 70 widget 数 |

私有原始证据在 `.tooling/next225/`。失败、Windows AV、did-not-complete 与重叠单例不累计成新整套通过。旧 224、eab失败以及原始 core/RAW 收据不覆盖；最终接受依据是新f11同源全套与独立验包，不改写历史执行来源。

仅本地测试，不部署/发布。iOS QQ 缺用户真实 HTTPS Universal Link/AASA，当前返回 QQ_CONFIGURATION_REQUIRED，请使用账号密码；不能写成仅待真机即可正常。实体 iPhone自签、相机Wi-Fi+蜂窝、USB、原生QQ及16KiB设备未实测，见source.json knownLimitations。
