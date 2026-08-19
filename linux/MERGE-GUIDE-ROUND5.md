# 合并交接书：`merge/debian-ubuntu-curated` → `linux` → PR #5

> **本文件不进入 PR #5。** 合并进 `linux` 之前必须先
> `git rm linux/MERGE-GUIDE-ROUND5.md` 并单独提交。
> 它和已删除的 `REVIEW-HANDOFF-ROUND5.md` 是同一类内部交接文档。

## 0. 给下一位 agent 的第一句话

第 5 轮审查已完成，结论是 **可以合入 `linux`**，无 P1、无阻塞项。审查中发现的
3 项问题已在本分支上各自独立提交修好。你的任务是**执行合并并更新 PR #5**，
不是重新审查。委托人明确要求：**不要 merge PR #5 本身**（那是上游作者的决定）。

## 1. 坐标

| 项 | 值 |
|----|----|
| 本地仓库 | `/home/kurt/Projects/dsh desktop/DeepSeek-Harness-Desktop` |
| fork remote | `fork` → `https://github.com/ArKurt/DeepSeek-Harness-Desktop.git` |
| upstream remote | `origin` → `https://github.com/XinXie-Condex/DeepSeek-Harness-Desktop.git` |
| PR | #5，`ArKurt:linux` → `XinXie-Condex:main`，OPEN |
| PR 标题（待改） | `Add Linux desktop shell (Electron) for Garuda/Arch` |
| 待合入分支 | `merge/debian-ubuntu-curated` |
| 目标分支 | `linux`（PR #5 的 head，合并后 PR 自动更新） |
| 无关分支 | `feature/tray-minimize`、`debian-ubuntu-test-plan`（只读档案），**都不要动** |

## 2. 第 5 轮审查结论摘要

**总评：可以合入 `linux`。** P1 = 0。

已在本分支修复（每项一个提交）：

| 级别 | 问题 | 提交 |
|------|------|------|
| P2 | CI 两处冒烟只看退出码。`--smoke-test` 跑在 `app.requestSingleInstanceLock()` **之后**，命中单实例锁时 `app.quit()` 也返回 0，冒烟会静默"通过"而其实什么都没测。已改为 `tee` + `grep -q DSH_SMOKE_CLEAN` 断言，并把 `.desktop` 断言锚到 `^Exec=` 行 | `52b9a5b` |
| P3 | `install-linux.sh` 安装分支的 `gtk-update-icon-cache ... \|\| true`。用户级 `~/.local/share/icons/hicolor` 通常没有 `index.theme`，该命令必然失败（本机实测 `No theme index file`），残留的旧 `icon-theme.cache` 会继续遮住新图标。已与卸载分支统一为 `\|\| rm -f .../icon-theme.cache` | `7cd5807` |
| P3 | 两处文档与实物不符：AppImage 的 `--smoke-test` 透传（实测不需要 `--` 分隔）、`scripts/prebuild.js` 只是探测不构建 | `59cc830` |

**已核对无误、不要再改的点**（实物核验，非转述）：

- `deb` control：`Depends` 覆盖 electron-builder 26 默认 9 项 + `libgbm1` +
  `libasound2t64 | libasound2`，t64 alternatives 写法正确。
- `.desktop`：`Exec=/opt/DeepSeek/deepseek --ozone-platform=x11 %U`、
  `StartupWMClass=deepseek`、7 档 hicolor 图标齐全。
- `desktopName` 保持 package.json **顶层**正确：
  `app-builder-lib/out/targets/LinuxTargetHelper.js` 读的是
  `packager.info.metadata.desktopName`。第 3 轮 F7 建议确认不成立。
- `src/main.js` 生命周期：`window-all-closed` 空 handler + 先建主窗口再关欢迎屏
  + 各处 `quitting` 守卫，逻辑自洽；崩溃重启路径先置
  `startupPhase='splash'` 再 `closeMainWindow()`，不会被 `closed` handler 误杀。
- `build-linux.sh` 的 node-pty 兜底：`PTY_NODE` 用绝对路径、子 shell 里 `cd`
  不影响判断、`NODE_GYP` 两级回退、`set -e` 下子 shell `exit 1` 会正确冒泡。

**已知限制（记录在案，不阻塞，`STARTUP-FIX-VALIDATION.md` §4 已写）**：

- `.deb` / tar.gz 直跑二进制不带 `--ozone-platform=x11`，也没有 `Singleton*`
  清理（只有 AppImage wrapper 和 Arch 启动器有）。README 已说明。
  若上游希望统一，后续可把清理逻辑上移到 `main.js`，本轮不做。
- Singleton 锁清理存在 TOCTOU / PID 复用窗口。
- node-gyp 会在 `node-pty/node-addon-api/*.target.mk` 留下含构建机绝对路径的
  中间文件（`build/` 下的已被清掉，这几个不在 `build/` 下所以漏网）。
  CI 产物里是 `/home/runner/...`，无敏感信息，P3。

## 3. 合并前置检查

```bash
cd "/home/kurt/Projects/dsh desktop/DeepSeek-Harness-Desktop"
git fetch --all --prune
git status --short --branch          # 必须 clean
git log --oneline linux..merge/debian-ubuntu-curated
```

确认：

1. `linux` 分支 HEAD 仍是 `d6bd9b8`（审查期间不得被推进）。若已变，先停下问委托人。
2. `merge/debian-ubuntu-curated` 与 `fork/merge/debian-ubuntu-curated` 一致。
3. `cd linux && npm test` → `WINDOW STATE TEST PASSED` + `SERVER CRASH TEST PASSED`。

## 4. 执行合并

```bash
cd "/home/kurt/Projects/dsh desktop/DeepSeek-Harness-Desktop"

# 1) 先删掉本交接文档，单独提交
git checkout merge/debian-ubuntu-curated
git rm linux/MERGE-GUIDE-ROUND5.md
git commit -m "Remove the round-5 merge handoff document"

# 2) 合入 linux（保留整理过的提交历史，不要 squash）
git checkout linux
git merge --no-ff merge/debian-ubuntu-curated \
  -m "Merge Linux Debian/Ubuntu packaging and Wayland startup fixes"

# 3) 推送，PR #5 自动更新
git push fork linux
```

**squash 陷阱**：`linux` 是 PR #5 的 head 分支，历史已经推到 GitHub。
不要在 `linux` 上 rebase 或 squash 已推送的提交，否则 PR 的评论行号会全部错位。

## 5. 推送后

1. 确认 CI 触发并通过。`build-linux.yml` 的 push 触发分支包含 `linux`：

   ```bash
   gh run list --repo ArKurt/DeepSeek-Harness-Desktop --branch linux --limit 5
   gh run watch --repo ArKurt/DeepSeek-Harness-Desktop <run-id>
   ```

   全绿的判据包括新加的 `grep -q DSH_SMOKE_CLEAN` 两处断言。

2. 更新 PR #5 标题与描述。当前标题还是 Garuda/Arch 时代的措辞，已经不准确。

   建议标题：

   ```text
   Add Linux desktop shell (Electron) with Debian/Ubuntu .deb packaging
   ```

   描述要点：

   - Electron 43 + 内置 Node v24 + `@deepseek-ai/dsh`，自动拉起 `dsh web`；
   - 分发形态：`.deb`（新增）/ AppImage / tar.gz / Arch PKGBUILD；
   - 修复 niri / 纯 Wayland 上"欢迎屏一闪退出"（先建主窗口再关欢迎屏、
     `window-all-closed` 只拦默认行为、退出竞态守卫）；
   - 启动器统一附加 `--ozone-platform=x11`（Electron 43 已忽略
     `ELECTRON_OZONE_PLATFORM_HINT`），用户可用 `--ozone-platform=wayland` 覆盖；
   - workflow 变更：`build-linux.yml` / `release-linux.yml` 增加 deb 打包、
     apt 安装冒烟、`.desktop` 与 `DSH_SMOKE_CLEAN` 断言，产物/Release 资产加 `.deb`；
   - 测试方式：`cd linux && npm test`；三种形态 `--smoke-test` 均核对
     `DSH_SMOKE_CLEAN`；文档见 `linux/DEBIAN-UBUNTU-TESTING.md`、
     `linux/STARTUP-FIX-VALIDATION.md`；
   - 建议合并方式：**merge commit 或 rebase，不要 squash**（提交已按主题整理过）。

3. **不要 merge PR #5。** 委托人已明确：合并与否由上游作者决定。

## 6. 发布（等上游合并后再做，本轮不做）

建议先打 `linux-v1.0.1-rc1` 做 pre-release 验证 `release-linux.yml` 的
资产列表（含 `.deb`）与 deb 安装冒烟，再打正式标签。
`STARTUP-FIX-VALIDATION.md` §6 有完整检查单。
