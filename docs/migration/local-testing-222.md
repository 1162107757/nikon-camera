# 222 本地测试说明

**222三个同源安装包已接受本地测试交付，未公开发布。** 冻结源码为 `9559591734f8cc07a8b9dcc1cf5ca596020904b5`；Apple [full 43560076101](https://github.com/1162107757/nikon-camera/actions/runs/43560076101) success，IPA独立验包exit 0。`acceptedForLocalTesting=true`、`acceptedForDelivery=true`，`published=false`。

本轮恢复旧Android滤镜和调色工作区，改进连续预览，并接入已批准的连接、遥控和同步工具布局及相机照片排序。[221已验收基线](../../dist/migration221/README.md)保持原样。以下步骤供本地复测。

| 附件 | 用途或条件 | 字节数 |
| --- | --- | ---: |
| [Android ARM64 APK](../../dist/migration222/huevia-0.31.0-dev-222-android-arm64.apk) | 手机本地测试 | 52,985,650 |
| [Android x64 APK](../../dist/migration222/huevia-0.31.0-dev-222-android-x64.apk) | x64测试环境，精确包运行已通过 | 56,488,154 |
| [iPhone未签名IPA](../../dist/migration222/huevia-0.31.0-dev-222-ios-unsigned.ipa) | iOS16+，需自行签名；实际手机安装未验证 | 65,057,023 |

## 滤镜与调色

1. **同一条中心线。** 打开照片的“滤镜”，比较固定的“我的｜在线”、分类文字和最右侧“全部滤镜”网格图标：可见文字/图标应在同一水平中心线上。选中分类的下划线在文字下方，不推高文字。普通字号、放大字号、短屏和横屏均需查看；不要只比较三个48dp点击框的外沿。
2. **浏览不改变效果。** 左右滚动分类与缩略图，切换“我的/在线”。浏览本身不应改变当前滤镜、强度或撤销记录。缩略图保留白底名称、14dp卡间距和单个选择勾；照片预览保持可见。
3. **查看全部。** 点击右侧网格，检查三列滤镜、名称/分类搜索、“未分类”和清空搜索。选择成功后应用滤镜并返回；准备失败应保留原效果并允许重试。准备中取消、返回或切换账号，迟到结果不得安装到照片或关闭后续页面。
4. **旧版调色工作区。** 打开曲线、调色盘、HSL和去灰，核对旧版控件、强度/通道、去灰高级选项及确认、取消。竖屏照片在控件上方，横屏保留照片和侧栏；照片不能被大面积弹层挤没。应用后撤销可回到进入前状态，取消不写入候选调节。

## 连续预览与相机页面

5. **连续调节。** 拖动编辑器、RAW显影和人像参数，照片应随最新候选更新；松手完成最终质量预览，一次手势形成一次撤销。连续快速拖动后核对最终值，取消后核对原状态；旧请求晚到不能覆盖最新结果。RAW显影仍沿用既有原生质量合同，不把控件回归当成新的RAW像素或实体设备验证。
6. **连接和同步工具。** 检查已批准的连接页、遥控面板和同步工具dock。连接成功直接返回调用流程，连接流程本身不读图；用户进入“同步→相机照片”后再读取，无需额外手点“浏览”。由预设导入触发的连接应继续导入/槽位流程。工具打开、关闭与返回应保持原有忙碌保护。
7. **相机照片排序。** 在相机照片中切换时间、文件名及相应顺序，核对排序结果、选中状态和下载对象仍对应同一照片；排序不应自行触发拍摄、删除或反复读取整个图库。
8. **账号切换。** 在编辑器或人像预览仍加载时切换账号或离开页面，再进入当前照片。旧账号的迟到氛围背景不得出现在新页面，也不能覆盖新页面的加载状态。

## 当前证据与边界

[Android实装收据](validation/features-222/android/ui-result.json)绑定最终x64 APK：曝光、曲线、HSL、调色盘、去灰各做7秒持续拖动，每项两帧截图时指针仍未抬起，照片区域均已变化；测试原图SHA前后相同。两ABI验签、各8个ELF的16KiB静态对齐和10张预览图通过，精确x64在API31/4KiB模拟器实际通过78项R8及四根标签、两内页共6项返回验证；4KiB模拟器不等于16KiB实体设备实测。

实际Android截图：[滤镜分类](validation/features-222/screenshots/final-filter-category.png)、[全部滤镜](validation/features-222/screenshots/final-filter-grid.png)、[曲线](validation/features-222/screenshots/final-curve-workspace.png)、[HSL](validation/features-222/screenshots/final-hsl-workspace.png)、[调色盘](validation/features-222/screenshots/final-palette-workspace.png)、[去灰](validation/features-222/screenshots/final-cleanup-workspace.png)、[去灰高级](validation/features-222/screenshots/final-cleanup-advanced.png)、[连接](validation/features-222/screenshots/final-connection.png)、[同步工具](validation/features-222/screenshots/final-sync-tools.png)、[下载队列](validation/features-222/screenshots/final-floating-queue.png)。这些是模拟器实装截图，不是iPhone或实体相机证明。

最终Apple实际通过541项Flutter、5项UIKit、1个完整native pipeline和1770项核心一致性；IPA同源、iPhoneOS/arm64、模型、字体及10图独立核对通过。前台fixture通过证据为machine-test，snapshot为null，不捏造独立快照次数。本地核心沿用已绑定的243个Java输入与参考golden，未冒称本地222新JVM执行。[验证索引](validation/features-222/README.md)列实测项目；[来源记录](validation/features-222/source.json)分开保留旧尝试；三包实际字节和SHA见 [ARTIFACTS.json](../../dist/migration222/ARTIFACTS.json)。

仅本地测试，不公开发布、上传草稿或更新分发清单。实体Z6II Wi-Fi、实际iPhone安装/连接、USB、QQ真实授权和16KiB实体设备仍未验证；iOS QQ Universal Link未配置，既有RAW原图删除限制保留。相机现场复测仍按 [221边界](local-testing-221.md)及 [220指南](local-testing-220.md)进行，不承诺亮屏/后台永久连接。

已知后续问题：实时预览进度条闪动、皮肤选色有冗余确认，已转223处理，不属于222已修复范围。223是独立工作，不纳入本次源码或附件。
