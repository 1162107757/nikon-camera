# 226 同源本地验证

最终产品来源 `ed48347f1b3e6c92492207259cf24d1613ea12e3`，两端已接受为本地测试包，未发布。实际三包 SHA 与状态见 [source.json](source.json) / [ARTIFACTS](../../../../dist/migration226/ARTIFACTS.json)。

[Apple full/macOS26 43663233293](https://github.com/1162107757/nikon-camera/actions/runs/43663233293) 成功；[独立验包](apple/independent-verification.json) / [CI 证据](apple/ci-result.json) exit0：697 Flutter、5 UIKit、1 原生场景。原始前台夹具/pin、schema2 公网隔离 compile0/runtime0及六份 Git 输入、1865 ObjC/JVM parity、arm64未签名 IPA、Huevia正式名、模型与10图资源均通过。两端产品 source 相同，无跨源差异。

[Android 最终原件](android-ed48347/) 的新执行四项 pipeline 全部 exit0，精确 release R8 123、返回4+2、三项实际 GUI、正式名、签名/16KiB 文件布局和10图字节保留通过。[签名布局](android-signing-alignment.json) 与 [预览图](preset-preview-assets.json) 收据绑定最终 APK SHA。77份原件含压缩成员逐字节验证，实际界面来自 API31 x64 模拟器，未连接实体相机。

[core](core/) 是显式 JDK17 真实新执行：1859 boundary + 6 atmosphere =1865，编译和执行均0。八份原始执行件、canonical工具仅OUT差异与工具链观察均保存。261编译项/246去重项逐项匹配最终冻结 Git，绑定不是重跑。614→ed仅Dart widget测试变化，原Java输入完全相同。源码保护检查420项：13项已批准修复、407项未变，exit0。

[shared](shared/) 最后下载回归整文件19/0，A界面整6/0，format/analyze0。历史84个不同所选exit0不与这些整文件盲加；早期AV/未完成保留为原资格。Mac最终697项提供完整覆盖。各次结果及输入hash见 [矩阵](shared/test-matrix.json)。

失败历史完整保留于 [attempts](attempts/)：旧0bf Mac43659369969在RAW夹具字面/规范路径差异处失败；旧614 Mac43660752971为695/2，确认弹窗动画使全局pumpAndSettle超时。只修夹具等待实际可点击按钮、Dialog内exact-one查找及实际stopped后解锁，保所有业务断言。两次后续本机真实失败（0/1+5AV未完成、5/1）以及Java8 --release早期编译exit2都单列，不算通过。旧614 Android通过归档 [android-61423d6](attempts/android-61423d6/)，不作为最终ed新执行的替代。

[测试指南](../../local-testing-226.md) 与 [安装包](../../../../dist/migration226/README.md) 已就绪。iOS QQ Universal Link/AASA未配置；实体相机/蜂窝、USB、QQ、16KiB真机及自签iPhone待复测。未部署服务端、更新清单或商店发布。
