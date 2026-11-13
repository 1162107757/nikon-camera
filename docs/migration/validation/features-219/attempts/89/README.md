# 89未交付候选：Android通过，Apple失败

源码`89c1393272f2164594f9eecc30df7d1f65153d01`的Android精确包R8 78、签名/各8 ELF静态/十图与冷启动2·50·19通过，完整功能UI仅引用a54。[索引](result.json)保存14份小快照SHA；无APK/IPA复制。旧ARM64为52,723,506B/SHA`d81cf0f6f670368ed842a7ade6fe40b5db31e6d3f584379ed0ae6882c9da68ae`，旧x64为56,226,010B/SHA`dc74d3a4a8f734f6d008a7973195f8186f91ce88f71488e7be6c0dccd72dddba`。

[Android收据](android-final-receipts.json)、[签名静态](android-signing-alignment.json)、[R8日志](release-runtime.log)、[结果](release-runtime-result.json)、[冷启动](final-exact-apk-cold-launch.json)和[三事件](cold-launch-events.json)均保89归属。旧[89→a54全native树比较](source-equivalent-ui-binding.json)只属原范围；新91 iOS消费者变化，不能沿用该全平台等价。

Mac43464094785实际NativeCore/Avatar/WiFi准备通过、core parity1629、Flutter447通过2失败；设备编译因HueviaOriginalFiles.mm:44向只读取消属性赋值失败。完整5项UIKit/IPA未接受，见[消费者失败/修复记录](../../native-cancellation/api-consumer-migration/README.md)与[两旧fixture补充](../../flutter-camera/supplements/legacy-fixture-contract/README.md)。其后补丁另作新源验证，原失败不改成通过。此候选未交付、不公开发布。
