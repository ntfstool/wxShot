<h1 align="center">wxShot</h1>

<p align="center"><b>微信截图替代品 · 不登录微信也能用的 macOS 截图工具</b><br>
The WeChat-style screenshot for macOS that works when WeChat is not signed in.</p>

<p align="center">
  <a href="https://github.com/ntfstool/wxShot/releases/latest"><b>Download / 下载</b></a> ·
  <a href="https://ntfstool.com/wxshot/">ntfstool.com/wxshot</a> ·
  macOS 14+ · Apple Silicon & Intel · MIT
</p>

## 中文

微信没登录、没打开，就不能截图？wxShot 是一个常驻后台的原生 macOS 截图工具，**手感和微信截图一样**，完全免费、不上传任何截图、安装包不到 4 MB。

- **同款操作**：默认快捷键 `⌥A`；拖动框选，窗口自动吸附；工具栏在选区右下角；双击或回车复制；`Esc` 退出。
- **同款标注**：矩形、圆形、箭头、画笔、马赛克、文字、序号、撤销。
- **长截图**：在选区里滚动，边滚边拼。
- **提取文字**：用 macOS 自带的 Vision 离线识别，数据不出本机。
- **贴图**：把截图钉在所有窗口之上。
- **和微信共存**：微信没运行或没登录时由 wxShot 截图；微信登录后默认交还给微信，也可以在设置里改成始终使用 wxShot。
- **隐形后台**：无 Dock 图标、默认无菜单栏图标；再次打开 App 即进入设置。

### 隐私
不联网上传截图、文字或文件。仅在安装后的前几个检查点发送匿名存活信息（随机安装编号、版本、系统、语言、微信是否运行），可在设置中关闭。源码即证明。

### 安装
```bash
brew install --cask wxshot   # Homebrew 收录后可用
```
或在 [Releases](https://github.com/ntfstool/wxShot/releases/latest) 下载 `wxShot.dmg`（已签名并公证）。首次启动按提示允许「屏幕录制」。

## English

WeChat's built-in screenshot only works while WeChat is running and signed in. wxShot is a tiny native background app with the same feel: drag to select, windows snap, double-click or Return copies, Esc cancels. It adds long screenshots, offline text extraction (Apple Vision) and pinning. Free, MIT, no screenshot ever leaves your Mac.

Default shortcut `⌥A`. When WeChat is signed in, wxShot hands the shortcut back to WeChat by default (configurable).

## Build
```bash
swift build && swift test
scripts/build.sh            # dist/wxShot.app
```

## Credits
PermissionFlow is vendored under `ThirdParty/`.

wxShot is an independent project and is not affiliated with Tencent. "WeChat" is a trademark of its owner and is used only to describe compatibility.
