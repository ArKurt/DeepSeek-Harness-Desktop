# Linux 欢迎屏退出修复 — 第 2 轮无头交叉验证

给远程/无头审查者的只读任务书。不要改仓库、不要重打包、不要推送。

**请先读本文件，再读代码。** 第 1 轮结论不能当默认真，要用 Electron 43.4.0 源码/文档复核。

---

## 0. 仓库状态（审查前必读）

- 分支：`debian-ubuntu-test-plan`（**不要**当成 PR #5 / `linux` 的合并候选）。
- 第 1 轮合入提交：`a456646` *Fix Linux splash-to-main quit on niri/Wayland.*
- 第 2 轮修复目前在**工作区未提交 diff**里（相对 `a456646` / 当前 HEAD）。若 clone 后 `git status` 干净，说明没带上第 2 轮，请停下来向提交人要工作区或补一次 commit。
- 本轮审查范围只有启动/窗口生命周期与启动器：
  - `linux/src/main.js`
  - `linux/install-linux.sh`（生成的 `~/.local/bin/deepseek` wrapper）
  - `linux/arch/deepseek.sh`
  - `linux/package.json`（`scripts.start`、`build.linux.executableArgs`）
  - `linux/README.md` 中 Wayland / ozone 段落
- **本轮不要评**：`.deb` 打包、t64 Depends、glibc/`node-pty`、Debian 图标缓存。那些是同分支上另一条线。

Electron 版本：`linux/package.json` 里 `electron` `^43.4.0`。

---

## 1. 第 1 轮在修什么（机制）

现象（Arch + **niri** + noctalia）：点 DeepSeek → 欢迎屏一闪 → 进程退出（用户称「一击脱出」）。Debian 13 + Xfce/X11 上**发行版 AppImage 不复现**，所以这是 Linux Electron + 纯 Wayland 合成器上的窗口生命周期问题，不是 dsh 服务起不来。

根因叠了几层：

1. **Linux Electron 默认：最后一个 `BrowserWindow` 关闭就 `app.quit()`。**
2. 旧 `runStartup()` **先关欢迎屏再创建主窗口**。关欢迎屏的瞬间窗口数为 0，进程退出。欢迎屏 `skipTaskbar: true`，任务栏上看不到；niri 还可能把后来的主窗口开到别的 workspace，看起来更像闪退。
3. 进程异常退出后 `~/.config/DeepSeek/SingletonLock` 可能残留。第二次点击命中单实例锁，新进程立刻退出。
4. Cursor agent 的 shell 常带 `ELECTRON_RUN_AS_NODE=1`，直接拉 Electron 会当成 Node 跑。这是调试干扰，不是产品根因。

第 1 轮 `a456646` 的声称修复：

| # | 声称 | 代码位置（当时） |
|---|---|---|
| A | 先 `createMainWindow()` 再关欢迎屏 | `runStartup()` |
| B | 监听 `window-all-closed`，只在「splash 阶段且两个窗口都没了」时 `app.quit()`，用来挡默认退出 | `main.js` 当时约 493–500 行 |
| C | 欢迎屏 `closed`：用户 Alt+F4 且仍是 splash 则退出 | `createSplashWindow` |
| D | 主窗口 `closed`：`startupPhase === 'main'` 则退出 | `createMainWindow` |
| E | 主窗口创建后立刻 `show()`，减轻 niri 上 `show:false` 不映射 | `createMainWindow` |
| F | AppImage wrapper：清残留 `SingletonLock`；`export ELECTRON_OZONE_PLATFORM_HINT=x11`；`unset ELECTRON_RUN_AS_NODE` | `install-linux.sh` 生成脚本 |
| G | niri workspace / skipTaskbar **没有代码修**，只写 README | `linux/README.md` |

服务崩溃恢复（第 1 轮就有，不是 niri 专用）：`handleUnexpectedServerExit` 在用户点「重新启动」时：

```text
startupPhase = 'splash'
await closeMainWindow()   // 同步关掉最后一个窗口
await runStartup()        // 再建欢迎屏
```

---

## 2. 第 1 轮交叉验证历史

审查方式：本机 Cursor 实现 → 用户把 **Prefab Anchored Standard / DeepSeek** 当独立审查者，只读（`git show`、读文件、/tmp 抽 asar 比对），三个 subagent：缺陷 / 桌面 Wayland / 启动器。

### 2.1 审查结论摘要（DeepSeek，第 1 轮）

**P1（缺陷审查）**  
新的 `window-all-closed` 会误杀崩溃重启：`handleUnexpectedServerExit` 先把 `startupPhase='splash'`，再 `await closeMainWindow()`。最后一个窗口关闭后，handler 看到 `splash && !splashWindow && !mainWindow` 并 `app.quit()`，`runStartup()` 被退出流程盖掉。

**Wayland**  
- 正常欢迎屏→主窗口：先建主窗再关欢迎屏，不再「零窗口退出」。正常关主窗口走 `closed → app.quit → before-quit → quitApp → shutdownServer`。
- `ELECTRON_OZONE_PLATFORM_HINT=x11` 在 Electron 43.4.0 **无效**；niri 实测只有 `--ozone-platform=x11` 才走 XWayland。`main.js` 里在 `require('electron')` 前后设环境变量都太晚（ozone 是原生初始化）。该 hint 在 Electron v38 已移除，v43 breaking-changes 写明只能用 CLI。
- 提前 `mainWindow.show()` 可能短暂白屏（3 秒兜底仍在）。skipTaskbar / 别的 workspace：**无代码修复**。

**启动器**  
- `SingletonLock` 的 `${lock_target##*-}` 与 Electron `hostname-pid` 格式相符。
- 问题：无数字校验；PID 复用；TOCTOU；`CONFIG_DIR` 在只读 HOME 的 XDG 回退**之前**计算，清不到真实锁目录；Arch `linux/arch/deepseek.sh` **完全没同步**。
- `unset ELECTRON_RUN_AS_NODE` 副作用小，应保留。

### 2.2 当时的唯一实质分歧

- **A**：`window-all-closed` 会杀掉崩溃重启。
- **B（桌面实测）**：认为 `await` 微任务会先于 `window-all-closed` 跑，会先重建欢迎屏，所以安全。

DeepSeek 汇总时按 **Electron 43.4.0 源码**复核：

`NativeWindow::NotifyWindowClosed()` 先同步 emit `closed`，接着  
`WindowList::RemoveWindow → Browser::OnWindowAllClosed → App::OnWindowAllClosed`  
同步 emit `window-all-closed`，**全在微任务检查点之前**。

因此 **A 与源码一致**；B 的「微任务先跑」存疑。第 2 轮按 A 修。

### 2.3 声称 vs 第 1 轮实际（审查表）

| 声称 | 第 1 轮判定 |
|---|---|
| 欢迎屏→主窗口间隙退出已修 | 正常路径有代码；崩溃重启被新 handler 引入回归 → **部分修复** |
| niri 别的 workspace / skipTaskbar | **没修**，只文档化 |
| 残留 SingletonLock 导致二次点击退出 | 仅 AppImage wrapper；只读 HOME 未覆盖；README 偏宽 |
| 默认 `ELECTRON_OZONE_PLATFORM_HINT=x11` | 代码有，但 Electron 43 **无效**；「默认 XWayland」是注释/README 声称 |
| 只拉 git、不重打包 AppImage 就够 | **分发不够**。本机 asar 曾手工打过补丁所以碰巧一致 |

第 1 轮总评：**先修再合。** 方向对，但要先修 P1、把 ozone 改成 CLI、锁清理移到 XDG 回退之后，再在 niri 复测崩溃重启。

---

## 3. 第 2 轮已做的修改（待你验证）

实现方同意第 1 轮「先修再合」，在工作区做了外科手术，**尚未 commit、尚未重打包 AppImage/.deb**。

### 3.1 `window-all-closed`（针对 P1）

`linux/src/main.js` 现为：

```js
app.on('window-all-closed', () => {});
```

意图：只拦截 Linux 默认 quit，**这里不再 `app.quit()`**。退出应走：

- 欢迎屏 `closed`：`!quitting && startupPhase === 'splash'` → `app.quit()`
- 主窗口 `closed`：`!quitting && startupPhase === 'main'` → `app.quit()`
- `quitApp()` / `before-quit`

崩溃重启仍是：`startupPhase='splash'` → `closeMainWindow()` → `runStartup()`。零窗口窗口期不应再被 `window-all-closed` 杀掉。

**请重点推演：**

1. 正常欢迎屏→主窗口（主窗口已先创建）。
2. 用户关主窗口。
3. 用户 Alt+F4 欢迎屏（仍在 splash）。
4. 服务崩溃 → 点「重新启动」（P1 回归）。
5. 启动失败对话框（`startupPhase='failed'`，欢迎屏已关，0 窗口）点「重试」/「退出」。
6. 空 handler 会不会留下无窗口僵尸进程？各 `closed` 是否仍覆盖所有用户退出路径？

### 3.2 Ozone：环境变量 → `--ozone-platform=x11`

已删除 `main.js` 里对 `ELECTRON_OZONE_PLATFORM_HINT` 的赋值。

改为启动参数（用户后续参数可覆盖）：

| 入口 | 做法 |
|---|---|
| AppImage wrapper（`install-linux.sh` 生成） | `exec …AppImage --ozone-platform=x11 "$@"` |
| Arch `linux/arch/deepseek.sh` | `exec /usr/bin/electron --ozone-platform=x11 /opt/deepseek/app "$@"` |
| `package.json` `scripts.start` | `electron --ozone-platform=x11 .` |
| `build.linux.executableArgs` | `["--ozone-platform=x11"]`（`.desktop` Exec，影响 .deb/AppImage 菜单） |

**请核对：** Electron 43 文档是否确实只认 CLI；AppImage 是否会把 `--ozone-platform` 吃成 runtime 参数（对比 `--no-sandbox` 与 `-- --smoke-test` 的既有约定）；直接跑 `/opt/DeepSeek/deepseek` / `./deepseek`（tar.gz）**不经 wrapper、不经 .desktop** 时是否仍无 ozone 标志。

### 3.3 SingletonLock 清理

AppImage wrapper：先做只读 HOME → `XDG_CONFIG_HOME=$PREFIX/config` 回退，**再**算 `CONFIG_DIR`，再清锁。PID 必须整段为数字才 `kill -0`。

Arch 启动器已同步：锁清理 + `unset ELECTRON_RUN_AS_NODE` + `--ozone-platform=x11`。Arch 包一般可写 HOME，**没有** AppImage 那套 prefix 回退。

**请核对：** 只读 HOME 路径现在能否清到真实锁；数字校验是否足够；TOCTOU / PID 复用是否仍应标为已知限制（实现方故意没做成原子）。

### 3.4 明确仍未做

- skipTaskbar / niri 把窗口放到别的 workspace：仍只 README。
- 锁 TOCTOU、PID 复用：只加了数字校验。
- 未重打包；已安装 AppImage 的 asar **不会**自动包含第 2 轮 `main.js`。
- 未在 niri 实机复测崩溃重启（第 1 轮要求的回归，本轮实现后也还没跑）。

---

## 4. 请你交付的内容

用中文，缺陷优先。不要给「感觉更好」的重构。

1. **第 2 轮是否消化了第 1 轮 P1 / ozone / 锁时机？** 逐条：已修 / 部分 / 未修，引用文件与行号。
2. **空 `window-all-closed` 是否引入新的退出漏洞或僵尸进程？** 用 Electron 43 的同步关闭顺序论证，不要用「微任务会先跑」除非你能指出与 v43.4.0 源码不符之处。
3. **ozone CLI 是否真能在 niri 上选 XWayland？** 哪些启动路径仍缺标志。
4. **声称 vs 当前工作区代码** 再填一张表（对应第 1 轮那 5 条声称 + 第 2 轮新增声称）。
5. **总评：** 可以重打包并准备合 `linux` / 还要再修 / 只文档债。给出最短必须再改的列表。

不要修改文件。不要根据本文件的「意图」放水：以代码为准。
