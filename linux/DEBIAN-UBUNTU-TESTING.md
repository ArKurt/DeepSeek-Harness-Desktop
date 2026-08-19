# Debian / Ubuntu 测试计划

> 状态：**计划书，尚未进入 PR**。
> 本文件提交在 fork 的 `debian-ubuntu-test-plan` 分支上，验证完成前不会合并回
> `linux`，因此 PR #5（head = `ArKurt:linux`）不会包含本文档。

## 目标

验证 Linux 桌面版在 Debian / Ubuntu 上的安装与运行，并打出 `.deb`。
AppImage / tar.gz 冒烟是基线；`.deb` 通过后再把打包目标合进 `linux`。

## 测试矩阵

| 发行版 | 优先测试项 |
|--------|------------|
| Debian 13 | tar.gz 冒烟、AppImage 冒烟、GUI、apt 安装 .deb（当前实机） |
| Debian 12 | tar.gz 冒烟、AppImage 冒烟、GUI 启动、本地构建 .deb |
| Ubuntu 22.04 | tar.gz 冒烟、AppImage 冒烟、GUI 启动 |
| Ubuntu 24.04 | tar.gz 冒烟、AppImage 冒烟、GUI 启动 |

## 1. 获取测试产物

PR 的 **Build Linux** 工作流 Artifacts `DeepSeek-Linux` 中包含：

- `DeepSeek-1.0.1-x86_64.AppImage`
- `DeepSeek-1.0.1-x64.tar.gz`

`.deb` 目前只在本分支本地打（不进 CI，避免改动 PR #5）：

```bash
# Arch / CachyOS 构建机需要 fpm 的 libcrypt.so.1 兼容库（不要把 .so.1 软链到 .so.2）
sudo pacman -S libxcrypt-compat
# 若暂时不能 sudo：从官方仓库解出 libxcrypt-compat，构建时设置
# LD_LIBRARY_PATH=<extract>/usr/lib

git clone --branch debian-ubuntu-test-plan https://github.com/ArKurt/DeepSeek-Harness-Desktop
cd DeepSeek-Harness-Desktop/linux
./build-linux.sh --runtime-only
./build-linux.sh --skip-runtime
# 产物含 AppImage、tar.gz、DeepSeek-1.0.1-amd64.deb
```

不要在 2 核 / 4GB 的 Debian 测试 VM 上跑完整 `build-linux.sh`。

Arch 上现场编译的 `node-pty` 会链到本机 glibc（CachyOS 为 2.42）。Debian 13 是 glibc 2.41，
装上后冒烟会报 `GLIBC_2.42 not found`。发往 Debian/Ubuntu 的包应在
`ubuntu-latest`（或同等旧 glibc）上组装 runtime；本机验证时可把 CI/发行版
产物里的 `node-pty/build/Release/pty.node` 换进 `linux/runtime` 后再打 `.deb`。

## 2. 安装运行时依赖

Debian 12 / Ubuntu 22.04：

```bash
sudo apt-get update
sudo apt-get install -y libfuse2 libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 \
  libatspi2.0-0 libuuid1 libsecret-1-0 libgbm1 libasound2 libxkbcommon0 libdrm2 xvfb
```

Debian 13 / Ubuntu 24.04（t64 包名）：

```bash
sudo apt-get update
sudo apt-get install -y libfuse2t64 libgtk-3-0t64 libnotify4 libnss3 libxss1 libxtst6 \
  libatspi2.0-0t64 libuuid1 libsecret-1-0 libgbm1 libasound2t64 libxkbcommon0 libdrm2 xvfb
```

## 3. 无头冒烟测试

### tar.gz 版

```bash
tar -xzf DeepSeek-1.0.1-x64.tar.gz
cd DeepSeek-1.0.1-x64

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-debian-smoke \
  ./deepseek --smoke-test --no-sandbox --disable-gpu
```

### AppImage 版

AppImage 运行时会把 `--smoke-test` 吃掉（`bad option`，退出码 9）。必须加 `--`：

```bash
chmod +x DeepSeek-1.0.1-x86_64.AppImage

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-debian-smoke \
  ./DeepSeek-1.0.1-x86_64.AppImage --no-sandbox --disable-gpu -- --smoke-test
```

FUSE 不可用时：

```bash
APPIMAGE_EXTRACT_AND_RUN=1 \
  ./DeepSeek-1.0.1-x86_64.AppImage --no-sandbox --disable-gpu -- --smoke-test
```

通过标准：

- 输出 `DSH_SMOKE_READY port=3099 reused=false`
- 输出 `DSH_SMOKE_CLEAN`
- 退出码 `0`

## 4. GUI 实机测试

```bash
DSH_DESKTOP_HOME=/tmp/dsh-gui ./deepseek
```

检查点：

1. 启动动画结束后出现主窗口，可以输入 API / 加载对话。
2. 关闭窗口后服务被清理：`pgrep -af 'bin.js web'` 为空。
3. 日志在 `${XDG_STATE_HOME:-~/.local/state}/deepseek/server.log`。
4. 若 `3080` 端口已有服务，桌面版复用且退出时不关闭它，属预期行为。
5. niri / 纯 Wayland 上欢迎屏闪退后进程退出是已知问题（`linux` 已修）；Debian 13 + Xfce/X11 上发行版 AppImage 可正常切到主窗口。

中文界面缺字（小方块）时安装 `fonts-noto-cjk fonts-noto-color-emoji`。

## 5. 安装 .deb（推荐：Arch 构建，Debian 只装）

用户级 AppImage 启动器 `~/.local/bin/deepseek` 会抢 PATH。装 .deb 前先卸掉：

```bash
cd linux
./install-linux.sh --uninstall
```

若菜单里 DeepSeek 没有图标：多半是卸载后留下了
`~/.local/share/icons/hicolor/icon-theme.cache`。删掉该文件，或重新跑一次
带图标缓存刷新的 `install-linux.sh --uninstall`，然后注销/重开一次菜单。

然后：

```bash
sudo apt install -y ./dist/DeepSeek-1.0.1-amd64.deb

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-deb-smoke \
  deepseek --no-sandbox --disable-gpu --smoke-test
```

检查系统菜单：`/usr/share/applications/deepseek.desktop`，可执行文件默认在
`/opt/DeepSeek/deepseek`。会话数据仍是 `~/.dsh`。

卸载：

```bash
sudo apt remove deepseek-harness-desktop
```

## 6. 后续收尾

- 测试通过后，再把 `.deb` 打包目标与多发行版 CI 矩阵加入 `linux` 分支并推送
  （此时 PR #5 才会更新）。
- 需要支持 Debian 12 / Ubuntu 22.04 / 24.04 时，CI 可使用 Docker 容器矩阵：
  `ubuntu:22.04`、`ubuntu:24.04`、`debian:12`、`debian:13`。
- 在 CI 中执行“`apt install ./...deb` → `deepseek --smoke-test`”，
  模拟真实用户的安装与启动路径。
