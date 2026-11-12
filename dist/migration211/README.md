# 211 自动边拍边传

接通迁移清单A1：Nikon相机前台自动接收新JPEG，初始旧库存不补收，重复通知去重、缺失事件盘点、稳定元数据后接收，以及可信相机重连补片。可不使用默认预设只收原图；设置预设时另存成品，原图保留。断线页提供重新连接，四个底部标签切换保留进度。

三个包的源码均为 `db8e2ef3766a228bd2dd93f6e1e139b697d3ff18`。Android ARM64 手机包最低Android8，x64用于模拟器；标识cc.huevia.next。IPA是iPhoneOS ARM64、iOS16+未签名设备包，需自行签名。

| 文件 | 字节数 | SHA-256 |
| --- | ---: | --- |
| huevia-0.31.0-dev-211-android-arm64.apk | 51307590 | `a4280e6bf7f74a148c07cb9af55cbdfa6a8cfec656ee9d10677dc550c14d80c8` |
| huevia-0.31.0-dev-211-android-x64.apk | 54679022 | `9954265b93133ff35a5b1df40746dc450f8aab40e97609af8cc6731c0537bc16` |
| huevia-0.31.0-dev-211-ios-unsigned.ipa | 29638281 | `0c16ed2a127b44232a77729e364db34119b6f343301afc037c50e92fe4d6eab1` |

Android安装56项控件/状态检查通过，普通release实际受控PTP/IP流程核对9个新原图、8个成品、1个仅原图、两次断流补收及停止后不收。原图SHA、索引与收据核对通过。215项Mac Flutter、878项共享核心、24项原生Wi-Fi、38项原生头像与1个真实PhotoKit/图像/RAW/项目场景通过，见 [Actions](https://github.com/1162107757/nikon-camera/actions/runs/43246481303)。

原工程保留。A1仅前台Nikon JPEG；后台服务、系统终止完整恢复、Fuji自动收片和其余开发项仍待完成。实体Nikon/iPhone与荣耀Magic不以模拟器代替验收。详见 [211冻结记录](../../docs/migration/validation/camera-live-211/README.md) 与 [12项剩余工作](../../docs/migration/remaining-work-211.md)。candidates为早期包，不是当前交付。
