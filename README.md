# Snaplet

独立的 macOS 截图与标注项目，基于 sw33tLie/macshot v4.3.0（GPL-3.0），由 TC023456-sys 维护修改版。不是上游官方发布。

此项目仅包含 Snaplet：源码修改、品牌资源、键盘修复、测试及 GitHub Actions 构建流程。不包含 Retina Dummy 源码、MIT 许可证或发布工作流。

## 状态

本项目现已独立为 `TC023456-sys/Snaplet`。RetinaDummy 当前分支中的截图源码及截图构建流程已移除；旧的截图 Releases 和 Git 历史保留用于恢复和兼容旧版本。

新版下载见 [Releases](https://github.com/TC023456-sys/Snaplet/releases)。只有构建和测试成功后才发布安装包；未发布时请等待工作流完成。

## 构建

详见 `macshot-finder/README.md` 和 `.github/workflows/macshot-finder.yml`。工作流克隆固定上游版本、应用补丁、替换品牌图片、运行测试、构建并使用临时签名打包。上游来源、作者署名和 GPL 声明保留。

新发布版本为 `4.3.0-finder.8`，更新服务只读取 `TC023456-sys/Snaplet`。旧安装包文件名与标签前缀暂时保留，用于更新兼容。旧版本的更新地址不会因为远程迁移自动改变；需要安装独立项目的新版本。

## 迁移顺序

1. 创建同名公共仓库，上传此项目。
2. 验证 CI、完整对应源码及安装包；迁移旧 Snaplet 发布资料并核对文件摘要。
3. 从 RetinaDummy 当前分支移除 `macshot-finder` 和其构建工作流，保留显示器工具。
4. 旧下载迁移确认后清理旧发布资料，不改写 Git 提交历史。

设置页已加入原生 AppKit 改版实现：左侧导航、墨绿点缀、自适应分组卡片、右侧勾选控件、浅深色切换和可展开的自定义外观。构建时运行 `redesign-settings.py`，不使用 WebView 包装设计预览。

当前通过辅助组件 Swift 优化模式类型检查、生成控制器语法检查、原设置操作保留检查及品牌资源检查；完整 Release 构建和安装后的实际布局仍待验证。截图权限、快捷键与更新均需新安装包实测，不能以源代码检查代替。
