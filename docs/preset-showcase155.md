# 预设展示摄影样片 · 155 / 0.30.1-beta

用户选择全部使用摄影样片，范围限于预设浏览列表和预设详情。处理照片时的预设选择/滤镜预览保持原路径。已与「按参考风格设计 App」任务协调：154完成冻结后交还MainActivity、production素材、版本号、模拟器与根文档写窗口，155从其最新磁盘文件增量接线。154安装包与验证目录保留。

## 素材与来源

全部10张为Pexels摄影照片，不包含生成插画。依据[官方Pexels License](https://www.pexels.com/license/)用于应用内经过参数模拟的展示，保留作者、原页面、下载URL、许可URL、获取时间、原下载SHA与打包SHA。源JPEG经过Pexels CDN压缩、sRGB和最长边960px处理，保持比例；随后仅嵌入来源注释，不改变解码像素。素材自身未烘焙任何Huevia预设效果。许可页及各原页面于2026-11-07核对；摄影者不构成对应用或配方的推荐。

| 样片 | 题材 | 摄影作者 | 原页面 | 尺寸 | JPEG字节 |
| --- | --- | --- | --- | --- | ---: |
| 自然光人像 | 人像 | Andrea Piacquadio | [Pexels 774909](https://www.pexels.com/photo/woman-in-collared-shirt-774909/) | 640×960 | 93210 |
| 近景人像 | 人像 | Simon Robben | [Pexels 614810](https://www.pexels.com/photo/man-in-brown-polo-shirt-614810/) | 960×820 | 48125 |
| 山湖倒影 | 风景 | James Wheeler | [Pexels 417074](https://www.pexels.com/photo/lake-and-mountain-417074/) | 960×647 | 103191 |
| 林间晨光 | 风景 | Kamil Szerlag | [Pexels 4413480](https://www.pexels.com/photo/bright-sunshine-illuminating-path-between-woods-at-sunrise-4413480/) | 960×640 | 110831 |
| 日间城市 | 城市 | Lukas Kloeppel | [Pexels 466685](https://www.pexels.com/photo/empire-state-building-new-york-466685/) | 960×596 | 159137 |
| 霓虹街道 | 夜景 | Piotr Wojnowski | [Pexels 40512875](https://www.pexels.com/photo/quiet-urban-street-at-night-with-neon-signs-40512875/) | 720×960 | 95366 |
| 海岸浪花 | 海边 | Pok Rie | [Pexels 4103594](https://www.pexels.com/photo/transparent-sea-water-on-bright-sandy-beach-in-daylight-4103594/) | 960×640 | 107309 |
| 粉色郁金香 | 花卉 | Nika Benedictova | [Pexels 15802403](https://www.pexels.com/photo/close-up-of-tulip-flowers-15802403/) | 636×960 | 41800 |
| 早餐静物 | 静物 | Ash Craig | [Pexels 376464](https://www.pexels.com/photo/pancake-with-sliced-strawberry-376464/) | 960×586 | 76119 |
| 雨夜街头 | 夜景 | Dương Nhân | [Pexels 20188510](https://www.pexels.com/photo/people-on-a-street-in-japan-at-night-20188510/) | 960×639 | 129907 |

10张JPEG合计964,995字节，随APK打包，便于离线预览；manifest文件另计。来源也嵌入每个JPEG的COM段，Impeccable来源扫描10张、0缺失。[完整清单](../app/src/main/assets/preset-showcase/manifest.json)包含校验值和获取时间。

## 浏览行为与边界

PresetShowcaseRenderer仅由MainActivity预设浏览/详情及设置实源查看使用。根据原始预设SHA和分类选择固定场景；人像/夜景各有两张，风景包括山湖/森林/海岸，日常使用多题材，其他分类覆盖全部10张。分类不变时列表、详情和再次进入保持同一张；变更分类可能改配图。用户已设置自选模板时仍优先沿用该模板。效果来自既有PresetPreviewProfiles近似模型，保留“模板模拟”标识，详情增加样片/摄影署名；不会当作相机真实试拍。

设置默认显示“摄影样片 · 10 张”，查看入口列出实际十张源图；自选模板时显示当前一张。“恢复内置摄影样片”恢复默认源图集。原图查看保留完整比例与作者署名，并按屏幕可用高度限制图片，保持横屏关闭操作可达；没有把旧合成模板继续称为当前浏览源图。

每个请求冻结Source，其cacheKey包括模型/模板/素材包/场景/照片SHA，效果与原图共用该Source。模板改变时过期结果被丢弃。3项LRU只缓存未改色的源像素；结果Bitmap由现有界面缓存管理，图片工作在worker线程，最大边960px。

PhotoFilterEditor、PresetSelectionPage、PresetPreviewRenderer、HoldToCompare四个既有文件与154交接时SHA完全相同；见[隔离记录](validation/preset-showcase/editor-scope.json)。没有把原始素材填入previewUrl/previewUri，没有修改“实拍参考”功能。

## 云端素材上传

使用现有CloudBase资产/私有存储接口上传10份独立preview资产，SHA寻址；逐一认证下载回读、比较完整字节。原有390份预设的ID、revision、publishedRevision、status、原始文件SHA和样片ID前后状态哈希相同。未绑定任何预设，未改公共目录/服务端行为，未部署服务、发布预设或公开发布APK。客户端展示使用随包摄影源再按当前配方生成，不依赖这些未公开绑定的素材资产URL。后台短期登录会话失效，上传使用项目已有环境匹配的服务凭据；凭据从未进入回执、源码或日志。见[上传回执](validation/preset-showcase/upload-verification.json)。

复核已上传素材可运行：

```powershell
node online-library/scripts/upload-showcase-pack.mjs app/src/main/assets/preset-showcase/manifest.json --verify --service --receipt=docs/validation/preset-showcase/upload-reverification.json
```

## 验证

155最终本地安装包：dist/huevia-0.30.1-beta-debug.apk，34,581,880字节，SHA-256 `b7d39e4930ca02a01174dcbdb26b7aa91d57dd84f2ebe20baf17305e44e61beb`。原生探针从已安装生产APK加载类，独立测试包只包含手工生成NCP夹具。手机/大字/窄屏/横屏/平板/平板横屏/暗色共167次断言执行、35张截图；另4项真实在线目录/效果/详情原图验证和2张截图，合计171。

覆盖10张源图的打包SHA、不同输入、现有预设模型逐像素输出、原图未被修改、缓存上限、自选模板优先、过期Source拒绝，以及实际浏览详情对比；有真实在线预设读取与渲染，十张模型输出另存缩略图。安装包十份素材 SHA、全部 ZIP CRC、V2／V3 签名及模拟器完整文件安装通过。未声称物理手机或尼康相机实拍验证。

初次[独立复核](../.impeccable/review/preset-showcase155/review.md)为 FIX，唯一 F1 是设置入口仍指向旧模板；已同步默认说明、十张样片列表及实际原图查看，并限制横屏原图高度保留关闭操作。最终[有界评分](../.impeccable/review/preset-showcase155/verdict.md)为 `disposition: ship`，13 张修正后截图均已打开；只关闭 F1 设置默认状态、实源查看、恢复文案及直接回归，含横屏关闭、自选模板和浏览页，不构成整个 App、154 或编辑页的全量 ship。原始报告与图片见[验证摘要](validation/preset-showcase/summary.json)、[安装包核对](validation/preset-showcase/apk-integrity.json)及[本轮边界](../.impeccable/review/preset-showcase155/contract.md)。
