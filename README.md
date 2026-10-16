# Snaplet

独立的 macOS 截图与标注项目，基于 [sw33tLie/macshot v4.3.0](https://github.com/sw33tLie/macshot/tree/v4.3.0)（GPL-3.0），由 TC023456-sys 维护修改版。非上游官方发布。

本仓库仅包含 Snaplet 源码修改、品牌资源、键盘修复、测试及构建流程，不包含 Retina Dummy 项目。

## 下载与构建

公开安装包见 [Releases](https://github.com/TC023456-sys/Snaplet/releases)，版本变更见 `macshot-finder/RELEASE-NOTES.md`。草稿和本地修改不等于公开更新。

构建说明见 `macshot-finder/README.md`，自动步骤见 `.github/workflows/macshot-finder.yml`。流程克隆固定上游、应用补丁、替换品牌资源、执行测试并构建安装包及完整对应源码。原作者署名与 GPL 声明保留。

设置采用原生 AppKit 侧栏和简洁分组，支持浅深色及高级选项，不使用 WebView 包装预览。

更新服务只读取 `TC023456-sys/Snaplet`。旧包文件名、标签前缀及应用标识为兼容更新和现有设置而保留。临时签名版本更新后可能需要重新授予录屏权限；源码测试不代替安装后的权限验证。

## 自愿赞赏

好用的话，请我喝杯咖啡 ☕

<p><img src="wechat-donation.png" alt="微信赞赏码" width="220"></p>

软件免费使用，赞赏完全自愿，不影响功能，也不附带额外服务承诺。
