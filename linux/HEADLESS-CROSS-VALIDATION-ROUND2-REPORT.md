# 第 2 轮无头交叉验证 — 审查报告

对 `linux/HEADLESS-CROSS-VALIDATION.md` 的回复。只读审查，未修改被审代码、未重打包。

- 审查对象：`debian-ubuntu-test-plan` @ `a0286d3` *Fix crash relaunch quit and switch Linux ozone to CLI flags.*
- 第 1 轮基线：`a456646` *Fix Linux splash-to-main quit on niri/Wayland.*
- 审查范围：`linux/src/main.js`、`linux/install-linux.sh`、`linux/arch/deepseek.sh`、`linux/package.json`、`linux/README.md`。按任务书要求，**未评** `.deb` 打包 / t64 Depends / glibc / `node-pty` / 图标缓存。

## 0. 与任务书前提不符的一点

任务书 §0 称第 2 轮修复在「工作区未提交 diff」里，并要求 clone 后若 `git status` 干净就停下来要工作区。

**实际：第 2 轮已提交为 `a0286d3`（2026-08-18）。** `git status` 干净但内容在树里，无需索要工作区。历史链：

```
a456646 → 9fc0ed9 (merge linux) → 4fe1158 → fa91b39 → 310fce4 → a0286d3
```

本报告以 `a0286d3` 的代码为准。

---

## 1. 第 2 轮是否消化了第 1 轮 P1 / ozone / 锁时机

| 第 1 轮问题 | 判定 | 依据 |
|---|---|---|
| **P1：`window-all-closed` 误杀崩溃重启** | **已修** | `src/main.js:493` 现为 `app.on('window-all-closed', () => {});`，handler 内不再 `app.quit()`。防线是双层的：`main.js:423-425` 崩溃重启先 `startupPhase='splash'` 再 `await closeMainWindow()`，而主窗口 `closed`（`main.js:300`）带 `startupPhase === 'main'` 守卫，程序性关窗不触发退出。 |
| **ozone：环境变量无效** | **机制已修，覆盖不全** | `main.js:3-5` 已删除 `ELECTRON_OZONE_PLATFORM_HINT` 赋值并留注释；`install-linux.sh:125,127`、`arch/deepseek.sh:22`、`package.json:12`（`scripts.start`）、`package.json:67-69`（`executableArgs`）改为 CLI 标志。缺口见 §3。 |
| **锁清理时机（只读 HOME 算错 CONFIG_DIR）** | **已修** | `install-linux.sh:102-107` 先做只读 HOME → `XDG_CONFIG_HOME=$PREFIX/config` 回退，`:108` 才计算 `CONFIG_DIR`，顺序正确。 |
| **PID 无数字校验** | **已修** | `install-linux.sh:112-114`、`arch/deepseek.sh:10-12` 的 `case "$lock_pid" in ''\|*[!0-9]*) ;;` 在 `kill -0` 之前拦住非数字。 |
| **Arch 启动器完全没同步** | **已修** | `arch/deepseek.sh:5` `unset ELECTRON_RUN_AS_NODE`、`:6-20` 锁清理、`:22` ozone 标志，三项齐全。 |
| **TOCTOU / PID 复用** | **未修**（实现方声明为已知限制） | 仍是 `readlink` → `kill -0` → `rm -f` 的非原子序列。 |
| **skipTaskbar / niri workspace** | **未修**，只文档 | `main.js:115`、`README.md:93-104`。与 §3.4 自述一致。 |

### 1.1 锁清理的两个残留缺口（§3.4 未承认）

1. `install-linux.sh:102` 的条件是 `[ ! -w "$HOME" ] && [ -w "$PREFIX" ]`。系统安装（`--prefix /usr/local`）后以普通用户运行时 `$PREFIX` 不可写，回退不发生，`CONFIG_DIR` 仍落在不可写的 `$HOME/.config` —— 第 1 轮「只读 HOME 清不到真实锁」在这条路径上依然成立。
2. `install-linux.sh:109` / `arch/deepseek.sh:7` 的入口条件是 `[ -L "$CONFIG_DIR/SingletonLock" ]`。若 SIGKILL 后残留的是普通文件，或 `SingletonLock` 已消失而 `SingletonCookie`/`SingletonSocket` 还在，整段清理被跳过。

---

## 2. 空 `window-all-closed` 是否引入新的退出漏洞或僵尸进程

### 2.1 同步顺序前提

认同第 1 轮 DeepSeek 的 A 结论：`NotifyWindowClosed()` 同步 emit `closed`，随后 `WindowList::RemoveWindow → Browser::WindowAllClosed → App` 同步 emit `window-all-closed`，整条链在 C++ 内跑完才回到 JS 微任务检查点，B 的「`await` 微任务先跑」不成立。

> **披露：未在本 checkout 内读到 v43.4.0 的 C++ 源码**（`linux/node_modules` 未安装，本轮未拉取 Electron 源码）。该结论按已知 Electron 实现结构复核，非逐行比对。若要作为合并门禁，请让实现方贴一次 `window_list.cc` / `electron_api_base_window.cc` 的实际代码。

### 2.2 §3.1 六个场景推演

| # | 场景 | 结论 |
|---|---|---|
| 1 | 正常欢迎屏→主窗口 | **正确**。`main.js:459` 先 `startupPhase='main'`，`:463` 建主窗，`:464-466` 才关欢迎屏；splash `closed`（`:135`）见 phase 已是 `'main'` → 不退。窗口数从未归零。 |
| 2 | 用户关主窗口 | **正确**。`:300` `!quitting && startupPhase === 'main'` → `app.quit()`。 |
| 3 | Alt+F4 欢迎屏（仍 splash） | **正确**。`:135-137` → `app.quit()`。 |
| 4 | 崩溃 →「重新启动」（P1 回归） | **已消除**。`:423-425` phase 先转 `'splash'`，`closeMainWindow()` 触发的 `closed` 被 `:300` 的 phase 守卫挡下，`window-all-closed` 空转，`runStartup()` 在 `:433-435` 重建欢迎屏。 |
| 5 | 启动失败对话框（`'failed'`，0 窗口） | **正确**。`:367-369` 关欢迎屏时 splash `closed` 的守卫是 `=== 'splash'`，phase 已是 `'failed'` → 不退；`:371` 的 `showMessageBox` 无父窗口，0 窗口下仍能弹；「重试」→ `:383-384`，「退出」→ `:386`，直接关闭走 `cancelId: 1` 同「退出」。 |
| 6 | 无窗口僵尸 | 退出路径本身**安全**：`quitApp()`（`:475-481`）的 `shutdownServer` 有界 —— `server-manager.js:227-236` SIGTERM + 3s 宽限 + SIGKILL，不会挂住。 |

### 2.3 缺陷：`quitting` 守卫缺失导致的窗口化僵尸

**根因不是空 handler 本身，而是 `runStartup()` / `showStartupErrorAndMaybeRetry()` 全程不检查 `quitting`。**

复现链：

1. `main.js:135` splash `closed` → `app.quit()` → `before-quit`（`:483-487`）`preventDefault` → `quitApp()` 置 `quitting=true`，杀服务；
2. 此时仍在 `await` 中的 `runStartup()`（`:447`）因服务被杀而 `ensureServer()` 失败 → `:455` 进入 `showStartupErrorAndMaybeRetry()`，**该函数不检查 `quitting`**，于是在用户已请求退出后仍弹出「DeepSeek 启动失败」；
3. 用户点「重试」→ `:383-384` `startupPhase='splash'; await runStartup()` → `:434` `createSplashWindow()`，**在 `quitting === true` 下复活窗口**；
4. 此后 splash `closed`（`:135`）、main `closed`（`:300`）的守卫都是 `!quitting` → 恒假；`window-all-closed`（`:493`）空；`quitApp()`（`:476`）`if (quitting) return` 自锁。

**后果：关掉所有窗口后进程不退出，继续占端口与 `SingletonLock`**，正是 `README.md:97` 描述的「点第二次立刻退出」。仅菜单「文件→退出」（`:319` `role: 'quit'`）还能出去，因为那时 `cleanedUp` 已为 `true`、`before-quit` 直接放行。

**影响面（诚实标注）：** 需要「splash 阶段退出」与「随后点重试」的竞态，触发概率低。**第 1 轮的 handler 也只覆盖其中 phase 仍为 `'splash'` 的子情况**，phase 走到 `'main'` 后同样漏 —— 所以这不是第 2 轮新引入的缺陷，而是空 handler 移除最后一层兜底后完全暴露。

**建议修法（不要把 `app.quit()` 加回 `window-all-closed`）：** 见 §5 建议 1。

### 2.4 次要项

`main.js:496-500` 的 SIGTERM/SIGINT/SIGHUP → `app.quit()`，在 `quitting=true && cleanedUp=false` 的约 3 秒窗口内会被 `before-quit` 吞掉（`quitApp()` 早退）。因 `shutdownServer` 有界，3 秒后自愈，可不修，但值得记录。

---

## 3. ozone CLI 是否真能在 niri 上选 XWayland

**机制正确，已外部核实。** Electron 官方 breaking-changes 确认 `ELECTRON_OZONE_PLATFORM_HINT` 在 **Electron 38.0** 移除，`--ozone-platform` 默认值改为 `auto`（Wayland 会话下默认原生 Wayland），强制 XWayland 的唯一手段是 `--ozone-platform=x11` 命令行标志。第 1 轮判断与第 2 轮改法均成立。

### 3.1 各启动路径覆盖情况

| 启动路径 | 带 `--ozone-platform=x11` | 位置 |
|---|---|---|
| AppImage 经 `~/.local/bin/deepseek` wrapper | ✅ | `install-linux.sh:125`（FUSE）、`:127`（`APPIMAGE_EXTRACT_AND_RUN`） |
| AppImage 经 `.desktop` | ✅ | `install-linux.sh:147` `Exec="$BIN_DIR/deepseek" %U` → wrapper |
| Arch 包（菜单或 `deepseek`） | ✅ | `arch/deepseek.desktop:6` → `PKGBUILD:47` → `arch/deepseek.sh:22` |
| `npm start` | ✅ | `package.json:12` |
| .deb 经应用菜单 | ⚠️ **未验证** | 依赖 `package.json:67-69` `executableArgs` 是否被 electron-builder 26.15.3 写进 `.desktop` 的 `Exec`。`node_modules` 未安装，无法查证。 |
| **tar.gz 解包后直跑 `./deepseek`** | ❌ | — |
| **.deb 装完直跑 `/opt/DeepSeek/deepseek`** | ❌ | — |
| **AppImage 直跑（不经 wrapper）** | ❌ | — |

三条 ❌ 正是 §3.2 要求核对的，确认成立：`executableArgs` 只能进 `.desktop`，管不到直接调用二进制。

### 3.2 测试计划自身的问题

`DEBIAN-UBUNTU-TESTING.md:107` 的 GUI 实机测试命令是：

```bash
DSH_DESKTOP_HOME=/tmp/dsh-gui ./deepseek
```

**不带标志、不经 wrapper。** 在 Wayland 会话上这条会以原生 Wayland 跑，**恰好绕开本轮修复**，niri 上的复测等于没测到 XWayland 路径。`:77` 的 `./deepseek --smoke-test` 无头不建窗口，不受影响。

### 3.3 参数透传（文档推理，未实机验证）

- AppImage runtime 只截获 `--appimage-*` 前缀参数，其余透传给应用，`--ozone-platform=x11` 能到 Chromium；与 `DEBIAN-UBUNTU-TESTING.md:88` 既有的 `--no-sandbox --disable-gpu -- --smoke-test` 约定不冲突（`--` 之后才是应用参数）。
- wrapper 把标志放在 `"$@"` 之前，用户追加的 `--ozone-platform=wayland` 因 Chromium CommandLine 后者覆盖前者而生效，`README.md:86` 的说法成立。

---

## 4. 声称 vs 当前代码

| # | 声称 | 判定 | 位置 |
|---|---|---|---|
| 1 | 欢迎屏→主窗口间隙退出已修 | **已修**（正常路径 + 崩溃重启回归都覆盖） | `main.js:459-466`、`:300`、`:423-425`、`:493` |
| 2 | niri 别的 workspace / skipTaskbar | **未修**，仍只文档 | `main.js:115`、`README.md:93-104` |
| 3 | 残留 SingletonLock 导致二次点击退出 | **部分修复**：AppImage + Arch 均覆盖，时机正确、有数字校验；系统 prefix 不可写的只读 HOME 仍漏，非符号链接残留仍漏 | `install-linux.sh:102-122`、`arch/deepseek.sh:6-20` |
| 4 | 默认走 XWayland | **部分修复**：机制正确（已核实 Electron 38 移除该 env），wrapper/.desktop/npm start 覆盖；直跑二进制三条路径无标志 | `main.js:3-5`、`install-linux.sh:125,127`、`arch/deepseek.sh:22`、`package.json:12,67-69` |
| 5 | 只拉 git 不重打包就够 | **仍不够**；已装 AppImage 的 asar 不含本轮 `main.js` | §3.4 自述 |
| 6（新） | 空 `window-all-closed` 只拦默认退出、不引入新漏洞 | **基本成立**，但缺 `quitting` 守卫，存在窄条件下无法退出的窗口化僵尸 | `main.js:366`、`:432`、`:135`、`:300`、`:476` |
| 7（新） | 锁清理已移到 XDG 回退之后 | **成立** | `install-linux.sh:102-108` |
| 8（新） | Arch 启动器已同步 | **成立**（无 prefix 回退是设计选择，Arch 包一般可写 HOME） | `arch/deepseek.sh:5-22` |
| 9（新） | ozone 改 CLI，用户参数可覆盖 | **成立但未实机验证**；不覆盖直跑二进制 | 见 §3.1 |

---

## 5. 总评与建议

**方向正确，第 1 轮的三个 P 级问题（P1 回归、ozone 机制、锁时机）都真的修掉了，不是文档式修复。**

**但先别重打包、先别合 `linux`** —— 不是因为代码危险，而是因为**本轮的关键回归至今没有在 niri 上跑过一次**（§3.4 自承），而测试计划里的 GUI 命令又恰好绕开了 ozone 修复。现在合入等于在没有证据的情况下合。

### 5.1 最短必须再改（给本地 agent 的执行清单）

- [ ] **建议 1 — 堵住 §2.3 的僵尸路径。** 两行改动，风险极低。
  - `src/main.js` 的 `showStartupErrorAndMaybeRetry()` 开头（约 `:366`）加 `if (quitting) return;`
  - `src/main.js` 的 `runStartup()` 开头（约 `:432`）加 `if (quitting) return;`
  - **不要**把 `app.quit()` 加回 `window-all-closed`（`:493`）—— 那会让 P1 回归。
  - 验证：`node test/window-state.test.js && node test/server-crash.test.js` 仍通过。

- [ ] **建议 2 — 修正 GUI 测试命令与文档。**
  - `DEBIAN-UBUNTU-TESTING.md:107` 改为 `DSH_DESKTOP_HOME=/tmp/dsh-gui ./deepseek --ozone-platform=x11`
  - `README.md:85-86` 补一句：直跑二进制（tar.gz `./deepseek`、`/opt/DeepSeek/deepseek`、AppImage 不经 wrapper）不带 ozone 标志，需手动加。

- [ ] **建议 3 — niri 实机跑第 1 轮就要求、第 2 轮仍欠的回归。** 这是唯一能证明 P1 真修好的证据。
  1. 启动 → 确认欢迎屏→主窗口无闪退
  2. `pkill -f dsh` 或 kill 掉服务子进程，触发「本地服务已停止」
  3. 点「重新启动」→ **确认欢迎屏重建、进程不退出、主窗口恢复**
  4. 记录 `niri msg windows | rg -i deepseek` 输出

- [ ] **建议 4 — 确认 .deb 的 `executableArgs` 是否落地。**
  ```bash
  grep Exec /usr/share/applications/deepseek.desktop
  ```
  期望包含 `--ozone-platform=x11`。若没有，需要在 electron-builder 配置里换用 `desktop.entry.Exec` 显式指定。

**建议 1、2 完成 + 建议 3 有实测记录后，再重打包并推 `linux`。**

### 5.2 可留作文档债（本轮不必改）

- 锁的 TOCTOU / PID 复用（实现方明确的设计取舍）
- skipTaskbar / niri workspace
- 系统 prefix 不可写时的只读 HOME 边角（§1.1 第 1 条）
- 非符号链接的锁残留（§1.1 第 2 条）—— 建议至少在 README 补一句「必要时 `pkill -x deepseek` 后手工删 `Singleton*`」
- `main.js:496-500` 信号处理在 3 秒窗口内被吞（自愈，见 §2.4）

---

## 附：本轮未做的验证

诚实列出，供下一轮补齐：

1. 未读 Electron v43.4.0 的 C++ 源码（`node_modules` 未安装）—— §2.1 的同步顺序结论是结构性复核。
2. 未实机运行任何产物（无头环境，且任务书要求不重打包）。
3. 未验证 electron-builder 26.15.3 对 `executableArgs` 的实际处理 —— §3.1 的 .deb 行。
4. 未验证 AppImage runtime 的参数透传与 Chromium CommandLine 的后者覆盖行为 —— §3.3 为文档推理。
