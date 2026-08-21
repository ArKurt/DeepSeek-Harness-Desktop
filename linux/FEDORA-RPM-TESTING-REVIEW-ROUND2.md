# Fedora / RPM 落地审查 — 第 2 轮

对 `43555f7` 的只读审查：未修改被审文件、未改打包配置、未打包、未合并任何分支。

- **审查对象：** `fedora-rpm-test-plan` @ `43555f7`（相对 `origin/linux` = `6f67e6a` 共 5 个提交）
- **上一轮：** `linux/FEDORA-RPM-TESTING-REVIEW.md`（对 `1d854d2` 测试计划的表态）
- **本轮范围：** 上一轮建议的落地情况、`rpm` 打包配置、CI `smoke-rpm`、以及新增的 Hyprland 实机结论

---

## 0. 上一轮建议的落地情况 — 全部采纳

| 上一轮项 | 状态 | 位置 |
|---|---|---|
| 缺陷 1：`(mesa-libgbm or libgbm.so.1)` → `(mesa-libgbm or libgbm1)` | ✅ 已改 | `package.json` `build.rpm.depends` |
| 缺陷 2：`(libXtst or libXtst.so.6)` → `(libXtst or libXtst6)` | ✅ 已改 | 同上 |
| §1.4：`(libsecret or libsecret-1-0)` 风格对齐 | ✅ 已改 | 同上 |
| Q2：用 `ldd` 定 `libXScrnSaver`，且两端一致 | ✅ **已跑并两端同步** | `FEDORA-RPM-TESTING.md` §0.1.1 记录 `ldd … \| grep -iE 'Xss\|Xscrn'` 无输出；`rpm` 不写、`deb` 删掉 `libxss1` |
| Q4：不单独装 fpm，只需 `rpmbuild` | ✅ 已改 | CI 只加 `rpm` 包；构建文档同步 |
| Q5：加 Fedora container 安装冒烟 | ✅ 已加 | `build-linux.yml` `smoke-rpm` job（但见缺陷 B） |
| Q6：Release notes 区分资产 | ✅ 已加 | `release-linux.yml` `body:` 一行 |
| Q7：README 只承诺 Fedora，openSUSE 加免责 | ✅ 已加 | `linux/README.md`「openSUSE 未经测试…」 |
| Q8：SELinux 落成实机检查而非说明文字 | ✅ 已做 | `ausearch -m AVC` 无 deepseek 拒绝 |
| §3 文档一致性 3 条 | ✅ 已改 | AppImage 措辞、`grep -q --` 断言、§7 补 stdout 断言 |

`rpm.depends` 最终清单与上一轮 §4 建议逐字一致。**上一轮没有遗留项。**

### 0.1 一条关键确认，提高了 `depends` 的权重

`FEDORA-RPM-TESTING.md` §7 记录：

> `rpm -qpR` 仅手写 depends，**无自动 soname**

这确认了上一轮 §3.1 提出的疑问，并且落在更危险的那一侧：**fpm 生成的 spec 关闭了 rpmbuild 的自动依赖生成，手写 `depends` 是唯一防线**，没有双保险。含义：

- 上一轮那两条 soname 写错（`libgbm.so.1` / `libXtst.so.6`）若照原样落地，`.rpm` **不会**从别处补回 libgbm 依赖 —— 后果比当时评估的更严重；
- 今后任何新增的运行时库依赖都必须手工加进 `depends`，没有任何自动机制兜底。

按此复核当前清单：`libdrm` 由 `mesa-libgbm` 传递、`libxkbcommon` 由 `gtk3` 传递，两者不必显式写；`libgbm` / `alsa-lib` / `at-spi2-core` / `libsecret` / `libuuid` / `libXtst` / `nss` / `libnotify` / `gtk3` / `xdg-utils` 齐全。**当前清单判定为完备。**

---

## 1. 缺陷

### 缺陷 A（P1）：Hyprland 上包的默认配置不出窗，而记录的证据不足以支持「Hyprland 需要 wayland」这个结论

`FEDORA-RPM-TESTING.md` §4 新增：

> **Hyprland 0.56.2：** 包默认 `--ozone-platform=x11` 会起进程但不出窗；改为 `--ozone-platform=wayland` 后正常。

**这是本分支最重要的发现，但目前的归因不成立。** `--ozone-platform=x11` 让 Chromium 去连 X server，在 Wayland 会话下那就是 XWayland。「起进程但不出窗」至少有两个截然不同的根因：

| 候选根因 | 含义 | 判别方法 |
|---|---|---|
| **(a) XWayland 缺失/被禁** | Hyprland 的 `xwayland { enabled = false }`，或没装 `xorg-xwayland`。此时 x11 后端根本没有可映射的显示。**这与 Hyprland 无关，任何没有 XWayland 的纯 Wayland 会话都会中招** —— 包括不跑 `xwayland-satellite` 的 niri | `pgrep -f Xwayland`；`echo $DISPLAY` |
| **(b) XWayland 正常，但窗口没被看到** | 窗口开在别的 workspace 或未获焦点。**这正是第 1 轮 README 已经记录过的 niri 症状** | `hyprctl clients`（会列出 XWayland 窗口的 class / workspace） |

两者的修复完全不同：(a) 要么装 XWayland、要么改默认；(b) 是一条窗口规则，跟 ozone 无关。

**请补三条命令的输出再定论**（在 Hyprland 会话里，用包默认的 x11 启动之后）：

```bash
pgrep -af Xwayland
echo "DISPLAY=$DISPLAY WAYLAND_DISPLAY=$WAYLAND_DISPLAY"
hyprctl clients | grep -iA5 deepseek
```

### 缺陷 A'（P1，同源但更重要）：`--ozone-platform=x11` 这个默认值从未被隔离验证过

回顾这条标志的来历：

- 它是在第 2 轮（`a0286d3`）与 JS 侧的窗口生命周期修复**同一批**引入的；
- 第 3 轮的 niri 实机复测用的是**带 `--ozone-platform=x11`** 的命令；
- 第 3 轮报告 §3.2 已经写明：「欢迎屏退出这个 bug 的修复主体在 JS，不依赖 XWayland；`--ozone-platform=x11` 是针对 niri 合成器怪癖的加固，**不是修复本体**」。

也就是说：**没有任何一次实验验证过「JS 修复已经就位之后，niri 是否还需要这个标志」。** 而现在有了反向证据 —— 在 Hyprland 上这个默认值会让包**不出窗**，症状恰好落回项目最初要修的那一类（「起来了但看不到窗口」）。

代价评估：GNOME / KDE 默认带 XWayland，绝大多数用户不受影响；受影响的是平铺式 Wayland 合成器用户 —— 而这恰恰是本项目最初 bug 报告者所在的人群。

**建议的决定性实验（在 niri 机器上，用当前构建）：**

1. `--ozone-platform=wayland` 跑一遍：正常启动 + 服务崩溃后点「重新启动」；
2. **不带任何 ozone 标志**（即 Electron 43 默认 `auto`）再跑一遍同样两项。

结果决定默认值：

- **若 niri 在 `auto` 下通过** → 从 `executableArgs`、两个 wrapper、`scripts.start` 里去掉 `--ozone-platform=x11`，README 把 x11 和 wayland 都写成可选覆盖。这样 Hyprland、niri、GNOME、KDE、纯 X11 会话全部开箱可用，且少维护一个特例。
- **若 niri 仍需 x11** → 保留默认，但 README 必须把「Wayland 会话下若不出窗，改用 `--ozone-platform=wayland`」写在显眼位置；并考虑把探测逻辑放进 `install-linux.sh` 生成的 wrapper（wrapper 能读 `$WAYLAND_DISPLAY` / `$DISPLAY` 做判断，而 `.desktop` 的 `Exec` 与 `executableArgs` 不能）。

**在这个实验做完之前，不建议把本分支合进 `linux`。** 不是因为 rpm 打包有问题（那部分是干净的），而是因为一个已知会让包在某类环境下不出窗的默认值，不应该跟着新的分发格式一起扩大投放面。

### 缺陷 B（P1）：CI 的 `container: fedora:41` 已经 EOL，`dnf` 很可能拉不到仓库

`build-linux.yml` 的 `smoke-rpm` job 用 `container: fedora:41`。**Fedora 41 已于 2025-12-10 结束维护**（今天 2026-08-21，已 EOL 约 8 个月）。EOL 之后该版本的内容被移到 `archives.fedoraproject.org`，默认 mirrorlist 不再返回镜像，容器里 `dnf install` 通常直接失败在拉取元数据这一步。

**这个版本号是我上一轮给的建议，当时没有核对生命周期，是我的错。** 现在的正确取值：Fedora 44 是本次实机验证的平台，43 是仍在维护的上一版。

**建议：** 改成 `container: fedora:43`（仍在维护、且比验证平台旧一档，对依赖可用性是更严格的检验），或直接与验证平台对齐用 `fedora:44`。更稳的做法是矩阵化：

```yaml
smoke-rpm:
  needs: build
  runs-on: ubuntu-latest
  strategy:
    matrix:
      fedora: [43, 44]
  container: fedora:${{ matrix.fedora }}
```

无论取哪个，**不要用 `fedora:latest`** —— 它会随上游滚动，某天悄悄换成一个没测过的版本。

### 缺陷 C（P2）：`release-linux.yml` 会发布一个从未被安装验证过的 `.rpm`

对比两个工作流：

| | `.deb` 安装冒烟 | `.rpm` 安装冒烟 |
|---|---|---|
| `build-linux.yml` | ✅ 有 | ✅ 有（`smoke-rpm` job） |
| `release-linux.yml` | ✅ 有 | ❌ **无** |

`release-linux.yml` 打出 `.rpm`、上传为 Release 资产，中间没有任何 `dnf install` 环节。而 `.deb` 在同一个工作流里是有安装冒烟的 —— 这个不对称没有理由。

风险场景很具体：`build-linux.yml` 只在 push 到 `main` / `linux` 且路径命中 `linux/**` 时触发；打 `linux-v*` 标签只会触发 release 工作流。因此完全可能出现「某个 commit 的 build CI 没跑过或跑挂了，但标签照打，`.rpm` 直接进 Release」。

**建议：** 在 `release-linux.yml` 里加一个与 `smoke-rpm` 同构的 job，并让发布 job `needs:` 它 —— 让安装冒烟成为发布的前置条件，而不是旁路。

### 缺陷 D（P3）：顶部状态块与 Hyprland 结果不一致

`FEDORA-RPM-TESTING.md` 第 3 行：

> 状态：交叉验证已完成；Fedora 44 上 AppImage / tar.gz / **`.rpm` 无头冒烟与座舱 GUI 均已通过**

「均已通过」与同一份文档 §4 里「Hyprland 上包默认配置不出窗、需用户级 `.desktop` 覆盖」并存，读者只看状态块会得到过于乐观的结论。而且那个覆盖写在 `~/.local/share/applications/`，**不随包分发** —— 对其他 Hyprland 用户不存在。

**建议：** 状态块补一句限定，例如「GNOME/座舱路径已通过；Hyprland 需 `--ozone-platform=wayland`，默认值待定（见 §4）」。

---

## 2. 判定正确的部分

| 项 | 依据 |
|---|---|
| `rpm.depends` 最终清单 | 与上一轮建议逐字一致；在「无自动 soname」的前提下复核仍判定完备（§0.1） |
| `libxss1` / `libXScrnSaver` 两端同步删除 | 由 `ldd` 实测支撑，不是推理；两端不对称已消除 |
| `smoke-rpm` job 的步骤设计 | `dnf install` → `grep -q -- '^Exec=.*--ozone-platform=x11'` → `--ozone-platform=headless --no-sandbox` + `tee` + `grep -q DSH_SMOKE_CLEAN`，与 `.deb` 侧完全对称，容器内必需的 `--no-sandbox` 也带上了 |
| CI 构建依赖只加 `rpm` | 与 `FpmTarget.ts` 的实际要求一致，没有多装 fpm |
| `artifactName` → `DeepSeek-1.0.1-x86_64.rpm` | 与 AppImage 只差后缀，Release 资产不撞名 |
| `body:` + `generate_release_notes: true` | GitHub API 会把 `body` 前置于自动生成的说明，两者不冲突 |
| README / `linux/README.md` | 分发表、安装小节、openSUSE 免责均已补齐 |
| `rpm -qpR` 人工核对 | 做了，而且把结论（无自动 soname）写进了文档 —— 这是本轮最有价值的一条记录 |

---

## 3. 总评

**RPM 打包这条线本身是干净的，可以合；挡住合并的是 `--ozone-platform=x11` 这个默认值的悬而未决，以及两处 CI 问题。**

上一轮开出的每一条都落地了，`ldd`、`ausearch`、`rpm -qpR` 三项实测都真的跑了并把结论写进文档 —— 特别是「无自动 soname」这条，它把手写 `depends` 从双保险降级为唯一防线，是后续任何依赖变更都必须记住的前提。

但本轮新增的 Hyprland 结论暴露了一个更早的问题：`--ozone-platform=x11` 从引入起就没被单独验证过，现在有了它在某类环境下导致「不出窗」的反向证据，而「不出窗」正是本项目最初要修的症状。在把这个默认值随着新的分发格式扩大投放之前，应该先把它验清楚。

### 3.1 最短必须再改

- [ ] **缺陷 B** — `container: fedora:41` 改为 `fedora:43`（或 43/44 矩阵）。当前值已 EOL，CI 大概率直接失败。
- [ ] **缺陷 A** — 在 Hyprland 会话补 `pgrep -af Xwayland` / `echo $DISPLAY` / `hyprctl clients` 三条输出，区分「XWayland 缺失」与「窗口在别的 workspace」。
- [ ] **缺陷 A'** — 在 niri 上跑隔离实验：`--ozone-platform=wayland` 与**不带标志**各跑一遍（正常启动 + 崩溃重启），据此决定是否保留 x11 默认值。

### 3.2 合并前建议做

- [ ] **缺陷 C** — `release-linux.yml` 补一个与 `smoke-rpm` 同构的 job，并让发布 `needs:` 它。
- [ ] **缺陷 D** — 状态块补上 Hyprland 的限定条件。
- [ ] 手动跑一次 CI 验证 `smoke-rpm`（本分支不在触发条件里）：
      `gh workflow run "Build Linux" --repo ArKurt/DeepSeek-Harness-Desktop --ref fedora-rpm-test-plan`

---

## 附：本轮未做的验证与引用

**未做的验证：**

1. **未在 Fedora / Hyprland / niri 上运行任何东西** —— 缺陷 A、A' 的两个候选根因与建议实验均为分析，未实跑。
2. **未打 `.rpm`、未运行 CI** —— `rpm -qpR` 无自动 soname、Fedora 44 冒烟与 GUI、AVC 检查，全部为实现方陈述，**未独立复现**；`smoke-rpm` job 未实跑，缺陷 B 是依据 Fedora 生命周期的推断。
3. **未验证 `fedora:43` / `fedora:44` 容器内能否解析当前 `depends`** —— §1 缺陷 B 的建议未实跑。
4. 未修改被审文件、未改配置、未合并任何分支。

**引用来源：**

- Fedora 41 生命周期（EOL 2025-12-10；Fedora N 维护至 N+2 发布后约 1 个月）：
  https://fedoraproject.org/wiki/Fedora_Release_Life_Cycle
  https://discussion.fedoraproject.org/t/fedora-41-eol-whoops/175073
- electron-builder `FpmTarget.ts`（rpm 默认依赖、`rpmbuild` 要求），查阅于 2026-08-20：
  https://github.com/electron-userland/electron-builder/blob/master/packages/app-builder-lib/src/targets/linux/FpmTarget.ts
- 本仓库 `origin/linux` @ `6f67e6a` 与 `fedora-rpm-test-plan` @ `43555f7`
