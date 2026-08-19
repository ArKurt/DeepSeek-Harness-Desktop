# 第 3 轮无头交叉验证 — 审查报告

对 `linux/HEADLESS-CROSS-VALIDATION-ROUND3.md` 的回复。只读审查：未修改被审代码、未重打包、未推送产物。

- 审查对象：`debian-ubuntu-test-plan` @ `2848666`（含 `367a8c9` *Guard startup against quit races and document ozone on raw binaries.*）
- 阅读顺序按任务书：ROUND3 → `HEADLESS-CROSS-VALIDATION.md`（第 2 轮任务书）→ `HEADLESS-CROSS-VALIDATION-ROUND2-REPORT.md` → 当前树代码
- 审查范围：`linux/src/main.js`、`linux/install-linux.sh`、`linux/arch/deepseek.sh`、`linux/package.json`、`linux/README.md`、`linux/DEBIAN-UBUNTU-TESTING.md`
- 按任务书要求，**未评** `.deb` 的 t64 Depends / glibc / `node-pty` / 图标缓存；`.deb` 只核对 `Exec` 与 ozone 配置
- 行号以当前树为准，非第 2 轮报告的行号

**已核实的仓库状态：** `git log --oneline -3` = `2848666` / `367a8c9` / `da9b673`；`git merge-base --is-ancestor 367a8c9 HEAD` 为真。`git show 367a8c9 -- linux/src/main.js` 的 diff 确实只有两行 `if (quitting) return;`（`showStartupErrorAndMaybeRetry` 与 `runStartup` 入口），`window-all-closed` 未被改动。全提交共 3 个文件 5 增 1 删。

---

## 1. 建议 1、2 是否已消化第 2 轮 P 级残留

### 1.1 建议 1（`quitting` 守卫）— **已修**

| 位置 | 现状 |
|---|---|
| `src/main.js:366` | `showStartupErrorAndMaybeRetry()` 首行 `if (quitting) return;` |
| `src/main.js:433` | `runStartup()` 首行 `if (quitting) return;` |
| `src/main.js:495` | `app.on('window-all-closed', () => {});` 仍为空，**没有**把 `app.quit()` 加回去（正确，加回去会让第 1 轮 P1 复发） |

**第 2 轮 §2.3 复现链是否被切断：是，切在第 2 步。** 逐步复核：

1. `:135` 欢迎屏 `closed`（Alt+F4，`startupPhase === 'splash'`）→ `app.quit()`；
2. `:485-489` `before-quit` 见 `cleanedUp === false` → `preventDefault()` + `quitApp()`；`quitApp()`（`:477-483`）在第一个 `await` 之前**同步**执行 `quitting = true`（`:479`），所以此后所有守卫立即可见；
3. 仍挂在 `await server.ensureServer()`（`:449`）的 `runStartup` 因服务被杀而失败 → `:456-457` 调 `showStartupErrorAndMaybeRetry()` → **`:366` 直接 return**，「DeepSeek 启动失败」对话框不再弹出；
4. 第 2 轮那条「弹框 → 点重试 → `:385` `runStartup()` → `:436` `createSplashWindow()` 在 `quitting === true` 下复活窗口」的路径，源头（第 3 步）已经消失。

**对话框 `await` 期间 `quitting` 变 true、之后点「重试」是否仍安全：安全，但是靠 `runStartup` 的守卫兜住，`showStartupErrorAndMaybeRetry` 对话框返回后确实不再复检。** 具体：该函数进入时 `quitting` 为假（`:366` 放行），执行到 `:372` 打开无父窗口对话框；此刻 0 窗口，Linux 上应用菜单随窗口消失，因此期间把 `quitting` 置真的现实来源只有 `:498-502` 的 SIGTERM/SIGINT/SIGHUP → `app.quit()` → `before-quit` → `quitApp()`。用户随后点「重试」时：

- `:383-385`「重试」分支 → `startupPhase = 'splash'` → `await runStartup()` → **`:433` 立即 return**，不建欢迎屏、不起服务；
- `:387`「退出」分支 → `quitApp()` → `:478` `if (quitting) return` 自锁，同样是空操作。

即两条分支在 `quitting === true` 时都退化为**空操作**，不会复活窗口 → 第 2 轮那个「窗口化僵尸」不成立。副作用是 `startupPhase` 被留在 `'splash'`，但此时 `:135` / `:300` 的守卫都带 `!quitting`，phase 值已无意义。

**是否引入「用户已退出却弹不出失败框 / 无法重试」的误伤：无。** `quitting` 只在 `quitApp()`（`:479`）一处被置真，而 `quitApp()` 的全部调用点都是明确的退出意图：`:272`（界面加载失败框选「退出」）、`:387`（启动失败框选「退出」）、`:428`（崩溃框选「退出」）、`:488`（`before-quit`）。不存在「用户没要退出但 `quitting` 为真」的状态，因此守卫不会吞掉正常的失败提示。这与 `:252` `showLoadFailureDialog` 早就有的 `quitting` 判断也保持了一致。

### 1.2 建议 2（文档）— **已修，覆盖面差一条**

| 文件 | 现状 | 与 `package.json` / wrapper 一致性 |
|---|---|---|
| `DEBIAN-UBUNTU-TESTING.md:107` | `DSH_DESKTOP_HOME=/tmp/dsh-gui ./deepseek --ozone-platform=x11` | ✅ 与 `package.json:67-69` `executableArgs`、`install-linux.sh:123-127`、`arch/deepseek.sh:22`、`package.json:12` `scripts.start` 全部一致 |
| `README.md:85-86` | 「启动器默认附加 `--ozone-platform=x11`；Electron 43 已忽略 `ELECTRON_OZONE_PLATFORM_HINT`；要原生 Wayland 用 `deepseek --ozone-platform=wayland`」 | ✅ 与 `main.js:3-4` 注释、各 wrapper「标志在 `"$@"` 之前」的写法一致 |
| `README.md:87-88` | 「直跑二进制不带该标志，需手动加：tar.gz 的 `./deepseek`、`.deb` 的 `/opt/DeepSeek/deepseek`、不经 wrapper 的 AppImage」 | ⚠️ 见下方 F5 |

**仍在教人直跑且不带标志的命令：** 逐条核对 `DEBIAN-UBUNTU-TESTING.md` 里所有拉起可执行文件的命令：

- `:77` `./deepseek --smoke-test --no-sandbox --disable-gpu` — 冒烟路径走 `main.js:52-54` → `runSmokeTest()`，不建任何 `BrowserWindow`，与 ozone 无关，**不需要**标志；
- `:88` / `:94` AppImage `-- --smoke-test` — 同上；
- `:107` GUI 实机 — 已带标志 ✅；
- `:139` `deepseek --no-sandbox --disable-gpu --smoke-test` — .deb 装完后走 PATH 上的 `deepseek`，仍是冒烟，**不需要**标志。

结论：**没有遗留「GUI 直跑却不带标志」的命令**，建议 2 的字面要求已满足。缺口在 F5（README 的直跑清单漏了 PATH 上的 `deepseek`）与 F6（.deb 段完全没有 GUI 步骤）。

---

## 2. 空 `window-all-closed` + `quitting` 守卫是否还留退出漏洞或僵尸

前提沿用第 1/2 轮的 A 结论：Electron 43 中 `NotifyWindowClosed()` 同步 emit `closed`，随后 `WindowList::RemoveWindow → Browser::WindowAllClosed → App` 同步 emit `window-all-closed`，整条链在回到 JS 微任务检查点之前跑完，不能用「`await` 微任务会先跑」论证。

> **披露：本轮同样未读到 v43.4.0 的 C++ 源码**（`linux/node_modules` 未安装，无头环境未拉 Electron 源码）。此前提是结构性复核，与第 2 轮报告 §2.1 的披露一致，未新增证据。

### 2.1 退出路径是否仍然完备

空 handler 之后，唯一的退出入口是显式 `app.quit()`：`:136`（splash `closed` 且 phase 为 `'splash'`）、`:300`（main `closed` 且 phase 为 `'main'`）、`:319` 菜单「文件→退出」的 `role: 'quit'`、`:482` `quitApp()` 末尾、`:500` 信号处理。逐个 phase 核对窗口覆盖：

| phase | 存在的窗口 | 关掉它谁负责退出 |
|---|---|---|
| `'splash'`（首启） | 欢迎屏 | `:135-137` ✅ |
| `'splash'`（崩溃重启中，`:424` 起） | 先 0 窗口、再欢迎屏 | 关主窗口时 `:300` 因 phase 为 `'splash'` 不退（这正是 P1 的修法）；新欢迎屏由 `:135-137` 覆盖 ✅ |
| `'main'` | 主窗口 | `:300` ✅ |
| `'failed'` | 0 窗口 + 一个无父对话框 | 由对话框「退出」→ `:387` `quitApp()` 覆盖 ✅（欢迎屏在 `:367` 把 phase 改成 `'failed'` **之后**才于 `:369` 关闭，所以 `:135` 的 `=== 'splash'` 守卫不会误退，顺序正确） |

**没有发现哪个 phase 下用户可见的窗口关闭后无人负责退出。** 第 2 轮报告 §2.3 那条唯一的漏洞已被建议 1 堵住。

### 2.2 F1（低危，残留）：`runStartup()` 只在入口检查 `quitting`，成功分支不复检

`runStartup()` 在 `:433` 检查一次之后要经过两个 `await`：`:449` `server.ensureServer()`、`:454` `waitMinSplash()`（`SPLASH_MIN_MS = 5200`，**最长 5.2 秒**）。失败分支在 `:457` 被 `showStartupErrorAndMaybeRetry` 的 `:366` 二次守住，**成功分支 `:461-468` 没有任何复检**：

```
:461 startupPhase = 'main';
:465 createMainWindow(url);
:466-468 关闭欢迎屏
```

可达的时序：首启 splash 阶段，服务已就绪、正卡在 `waitMinSplash` 的剩余等待里（这是个几秒量级的宽窗口），用户此时 Alt+F4 欢迎屏 → `:136` `app.quit()` → `quitApp()` 置 `quitting = true` → `await shutdownServer()`（`server-manager.js` 的 `shutdown` 为 SIGTERM + 最长 3 秒宽限 + SIGKILL，有界）→ `cleanedUp = true` → `:482` `app.quit()`。

若 `shutdownServer` 耗时长于 `waitMinSplash` 的剩余时间，`:465` 会**在 `quitting === true` 之后创建主窗口**。

**后果：不构成僵尸。** 随后 `quitApp()` 的 `app.quit()` 会关闭全部窗口并走完 `before-quit`（`:486` `cleanedUp` 为真直接放行）→ `will-quit` → 退出；新建的主窗口在退出序列里被销毁，`:300` 的 `!quitting` 为假只是不再重复 `app.quit()`，不影响这次退出。用户可见后果最多是**退出过程中主窗口闪一下**。

判定 **P3**：不阻塞合入，但正确性依赖「`quitApp` 的 `app.quit()` 一定会到」这一条外部保证，而不是 `runStartup` 自身的不变量；`quitting` 的守卫在这条路径上是不完整的。

### 2.3 F2（低危，残留）：对话框返回后没有人补发 `app.quit()`

承 §1.1 的结论：`quitting === true` 时，`showStartupErrorAndMaybeRetry` 的两条分支都变成空操作（`:385` 的 `runStartup` 被 `:433` 挡下；`:387` 的 `quitApp` 被 `:478` 自锁）。这意味着**进程能否退出，完全取决于更早那次 `app.quit()` 是否在 0 窗口 + 一个无父窗口 GTK 对话框仍在运行的情况下走完退出序列**。

- 该行为无头环境**无法验证**（需要真 GTK 会话）。
- 若那次 `app.quit()` 被对话框的原生消息循环挡住，则对话框关闭后没有任何代码补发退出 —— 但也不会有窗口被复活，属于「进程滞留」而非第 2 轮那种「僵尸窗口 + 占端口」。
- 触发条件很窄：必须在「启动失败对话框已打开」期间收到 SIGTERM/SIGINT/SIGHUP（会话注销、`kill`）。

判定 **P3 / 文档债**。同一类的还有第 2 轮报告 §2.4 已记录的项：`:498-502` 的信号处理在 `quitting === true && cleanedUp === false` 的约 3 秒窗口内会被 `before-quit` 吞掉，因 `shutdownServer` 有界而自愈，本轮复核仍然成立、仍可不修。

### 2.4 F3（证据缺口）：`npm test` 不覆盖本次改动

`package.json:16` 的 `test` = `node test/window-state.test.js && node test/server-crash.test.js`。本轮实跑，两个都通过：

```
WINDOW STATE TEST PASSED
SERVER CRASH TEST PASSED
```

但读过用例后必须指出：`test/server-crash.test.js` 只驱动 `ServerManager`（假 dsh 起 HTTP 服务 → `process.exit(23)` → 断言 `unexpected-exit` 事件与 `shutdown` 不卡死），**完全没有加载 `main.js`**；`test/window-state.test.js` 只测 `window-state` 的读写。仓库里**没有任何用例触及 `quitting`、`runStartup`、`showStartupErrorAndMaybeRetry` 或窗口生命周期**。

因此「本地跑过 `node test/window-state.test.js && node test/server-crash.test.js`」对建议 1 只是**非回归信号**，不是验证。建议 1 目前的全部依据是代码走查（本报告 §1.1）+ 建议 3 的实机记录（间接覆盖崩溃重启，不覆盖 splash-退出-再重试这条竞态）。**§1.1 那条竞态至今没有被任何自动或人工手段执行过。**

---

## 3. 建议 3、4 的实现方陈述采信程度

**统一标注：以下 niri 实机记录与 `.deb` 解包结果均为实现方陈述，本轮无头环境未独立复现。**

### 3.1 建议 3（niri 实机）— 采信为「已完成第 2 轮列出的 4 步」，欢迎屏截图降为文档债

第 2 轮 §5.1 建议 3 列的 4 步与实现方陈述逐条对照：

| 第 2 轮要求 | 实现方陈述 | 判定 |
|---|---|---|
| 1. 启动 → 欢迎屏→主窗口无闪退 | 主窗口 `DeepSeek Harness`、`app-id=deepseek`、cmdline 含 `--ozone-platform=x11`、窗口 PID 落在 `xwayland-satellite` | 覆盖，且顺带证明 ozone CLI 在 niri 上真的走了 XWayland（第 2 轮 §3 只有文档推理） |
| 2. kill 服务子进程 → 出现「本地服务已停止」 | kill `bin.js web --port 3098` 后 Electron 未退出；浮动窗标题 `DeepSeek`、文案「本地服务已停止」、按钮「重新启动 / 退出」 | 覆盖 |
| 3. 点「重新启动」→ 欢迎屏重建、进程不退出、主窗口恢复 | Electron PID 不变；`dsh` 以新 PID 重听 3098；主窗口新 id | **三项要求中的两项直接证实**（进程不退、主窗口恢复），「欢迎屏重建」未截到 |
| 4. 记录 `niri msg windows` | 记录了窗口 id / Title / Workspace | 覆盖 |

**判断：足以关闭第 2 轮「必须 niri 实机」这道门禁。** 理由是这道门禁要证的命题是「第 1 轮 P1 的回归已经不复发」，而 P1 的失败模式是**进程在零窗口窗口期被 `window-all-closed` 杀掉**。「测试 Electron PID 仍在 + 主窗口以新 id 回来」直接否证了这个失败模式；欢迎屏在这条链上是中间态，它若没建起来，主窗口也回不来（`runStartup` 里 `:436` 建欢迎屏在前、`:465` 建主窗口在后，是同一条 `await` 链）。所以缺欢迎屏截图不改变结论，只是证据不够漂亮。

**但有两条必须记账：**

- **F4（证据未落盘）：这份实机记录不在仓库任何文件里。** `DEBIAN-UBUNTU-TESTING.md` 的 §4 只有通用检查点，没有本次 niri 崩溃重启复测的结果。下一轮或发布时无法复查这次到底跑了什么。建议把这段记录（含 `--user-data-dir=/tmp/dsh-niri-retest`、`DSH_DESKTOP_PORT=3098`、`niri msg windows` 输出）追加进 `DEBIAN-UBUNTU-TESTING.md`。
- **该实机跑的是崩溃重启路径，不是建议 1 修的那条路径。** 建议 1 针对的是「splash 阶段退出 → 再点重试」，实机没有覆盖（也很难手动构造）。这条仍然只有代码走查支撑，见 F3。

### 3.2 建议 4（`.deb` 的 `Exec`）— 菜单路径采信，CLI 路径判为文档债

**已在当前树核实的配置端：** `package.json:67-69` `"executableArgs": ["--ozone-platform=x11"]`，`:66` `"executableName": "deepseek"`。实现方从 `data.tar.xz` 抽出的

```
Exec=/opt/DeepSeek/deepseek --ozone-platform=x11 %U
```

与该配置一致，且与 electron-builder 把 `executableArgs` 拼进 `.desktop` `Exec` 的既有行为吻合。**未独立复现**（无头环境未装 `node_modules`、未重打包），但配置 + 解包两端互相印证，**判定：够用，不必在 Debian 13 上重装该 `.deb` 才放行**。这也把第 2 轮 §3.1 表格里那行 ⚠️「.deb 经应用菜单」从「未验证」推进为「已核实（未独立复现）」。

**CLI `/usr/bin/deepseek` 仍无标志：判为文档债，不必再包一层 wrapper。** 理由：

1. 欢迎屏退出这个 bug 的修复主体在 JS（`:463-468` 先建主窗口再关欢迎屏 + `:495` 空 `window-all-closed`），**不依赖 XWayland**；`--ozone-platform=x11` 是针对 niri 上 `show:false` 不映射等合成器怪癖的加固，不是修复本体。少这个标志的路径是「体验降级」，不是「bug 复发」。
2. 再包一层 wrapper 会与 electron-builder 的 `executableName` / `/usr/bin` 符号链接打架，改动面比它挡住的风险大。
3. `README.md:87-88` 已经把「直跑不带标志」写清楚了。

代价是：Wayland 会话的用户在终端敲 `deepseek` 时会跑原生 Wayland。这一点应当补文档（F5）。

### 3.3 F5（文档缺口）：README 的「直跑」清单漏了 PATH 上的 `deepseek`

`README.md:87-88` 列了三条：tar.gz 的 `./deepseek`、`.deb` 的 `/opt/DeepSeek/deepseek`、不经 wrapper 的 AppImage。**漏了 `.deb` 装完后 PATH 上的 `deepseek`**（electron-builder 生成的 `/usr/bin` 符号链接）—— 而这恰恰是最常见的终端调用方式，`DEBIAN-UBUNTU-TESTING.md:139` 自己就是这么调的。同理 `DEBIAN-UBUNTU-TESTING.md:142-143` 只说了「可执行文件默认在 `/opt/DeepSeek/deepseek`」，没提 PATH 上的那个。

### 3.4 F6（文档缺口）：`.deb` 段没有 GUI 步骤，也没把 `Exec` 核对写进测试计划

`DEBIAN-UBUNTU-TESTING.md` §5 装完 `.deb` 之后只有 `xvfb-run … --smoke-test` 的无头冒烟（`:137-140`）和一句「检查系统菜单」（`:142`），**既没有 GUI 启动步骤，也没有第 2 轮建议 4 要求的 `grep Exec /usr/share/applications/deepseek.desktop` 核对**。也就是说建议 4 的验证是这次一次性手工做掉的，没有沉淀成任何人下次能重跑的步骤。

### 3.5 F7（观察，无影响）：`package.json` 的 `desktopName` 放错了层级

`package.json:89` 的 `"desktopName": "deepseek.desktop"` 是 **`build` 对象之外的顶层键**（顶层键序列：… `devDependencies`、`build`、`desktopName`），`build.linux` 里没有该键，electron-builder 读不到它。因为默认 `.desktop` 文件名就是 `${executableName}.desktop` = `deepseek.desktop`，**实际结果恰好正确，无影响**；仅作为「看着像已配置、其实没生效」的误导项记录。属 `.desktop` 生成配置，与任务书排除的 t64/glibc/图标缓存无关。

---

## 4. 声称 vs 当前 git 树

| # | 声称 | 判定 | 依据 / 位置 |
|---|---|---|---|
| 1 | `showStartupErrorAndMaybeRetry()` 开头加 `if (quitting) return;` | **属实** | `src/main.js:366`；`git show 367a8c9` 确认 |
| 2 | `runStartup()` 开头加 `if (quitting) return;` | **属实** | `src/main.js:433`；`git show 367a8c9` 确认 |
| 3 | `window-all-closed` 仍是空函数、未加回 `app.quit()` | **属实**（且正确，加回会让 P1 复发） | `src/main.js:495` |
| 4 | 这两行切断第 2 轮 §2.3 的僵尸链 | **成立** | 本报告 §1.1；链的第 3 步被 `:366` 截断，第 4 步的窗口复活被 `:433` 兜底 |
| 5 | 未引入「已退出却弹不出失败框」的误伤 | **成立** | `quitting` 仅在 `:479` 置真，四处调用点均为明确退出意图 |
| 6 | 本地 `node test/window-state.test.js && node test/server-crash.test.js` 通过 | **属实，但不构成对本次改动的验证** | 本轮实跑均 PASSED；两个用例都不加载 `main.js`（F3） |
| 7 | `DEBIAN-UBUNTU-TESTING.md` GUI 命令已带 `--ozone-platform=x11` | **属实** | `DEBIAN-UBUNTU-TESTING.md:107` |
| 8 | `README.md` 写明直跑二进制不带 ozone 标志 | **基本属实，清单漏一条** | `README.md:85-88`；漏 PATH 上的 `deepseek`（F5） |
| 9 | niri 实机：启动走 XWayland、`app-id=deepseek` | **未独立复现**，采信 | 实机陈述；与 `arch/deepseek.sh:22`、`README.md:100-104` 一致 |
| 10 | niri 实机：kill 服务后 Electron 未退出、弹「本地服务已停止」 | **未独立复现**，采信 | 实机陈述；与 `main.js:405-420` 一致 |
| 11 | niri 实机：点「重新启动」后进程未退、服务重建、主窗口新 id | **未独立复现**，采信；这是 P1 已修的直接证据 | 实机陈述；对应 `main.js:423-426`、`:300`、`:495` |
| 12 | niri 实机：未单独截到欢迎屏重建 | **属实的自承缺口**，判为不影响结论 | 本报告 §3.1 |
| 13 | 重打包后 `.deb` 的 `Exec=/opt/DeepSeek/deepseek --ozone-platform=x11 %U` | **未独立复现**，采信；与配置端互证 | `package.json:66-69` + 解包陈述 |
| 14 | 未在 Debian 13 重装新 `.deb` | **属实**，判为可接受 | 本报告 §3.2 |
| 15（第 2 轮遗留）| 只拉 git 不重打包就够 | **仍不够** | 已装的 AppImage/.deb 内 asar 不含 `367a8c9` 的 `main.js`，合入后必须重打包 |
| 16（第 2 轮遗留）| 锁清理、Arch 启动器同步、ozone CLI 覆盖 | **维持第 2 轮判定，本轮未变** | `install-linux.sh:102-127`、`arch/deepseek.sh:5-22`、`package.json:12,67-69` |

---

## 5. 总评

**代码层面：可以准备合 `linux`。**

第 1 轮的三个 P 级问题（`window-all-closed` 误杀崩溃重启、ozone 机制、锁清理时机）在第 2 轮已实修；第 2 轮唯一的 P 级残留（`quitting` 守卫缺失导致的窗口化僵尸）在 `367a8c9` 已实修，两行改动、位置正确、没有顺手把 `app.quit()` 加回 `window-all-closed`。第 2 轮把「先别合」的理由明确定位为「关键回归没在 niri 上跑过」，这条门禁现在有了实机记录（未独立复现，但覆盖了要求的 4 步中最关键的第 3 步），可以关闭。

**本轮新发现的问题全部是 P3 或文档债，没有一条构成合入阻塞：**

- F1 `runStartup()` 成功分支不复检 `quitting`，可在退出中创建主窗口 —— 由 `quitApp()` 的 `app.quit()` 兜住，最多闪一下窗口（§2.2）
- F2 对话框返回后无人补发 `app.quit()`，窄条件下可能进程滞留 —— 无头不可验证（§2.3）
- F3 测试套件完全不覆盖 `main.js` 的窗口/退出逻辑，「测试通过」不是对建议 1 的验证（§2.4）
- F4 niri 实机记录未落盘到仓库（§3.1）
- F5 README 直跑清单漏了 PATH 上的 `deepseek`（§3.3）
- F6 `.deb` 段无 GUI 步骤、无 `Exec` 核对步骤（§3.4）
- F7 `desktopName` 放在 `build` 外层，未生效但结果恰好正确（§3.5）

### 5.1 最短必须再改

**代码：0 项。** 不需要为合入再改任何产品代码。

**合入前必做的非代码项（2 项，都是把已有事实落盘）：**

- [ ] **把 niri 崩溃重启复测记录写进 `DEBIAN-UBUNTU-TESTING.md`**（F4）。含 `--ozone-platform=x11`、`--user-data-dir=/tmp/dsh-niri-retest`、`DSH_DESKTOP_PORT=3098`、`niri msg windows | rg -i deepseek` 输出，以及「欢迎屏未单独截图」这个自承缺口。理由：这是本轮放行的**唯一实机证据**，不落盘等于下一轮又要重跑。
- [ ] **`README.md:87-88` 的直跑清单补上 `.deb` 装完后 PATH 上的 `deepseek`**（F5）。理由：这是终端里最常见的调用方式，也是 `DEBIAN-UBUNTU-TESTING.md:139` 自己在用的方式，漏掉会让 Wayland 用户以为自己走了 XWayland。

**合入时的发布步骤（不是代码缺陷，但漏了等于白合）：**

- [ ] **重打包 AppImage / tar.gz / `.deb`**。已装产物内的 asar 不含 `a0286d3` + `367a8c9` 的 `main.js`（声称 15）。
- [ ] 重装后跑一次 `grep Exec /usr/share/applications/deepseek.desktop`，确认 `--ozone-platform=x11` 在位（这次是手工核的，顺手固化）。

### 5.2 可留作文档债（本轮不必改）

- F1 / F2：`runStartup` 成功分支与对话框返回后的 `quitting` 复检（P3；若将来重构启动流程再一并收敛）
- F3：给 `main.js` 的退出竞态补一个可跑用例（当前 `test/` 三个用例都不加载 `main.js`）
- F6：`.deb` 段补 GUI 测试步骤与 `Exec` 核对
- F7：`desktopName` 挪进 `build.linux`（当前无影响）
- 第 2 轮已列且仍未修，本轮复核维持原判：锁的 TOCTOU / PID 复用；`install-linux.sh:102` 系统 prefix 不可写时的只读 HOME 边角；非符号链接的 `Singleton*` 残留（`install-linux.sh:109` / `arch/deepseek.sh:7` 的 `[ -L ... ]` 入口条件）—— 其中 `README.md:99` 已补了「也可先 `pkill -x deepseek` 再开」，缓解到位；`skipTaskbar` / niri workspace；`main.js:498-502` 信号在 3 秒窗口内被吞（自愈）

---

## 附：本轮未做的验证

1. 未读 Electron v43.4.0 的 C++ 源码（`linux/node_modules` 未安装）—— §2 的同步关闭顺序仍是结构性复核，与第 2 轮同一披露。
2. **niri 实机记录未独立复现**（无头环境无 GUI 会话）。
3. **`.deb` 重打包与 `data.tar.xz` 解包未独立复现**（未装 `node_modules`、未重打包）。
4. 未验证 0 窗口 + 无父窗口 GTK 对话框存续期间 `app.quit()` 的实际行为 —— F2 因此只能标为「无头不可验证」。
5. 未实机运行任何产物；未修改任何被审文件。
