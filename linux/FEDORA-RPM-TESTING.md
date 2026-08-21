# Fedora / RPM 测试计划

> 状态：交叉验证已完成；Fedora 44 上 AppImage / tar.gz / **`.rpm` 无头冒烟与座舱 GUI
> 均已通过**（2026-08-21）；SELinux enforcing 下 `ausearch` **无 AVC 拒绝**。
> 配置已落地本分支。CI 待合并进触发分支后验证。

## 目标

1. 在 Fedora 上确认现有 **AppImage / tar.gz** 可冒烟、可 GUI（不依赖 RPM）。
2. 定稿 electron-builder 的 `rpm` 配置（尤其 `depends`），再真正打包。
3. 在 Fedora VM 上 `dnf install` 本地 `.rpm`，冒烟 + GUI，通过后再进 CI / Release。

AppImage / tar.gz 是基线；**.rpm 通过后再**把目标合进 `linux` 与工作流。

## 测试矩阵

| 发行版 | 优先测试项 | 状态 |
|--------|------------|------|
| Fedora 44 Workstation（VM `192.168.31.185`） | tar.gz / AppImage 冒烟、GUI、dnf 装 .rpm | 全部通过（含座舱 GUI；无 AVC） |
| Fedora 41（CI container 建议固定版） | `dnf install` + packaged smoke | 待 CI |
| openSUSE | 不承诺；rich deps 理论上可解析 | 非范围 |

实机记录（2026-08-21）：

| 项 | 值 |
|----|-----|
| `NAME` / `VERSION_ID` | Fedora Linux / 44 |
| glibc | 2.43（`ldd (GNU libc) 2.43`） |
| 内核 | `7.1.8-200.fc44.x86_64` |
| 桌面 | Hyprland（COPR）/ GNOME 可选 |
| 产物来源 | Cachy 本机 `linux/dist`（2026-08-18 构建）scp 至 `~/dsh-artifacts` |

## 0. 定稿配置（已落地本分支）

审查报告：`linux/FEDORA-RPM-TESTING-REVIEW.md`。下列项已写入仓库；CI 在合并到
`linux`/`main` 或手动 `workflow_dispatch` 后才会跑。

### 0.1 `linux/package.json`

- `scripts.dist` / `build.linux.target`：增加 `rpm`（x64）。
- 新增 `build.rpm`（整体替换默认 `depends`，不是追加）。

**定稿 `rpm.depends`：**

```json
"rpm": {
  "depends": [
    "gtk3",
    "libnotify",
    "nss",
    "xdg-utils",
    "at-spi2-core",
    "(libXtst or libXtst6)",
    "(libuuid or libuuid1)",
    "(libsecret or libsecret-1-0)",
    "(mesa-libgbm or libgbm1)",
    "(alsa-lib or libasound2)"
  ]
}
```

同步：`deb.depends` **删除 `libxss1`**（与 rpm 一致，见 §0.1.1）。

其他约定：

| 点 | 决定 |
|----|------|
| 风格 | electron-builder 式 rich deps：`(Fedora名 or openSUSE名)` |
| `libXScrnSaver` / `libxss1` | **两端都不写**（见 §0.1.1） |
| 包名 | `deepseek-harness-desktop`；卸载 `sudo dnf remove deepseek-harness-desktop` |
| 产物名 | `DeepSeek-1.0.1-x86_64.rpm`（`${arch}` → `x86_64`） |
| `executableArgs` | 沿用 `linux.executableArgs`：`--ozone-platform=x11`；装包后断言 `Exec=` |

#### 0.1.1 Q2：`ldd` 结果（2026-08-21，Cachy）

```bash
ldd linux/dist/linux-unpacked/deepseek | grep -iE 'Xss|Xscrn'
# → 无输出（NO_XSS_LINK）
```

同一 Electron 二进制不链 `libXss`。故 **rpm 不写 `libXScrnSaver`，deb 同步去掉 `libxss1`**。

### 0.2 `linux/build-linux.sh`

- `npx electron-builder --linux AppImage tar.gz deb rpm`
- 构建机：`sudo pacman -S libxcrypt-compat rpm-tools`，确认 `which rpmbuild`
- **不必**单独安装 fpm（electron-builder 自带下载；`libxcrypt-compat` 供其 `libcrypt.so.1`）

### 0.3 CI

- ubuntu-latest 打包：`sudo apt-get install -y rpm`（提供 `rpmbuild`），目标加 `rpm`，上传 `*.rpm`
- **另起** `smoke-rpm` job：`container: fedora:41`，`dnf install ./…rpm` →
  `grep -q -- '^Exec=.*--ozone-platform=x11' …` →
  `deepseek --smoke-test --ozone-platform=headless --no-sandbox --disable-gpu` →
  `grep -q DSH_SMOKE_CLEAN`

### 0.4 文档 / 承诺范围

- README：Fedora + `.rpm`；AppImage 兜底
- openSUSE：一句「未经测试，依赖理论上可解析」；**不提 RHEL**

## 1. 获取测试产物

```bash
# 构建机 Arch / CachyOS
sudo pacman -S libxcrypt-compat rpm-tools
# 确认 which rpmbuild；fpm 由 electron-builder 自带，勿单独装

cd linux
./build-linux.sh --runtime-only
./build-linux.sh --skip-runtime   # 定稿后应含 *.rpm
```

**不要在小规格 Fedora 测试 VM 上跑完整 `build-linux.sh`。**

### glibc / node-pty

发版 runtime 仍以 CI `ubuntu-latest` 组装为准。本轮 Fedora 44 glibc 2.43，
对本机构建的 Aug-18 产物无头冒烟已通过，未见 `GLIBC_* not found`。

## 2. Fedora 运行时依赖

```bash
sudo dnf install -y xorg-x11-server-Xvfb fuse fuse-libs \
  gtk3 libnotify nss libXtst at-spi2-core libuuid libsecret \
  mesa-libgbm alsa-lib libdrm libxcb libxkbcommon nss-util \
  google-noto-sans-cjk-fonts google-noto-emoji-fonts
```

> 可选：`libXScrnSaver` 仅当运行时报缺库再装；**不要**写进 RPM `Requires`。

本轮 VM 已按上表安装（含 fuse-libs、Xvfb）。

## 3. 无头冒烟（基线）— 已通过

### tar.gz

```bash
tar -xzf DeepSeek-1.0.1-x64.tar.gz
cd DeepSeek-1.0.1-x64

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-fedora-smoke \
  ./deepseek --smoke-test --no-sandbox --disable-gpu
```

**结果（Fedora 44）：** `DSH_SMOKE_READY port=3099 reused=false` + `DSH_SMOKE_CLEAN`。

### AppImage

应用参数 `--smoke-test` 必须加 `--` 分隔；wrapper / 运行时注入的
`--ozone-platform=x11` 属运行时参数（与 `DEBIAN-UBUNTU-TESTING.md` 一致）。
保险写法：

```bash
chmod +x DeepSeek-1.0.1-x86_64.AppImage

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-fedora-smoke \
  ./DeepSeek-1.0.1-x86_64.AppImage --no-sandbox --disable-gpu -- --smoke-test
```

FUSE 不可用：

```bash
APPIMAGE_EXTRACT_AND_RUN=1 \
  ./DeepSeek-1.0.1-x86_64.AppImage --no-sandbox --disable-gpu -- --smoke-test
```

**结果（Fedora 44）：** FUSE 直跑即通过（`DSH_SMOKE_READY` + `DSH_SMOKE_CLEAN`）。

通过标准：

- stdout 含 `DSH_SMOKE_READY port=3099 reused=false`
- stdout 含 `DSH_SMOKE_CLEAN`
- 退出码 `0`（仅退出码不够：单实例锁命中时也会返回 0）

## 4. GUI 实机 — 已通过（座舱）

在 **图形会话本机终端**（非纯 SSH）执行：

```bash
DSH_DESKTOP_HOME=/tmp/dsh-fedora-gui ./deepseek --ozone-platform=x11
```

检查点：

1. 启动动画后主窗口可用。
2. 关窗后 `pgrep -af 'bin.js web'` 为空。
3. 日志：`${XDG_STATE_HOME:-~/.local/state}/deepseek/server.log`。
4. 端口已被占用时复用、退出不杀外来服务，属预期。
5. 记录会话：Hyprland / GNOME；是否需 `--ozone-platform=x11`。

**结果（2026-08-21）：**

- 座舱 GUI 已通过；关窗后可再开；`ausearch` 无 deepseek AVC。
- **Hyprland 0.56.2：** 包默认 `--ozone-platform=x11` 会起进程但不出窗；改为
  `--ozone-platform=wayland` 后正常。用户级覆盖已写在
  `~/.local/share/applications/deepseek.desktop`（不改系统 rpm）。
- SSH / 无 `$DISPLAY`/`$WAYLAND_DISPLAY` 的终端会直接报 Missing X / Wayland 并可能
  coredump，不能当 GUI 失败证据。
- GNOME 会话本次未完成对照（登录异常，暂搁）。

## 5. 安装 .rpm（配置落地并打出包之后）

```bash
# 若曾装用户级 AppImage 启动器
./install-linux.sh --uninstall

sudo dnf install -y ./dist/DeepSeek-1.0.1-x86_64.rpm

grep -q -- '^Exec=.*--ozone-platform=x11' /usr/share/applications/deepseek.desktop
ls -l /usr/bin/deepseek /opt/DeepSeek/deepseek

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-rpm-smoke \
  deepseek --smoke-test --ozone-platform=headless --no-sandbox --disable-gpu
# 断言：DSH_SMOKE_READY + DSH_SMOKE_CLEAN
```

GUI（座舱）+ SELinux：

```bash
# 故意不加 --no-sandbox
DSH_DESKTOP_HOME=/tmp/dsh-rpm-gui deepseek --ozone-platform=x11
sudo ausearch -m AVC -ts recent | grep -i deepseek || echo "无 AVC 拒绝"
```

首次打包后必做：

```bash
rpm -qpR ./dist/DeepSeek-1.0.1-x86_64.rpm
```

看是否出现自动 soname（如 `libgbm.so.1()(64bit)`）；若没有，手写 `depends` 是唯一防线。

卸载：`sudo dnf remove deepseek-harness-desktop`。  
不要用 `--nodeps` 当通过标准。

## 6. 交叉验证结论（已裁决）

| # | 问题 | 结论 |
|---|------|------|
| Q1 | 先基线再打 RPM | **同意**；无头基线已完成 |
| Q2 | `libXScrnSaver` | **`ldd` 无链接 → rpm/deb 两端都不写** |
| Q3 | depends 风格 | **rich deps（Fedora or openSUSE 包名）** |
| Q4 | Arch 构建 + Fedora 装测 | **可接受**；只需 `rpm-tools` + `libxcrypt-compat` |
| Q5 | CI | **选 B**：`fedora:41` container 安装冒烟 |
| Q6 | 产物命名 | **够用** |
| Q7 | 承诺范围 | **只承诺 Fedora + AppImage**；openSUSE 免责一句；不提 RHEL |
| Q8 | SELinux | **加 AVC 实机检查**，无实测不写说明段落 |

审查指出的拟议清单硬伤（已并入 §0.1）：

- `(mesa-libgbm or libgbm.so.1)` → `(mesa-libgbm or libgbm1)`
- `(libXtst or libXtst.so.6)` → `(libXtst or libXtst6)`

## 7. 通过标准与收尾

基线：

- [x] Fedora VM：`os-release` + glibc 已记录（44 / 2.43）
- [x] tar.gz：`DSH_SMOKE_READY` + `DSH_SMOKE_CLEAN`
- [x] AppImage：同上（FUSE 直跑）
- [x] GUI：§4 座舱检查点

打包与收尾：

- [x] 落地 `package.json` / `build-linux.sh` / README / CI
- [x] 打出 `.rpm`（Fedora 44 上 electron-builder；`rpm -qpR` 仅手写 depends，无自动 soname）
- [x] Fedora：`dnf install` + smoke（`DSH_SMOKE_READY` + `DSH_SMOKE_CLEAN`；Exec 含 `--ozone-platform=x11`）
- [x] 座舱 GUI / AVC 检查（无 AVC 拒绝）
- [ ] CI / Release 在合并进触发分支后验证 `*.rpm` + `smoke-rpm` job

---

## 附录：与 Debian 计划的差异速查

| 项 | Debian / Ubuntu | Fedora / RPM |
|----|-----------------|--------------|
| 安装器 | `apt install ./…deb` | `dnf install ./…rpm` |
| 包名 | `deepseek-harness-desktop` | 同左 |
| 架构字段 | `amd64` | `x86_64` |
| 构建辅助 | electron-builder 内置 fpm + `libxcrypt-compat` | 同上 + `rpmbuild`（`rpm-tools`） |
| CI 安装冒烟 | ubuntu-latest 可直接 apt | `fedora:41` container job |
| 已知依赖坑 | t64 包名、较旧 glibc | 勿写错误 soname；勿强制 `libXScrnSaver` |
