# 219 照片格式标签专项

当前格式统一读取工作文件路径的已知后缀；平台不含文件名的资源 ID 才回退到现有名称。显影 JPG 的主标签为 `JPG`，关联原片另写为 `来源 NEF`。原始 NEF、直接 JPG 及同名 RAW/JPEG 的文件身份、打开路径、RAW 显影与像素处理不变。

| 检查 | 实际结果 | 原始证据 |
| --- | --- | --- |
| 新格式回归 | 4 项通过，exit 0 | [日志](format-regressions-final.log)、[退出码](format-regressions-final.exit)。覆盖工作路径优先、原始 NEF、直接 JPG、显影 JPG 与 NEF 来源分开显示、平台 URI / 未知格式回退，以及同基名 JPG/NEF 卡片分别打开；点 JPG 后编辑组件和渲染请求仍使用该 JPG，不触发 RAW 显影。 |
| 既有相册回归 | 1 项通过，exit 0 | [日志](photos-existing.log)、[退出码](photos-existing.exit)。星标、搜索、稳定编辑链接。 |
| 既有编辑菜单回归 | 1 项通过，exit 0 | [日志](editor-menu-existing.log)、[退出码](editor-menu-existing.exit)。菜单各页使用当前草稿并返回编辑器，保留显式 RAW 来源入口。 |
| 最终目标文件分析 | No issues，exit 0 | [日志](analyze-final.log)、[退出码](analyze-final.exit)。 |
| 初次目标文件分析 | 历史 1 条 info，进程 exit 0；不记作干净分析 | [原始日志](analyze.log)、[退出码](analyze.exit)。格式化使原 RAW 缩略图的单行裸 `if` 触发花括号提示；仅补花括号后取得上面的最终分析结果，保留此初次记录。 |

共计 **6 个独立用例实际通过**，未将重复运行累加。[结果元数据](result.json)保存五个改动文件及复用测试桩的 SHA、每份日志与退出码的 SHA。相册至编辑器回归使用实际 Flutter 页面和路由，平台操作由测试桩隔离；该记录不宣称 219 原生运行已经通过。最终 219 源提交、版本与双端门禁由主任务管理。

归档时只复制既有记录并核验指纹，未重跑 Flutter、JVM、构建或 ADB，也未修改已交付 218 的文档或安装包。既有菜单测试退出后留下一个由 Windows 文件映射占用的自建临时目录；随后递归清理请求被自动审批以 `blocked by policy` 拒绝，未重试删除，精确信息已单独交主任务核查。
