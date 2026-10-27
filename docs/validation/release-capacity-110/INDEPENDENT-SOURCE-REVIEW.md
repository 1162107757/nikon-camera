# 大包签名重定向独立源审查

2026-10-27，`/root/release_size_compatibility/redirect_security_review` 仅阅读源码与测试，未修改文件、访问网络、读取凭据、部署或操作存储。

结论：未发现必须修复的安全或兼容阻断。

- 签名 URL 仅固定 HTTPS Storage API origin、exact bucket 和 SHA 物理对象；服务凭据仅进签名 POST，禁止鉴权请求跟随外部重定向。
- Provider query 只接受单 token，检查短期 exp 后，仅从不可变版本身份追加严格 APK 文件名；测试覆盖恶意 host/path/query、密钥 echo、过期/超长 TTL 和文件名注入。
- 大包核验真实私有对象长度/SHA、原预算、签名前后发布状态及零正文 307；读取/签名中撤回均覆盖。
- 新对象 `.bin`/octet；017 兼容旧 `.apk`，明确替换 006 的旧跨列 CHECK 名，保留原 immutable、预算与权限。

发布仍需实际大包回读及 Android DownloadManager 307 验证。已发签名链接在短期有效窗口内仍可能可读，文档应保持该事实。
