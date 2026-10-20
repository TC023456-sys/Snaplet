# Snaplet — macshot 修改版

基于 [sw33tLie/macshot v4.3.0](https://github.com/sw33tLie/macshot/tree/v4.3.0)，上游固定提交为 `5b762998a1520f90b702953c6b6460772800d6f4`。由 TC023456-sys 独立维护，非上游官方发布。

## 功能

- 单个剪贴板项目提供 PNG、TIFF 和文件 URL，避免部分应用将一次复制识别为两个附件；在 Finder 中按 ⌘V 可粘贴为 PNG。
- Finder 复制缓存保留最近 1 / 5 / 10 / 20 张，默认 1 张。下次成功复制时清理旧缓存，保留当前图片。不触碰截图历史、已保存图片、无关文件、目录或符号链接。
- 在“设置 → 捕获 → 输出”点击“在 Finder 中打开”管理缓存。删除当前复制文件后，需要重新复制才能继续在 Finder 粘贴。
- 原生 AppKit 设置：侧栏、浅深色与跟随系统、简洁分组及可展开高级选项。来源、维护者和许可集中在“关于”。
- 保留 Esc 取消、回车确认修复；文字编辑时回车仍用于文字输入。
- 闲置时释放设置窗口和截图表面；正在截图或录制时不释放，不删除用户历史。

版本变更见 `RELEASE-NOTES.md`，公开下载以 [Releases](https://github.com/TC023456-sys/Snaplet/releases) 为准。草稿和本地修改不等于公开更新。

## 安装、更新与授权

下载 `MacShot-Finder.zip`，解压后将 `Snaplet.app` 放入“应用程序”。安装前退出并移走同标识旧应用，避免两份同时运行。旧包文件名、内部模块、应用标识和 `macshot://` 协议为兼容设置与更新而保留，不是废弃资源。

使用临时签名（ad-hoc），未经 Apple 公证，不使用用户钥匙串签名。首次启动或更新后可能需要重新登记录屏权限，不能保证跨版本继承。确认来源后按 macOS 提示允许打开；不要关闭系统安全保护或重置其他应用权限。

截图先尝试实际 ScreenCaptureKit 捕获，失败后才提示授权；不会以否定预检结果单独阻止截图，也不会绕过系统授权。

更新服务只读取 `TC023456-sys/Snaplet` 的匹配发布，忽略草稿和其他项目。自动检查至多每天一次，可在设置关闭；发现新版后打开下载页，由用户安装，不静默替换应用。

## 实现与验证

- `FinderClipboard.swift` 在沙盒缓存创建权限为 0600 的 PNG，通过单个 NSPasteboardItem 提供图片与文件表示。缓存可能包含敏感截图，可按需清理。
- 后台编码和写文件保留剪贴板世代检查，避免慢任务覆盖后来复制的内容。写文件失败时仍可复制图片，过期任务的文件会删除。
- `redesign-settings.py` 复用原设置控件和处理函数，移除被侧栏替代的工具栏与未显示控件，不改变已保存设置。
- 测试涵盖品牌资源、设置集成、AppKit 控件路由、键盘事件、隔离剪贴板、缓存保留和更新筛选。CI 另执行上游测试及通用 Release 构建。
- 接口测试不代替各聊天软件的端到端验证；不承诺解决微信窗口在截图期间消失的问题。

## 从源码构建

需要完整 Xcode 26，自动步骤见 `.github/workflows/macshot-finder.yml`：

1. 克隆并核对上游固定提交。
2. 依次应用 `finder-paste.patch` 和 `maintainer-attribution.patch`。
3. 依次运行 `python3 brand-snaplet.py <source>`、`python3 redesign-settings.py <source>`、`python3 cleanup-source.py <source>`、`python3 preserve-popups.py <source>` 和 `python3 optimize-capture.py <source>`。清理旧更新与授权残留，修复授权按钮布局，并将截图窗口创建、预热延后到实际取图之后。
4. 在 `preserve-popups.py` 之后、`optimize-capture.py` 之前应用 `capture-recovery.patch` 和 `overlay-warmup.patch`，并将 `CaptureDeadline.swift` 复制到 `macshot/Services/`。运行 `capture-deadline-tests.swift` 检查超时、迟到与重复回调。将 `FinderClipboard.swift` 和 `ForkUpdateService.swift` 复制到 `macshot/Services/`。设置辅助文件由改版脚本复制。
5. 运行测试，编译并强制链接 `keyboard/EscapeFix.m` 的通用静态库，再构建 `macshot` scheme。
6. 将外部包命名为 `Snaplet.app`，临时签名，打包安装包、完整修改后源码及校验值。普通提交只构建并上传 Actions 产物；验证且更新版本号与标签后，手动运行工作流并选择 `publish` 才公开发布（本次经授权的 finder.14 发布提交另有精确消息匹配入口），拒绝覆盖已发布的安装包。

Release 源码包的 `SnapletFork` 目录保留品牌脚本、资源、键盘代码、测试与补丁，便于重现构建。

### 截图资源优化（待打包验证）

- macOS 26 的矩形单帧截图不提前枚举共享窗口；窗口截图仍可按需查询。
- 整屏静态截图仅抓取鼠标所在显示器，SCK 和旧接口回退使用同一范围。普通框选及录制保持全屏幕支持，不降低原图分辨率。
- 控制器仅为成功返回的屏幕截图创建；结束截图后不重新加载自定义背景，下次安装截图时再恢复。
- `capture-efficiency-test.py` 检查实际生成源码的取图范围、主屏原点、Retina 尺寸、回退和背景加载时机。未完成新版整包及多显示器运行对比前，不宣称具体 CPU、内存或延迟收益。

## 许可

上游作者及贡献者：sw33tLie/macshot contributors。本修改版按 **GPL-3.0** 发布，见 `LICENSE`。完整对应源码随发布提供，第三方依赖保留各自许可证。
