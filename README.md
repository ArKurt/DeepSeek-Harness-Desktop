# DeepSeek Desktop

把 DeepSeek Harness 的 Web UI 打包成本地桌面应用：App 启动时自动用内置的
Node 运行时拉起本地服务器（默认端口 3080），并用原生 WebView 全屏承载界面。
无需打开浏览器，也无需手动启动 `dsh web`。

## 安装

把 `DeepSeek.app` 拖进「应用程序」即可。

- 首次打开若提示「无法验证开发者」：右键图标 →「打开」，或在
  「系统设置 → 隐私与安全性」中点击「仍要打开」。
- 要求：Apple 芯片（Apple Silicon）macOS 15 及以上。

## 使用

- 双击启动：先显示**皮克斯片头风格**的启动动画（字母逐个弹入拼出 "DeepSeek" →
  黑鲸鱼蹦跳进场把字母踩扁再弹回 → 浮现作者名 **by Condex**），
  等待本地服务就绪后自动进入 DeepSeek 界面。
- 数据（会话/凭据）与命令行 `dsh` 共用 `~/.dsh`，两边互相同步。
- 端口已被占用（例如你已手动运行过 `dsh web`）：App 会直接连接已有服务。
- `⌘R` 刷新页面。

## 防篡改

- App 启动时会自校验关键文件（Info.plist、图标、启动素材、dsh 启动脚本）的 SHA256，
  与构建时的值不一致即弹出警告并拒绝启动 —— 别人拿到安装包后改任何内容都会被拦下。
- `codesign --verify DeepSeek.app` 也能检测包内文件是否被改动。

## 高级

- `DSH_DESKTOP_PORT` 环境变量可改端口（默认 3080）。
- 退出 App 时，由 App 拉起的服务器会一并关闭；外部已有的服务器不受影响。

## 重新构建（开发者）

```bash
./make-icon.sh          # 生成图标（只需一次）
./build.sh              # 编译 + 捆绑运行时 + 签名 + 出 DMG
./build.sh --install    # 并安装到 /Applications
```

需要 Xcode 命令行工具 + Node（构建时用本机 node 二进制捆绑进 App）。
