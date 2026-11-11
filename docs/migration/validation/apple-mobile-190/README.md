# Apple 190 验证通过

[Actions 42969015766](https://github.com/1162107757/nikon-camera/actions/runs/42969015766) 构建固定提交 `d82c9e478194210af85e08127bdb584d24bb0dd7`。

27 项 Flutter 测试通过，新增根导航筛选/排序面板在横竖屏、大字体下的点击回归，以及完整目录的下载状态筛选。205 项共享边界检查与原核心检查通过，六组 Apple/JVM 图像指纹相同。

原生 XCTest 实际完成 HTTPS 在线分页，以及原 PNG/JPEG、RAW、去灰、几何、边框、复制/撤销和成品版本流程。默认语义句柄检查保留，实际回报 PASS。`simulator-result.txt` 保存操作和 XCTest 结果，`core-parity.json` 保存核心指纹。

IPA 已验证 ARM64/iPhoneOS 主程序、release Flutter AOT、版本、ZIP CRC、包哈希和 GitHub artifact 摘要。未签名，最低 iOS 16，供用户自签；未在实体 iPhone 安装。

全功能迁移、所有二级页面状态、荣耀 Magic 实机和未知型号 NEF 实样仍待验收。精确包哈希和限制见 `../apple-mobile-190-20261111.json`。
