# Fedora / RPM 测试计划（交叉验证稿）

> 状态：**尚未合入打包目标**。本文件先给实现方与远程审查方交叉验证；
> 清单与依赖声明定稿后，再改 `package.json` / `build-linux.sh` / CI，
> 并在本机打出 `.rpm` 后于 Fedora VM 实装。

## 目标

1. 在 Fedora 上确认现有 **AppImage / tar.gz** 可冒烟、可 GUI（不依赖 RPM）。
2. 定稿 electron-builder 的 `rpm` 配置（尤其 `depends`），再真正打包。
3. 在 Fedora VM 上 `dnf install` 本地 `.rpm`，冒烟 + GUI，通过后再进 CI / Release。

AppImage / tar.gz 是基线；**.rpm 通过后再**把目标合进 `linux` 与工作流。

## 测试矩阵

| 发行版 | 优先测试项 |
|--------|------------|
| Fedora（当前用户 VM，记清版本号） | tar.gz 冒烟、AppImage 冒烟、GUI；后续 dnf 装 .rpm |
| Fedora 41 / 42（可选） | 同上，关注 glibc / 依赖包名差异 |
| openSUSE Tumbleweed（可选，非必须） | 若 `depends` 用 soname，可抽测安装解析 |

请在实机结果里写明：`cat /etc/os-release` 的 `NAME` / `VERSION_ID`，以及 `ldd --version` 的 glibc。

## 0. 拟改动范围（审查用，尚未落地）

仅供交叉验证；**在审查通过前不要改仓库**。

### 0.1 `linux/package.json`

- `scripts.dist` / `build.linux.target`：增加 `rpm`（x64）。
- 新增 `build.rpm` 段（建议显式覆盖 `depends`，不要裸用 electron-builder 默认值）。

**拟议 `rpm.depends`（待审查）：**

```json
"rpm": {
  "depends": [
    "gtk3",
    "libnotify",
    "nss",
    "(libXtst or libXtst.so.6)",
    "xdg-utils",
    "at-spi2-core",
    "(libuuid or libuuid1)",
    "libsecret",
    "(mesa-libgbm or libgbm.so.1)",
    "(alsa-lib or libasound2)"
  ]
}
```

审查重点：

| 点 | 说明 |
|----|------|
| **刻意不写 `libXScrnSaver`** | electron-builder 默认会带；Electron 近年用 DBus idle，RHEL 10 / 部分新环境包不可用或非默认，易导致 `dnf install` 失败。与现有 `deb.depends` 里仍有 `libxss1` 不对称——若审查认为应两端一致，再定。 |
| **包名 vs soname** | Fedora 友好写法是 `gtk3` / `alsa-lib`；跨 openSUSE 时有人用 `libgtk-3.so.0()` 这类能力依赖。本仓库若只承诺 Fedora + 通用 AppImage，包名即可；若要对齐「RPM 全家桶」，倾向 soname / rich deps。 |
| **是否补 `libdrm`** | 部分 Electron RPM 会加 `(libdrm or libdrm2)`；现有 deb 未显式列，是否补上请定。 |
| **包名 `name`** | 顶层 `"name": "deepseek-harness-desktop"` → RPM 包名通常同此；卸载命令拟为 `sudo dnf remove deepseek-harness-desktop`。 |
| **artifactName** | 现有 `"DeepSeek-${version}-${arch}.${ext}"`；RPM 的 `${arch}` 一般为 `x86_64`（不同于 deb 的 `amd64`），产物名拟为 `DeepSeek-1.0.1-x86_64.rpm`。请确认与 Release 资产命名是否可接受。 |
| **`executableArgs`** | 已在 `linux.executableArgs` 设 `--ozone-platform=x11`，应同样写入 `.desktop` 的 `Exec=`；装包后需核对。 |

### 0.2 `linux/build-linux.sh`

- 文案与 `npx electron-builder --linux AppImage tar.gz deb` → 追加 `rpm`。
- 本机（CachyOS/Arch）构建前需：`rpm-tools`（`rpmbuild`）+ `fpm` + 既有 `libxcrypt-compat`（fpm 的 `libcrypt.so.1`）。

### 0.3 CI（定稿后再改）

- `build-linux.yml` / `release-linux.yml`：ubuntu-latest 上装 `rpm` / `ruby`+`fpm`（或项目惯用方式），打包目标加 `rpm`，artifact 上传 `*.rpm`。
- **ubuntu-latest 上无法 `dnf install` 做 packaged smoke**；可选：
  - A. 只构建上传，RPM 安装冒烟放人工 / Fedora 容器 job；
  - B. 增加 `fedora:latest`（或固定版本）container/job：`dnf install ./...rpm` → `deepseek --smoke-test`。
- 建议与 `.deb` 对称：至少有一条「安装后冒烟」路径，否则回归只能靠 VM。

### 0.4 文档

- `linux/README.md` 分发表、安装小节增加 RPM / Fedora。
- 根 `README.md` Linux 行补 `.rpm`。

## 1. 获取测试产物（基线，不依赖 RPM）

先用已有产物在 Fedora VM 跑通 §2–§4，再谈打 RPM。

当前可用（本机构建或 CI Artifact `DeepSeek-Linux`）：

- `DeepSeek-1.0.1-x86_64.AppImage`
- `DeepSeek-1.0.1-x64.tar.gz`
- （`.deb` 在 Fedora 上一般不测）

本地日后打 RPM（审查通过后）：

```bash
# 构建机 Arch / CachyOS
sudo pacman -S libxcrypt-compat rpm-tools
# fpm：按团队现有方式安装（gem / AUR）；确认 `which fpm rpmbuild`

cd linux
./build-linux.sh --runtime-only   # 或 --skip-runtime 若 runtime 已就绪
./build-linux.sh --skip-runtime   # 定稿后应产出 *.rpm
```

**不要在小规格 Fedora 测试 VM 上跑完整 `build-linux.sh`**（与 Debian 测试计划相同理由）。

### glibc / node-pty（与 Debian 同源风险）

Arch 上现场编译的 `node-pty` 会链到构建机 glibc。若 Fedora 的 glibc **低于** 构建机，冒烟可能 `GLIBC_x.y not found`。

- 发版 runtime 仍应以 **CI `ubuntu-latest`（或更旧 glibc）** 组装为准。
- 本机验证：可用 CI 产物里的 `node-pty/build/Release/pty.node` 换进 `linux/runtime` 再打 rpm。
- Fedora 新版本 glibc 通常 ≥ Ubuntu LTS，风险往往小于 Debian 旧版，但仍要在 VM 上实跑确认，不要假设。

## 2. Fedora 运行时依赖（AppImage / tar.gz / 之后 RPM）

无头冒烟：

```bash
sudo dnf install -y xorg-x11-server-Xvfb
# AppImage FUSE（若直跑需要；否则用 APPIMAGE_EXTRACT_AND_RUN=1）
sudo dnf install -y fuse fuse-libs
```

Electron 常见共享库（若 tar.gz / 解包二进制缺库再补；包名以 `dnf provides` 为准）：

```bash
sudo dnf install -y gtk3 libnotify nss libXtst libXScrnSaver \
  at-spi2-core libuuid libsecret mesa-libgbm alsa-lib \
  libdrm libxcb libxkbcommon nss-util
```

中文缺字：

```bash
sudo dnf install -y google-noto-sans-cjk-fonts google-noto-emoji-fonts
```

> `libXScrnSaver`：冒烟/运行时若缺再装；**RPM `Requires` 建议仍不强制**（见 §0.1），避免部分环境装不上。

## 3. 无头冒烟（基线）

### tar.gz

```bash
tar -xzf DeepSeek-1.0.1-x64.tar.gz
cd DeepSeek-1.0.1-x64

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-fedora-smoke \
  ./deepseek --smoke-test --no-sandbox --disable-gpu
```

### AppImage

与 Debian 文档相同注意点：electron-builder 26 运行时多数参数可直传；保险写法加 `--`：

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

通过标准：

- stdout 含 `DSH_SMOKE_READY port=3099 reused=false`
- stdout 含 `DSH_SMOKE_CLEAN`
- 退出码 `0`

> 仅看退出码不够：单实例锁命中时 `--smoke-test` 也会 `app.quit()` 且返回 0。

## 4. GUI 实机

```bash
DSH_DESKTOP_HOME=/tmp/dsh-fedora-gui ./deepseek --ozone-platform=x11
```

检查点（与 Debian §4 对齐）：

1. 启动动画后主窗口可用（输入 API / 对话）。
2. 关窗后 `pgrep -af 'bin.js web'` 为空（自己拉起的服务被清掉）。
3. 日志：`${XDG_STATE_HOME:-~/.local/state}/deepseek/server.log`。
4. 端口已被占用时复用、退出不杀外来服务，属预期。
5. 记录桌面环境：GNOME（Wayland 默认）下是否需 `--ozone-platform=x11`；原生 Wayland 是否另测。

## 5. 安装 .rpm（配置落地并打出包之后）

装系统包前，若曾用用户级 AppImage 启动器，先卸掉以免抢 PATH：

```bash
cd linux
./install-linux.sh --uninstall
```

```bash
sudo dnf install -y ./dist/DeepSeek-1.0.1-x86_64.rpm

# 核对 desktop Exec（应含 --ozone-platform=x11）
grep Exec /usr/share/applications/deepseek.desktop
ls -l /usr/bin/deepseek /opt/DeepSeek/deepseek

xvfb-run -a env DSH_DESKTOP_PORT=3099 DSH_DESKTOP_HOME=/tmp/dsh-rpm-smoke \
  deepseek --smoke-test --no-sandbox --disable-gpu
# 或无头：再加 --ozone-platform=headless
```

GUI：

```bash
DSH_DESKTOP_HOME=/tmp/dsh-rpm-gui deepseek --ozone-platform=x11
```

卸载：

```bash
sudo dnf remove deepseek-harness-desktop
```

### 依赖解析失败时

```bash
# 看 RPM 声明了什么
rpm -qpR ./dist/DeepSeek-1.0.1-x86_64.rpm
# 本机能否解析
sudo dnf install -y ./dist/DeepSeek-1.0.1-x86_64.rpm
```

把完整报错贴回审查线程，优先改 `rpm.depends`，不要用 `--nodeps` 当通过标准。

## 6. 建议的交叉验证问题（交给远程 Claude）

请逐条表态同意 / 反对 / 改写：

1. **阶段顺序**：先 Fedora 上 AppImage + tar.gz 冒烟/GUI，再改配置打 RPM——是否合理？
2. **`libXScrnSaver`**：RPM `depends` 是否同意省略？deb 侧要不要同步去掉 `libxss1`？
3. **`depends` 风格**：Fedora 包名，还是 soname / rich deps 兼顾 openSUSE？
4. **构建机**：继续 Arch 打 rpm + Fedora 只装测，是否可接受？构建依赖清单是否缺项？
5. **CI**：ubuntu 上只产出 rpm，还是必须加 Fedora job 做 `dnf install` 冒烟？
6. **产物命名** `DeepSeek-${version}-x86_64.rpm` 与现有 deb/AppImage 是否一致够用？
7. **是否要把 openSUSE / RHEL 写进承诺范围**，还是 README 只写 Fedora + AppImage 兜底？
8. **SELinux**：Fedora 默认 enforcing 下，装到 `/opt/DeepSeek` 的 Electron + 内嵌 Node 是否需额外说明或策略？（若审查认为高风险，补一条实机检查。）

## 7. 通过标准与收尾

基线通过：

- [ ] Fedora VM：`os-release` + glibc 已记录
- [ ] tar.gz：`DSH_SMOKE_CLEAN`
- [ ] AppImage：`DSH_SMOKE_CLEAN`（FUSE 或 extract-and-run）
- [ ] GUI：§4 检查点

配置审查通过后：

- [ ] 落地 `package.json` / `build-linux.sh` / README
- [ ] 本机打出 `.rpm`，`rpm -qpR` 依赖列表已人工看过
- [ ] Fedora：`dnf install` + smoke + GUI
- [ ] CI / Release 资产含 `*.rpm`（及约定的安装冒烟策略）

---

## 附录：与 Debian 计划的差异速查

| 项 | Debian / Ubuntu | Fedora / RPM |
|----|-----------------|--------------|
| 安装器 | `apt install ./…deb` | `dnf install ./…rpm` |
| 包名 | `deepseek-harness-desktop` | 同左（拟） |
| 架构字段 | `amd64` | `x86_64` |
| 构建辅助 | fpm + `libxcrypt-compat` | 同上 + `rpmbuild` |
| CI 安装冒烟 | ubuntu-latest 可直接 apt | 需 Fedora 环境或人工 |
| 已知依赖坑 | t64 包名、较旧 glibc | `libXScrnSaver`、包名/soname |
