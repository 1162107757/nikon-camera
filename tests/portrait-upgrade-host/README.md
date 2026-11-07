# 人像精修 131 主机检查

在项目根目录用 PowerShell 执行：

```powershell
& './tests/portrait-upgrade-host/run-host.ps1' -JdkRoot 'D:/dev/Java/jdk-17.0.19'
```

使用生产 Java 类，以 `-Xmx96m` 运行 10 组测试；结果输出到 `.tooling/portrait131/host`。检查精修参数保存与旧字节兼容、局部像素/alpha 保持、五官擦除范围、补光方向、实际背景保护变形，以及现有调色/人像/蒙版回归。逐像素断言次数不等同于场景数。

最终冻结记录见 `docs/validation/portrait131`。虚拟大图行处理不代表实体手机完整图像内存或帧率。
