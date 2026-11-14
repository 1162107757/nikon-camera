# 225 本地测试附件（Android / iOS，未发布）

225 改善放大、修补与切工具时先糊后清的问题，并加入公网独立队列、online.preview 缓存和注册状态/输入保留修复。三个附件均为最终来源 `f11c4bff4d566f147094579d9b2d74bb5a4d8e6f`，已通过本地验收。Android实际123 R8/Back6；[Apple full 43615396238](https://github.com/1162107757/nikon-camera/actions/runs/43615396238)为661 Flutter /5 UIKit /1模拟器原生流程，IPA已独立核验。`acceptedForLocalTesting=true`，`acceptedForDelivery=false`、`published=false`，不部署。GUI原件仍属eab，凭产品Git输入及逐APK解压payload同一性复用，不声称容器相同或GUI重跑。精确来源见 [ARTIFACTS.json](ARTIFACTS.json)。

- [Android ARM64 测试包](huevia-0.31.0-dev-225-android-arm64.apk)，53,264,178 字节，SHA-256 `e1c85fd5123124f183fe76764999f1dcd1ebc90944dee4af95331d7856b0b040`。
- [Android x64 测试包](huevia-0.31.0-dev-225-android-x64.apk)，56,701,146 字节，SHA-256 `5650c3606875ab0022afaf295dee5bdf198ce0b764f6e39c72ae032458b43af0`。
- [iOS 未签名 IPA](huevia-0.31.0-dev-225-ios-unsigned.ipa)，65,153,750 字节，SHA-256 `a9d73150f386f42a623cdb7357be5d4153a9c064f9740f1150021b5a25d57be6`。iOS 16及以上，需自行签名。

[224 三包](../migration224/README.md)是已验收本地测试基线：`08f414c5…`、619 Flutter / 5 UIKit / native 1。其精确包 SHA 和用户后续反馈原样保留，不继承为 225 验收。

见 [225 测试指南](../../docs/migration/local-testing-225.md)与 [验证索引](../../docs/migration/validation/features-225/README.md)。历史72本地case保留原资格，eab full659/2失败原件独立保存；最终f11完整661与IPA收据另计，不回写旧失败。新实际JVM261/246输入、1788检查已绑定f11，绑定没有重跑。

仅供本地测试，不发布商店或更新清单。iOS QQ 缺真实HTTPS Universal Link/AASA配置，当前无法原生授权，请使用账号密码；密码8–128位，可只用数字或字母。实体iPhone自签、相机Wi-Fi+蜂窝、USB、原生QQ及16KiB Android设备未实测，详见清单knownLimitations。
