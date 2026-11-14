# 224 冻结本地测试包

仅用于本地测试，未发布商店或OTA更新。源码`08f414c5b8baeb019acc6c634216cdbbdb44bf9e`；二进制在本机本目录，SHA与字节数见[ARTIFACTS.json](ARTIFACTS.json)。Android ARM64适合通常的手机，x64用于模拟器；iOS IPA未签名，需自行签名。

两端完整自动检查及独立包验证已通过：[验证记录](../../docs/migration/validation/features-224/README.md)。224包含人像拖动/自动识别/面板留白与放大采样修复。

用户实装后追加的“先糊后清”、相机Wi-Fi公网访问和注册会话问题正在225继续处理。224是该源码的测试基线，不作为这些新问题的修复结论。
