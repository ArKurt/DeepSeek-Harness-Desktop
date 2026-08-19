# Linux 欢迎屏退出修复 — 第 3 轮无头交叉验证

给远程/无头审查者的只读任务书。不要改仓库、不要重打包、不要推送。

**阅读顺序：** 本文件 → `linux/HEADLESS-CROSS-VALIDATION.md`（第 2 轮任务，其中「工作区未提交」已过时）→ `linux/HEADLESS-CROSS-VALIDATION-ROUND2-REPORT.md`（第 2 轮报告）→ 当前树代码。

第 1 / 2 轮结论不要当默认真。本轮要判断：**第 2 轮报告 §5.1 建议 1、2 是否已落地，以及建议 3、4 的实现方陈述是否足以支持「可以合 `linux`」以外的结论。**

---

## 0. 仓库状态

- 分支：`debian-ubuntu-test-plan`（**仍不要**当成 PR #5 / `linux` 的合并候选，除非你的总评明确说可以）。
- 审查 HEAD：请以 clone 时的 `HEAD` 为准；实现方预期至少包含：
  - `a456646` 第 1 轮 niri 修复
  - `a0286d3` 第 2 轮：空 `window-all-closed`、ozone CLI、锁清理顺序
  - `da9b673` 第 2 轮审查报告（只读，不要当代码）
  - `367a8c9` 第 2 轮建议 1+2：`quitting` 守卫 + 文档
- 若 `git log --oneline` 看不到 `367a8c9`，停下来。
- 范围仍是启动/窗口生命周期与启动器：
  - `linux/src/main.js`
  - `linux/install-linux.sh`
  - `linux/arch/deepseek.sh`
  - `linux/package.json`
  - `linux/README.md`、`linux/DEBIAN-UBUNTU-TESTING.md` 中 ozone / GUI 命令
- **不要评** t64 Depends、glibc/`node-pty`、Debian 图标缓存实现细节。`.deb` 的 `Exec` 只按下面「建议 4」核对配置与实现方陈述。

Electron：`package.json` 中 `^43.4.0`。

---

## 1. 前两轮压缩史

**第 1 轮（`a456646`）**  
niri 上欢迎屏一闪退出。根因：Linux 最后一个窗口关闭就 quit + 先关欢迎屏再开主窗口。修复：先建主窗口再关欢迎屏；并加了会 `app.quit()` 的 `window-all-closed`。

**第 1 轮交叉验证（DeepSeek / Prefab）**  
P1：该 handler 会同步误杀「服务崩溃 → 重新启动」（`startupPhase='splash'` 后 `closeMainWindow()`，零窗口时 splash 还不存在）。ozone 环境变量在 Electron 43 无效。锁清理写在 XDG 回退之前。总评：先修再合。

**第 2 轮（`a0286d3`）**  
`window-all-closed` 改为空 handler；启动器改 `--ozone-platform=x11`；锁清理挪到 XDG 回退之后并加 PID 数字校验；Arch 启动器同步。

**第 2 轮无头审查（`linux/HEADLESS-CROSS-VALIDATION-ROUND2-REPORT.md`）**  
P1 / ozone 机制 / 锁时机判定为**已修**。新问题：`runStartup` / `showStartupErrorAndMaybeRetry` 不看 `quitting`，splash 阶段退出后再点「重试」会窗口化僵尸。GUI 测试命令绕开 ozone。直跑二进制无标志。要求 niri 实机跑崩溃重启，并确认 `.deb` 桌面 `Exec`。总评：**先别重打包合 `linux`**，先做建议 1–3。

不要把第 2 轮报告里的行号当现在的行号；以当前文件为准。

---

## 2. 第 2 轮之后实现方声称已做的事

### 2.1 建议 1（代码，在 git 里）

`linux/src/main.js`：

- `showStartupErrorAndMaybeRetry()` 开头：`if (quitting) return;`
- `runStartup()` 开头：`if (quitting) return;`
- **`window-all-closed` 仍是空函数**，没有把 `app.quit()` 加回去。

提交：`367a8c9`。本地跑过 `node test/window-state.test.js && node test/server-crash.test.js`。

**请推演：** 第 2 轮 §2.3 的复现链是否被这两行切断；对话框 `await` 期间 `quitting` 变为 true 之后点「重试」是否仍安全（`runStartup` 守卫 vs 对话框返回后未再检查）；是否引入「用户已退出却弹不出失败框 / 无法重试」的误伤。

### 2.2 建议 2（文档，在 git 里）

- `linux/DEBIAN-UBUNTU-TESTING.md` GUI 命令为：
  `DSH_DESKTOP_HOME=/tmp/dsh-gui ./deepseek --ozone-platform=x11`
- `linux/README.md` 写明：tar.gz `./deepseek`、`.deb` `/opt/DeepSeek/deepseek`、不经 wrapper 的 AppImage **不带** ozone，需手动加。

**请核对** 文档与 `package.json` `executableArgs` / 各 wrapper 是否一致，有无仍在教人直跑且不带标志的命令。

### 2.3 建议 3（niri 实机，不在 git 里）

实现方在 Arch + niri 上用**当前工作区 `main.js`（含 `367a8c9` 守卫）**、独立 `--user-data-dir=/tmp/dsh-niri-retest`、`DSH_DESKTOP_PORT=3098`、`--ozone-platform=x11` 跑过：

1. 启动后主窗口 `DeepSeek Harness`，`app-id=deepseek`，XWayland（进程 cmdline 含 `--ozone-platform=x11`，窗口 PID 落在 `xwayland-satellite`）。
2. `kill` 掉 `bin.js web --port 3098` 后 Electron **未退出**；浮动窗标题 `DeepSeek`，文案「本地服务已停止」，按钮「重新启动 / 退出」。
3. 对对话框发送 Return（默认按钮是「重新启动」）后：测试 Electron PID 仍在；`dsh` 以新 PID 再听 3098；主窗口新 id（当时 `Window ID 16`，Title `DeepSeek Harness`，Workspace 1）。
4. 关闭该主窗口后测试 Electron exit 0，3098 无监听。

缺口（实现方自承）：欢迎屏 `skipTaskbar`，重启过程中**没有**单独截到鲸鱼欢迎屏；只证明进程未退、服务重建、主窗口回来。

无头环境无法复跑 GUI。请判断：这份记录是否足以关闭第 2 轮「必须 niri 实机」的门禁，还是仍要补欢迎屏截图 / 第二次复测。

### 2.4 建议 4（本地重打包，产物不在 git）

`linux/dist/` gitignore。实现方在 `367a8c9` 之后重打 `.deb`，从 `data.tar.xz` 抽出：

```
Exec=/opt/DeepSeek/deepseek --ozone-platform=x11 %U
```

即 `package.json` `build.linux.executableArgs` 被 electron-builder 26.15.3 写进 `.desktop`。

**未**在 Debian 13 上重装该新 `.deb`。请判断：配置 + 解包核对是否够；CLI `/usr/bin/deepseek` 仍无标志是否必须再包一层 wrapper。

---

## 3. 请你交付

用中文，缺陷优先。不要重构建议。

1. **建议 1、2 是否已消化第 2 轮 P 级残留？** 已修 / 部分 / 未修，引用当前行号。
2. **空 `window-all-closed` + `quitting` 守卫是否还留退出漏洞或僵尸？** 用 Electron 43 同步关闭顺序，不要用「微任务先跑」。
3. **建议 3、4 的实现方陈述你采信到什么程度？** 哪些仍必须实机，哪些可标文档债。
4. **声称 vs 当前 git 树** 填表（含守卫、文档、niri、`.deb` Exec）。
5. **总评：** 可以准备合 `linux` / 还要再修 / 只剩文档债或发布步骤。给出最短必须再改的列表。

不要修改文件。以代码为准；实现方的 niri / 解包陈述标为「未独立复现」。
