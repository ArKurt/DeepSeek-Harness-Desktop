# Debian / Ubuntu 测试计划

> 状态：**计划书，尚未进入 PR**。
> 本文件提交在 fork 的 `debian-ubuntu-test-plan` 分支上，验证完成前不会合并回
> `linux`，因此 PR #5（head = `ArKurt:linux`）不会包含本文档。

## 目标

验证 Linux 桌面版在 Debian / Ubuntu 上的安装与运行，为上游作者要求的
`.deb` 安装包做准备。

## 测试矩阵

| 发行版 | 优先测试项 |
|--------|------------|
| Debian 12 | tar.gz 冒烟、AppImage 冒烟、GUI 启动、本地构建 .deb |
| Ubuntu 22.04 | tar.gz 冒烟、AppImage 冒烟、GUI 启动 |
| Ubuntu 24.04 | tar.gz 冒烟、AppImage 冒烟、GUI 启动 |

## 1. 获取测试产物

PR 的 **Build Linux** 工作流 Artifacts `DeepSeek-Linux` 中包含：

- `DeepSeek-1.0.1-x86_64.AppImage`
- `DeepSeek-1.0.1-x64.tar.gz`

也可以本地构建：

```bash
git clone --branch linux https://github.com/ArKurt/DeepSeek-Harness-Desktop
cd DeepSeek-Harness-Desktop/linux
./build-linux.sh --runtime-only
./build-linux.sh --skip-runtime
```

## 2. 安装运行时依赖

Debian 12 / Ubuntu 22.04：

```bash
sudo apt-get update
sudo apt-get install -y libfuse2 libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 \
  libatspi2.0-0 libuuid1 libsecret-1-0 libgbm1 libasound2 libxkbcommon0 libdrm2
```

Ubuntu 24.04（FUSE 包名不同）：

```bash
sudo apt-get update
sudo apt-get install -y libfuse2t64 libgtk-3-0 libnotify4 libnss3 libxss1 libxtst6 \
  libatspi2.0-0 libuuid1 libsecret-1-0 libgbm1 libasound2 libxkbcommon0 libdrm2
```

## 3. 无头冒烟测试

### tar.gz 版

```bash
tar -xzf DeepSeek-1.0.1-x64.tar.gz
cd <解压目录>

DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-debian-smoke \
  ./deepseek --smoke-test --no-sandbox --disable-gpu
```

### AppImage 版

```bash
chmod +x DeepSeek-1.0.1-x86_64.AppImage

DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-debian-smoke \
  ./DeepSeek-1.0.1-x86_64.AppImage --smoke-test --no-sandbox --disable-gpu
```

FUSE 不可用时：

```bash
APPIMAGE_EXTRACT_AND_RUN=1 \
  ./DeepSeek-1.0.1-x86_64.AppImage --smoke-test --no-sandbox --disable-gpu
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

## 5. 在 Debian / Ubuntu 上现场构建并安装 .deb

```bash
sudo apt-get install -y nodejs npm librsvg2-bin
git clone --branch linux https://github.com/ArKurt/DeepSeek-Harness-Desktop
cd DeepSeek-Harness-Desktop/linux

./build-linux.sh --runtime-only
./build-linux.sh --skip-runtime
npx electron-builder --linux deb
```

安装与冒烟：

```bash
sudo apt install -y ./dist/DeepSeek-1.0.1-amd64.deb

DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-deb-smoke \
  deepseek --smoke-test --no-sandbox --disable-gpu
```

卸载：

```bash
sudo apt remove deepseek-harness-desktop
```

## 6. 后续收尾

- 测试通过后，再把 `.deb` 打包目标与多发行版 CI 矩阵加入 `linux` 分支并推送
  （此时 PR #5 才会更新）。
- 需要支持 Debian 12 / Ubuntu 22.04 / 24.04 时，CI 可使用 Docker 容器矩阵：
  `ubuntu:22.04`、`ubuntu:24.04`、`debian:12`。
- 在 CI 中执行“`apt install ./...deb` → `deepseek --smoke-test`”，
  模拟真实用户的安装与启动路径。
