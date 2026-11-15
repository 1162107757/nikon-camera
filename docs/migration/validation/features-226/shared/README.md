# 226 本地回归原件（来源待冻结）

[测试矩阵](test-matrix.json) 逐 attempt 记录真实 exit、通过计数和未完成项；[字节清单](byte-manifest.json) 对所有 raw 原件保留长度与 SHA256。本次只复制既有日志，没有重新运行测试。

所选 exit0 目标共 84 个不同用例：首次成功六个文件60、Intent 完整重试15、重连整文件5、接收记录末行1、UI3/4/5各1。重连此前 mixed 2pass/3fail、记录旧断言失败和初次未完成均独立保留，不叠加到唯一计数。新 UI1/2 在 Windows native AV79/零完成后仍未验收，不能计通过，等待最终 Mac full。

重连 fixture 修复等待滚动的新布局并先检查触摸命中；末行 fixture 用有限小幅真实手势滚至尾部。保留末行命中、旧 tab 区域、实际查看、两次 Back 与相机会话断言。没有修改产品以迎合测试。

这些收据来自尚未冻结的本地工作阶段，并非整套 Flutter/Mac、最终同源安装包或实体相机验收。当前 final-scope 回归仍由主任务执行，未在本矩阵冒称通过。JVM 实际新执行1865见 core；最后来源绑定另行完成。未发布。

## 后续本地 final-scope 原件

Live 整文件28/0、retirement 整文件7/0；reconnect 前3项后 Windows AV、后2项未完成（outer1），不能称整5通过。它与早先 fixture-final 整5/0 是不同 attempt。以上3日志及JSON原件另加到字节清单，保留执行阶段资格，不把重复项叠加到早先84计数。候选来源现冻结为 `0bf8da5d55996aa4aa0e3a70301f37a88f0eba7b`，但日志未重跑或重标为 Mac/安装包验收。

## 新61423d6候选下载迟到回复回归

新增原format/analyze/tests日志、result与runner共5份，未重新运行。camera_downloads_test整文件19/0，其中包含原12与新增7；不能把19直接叠加到旧84去重数。新7覆盖bindCurrent/skip的账号、队列选择及迟到回复隔离，当前合法回复仍能安装。收据是本地回归，非两平台包或Mac全套验收。

## ed48347：A面板最终整6/0

最终format/analyze/tests三项均exit0、A整文件6passed；5份原件和fixture-only-source-proof共6份已按字节追加。Git证明614→ed仅该widget test变化、产品输入完全不变。两个先前Windows未完成case现在本机已完成；但旧Mac614的695/2仍是失败，新Macfull43663233293待完成及独立验包。6不盲加旧84历史子集。

两次真实中间失败另存[duplicate text 0/1+5AV未完成](../attempts/a-dialog-readiness-duplicate-text/README.md)与[stop phase 5/1](../attempts/a-dialog-readiness-stop-phase/README.md)，含对应源码快照、runner、raw/metadata和独立manifest。最终修正只限定Dialog内exact-one文案及等待stopped后解锁，全部原业务断言保留。原失败不会改写成通过。
