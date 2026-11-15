# 228 同源本地验证

Android 和 iOS 均已通过本地测试验证。最终产品源码 `734aa3b0f6687dda815af9e13070f0f3c463873c`，未发布。[状态](source.json) / [包清单](../../../../dist/migration228/ARTIFACTS.json)。

[Android原件](android/)：当前228两ABI签名/16KiB文件布局/8Native库、10图保留、精确R8123、返回4+2、真实release GUI5均0。本次定向format/analyze0、CameraPage布局和连接回归整文件7/0、圆底与原选择下载流程整文件4/0；这些不冒称实体相机PTP测试。PNG与R8 mapping是无损压缩的原件，复制SHA与tar成员均有清单。

[共享核心绑定](core/source-binding.json) 复用 [227真实JVM执行](../features-227/core/result.json)：1885 boundary+6 atmosphere=1891，261输入/246去重项全未变并逐项匹配228 Git。这里没有冒称228重新执行JVM，Mac原生输出仍必须逐字段匹配相同golden。原Android420文件保护检查0（13已批准修复、407未变），未改Native/网络路由。

[full/macOS26 43696814968](https://github.com/1162107757/nikon-camera/actions/runs/43696814968) 同源完整通过：Flutter 724 项、UIKit 5 项、Native pipeline 1 项；固定前台 fixture/source pins、schema2 公网隔离编译与运行、共享核心 parity、模型和10张样图、arm64未签名IPA均核验。

[最终辅助原件](final-checks/) 保留本次完整source/门禁/辅助校验和未成功的辅助调用资格；synthetic verifier self-check只证明校验器的拒绝条件，不代替Apple运行。全目录字节清单包括嵌套attempt清单，仅排除自身。

[227历史](../features-227/README.md) 保留bf29的720通过/1清理超时及ac5a被228替代后的cancelled记录，不把旧构建当当前通过。

[测试指南](../../local-testing-228.md)。iOS QQ Universal Link/AASA未配置；实体相机/蜂窝/USB/原生QQ/16KiB/自签iPhone待实际测试。未部署服务端或更新清单。
