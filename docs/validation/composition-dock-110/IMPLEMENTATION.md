# 110 构图入口与发布容量实施记录

最终制品为 `110 / 0.22.1-beta`，路径 `dist/huevia-0.22.1-beta-debug.apk`，大小 **9,478,052 bytes**，SHA-256 **`5f42f3a9733e86bc472ce56cae0e669609828d1a2027e050db39934e27ae0fe8`**。[SOURCE-IDENTITY.json](SOURCE-IDENTITY.json) 冻结 **262 个输入，构建后漂移为 0**。此前 `852d17a8…` / 771 项批次是 UI-only 候选，不能替代本次最终制品的证据。

## 实施范围

相对冻结109恰有5个输入变化：

| 输入 | 用途 |
| --- | --- |
| `app/build.gradle` | 版本输入更新为110 / 0.22.1-beta；它是四个原 UI-release 输入之一。 |
| `app/src/main/java/cc/huevia/ui/AppIcon.java` | 构图工具图标，包含透视入口。 |
| `app/src/main/java/cc/huevia/ui/PhotoCropDialog.java` | 按入口选择裁剪、暂存旋转、拉直或透视状态。 |
| `app/src/main/java/cc/huevia/ui/PhotoFilterEditor.java` | 四个紧凑图文入口、角落重置，以及构图模式专属的内容高度。 |
| `app/src/main/java/cc/huevia/updates/UpdatePolicy.java` | 用户后续授权发布后，将客户端下载容量上限从4MiB提高至32MiB。 |

因此“四个 UI-release 输入”包含一个版本文件，并不是四个 Java UI 文件。最终发布重建只新增客户端 cap 变化；UI和RAW native输入与 UI-only 候选保持一致。

普通字号下，构图内容区从176dp缩到112dp，导航仍为48dp，整体 dock 从 **224dp缩到160dp**；滤镜、调节等其他模式仍使用176fp内容区。大字号使用 `fp=max(1,fontScale)` 适配。四入口为“裁剪／旋转／拉直／透视”，图标在上、短文字在下；角落重置仅缩小视觉，工具和重置均保留至少48dp触摸目标。横屏沿用固定侧栏，不宣称缩短内容会扩大照片宽度。

旋转入口先在构图弹窗暂存90°变化：取消不改变主状态，应用才形成一次历史记录；撤销／重做通过可见的“调节”面板按钮操作，再返回构图。裁剪、拉直、透视继续沿用同一工作区，透视可在真实原生菜单中切换水平和垂直。重置只清除几何构图，保留调色、局部编辑和边框，并可撤销恢复。原有账号／照片有效性、异步加载和起始状态保护保留。

## 最终原生验收

探针编译时只依赖Android API35，通过反射加载实际安装候选的生产类。三轮均绑定同一最终APK SHA和探针SHA `0c443f4ba491c0f134e7469db24106b2270371235d30eeb9506277bc6a39bfb1`：

| 模式 | 最终 run | 通过项 | PNG |
| --- | --- | ---: | ---: |
| phone | `20261027-232027-phone-0a1bdd50` | 258 | 2 |
| font1.3 | `20261027-232044-font1.3-2967af73` | 254 | 2 |
| landscape | `20261027-232101-landscape-157392ea` | 235 | 2 |
| 合计 | 最终发布包 | **747** | **6** |

证据位于 `docs/validation/composition-dock/5f42f3a9/<run>/<run>/`；各run上层保留候选／探针provenance及cleanup。phone是模拟器的竖屏布局模式，未进行物理手机对照。

最终实测：phone内容196px、总dock280px，照片stage高845→957px；font1.3内容255px、总dock364px，stage高688→833px；横屏内容196px，填满侧栏的dock为503px，stage高587→587px。数值对应标准字号112dp内容＋48dp导航及字体缩放规则。

原生流程实际点击四入口、取消／应用、重置和历史按钮，验证旋转暂存及单步历史、拉直焦点、真实透视菜单／按键、几何重置保留其他设置、模式高度恢复、48dp热区和单行短文字。每模式仅两张提交帧并稳定后的截图。最终phone首图已由协调任务确认无系统提示、短文字对齐正常；其余五张经独立查看无教学遮罩、全图调暗、菜单残影或异常遮挡，详见 [VISUAL-REVIEW.md](VISUAL-REVIEW.md)。

每轮cleanup均记录：自有JPEG／草稿已清理，font／旋转／airplane／immersive设置恢复，探针卸载成功，`errors=[]`，主应用数据未清空。总目录较早的 `CLEANUP.json` 不能证明最终会话的模拟器已关闭，本记录只引用三个最终run级cleanup。

## 客户端容量宿主回归

容量回归独立于747项原生构图验收：`tests/run-updates.ps1` **70项**、`tests/run-update-manager-host.ps1` **47项**，共 **117项**。日志在 `docs/validation/release-capacity-110/android-update-policy.log` 和 `android-update-manager-host.log`。

这些用例使用明确的离线合成metadata、Android对象及DownloadManager计数fixture，验证9,478,052字节元数据接受、32MiB边界接受、cap+1拒绝、超限reported received取消并移除下载记录／清除持久跟踪和验证状态，同时保留既有SHA、签名、mandatory、撤回及安装前复查用例。它们不冒充真实APK解析、实际网络、真机下载或安装认证。

## 历史尝试与探针修正

历史证据原样保留，且不计入最终747项：

- 首轮 `20261027-210821-phone-d43eefa0` 因探针使用公开构造查找而失败；`DownloadedPhoto`构造是package-private，改为五参 `getDeclaredConstructor` 并开放访问。
- `20261027-211537-phone-7774d409` 已通过旋转应用与保留设置检查，随后探针点击隐藏的撤销按钮失败；改为先进入调节再点击真实可见历史按钮。
- 较早彩卡样例被替换为发货 `preset_template` 照片，按比例缩放，唯一标识写入EXIF而不覆盖画面；菜单退出及窗口焦点等待移到原生键盘输入之前。
- `20261027-213659-phone-6e5bdb8e` 的原生流程通过，但首图被Android首次全屏教学提示遮罩，未接受为最终视觉证据。仅测试条件修正：临时确认并恢复immersive提示设置，截图前后检查并实际关闭 `Got it`，等待提交帧稳定。
- `852d17a8…` 的清洁 UI-only 三模式批次为270＋258＋243＝**771项**；其完整历史与旧遮罩说明保留在视觉审查及 [NATIVE-RESULTS.json](NATIVE-RESULTS.json)。发布cap变更后已针对最终 `5f42f3a9…` 包重跑747项。

## 发布状态与范围限制

用户在UI工作后另行授权发布。后台capacity迁移017已上线并通过读回确认，见 `docs/validation/release-capacity-110/MIGRATION-017-CONFIRMED.json` 及该目录实施记录。协调任务已通过Chrome正常管理员后台上传、保存强制策略并上架最终制品：release ID `fdb53c9f-f523-4b0c-a67e-e3e85b68e37d`。制品、签名、大小和说明均经后台显示复核，发布截图为 `release-110-published.png`，最终公网结果见 `PUBLICATION.json`。

真实Android系统DownloadManager已通过公开canonical地址的307下载完整9478052字节，核对SHA、原生PackageManager包名／版本／同签名，共35项通过。证据：`docs/validation/update-large-download/5f42f3a9/20261027-235957-a0eeb80c/`；下载记录和自有文件已清理，未启动安装器。它独立于747项构图检查。最终会话模拟器已关闭、launcher退出、serial消失，见 `CLEANUP-publication.json`。

**旧108必须从下载页下载同签名APK，覆盖安装一次**；已安装旧客户端的4MiB上限不能由服务端远程改变。最终新客户端使用32MiB上限。

本轮没有物理设备视觉对照。RAW库输入沿用冻结109的相同字节，本次构图探针使用JPEG，不声称在110重新测试RAW解码内核。该文档更新只整理本地证据，不修改生产、探针、README或在线状态。

