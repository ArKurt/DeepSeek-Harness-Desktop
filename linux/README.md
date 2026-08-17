# DeepSeek Desktop — Linux 版

Linux 桌面壳：Electron + 内置 Node.js/dsh 运行时，自动拉起 `dsh web` 并用
Chromium 窗口承载 Web UI。开发与测试环境为 **Garuda Mokka / Arch Linux**。

## ✨ 特性

- Electron 原生窗口，无浏览器依赖（Chromium 内置在 Electron 运行时中）
- 内置 Node.js v24 + `dsh` 包，启动时自动拉起本地服务
- 启动动画：鲸鱼 logo + "DeepSeek Harness / for Linux" + by Condex（约 5.2 秒）
- 单实例锁：重复启动会聚焦已打开的窗口
- 智能服务生命周期：端口已有服务则复用，退出时只清理自己拉起的进程
- 防篡改：启动时校验 `runtime/integrity.json` 中关键文件的 SHA256
- 数据互通：与命令行 `dsh` 共用 `~/.dsh`
- 日志：`${XDG_STATE_HOME:-~/.local/state}/deepseek/server.log`

## 📦 分发形式

| 文件 | 说明 |
|------|------|
| `DeepSeek-1.0.1-x86_64.AppImage` | 开箱即用 AppImage（内置 Electron + Node + dsh） |
| `DeepSeek-1.0.1-x64.tar.gz` | 解压后运行 `./deepseek` 的绿色版 |
| Arch PKGBUILD | Garuda/Arch 系统包，使用系统 electron + nodejs |

GitHub Actions 产物与 Release 中文件名以实际构建为准。

## 🔧 开发 / 构建

```bash
# 1. 组装运行时（下载 Node v24 + 安装 dsh；Linux 会现场编译 node-pty）
cd linux
./build-linux.sh --runtime-only

# 2. 本机开发运行（使用系统 electron）
DSH_DESKTOP_DEV=1 electron .

# 3. 打 AppImage + tar.gz（需要网络下载 Electron）
./build-linux.sh --skip-runtime
```

### 仅本机快速使用

```bash
cd linux
./build-linux.sh --runtime-only --system-node
DSH_DESKTOP_DEV=1 electron .
```

> 构建路径若包含空格，`build-linux.sh` 会自动在无空格临时目录创建符号链接
> 继续构建（产物仍写回原目录），无需手动搬迁项目；`mktemp` 不可用时才需要
> 把项目放到无空格路径。

### Garuda / Arch 安装

```bash
cd linux/arch
makepkg -si
# 或使用仓库提供的 AppImage
```

## ⚙️ 环境变量

- `DSH_DESKTOP_PORT`：目标端口，默认 `3080`
- `DSH_DESKTOP_HOME`：dsh 数据目录，默认 `~/.dsh`
- `DSH_DESKTOP_NODE`：自定义 Node 可执行文件（优先于内置 node）
- `DSH_DESKTOP_RUNTIME`：自定义 runtime 目录（包含 `bundle/.../bin.js`）
- `DSH_DESKTOP_DEV=1`：开发模式（跳过完整性清单、显示开发者工具菜单）

## ⚠️ 注意事项

- 插件与命令行共用 `~/.dsh/profiles/web`，详见仓库根目录 `PLUGINS.md`
- 不要用 `kill -9` 直接杀主进程；正常退出会走 SIGTERM → SIGKILL 清理进程组
- AppImage 若无法启动，可尝试 `./DeepSeek-*.AppImage --appimage-extract-and-run`
