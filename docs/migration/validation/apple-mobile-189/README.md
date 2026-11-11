# Apple 189 验证通过

[Actions 42963383351](https://github.com/1162107757/nikon-camera/actions/runs/42963383351) 使用提交 `1c424600dd284041ede82fa99a444ac37b94c63b`。`core-parity.json` 保存 Apple 原核心检查结果和与 JVM 相同的六组图像指纹；`simulator-result.txt` 保存实际原生操作、语义句柄数量与 XCTest 成功结果。

23 项 Flutter 测试通过。原生模拟器场景实际完成 PNG/JPEG、旋转/裁剪、去灰、三种边框、复制/撤销、成品版本以及两种设置的 DNG 显影；尺寸、白色高光、原图 SHA 和清理检查均保留。系统语义状态在套件开始前固定为启用，结束后还原，默认语义句柄清理检查正常执行。

IPA 的 ZIP CRC、主程序和 Flutter AOT 的 ARM64/iPhoneOS 标记、版本、无模拟器 Dart 内核、设备包哈希及 GitHub 外层 artifact 摘要均已校验。包为未签名开发 IPA，最低 iOS 16，须由用户自签；本机没有 Mac/实体 iPhone，未作手机安装验收。

精确构建和包哈希见 `../apple-mobile-189-20261111.json`。完整功能迁移、所有页面样式、未知型号 NEF 与荣耀 Magic 实机验证仍未完成。
