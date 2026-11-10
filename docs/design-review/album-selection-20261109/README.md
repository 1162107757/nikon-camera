# 相册多选操作栏概念图

2026-11-09，用户要求先看三张设计图，尚未选择或实现。使用内置 image_gen 生成，非原生截图；摄影内容及页面身份参考仓库既有 four-home154/native/phone/03-selection.png，操作功能核对当前180的LocalAlbumPanel。

- A-balanced-toolbar.png：取消与数量移入顶部，底部三个等宽图标操作。
- B-two-level-dock.png：保留原页面标题；底部状态／取消与三个动作分两层。
- C-edit-first-panel.png：编辑为主按钮，导出与删除为轻量辅助操作。

应用相册含编辑、导出、删除；手机相册按当前实现只提供批量编辑。图中均展示应用相册。原代码、180安装包、云服务均未改。完整生成提示见 prompts.json。
