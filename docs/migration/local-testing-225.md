# 225 本地测试说明（Android / iOS 候选已验收，未发布）

225 继续处理 224 实装后反馈的“先变模糊再变清楚”、修补每笔重新加载和切换功能重新加载，并包含公网请求与登录注册状态修复。最终来源 `f11c4bff4d566f147094579d9b2d74bb5a4d8e6f` 的两份 Android APK 与未签名 iOS IPA 已完成同源本地验收，[三个附件](../../dist/migration225/README.md)可测试。[Apple full 43615396238](https://github.com/1162107757/nikon-camera/actions/runs/43615396238)实际 661 Flutter / 5 UIKit / 1 模拟器原生流程通过，IPA 已另行独立验包。`acceptedForLocalTesting=true`，`acceptedForDelivery=false`、`published=false`；这是本地测试候选，不部署。

[上一完整基线 224](../../dist/migration224/README.md)仍对应 `08f414c5b8baeb019acc6c634216cdbbdb44bf9e`，Apple full `43597212999` 为 619 Flutter / 5 UIKit / native 1。其记录保留原样，不继承为 225 通过；当前已接受本地候选为 225。

双平台本地测试时重点核对：

1. **清晰画面连续替换。** 放大后进入人像、修补和调色，旧照片与已解码高清图块应保留到下一冻结效果的图块就绪，再同步更换。修补各阶段等待时不应先退回普通预览。交互拖动仍实时更新；取消、账号改变、退出后不能安装迟到结果。
2. **切换与无修改返回。** 同一配方进入子工具及未修改的应用/取消应复用已接受画面，不额外改 revision、渲染或保存草稿。原图、预设、几何或实际效果不同则须正确更新。人像内取消修补只返回同一人像，恢复原数据与撤销历史。
3. **缓存保持精确归属。** 图像 handoff 仅接纳账号、原图路径、源 SHA、完整配方和输出尺寸一致的像素；局部高清只代表其覆盖区域，其余区域继续从正确底图显示并按需升级。原图不改写，借用完整工作图不得被子工具误删。
4. **相机 Wi-Fi 下的公网请求。** 检查预设、账号及其他明确公网操作能使用合适互联网连接；账号与公共读取在 Android/iOS 分队列，不阻塞串行相机命令。相机协议与连接流程没有新增行为改动。真实相机与真实公网组合仍需现场验证，不能用 loopback 心跳替代。
5. **注册与登录页面。** 页面切换保留已输入信息，新 session revision 使迟到响应失效；密码提示与校验允许 8–128 位，纯数字或纯字母均可，保留服务端校验与实际认证要求。确认登录后当前页立即呈现正确账号，不因迟到响应恢复旧状态。

[验证索引](validation/features-225/README.md)及 [source.json](validation/features-225/source.json)区分实际执行与待办。当前 controller 35 项、注册 12 项整组已通过；旧 Color 8 项为独立运行通过。工具切换已有 7 项独立通过，另两项无修改 fixture 修正后分别在 `noop-debug-apply-final.log` 与 `noop-debug-cancel-final.log` 实际通过，各为 +1、退出 0；不能写成整文件通过。Sharp 的主流程与账号项在一轮整体失败的尝试中完成通过，取消、几何及新增两种 Apply 后续各有独立 +1/退出 0 收据；不把前两项写成独立进程通过。source-positioned Apply 首轮 Windows AV 保留，仅 retry1 计通过；这些是 widget/真实 PNG 的桥接与生命周期验证，不代表真实 native 塑形像素或设备验收。

历史本地回归加上修正夹具后的两项真实大字入口，共 72 个观察到通过的不同 case，已映射到 [本地矩阵](validation/features-225/shared/case-matrix.json)：70 个来自退出 0 的命令、2 个来自混合失败尝试。65 份原始收据共 1,549,740 字节按原样归档，[哈希清单](validation/features-225/shared/byte-manifest.json)逐份核对；归档没有运行 SDK 或测试，也没有把旧 raw 改标成 f11 执行。最终 f11 完整验证另以 [661 项 Mac 收据](validation/features-225/apple/ci-result.json)为准，不把历史重叠尝试加到全套计数。

前次 [eab full 43611891603](validation/features-225/attempts/eab-full-43611891603/result.json)实际 659 通过 / 2 失败、设备编译 0，未进入 IPA/原生集成。两项旧夹具省略真实 1×1 预览宽高，导致曲线入口校验不通过；修正仅补尺寸及真实源文件，保留全部入口和业务断言，本地整文件 2/0 不回写为旧 full 通过。

225 已实际新跑本地 JVM：261 输入、246 不同输入，1782 共享边界加 6 氛围，共 1788，编译和执行退出 0；这是 225 新执行，不是复制 224 绑定。原日志与输入指纹逐字节保留在 [core](validation/features-225/core/result.json)，[最终 Git 输入绑定](validation/features-225/core/source-binding.json)已逐项匹配 `f11c4bff…`；绑定本身没有重跑 JVM。公网 host/VPN 23 项实际通过，loopback 心跳持续，未连接实体相机。

f11 Android 的新构建、静态/照片、123 R8 和 Back4+2 已真实重新执行，[当前 Android 收据](validation/features-225/android/result.json)绑定新 APK/testAPK SHA；旧 [首批快照](validation/features-225/attempts/eab-android-first/)及 [7 组 168 帧 GUI 无损原件](validation/features-225/gui/result.json)保留 eab 来源。GUI 仅凭明确产品输入/payload 一致证据复用，为模拟器约 2fps 采样，不覆盖每显示帧或替代实体设备现场。

eab 安装包曾做两项界面烟测，原始来源保留并按同一性证据复用：[注册页](validation/features-225/gui/registration-installed.json)实际显示 8–128 位、纯数字或字母可用提示和已加载验证码，未填或提交账号；[在线预设页](validation/features-225/gui/online-presets-installed.json)在普通模拟器 Internet 下显示 391 条及内置模板预览。没有独立覆盖 `remoteCoverImagePath` 或相机 Wi-Fi 配合蜂窝选路，两项烟测不加入 72 个 Flutter case 数。

Apple 已核对双端冻结来源、`macos-26` 完整准备/构建步骤、[661 / 5 / 1 及前台证据](validation/features-225/apple/ci-result.json)、1788 shared parity、十图/模型及 [IPA 独立验证](validation/features-225/apple/independent-verification.json)。[公网 Foundation 原生门禁](validation/features-225/apple/public-internet/independent-verification.json)实际编译 0、执行 0、隔离通过，6 个输入 Git SHA 全匹配；这是 macOS Foundation 真实队列测试，不是实体相机加蜂窝验证。此前 9+11 项合成验证器自测不加到 runtime 计数。

IPA 适用于 iOS 16 及以上，需自行签名。iOS QQ 当前缺真实 HTTPS Universal Link/AASA 配置，原生授权会返回 `QQ_CONFIGURATION_REQUIRED`，请使用账号密码；不是等真机测试即可自动正常。密码允许 8–128 位，可仅数字或仅字母。

仅供本地测试，不发布商店或更新清单，不部署。实体 iPhone 自签安装、相机 Wi-Fi 配合蜂窝数据、USB、原生 QQ 授权及 16KiB Android 实体设备仍未实测，不能以模拟器/host 结果替代。
