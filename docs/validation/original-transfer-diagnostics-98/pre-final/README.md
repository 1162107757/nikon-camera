# 非最终证据

早期相册检查失败暴露原 LiveChanged 自动重收问题；live-progress-diagnostics.txt 保留 completed=1、两条身份记录的合成夹具输出。其后修复并加入防重传和后续真实新身份接收回归，最终 895 项控制器检查通过。该失败不是实机吞吐测量。

原生导出探针最初尝试用 ActivityMonitor 拦截系统文档选择器：缺少 MIME/类别的过滤器没有命中，失败记录为 native-filter-mismatch.json/txt。该次测试留下自有模拟器的系统 DocumentsUI 窗口，随后两次探针等待 MainActivity 启动分别达到 65 秒和 60 秒界限，未得到成功报告；第二次仅有 owned-emulator-only 与 installed-candidate-hash 两个检查点。

探针改为仅验证生产报告构造及 onActivityResult → ContentResolver 的本地受控目标；关闭仅属于自有 emulator-5588 的遗留 DocumentsUI 和目标进程后，当前候选 c9dfa603 的同一探针完成 9 项检查。最终 NATIVE-EXPORT.json 才是成功证据；不将早期失败/超时算作通过，也不声称系统文档选择器完整自动测试通过。

中间 e71a88fa 和 b6c09fd0 安装包仅保留在 .tooling/original-transfer-diagnostics-98，未交付。当前证据只绑定最终 c9dfa603 候选。
