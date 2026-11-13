# a54 Avatar 夹具混编失败

Intel Mac `43458258245` 在核心 parity 通过后，avatar 夹具报 [`--std=c++17` 不适用于 Objective-C](failure-excerpt.log)。a54脚本把新增 `HueviaTaskCancellation.m` 直接放入已有 `.mm` 链接调用，导致该错误；[当时脚本原字节](avatar-apple-a54.sh.txt)保留。

修正仅为 `avatar_apple.sh`：与原 `HueviaTask.m` 相同选项独立 `-c` 编译新 `.m`，生成 `avatar-task-cancellation.o`，再把对象文件交给 `.mm` 链接命令。没有改产品、断言或协议。

Windows 上 `bash -n`、差异检查通过，两个 Objective-C 编译单元的选项逐项相同；只读扫描未再找到其他工具 shell 中显式 `.m`/`.mm` 同命令输入。精确指纹及完整原始 job 日志 SHA 见 [result.json](result.json)。**本机未执行 Apple SDK 编译，必须重跑新源 Mac 全门禁。**
