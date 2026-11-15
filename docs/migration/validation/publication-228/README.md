# Huevia228 公开下载记录

按用户后续要求将原本地测试包上传至既有beta渠道。Android ARM64与iOS未签名IPA均经服务端重新检查，再从公开地址下载并逐字节/SHA比对；均匹配冻结源码734aa3b0f6687dda815af9e13070f0f3c463873c。

23条原先published的旧版记录通过带revision的正式withdraw API停用，现无公开旧版；连同原草稿和已下架条目，共33个旧版本地址在CloudBase与huevia.cc两域合计66次GET检查均404。没有删除安装包备份。

CloudBase下载页及huevia.cc/preset-library/download/已去掉原版/新版选择并默认当前Android；SCF线上压缩包只替换2个静态文件，另51个文件及运行配置未变。独立主站首页与下载页属于两套资源，状态以PUBLICATION.json的mainHomepageUpdated/complete为准。

页面与发布/撤回定向测试29通过、2个数据库外部环境测试按既有条件跳过、0失败。原应用724项Flutter/5UIKit/1Native等完整构建证明保持在features-228，未修改冻结记录。

主站首页已通过用户登录的腾讯云控制台完成原子切换，仅更新home.js和index.html，14个其他文件及Caddy配置保持。浏览器实测Android仅有一个安装包下载按钮，iOS显示当前228及自行签名提示。[Android实际页面截图](home-android-228.jpg)。

public-verification-partial.json保留首页登录前的检查，当前以public-verification.json完整结果为准：3个页面、6个版本查询、66个旧地址全部符合预期。
