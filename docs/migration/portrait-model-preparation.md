# 可移植人像模型准备

`mobile_apple.sh` 在准备原生 pod 前运行 `python3 cross-platform/tool/prepare_portrait_models.py`，日志为 `cross-platform/.build/mobile-apple/portrait-models.log`。脚本只从固定官方来源及自己的缓存准备 `native/ios/Assets/portrait`，不读取或修改原 `app/`、`ios/` 源树。

来源与输出沿用原 `scripts/prepare-face-landmarks.ps1`：

| 材料 | SHA-256 |
| --- | --- |
| Google 官方 Face Landmarker float16/version 1 `.task` | `64184e229b263107bc2b804c6625db1341ff2bb731874b0bcc2fe6544e0bc9ff` |
| 从 task 提取的 detector，2,553,590 字节 | `c7d54204ce0448474c7f3fa9af494787c0965cbdd6f20fc72867e43046bd43d5` |
| Google 官方 Selfie Multiclass float32/version 1，16,371,837 字节 | `c6748b1253a99067ef71f7e26ca71096cd449baefa8f101900ea23016507e0e0` |
| shuffle4/zlib 模型，13,881,786 字节 | `9920fafc503c9090b3840c6fb433efc7eeb117bb00176b04034bd589c0e19bb0` |

压缩前，四个字节平面满足 `shuffled[plane*N+i] = original[4*i+plane]`、`N=floor(length/4)`，最后一个尾字节原样保留。不能用系统 Python zlib 代替 encoder：同一个输入的压缩字节会不同。

macOS/Linux 用 CMake 与 host C compiler 构建固定的[上游 zlib-ng 2.2.5](https://github.com/zlib-ng/zlib-ng/tree/2.2.5)。官方源码包为 2,417,402 字节、SHA-256 `5b3b022489f3ced82384f06db1e13ba148cbce38c7941e424d6cb414416acd18`。使用 level 9、zlib 兼容接口、固定通用 C 路径；禁用测试、动态库和 CPU 指令选择。该 encoder 与 [.NET 10 的同源版本](https://raw.githubusercontent.com/dotnet/runtime/v10.0.0/src/native/external/zlib-ng/zlib.h.in)对应。Windows 使用原 PowerShell/.NET ZLibStream 路径；所有平台都必须通过同一压缩摘要，不能因平台变化接受另一个压缩流。

写出前再次验证 packed 长度及 SHA，完整 zlib 流末尾、解压字节、逆 shuffle 和原始 semantic SHA。缓存损坏会重新下载或重新生成；错误或不匹配不会覆盖最终资产。原官方 MediaPipe LICENSE、工具所用 zlib-ng LICENSE（Unix）及固定来源/输出清单写入 `Assets/third-party/portrait`。

Windows 空缓存实际网络准备已执行通过，未读原 assets；另用独立编译的 zlib-ng 2.2.5 验证 level 9，产生相同 `9920…`。macOS 源构建与后续推理由主任务 Apple CI 验证；模型文件准备成功本身不代替原生推理验收。
