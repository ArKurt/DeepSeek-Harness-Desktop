# 第 5 轮交叉审查交接书（本地 Claude / Cursor）

> 本文档只用于本轮审查交接，**不进入 PR #5**。
> 若后续要把 `merge/debian-ubuntu-curated` 合入 `linux`，请先删除本文件再合并。

## 0. 给审查员的第一句话

你是第 5 轮交叉审查员，运行在本地 Cursor 中。请只读审查，**不要修改代码、不要打包、
不要推送、不要合并**，除非委托人明确要求你执行后续任务。审查目标、历史、证据和待办
都在本文档里，结论请按第 7 节的格式输出。

## 1. 项目简介

DeepSeek-Harness-Desktop 是把 DeepSeek Harness Web UI 打包成桌面应用的仓库：

- 上游：`XinXie-Condex/DeepSeek-Harness-Desktop`
- 当前工作 fork：`ArKurt/DeepSeek-Harness-Desktop`
- Linux 版技术栈：Electron 43 + 内置 Node v24 + `@deepseek-ai/dsh`，自动拉起
  `dsh web` 并用 Chromium 窗口承载
- 目录：`linux/` 是 Electron 桌面壳源码、打包脚本、测试与文档
- 分发形态：AppImage、tar.gz、Arch PKGBUILD，本轮新增 Debian/Ubuntu `.deb`

## 2. 项目目录

```text
/home/kurt/Projects/dsh desktop/DeepSeek-Harness-Desktop
```

建议 Cursor 打开该目录后执行：

```bash
git fetch --all --prune
git status --short --branch
git log --oneline --decorate --graph -20
```

审查分支应当已检出：`merge/debian-ubuntu-curated`。

## 3. 当前任务和目标

上游作者在 PR #5 中问能否提供直接可安装的 `.deb`（面向 Ubuntu / Debian）。我们在
`debian-ubuntu-test-plan` 分支上完成了：

- `.deb` 打包支持；
- niri / 纯 Wayland 上欢迎屏一闪退出问题修复；
- 启动器 ozone 参数、SingletonLock 清理、图标缓存处理；
- 多轮无头交叉验证。

随后把净改动整理到审查分支 `merge/debian-ubuntu-curated`，目标是**在合并前把质量
和证据夯实**，合并进 `linux` 后自动更新 PR #5。

## 4. 关键分支状态

| 分支 | 含义 | 当前 HEAD | 注意 |
|------|------|-----------|------|
| `linux` | PR #5 的 head（`ArKurt:linux`） | `d6bd9b8` | 审查期间不得推进 |
| `merge/debian-ubuntu-curated` | **本轮审查对象** | `3c31d65` | 已推送 fork |
| `debian-ubuntu-test-plan` | 1–4 轮验证档案分支 | `8cc740a` | 只读档案 |
| `feature/tray-minimize` | 托盘功能计划分支 | `c74bb75` | **完全无关，不要评** |

审查对象相对 `linux` 的净 diff：

```bash
git diff --stat linux...merge/debian-ubuntu-curated
git diff --name-status linux...merge/debian-ubuntu-curated
```

## 5. 审查机制和历史

### 5.1 机制

每一轮由一位独立审查员（远程无头 / 本地）只读审查代码、产物陈述和证据，输出：
缺陷清单（P1/P2/P3）、声称 vs 实际对照表、总评（可合入 / 必须再修 / 只文档债）。
实现方只根据审查结论修代码，审查稿不进入最终合并分支。

### 5.2 历史

| 轮次 | 对象 | 关键结论 |
|------|------|----------|
| 第 1 轮 | niri/Wayland 欢迎屏退出修复 | 发现 `window-all-closed` 误杀崩溃重启（P1）、`ELECTRON_OZONE_PLATFORM_HINT` 在 Electron 43 无效、锁清理时机错误 |
| 第 2 轮 | `a0286d3` | P1/ozone/锁时机判定已修；新发现 `quitting` 守卫缺失导致窄条件窗口化僵尸 |
| 第 3 轮 | `2848666` + `367a8c9` | 代码层面可以准备合 `linux`；要求 F4 落盘 niri 记录、F5 补 README 直跑清单、发布前重打包 |
| 第 4 轮 | `merge/debian-ubuntu-curated @ 65d14e9` | 3 项必改（CI headless、grep 断言、`libgbm1`）+ 1 项必验（AppImage wrapper ozone 透传）；并给出 PR 标题/描述、squash 陷阱、pre-release 建议 |

原始审查稿都在 `debian-ubuntu-test-plan` 分支上，可这样查看：

```bash
git show fork/debian-ubuntu-test-plan:linux/HEADLESS-CROSS-VALIDATION.md
git show fork/debian-ubuntu-test-plan:linux/HEADLESS-CROSS-VALIDATION-ROUND2-REPORT.md
git show fork/debian-ubuntu-test-plan:linux/HEADLESS-CROSS-VALIDATION-ROUND3.md
git show fork/debian-ubuntu-test-plan:linux/HEADLESS-CROSS-VALIDATION-ROUND3-REPORT.md
git show fork/debian-ubuntu-test-plan:linux/HEADLESS-CROSS-VALIDATION-ROUND4-REPORT.md
```

### 5.3 对第 4 轮结论的两处修正

1. **F7 不成立。** electron-builder 26.15.3 源码（`LinuxTargetHelper.js`、
   `metadata.d.ts`）确认 `desktopName` 必须放在 package.json 顶层，用于生成
   `.desktop` 文件名并推导 `StartupWMClass`。现配置正确，不要挪层级。
2. **fakeroot 假设已由 `DEBUG=electron-builder` 实测证伪。** 真实失败是只读 HOME
   上的 Electron 缓存目录，与本分支处理只读 HOME 的环境约束同源。

## 6. 第 4 轮意见的执行结果

审查分支当前提交（`d6bd9b8..3c31d65`）：

```text
be60e9f Package Linux desktop as a .deb for Debian/Ubuntu
d0ab962 Fix Linux startup lifecycle on Wayland and guard quit races
f5f0f71 Harden Linux launchers for ozone, singleton locks, and icons
96f7564 Document Debian/Ubuntu packaging and Linux startup validation
65d14e9 Ship the Linux .deb in CI artifacts and releases
9642307 Address round-4 review: harden deb CI and dependencies
bcfdb73 Clarify AppImage wrapper ozone passthrough after live verification
3c31d65 Build node-pty explicitly when npm skips its install script
```

第 4 轮 4 项阻塞项：

1. **deb CI 冒烟缺 headless** → 两个工作流已加 `--ozone-platform=headless`。
2. **grep Exec 不是断言** → 改为 `grep -q -- '--ozone-platform=x11' ...`。
3. **deb.depends 缺 libgbm1** → 已加 `libgbm1`。
4. **wrapper 的 ozone 透传未验** → 已实测通过：主进程 cmdline 含
   `--ozone-platform=x11`，窗口正常映射，`WM_CLASS=deepseek`；文档矛盾已修正。

额外修复：CI 上 npm install 后未生成 `pty.node`，`build-linux.sh` 现在会在缺失时
显式执行 node-pty 的 prebuild，并在必要时用所选 Node 自带的 node-gyp 现场编译。

## 7. 已验证的证据（实现方陈述 + 可复核日志）

### 7.1 本地构建机（`/home/kurt`，只读 HOME 环境）

```bash
cd "/home/kurt/Projects/dsh desktop/DeepSeek-Harness-Desktop/linux"
npm test
# WINDOW STATE TEST PASSED
# SERVER CRASH TEST PASSED

DEBUG=electron-builder ./build-linux.sh --skip-runtime --skip-npm-install
# EXIT=0，产出：
#   DeepSeek-1.0.1-x86_64.AppImage
#   DeepSeek-1.0.1-x64.tar.gz
#   DeepSeek-1.0.1-amd64.deb
```

deb 解包核对：

- `Depends` 含 t64 alternatives 与 `libgbm1`
- `Exec=/opt/DeepSeek/deepseek --ozone-platform=x11 %U`
- `StartupWMClass=deepseek`
- 图标与目录结构完整

三种运行形态 smoke 均通过：

- `dist/linux-unpacked/deepseek --smoke-test` → PASS
- AppImage（`APPIMAGE_EXTRACT_AND_RUN=1`）→ PASS
- deb 解包后的 `/opt/DeepSeek/deepseek --smoke-test` → PASS

### 7.2 GitHub Actions（审查分支手动触发）

```bash
gh run view --repo ArKurt/DeepSeek-Harness-Desktop 32280227248
```

- `merge/debian-ubuntu-curated @ 3c31d65`
- 结果：`✓ build in 23m44s`
- 所有步骤通过，包括：
  - `Assemble runtime and smoke test`（node-pty 显式构建兜底触发并成功）
  - `Package AppImage, tar.gz, and deb`
  - `Smoke test installed deb`（`DSH_SMOKE_CLEAN`）
  - `Upload artifacts`（`DeepSeek-Linux`）

## 8. 本轮审查范围

请重点审查当前分支相对 `linux` 的全部改动，尤其是：

1. `linux/build-linux.sh`：node-pty 显式构建兜底的正确性、路径解析、错误处理；
2. `.github/workflows/build-linux.yml` / `release-linux.yml`：deb 安装冒烟与断言；
3. `linux/package.json`：deb target、`deb.depends`、`executableArgs`、顶层
   `desktopName`；
4. `linux/src/main.js`：窗口生命周期与 `quitting` 竞态修复；
5. `linux/install-linux.sh` / `linux/arch/deepseek.sh`：ozone 参数、锁清理、
   图标缓存；
6. 文档：`linux/README.md`、`linux/DEBIAN-UBUNTU-TESTING.md`、
   `linux/STARTUP-FIX-VALIDATION.md`、根 `README.md`。

不要评：

- `feature/tray-minimize`（完全独立）；
- 原始审查稿的措辞（它们不进入 PR）；
- 版本号 / 发布标签（上游合并后再定）。

## 9. 请交付的审查结论

用中文，缺陷优先：

1. P1/P2/P3 缺陷清单，引用文件与行号；
2. “声称 vs 实际”对照表；
3. 总评：可以合入 `linux` / 必须再修 / 只剩文档债；
4. 最短必须再改清单（若有）。

## 10. 审查通过后的执行交接

若委托人指示继续执行，按以下顺序操作：

1. 在 `merge/debian-ubuntu-curated` 上应用最终修复（每个修复独立提交）；
2. 重跑 `npm test`，必要时重新触发 CI；
3. **删除本交接文档**（`git rm linux/REVIEW-HANDOFF-ROUND5.md`）并单独提交；
4. 合入 `linux`（建议保留整理后的提交历史）：

   ```bash
   git checkout linux
   git merge --no-ff merge/debian-ubuntu-curated \
     -m "Merge Linux Debian/Ubuntu packaging and Wayland startup fixes"
   git push fork linux
   ```

5. 推送后 PR #5 自动更新；确认 CI 触发并通过；
6. PR 页面更新标题/描述，说明改动、测试方式、workflow 变更与建议的合并方式；
7. 发布事项等上游合并后再处理（建议先 `linux-v1.0.1-rc1` pre-release）。
