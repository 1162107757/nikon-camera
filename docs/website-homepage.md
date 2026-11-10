# Huevia 官网与后台入口 · 2026-11-07

后续更新（2026-11-08）：当前公开测试版已为 156。官网首屏、下载区和完整下载页新增 [iOS 正在准备中](validation/ios-download-20261108/README.md)入口，并完成[下载 JSON 错误修复](validation/download-json-20261108/README.md)。下文的 115 身份、目录与验收数量保留为首次迁移当时的记录。

已按用户要求上线：

| 用途 | 地址 |
| --- | --- |
| 产品介绍与 Android 下载 | https://huevia.cc/ |
| 管理后台 | https://admin.huevia.cc/ |
| 原后台入口 | https://huevia.cc/preset-library/admin/，302 转到新后台 |
| 既有完整下载页 | https://huevia.cc/preset-library/download/?channel=beta |

根域名现在提供产品介绍、摄影题材展示、照片工作流说明、版本渠道、下载、校验信息、手机二维码与常见问题。页面按正式版/测试版读取既有 release API；无正式版时明确提示可用测试版。当前公开版本仍是 **0.23.4-beta（115）**，9,531,300 字节，SHA-256 `ae2f90cf0580f265a893036b2977c9b36547b2b3000c4a6296e69c43249721c2`。本轮没有发布155或更改已发布版本、更新策略、预设记录。开发版155的界面截图明确标注“开发版本界面预览 · 演示预设”，不冒充当前公开版本截图。

## 文件与部署

网页源码在 [online-library/home](../online-library/home/index.html)，包括自托管 Outfit 字体及 OFL 许可、来自已收集摄影样片的6张素材、开发版界面 WebP、静态官网二维码与来源页。整个部署 ZIP 为672,256字节，SHA-256 `cc005874d1d6af361baed110733fe87a9407d1cb7f86d001eb0193e403761a8c`。摄影署名、许可及截图来源在 [asset-sources.json](../online-library/home/asset-sources.json)。截图只缩放和压缩；没有把摄影题材照片当成配方的真实相机试拍。

部署到原有轻量服务器 `118.24.164.117` / 成都 `lhins-ohyn9xlu`，Caddy 主配置仍 import `/etc/caddy/huevia.caddy`，其他站点未改。新增 DNS `admin / A / 118.24.164.117 / 默认 / TTL600`，原根域名A与两条验证TXT保持。新后台由Caddy自动申请HTTPS证书。

网页目录为 `/var/www/huevia-home/releases/20261107-v1`，`/var/www/huevia-home/current` 指向该目录。配置源为 [huevia.caddy](../online-library/infra/lighthouse/huevia.caddy)，服务器已启用配置的SHA-256为 `4fff434b6f048d3486c1adfb188693fa0dfe67dfffe9a531fecbfff891222414`；首页HTML的SHA-256为 `c6348d927611c5f71940bf5c549ab3f6493f947530c87a6e67f67569f29d7967`。

先阶段启用新后台并保留旧根路径，验证新后台HTTPS可访问后再激活根域首页。两次均先运行Caddy主配置校验，再reload；校验或reload失败会恢复该阶段之前的配置。执行脚本见 [deploy-home.sh](../online-library/infra/lighthouse/deploy-home.sh)。站点包经私有存储认证回读及SHA核对后，由只读限时包链接传至该服务器；链接只授权读取公开网页素材包，不包含服务凭据。

腾讯云CLI登录过期后由用户完成授权。新版CLI身份无法管理DNS，且其区域校验不支持成都TAT调用，故DNS及服务器命令通过已登录腾讯云控制台完成；未扩大云端权限或创建API密钥。云函数仅增补 `ALLOWED_BROWSER_ORIGINS=https://huevia.cc,https://admin.huevia.cc`，其余9个变量的完整值保留，未部署函数代码。明文快照只在被Git忽略的 `.local/homepage-migration/` 中；公开验证仅记录哈希，见 [admin-origin.json](validation/homepage-20261107/admin-origin.json)。

## 兼容与验证

`/preset-library` 下的既有App接口、公开目录、文件及下载路由继续代理原CloudBase。只有原后台HTML/静态资源入口转到admin子域。后台Cookie仍为原服务的安全Host-only会话，新域名需用现有账号密码重新登录。没有更改管理员密码或用户权限。

公网检查 [18项全部通过](validation/homepage-20261107/live-verification.json)：根域首页、静态资源、旧后台跳转、新后台登录页与有效HTTPS、管理API未登录401、合法新Origin仍需认证、非信任Origin403、既有健康接口、390份预设目录、已发布版本身份不变，以及完整9,531,300字节APK经标准307签名下载跳转后的SHA校验。下载校验URL仅认可当前站点或原发布服务的固定release路径；2组Node测试覆盖大于32MiB包及不受信任地址/畸形身份拒绝。

曾用本地最初管理员凭据尝试新域登录一次，返回401；该旧凭据已不是当前密码。本轮未猜测、重置或改变密码，也不声称验证了管理员实际登录成功。验证了新Origin允许进入原鉴权流程，未登录管理数据仍受保护。

Chrome实际检查了本地390px宽度无横向溢出、图片全部加载，线上桌面2048px无横向溢出、正式版空状态与测试版切换、FAQ展开、真实版本下载链接及新后台登录页。Edge独立渲染保留了线上1440px桌面和500px移动布局截图；较窄的headless窗口被Edge最小宽度限制，未将其冒充390px截图。临时浏览器视口已复位，云控制台中间页已关闭，官网和新后台标签页作为交付保留。

![线上首页](validation/homepage-20261107/desktop.png)

## 回退

原配置保留于服务器 `/etc/caddy/huevia.caddy.before-homepage-20261107`。需要回退入口时，将其复制回 `/etc/caddy/huevia.caddy`，先校验 `/etc/caddy/Caddyfile`，再reload Caddy。静态版本目录可保留以便恢复；不要覆盖其他站点的主配置，也不要删除既有根域A、验证TXT或CloudBase绑定。本轮没有变更Android源码或154/155冻结安装包。
