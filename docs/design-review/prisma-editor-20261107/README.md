# Huevia 图片编辑 · Prisma 风格原型

设计参考：[Prisma Photo Editor — Daria Bugrowskaia / Prisma Labs](https://dribbble.com/shots/15854036-Prisma-Photo-Editor)。

双击 `prototype.html`，在浏览器中直接打开即可交互。照片、样式和脚本全部内嵌，可离线使用。`index.html`、`style.css`、`app.js` 为方便后续调整而保留的模块化源码。

## 这版设计

照片占据主要空间；画面延伸为模糊背景，顶部保留关闭与黄色「导出」，底部采用黑色圆形工具和横向滤镜缩略图。桌面总览并列展示滤镜、调节与裁切，窄屏显示一个可切换工具的完整编辑页。

- 滤镜分类、效果选择和强度调节。
- 曝光、对比度、饱和度和色温的实时示意。
- 原图／效果分割对比，可用鼠标、触摸或键盘移动分割位置。
- 居中比例裁切、90° 旋转、水平翻转；白框和黑框。
- 撤销、重做、重置；实际导出新的示意 JPEG。
- 人像标签仅演示色彩和布局，未接入人脸检测、磨皮或真实人像算法。

滤镜名称与色彩效果均为原型演示数据，不代表 App 内预设、Prisma 算法或尼康相机的实际渲染。示意照片取自本项目既有素材并裁为 4:5，来源记录于 `assets/provenance.json`。参考作品图只用于设计对照，不在原型中展示。

## 验证范围

通过真实浏览器检查滤镜切换、强度、撤销、曝光、分割对比、正方形裁切、旋转和带白框 JPEG 下载。浏览器无警告或错误。验证截图：

- `.impeccable/review/desktop.png`：设计总览及三个初始状态。
- `.impeccable/review/mobile.png`：390 × 844。
- `.impeccable/review/narrow.png`：320 × 640。
- `.impeccable/review/exported-demo.jpg`：实际导出的 800 × 1000 示意 JPEG。

JavaScript 语法检查通过。设计检测器因缺少 HTML/CSS 解析依赖而使用正则降级，没有报告问题；此结果不表示计算样式或对比度认证。素材来源扫描为 2 张、0 缺失。

离线文件通过内嵌资源结构检查与提取脚本的语法检查；实际浏览器交互验证使用同一源码的本地 HTTP 版本。内置浏览器禁止直接访问 `file://`，因此没有把离线文件标为已在内置浏览器运行验证。

交付范围为独立 Web 原型；原生 Android 布局、图像算法及安装包不属于本次交付。最终独立视觉意见见 `.impeccable/review/review.md`。

如需本地 HTTP 预览，可在项目目录执行：

```powershell
node docs/design-review/prisma-editor-20261107/serve.mjs
```

随后访问 `http://127.0.0.1:4187`。

修改模块化源码后，重新生成离线版：

```powershell
node docs/design-review/prisma-editor-20261107/build.mjs
```
