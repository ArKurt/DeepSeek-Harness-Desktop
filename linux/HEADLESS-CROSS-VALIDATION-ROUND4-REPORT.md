# 第 4 轮无头交叉验证 — 审查意见与建议

只读审查：未修改被审代码、未重打包、未推送产物、未合并任何分支。

- **审查对象：** `merge/debian-ubuntu-curated` @ `65d14e9`（5 个提交，落在 `origin/linux` = `d6bd9b8` 之上）
- **本报告所在分支：** `debian-ubuntu-test-plan`（沿用前三轮，审查稿不进入合并分支）
- **前三轮：** `HEADLESS-CROSS-VALIDATION.md`（第 2 轮任务书）、`HEADLESS-CROSS-VALIDATION-ROUND2-REPORT.md`、`HEADLESS-CROSS-VALIDATION-ROUND3.md`、`HEADLESS-CROSS-VALIDATION-ROUND3-REPORT.md`
- **本轮新增范围（前三轮未评）：** `.deb` 打包配置、启动器硬化、CI/Release 工作流，以及 GitHub 官方 PR / 合并 / Release 规范对照

第 3 轮任务书里「不要评 `.deb` 打包细节」的限制，本轮由提交人明确解除。

---

## 0. 已核实的仓库事实

| 项 | 值 | 核实方式 |
|---|---|---|
| 审查分支 HEAD | `65d14e9` | `git rev-parse` |
| 基线 | `origin/linux` = `d6bd9b8`，未被推进 | `git rev-parse` |
| 净 diff 规模 | 11 个文件，+439 / -23 | `git diff --stat origin/linux...origin/merge/debian-ubuntu-curated` |
| 审查稿是否排除 | 是，分支内无 `*CROSS-VALIDATION*` 文件 | `git ls-tree -r --name-only` |
| PR #5 位置 | 上游 `XinXie-Condex/DeepSeek-Harness-Desktop#5`，head `ArKurt:linux` → base `main` | `gh pr view 5` |
| PR #5 状态 | OPEN / MERGEABLE / 无 review decision / `maintainerCanModify: true` | 同上 |
| PR #5 实际内容 | 相对**当前**上游 main 为 **8 个提交**，全部 Linux 相关，无夹带 | `git log origin/linux ^<upstream/main>` |
| 上游 main 历史形状 | 20 个提交，**0 个 merge commit** | `git rev-list --merges --count` |
| fork main vs 上游 main | 双向分叉 **6 / 6** | `git rev-list --left-right --count` |

---

## 1. 第 3 轮遗留项的消化情况

本轮先复核第 3 轮报告 §5.1 的清单，`merge/debian-ubuntu-curated` 上的结果：

| 第 3 轮编号 | 要求 | 状态 | 位置 |
|---|---|---|---|
| F4 | niri 实机记录落盘 | **已做** | 新增 `linux/STARTUP-FIX-VALIDATION.md`；4 步记录、`--user-data-dir=/tmp/dsh-niri-retest`、`DSH_DESKTOP_PORT=3098`、「欢迎屏未单独截图」自承缺口齐全 |
| F5 | README 直跑清单补 PATH 上的 `deepseek` | **已做** | `linux/README.md:95-96` |
| F1 | `runStartup()` 成功分支复检 `quitting` | **已做，超出清单** | `src/main.js:465`，位于 `waitMinSplash()` 之后、分支之前；到 `createMainWindow()` 之间无 `await`，对 `quitting` 是原子的 |
| F2 | 对话框返回后补发退出 | **已做，超出清单** | `src/main.js:385-388` `if (quitting) { app.quit(); return; }`。两种时序都安全：`cleanedUp` 已真则直接放行；仍在关服务的 3 秒窗口内会被 `before-quit` 吞掉，但 `quitApp()` 自身末尾那次 `app.quit()` 仍会到 |
| F3 | 补 `main.js` 退出竞态的自动化用例 | **未做，已明确记为文档债** | 实现方在 `STARTUP-FIX-VALIDATION.md` 标注；**判定：可接受**，见 §5 |
| F6 | `.deb` 段补 `Exec` 核对 | **部分做到** | 进了 CI（`65d14e9`），但断言无效，见 §2 缺陷 2 |
| F7 | `desktopName` 层级 | 未动 | 见 §2 缺陷 7 |

结论：第 3 轮开出的两项「合入前必做」全部完成，且顺手收掉了两条 P3。**第 3 轮的门禁已全部关闭。**

---

## 2. 缺陷清单（按严重度）

### P1 — 会让「验证」形同虚设

#### 缺陷 1：CI 的 `.deb` 冒烟缺 `--ozone-platform=headless`，大概率直接失败

位置：`.github/workflows/build-linux.yml:63-64`、`.github/workflows/release-linux.yml` 同一段（`65d14e9`）。

紧邻的上一步（`build-linux.yml:54`）是：

```
./dist/linux-unpacked/deepseek --smoke-test --ozone-platform=headless --no-sandbox --disable-gpu
```

新加的这步是：

```
deepseek --smoke-test --no-sandbox --disable-gpu
```

三条事实叠在一起构成失败：

1. runner 上没有 `DISPLAY`；
2. Electron 43 的 `--ozone-platform` 默认值是 `auto`，`app.whenReady()` 阶段就要初始化平台 —— 上一步之所以显式写 `headless` 正是为此；
3. `.deb` 装出来的 `/usr/bin/deepseek` **既不经过 `.desktop`**（拿不到 `executableArgs` 里的 `--ozone-platform=x11`），也没有 wrapper。

而仓库自己的 `DEBIAN-UBUNTU-TESTING.md:137-140` 在同一条路径上是用 `xvfb-run` 的，CI 里 xvfb 和 `headless` 两样都没有。

**影响：** 在 `release-linux.yml` 里失败 = 打了 `linux-v*` 标签后发布中断。

**最小改法：** 给这两步补 `--ozone-platform=headless`，与上一步对齐。

#### 缺陷 2：`grep Exec` 不是断言，标志掉了照样绿

位置：两个工作流的 `Smoke test installed deb` 步骤。

```bash
grep Exec /usr/share/applications/deepseek.desktop
```

只要文件里存在任何一行含 `Exec` 就退出 0。`executableArgs` 若哪天失效、或 electron-builder 升级改了行为，这条**不会**变红，只会在日志里安静地打印一行没有标志的 `Exec=`。

这一步的出发点正是第 3 轮 F6 要求的「把手工核对固化进测试计划」，方向对，但目前挡不住回归。

**最小改法：** `grep -q -- '--ozone-platform=x11' /usr/share/applications/deepseek.desktop`。

### P2 — 运行时风险

#### 缺陷 3：`deb.depends` 缺 `libgbm1`

位置：`linux/package.json` `build.deb.depends`（`be60e9f`）。

electron-builder 的 `depends` 是**整体替换**默认值，不是追加。当前这份 = 默认列表 + `libasound2` 的 t64 alternatives。t64 写法本身正确（见 §3）。

问题在于**缺什么**：仓库自己的 `DEBIAN-UBUNTU-TESTING.md` §2 在装 AppImage 运行依赖时明确列了 `libgbm1`、`libxkbcommon0`、`libdrm2`，而 `deb.depends` 里一个都没有。其中 `libdrm2` 会随 `libgbm1` 进来、`libxkbcommon0` 一般由 GTK3 带进来，但 **`libgbm1` 没有任何一条现有 Depends 会拉它** —— Chromium/Electron 直接链 `libgbm.so.1`。

**为什么现有验证全都测不出来：** GitHub runner 和任何装了 mesa 的桌面机都自带 `libgbm1`。本地 Arch 构建机、CI runner、Debian 13 桌面全都覆盖不到。暴露场景是最小化安装 / 容器 / 无 GPU 的服务器：`apt install` 干净成功，一启动就报缺库。

**最小改法：** `deb.depends` 里加 `libgbm1`；`libxkbcommon0`、`libdrm2` 属于「便宜的保险」，加不加都行。

#### 缺陷 4：AppImage wrapper 的 `--ozone-platform=x11` 透传与仓库自己的文档相互矛盾，且从未验证

位置：`linux/install-linux.sh:125,127` 生成的 wrapper（`f5f0f71`）：

```sh
exec "$INSTALLED_APPIMAGE" --ozone-platform=x11 "$@"
```

而 `DEBIAN-UBUNTU-TESTING.md:81-88` 白纸黑字写着：AppImage 运行时会把 `--smoke-test` 吃掉（`bad option`，退出码 9），**必须**加 `--` 才能把参数交给应用。

这两件事不可能同时为真：

- 若 AppImage 运行时会拒绝未知长选项，则 wrapper 里没有 `--` 的 `--ozone-platform=x11` 同样会被拒 → **wrapper 是坏的**，且用户通过 wrapper 跑 `deepseek --smoke-test` 也会踩同一个坑；
- 若不会拒绝，则 `DEBIAN-UBUNTU-TESTING.md` 关于 `--` 的那段结论需要修正。

**现有证据都没覆盖到这条路径：**

- 第 2 轮报告 §3.3 对此明确标注为「文档推理，未实机验证」；
- 第 3 轮的 niri 实机跑的是 Arch 的 `/usr/bin/electron` 路径；
- 本轮实现方的 AppImage smoke test 未说明是否经 wrapper、是否带 `--`。

**判定：P2，合并前应验一次**（现在已有产物，成本极低）。

**决定性验证：** 装完后用 wrapper 起 GUI，读 `/proc/<pid>/cmdline` 是否含 `--ozone-platform=x11`。用 smoke test 验会被 `--smoke-test` 自身是否被吃掉这个变量污染，不干净。

### P3 — 记账即可

5. **安装时的 icon cache 刷新多半是空转。** `install-linux.sh:135-137` 的 `gtk-update-icon-cache -f "$ICON_BASE" >/dev/null 2>&1 || true`：用户级 `~/.local/share/icons/hicolor` 通常没有 `index.theme`，该命令会失败并被 `|| true` 吞掉，缓存没建成。不影响正确性（无缓存时 GTK 直接扫目录），但注释承诺的效果实际只在**卸载**路径成立。需要真建缓存的话要加 `--ignore-theme-index`。
6. **`kill -0` 的 EPERM 被当成「进程已死」。** `install-linux.sh:112-114` / `arch/deepseek.sh:10-13`：锁 PID 若属于其他用户的进程，`kill -0` 返回 EPERM（非零），会走进删锁分支。锁在自己 `$HOME` 下，实际风险低；与前两轮记录的 TOCTOU / PID 复用同属一类，维持文档债。
7. **`desktopName` 仍在 `build` 对象之外。** `package.json` 顶层键，electron-builder 读不到；因默认值恰好是 `${executableName}.desktop` = `deepseek.desktop`，结果正确、无影响。第 3 轮 F7 的原样遗留。
8. **`Upload artifacts` 排在 `.deb` 冒烟之后。** `build-linux.yml:66-74`：冒烟一失败就一个产物都拿不到，排查时只能重跑。建议 `if: always()` 或把 upload 前移。

---

## 3. 判定正确的部分

| 项 | 依据 |
|---|---|
| t64 alternatives 语法 | `libgtk-3-0t64 \| libgtk-3-0` 等；apt 在 Debian 12 / Ubuntu 22.04（pre-t64）与 Debian 13 / Ubuntu 24.04（t64）两边都能解析到可安装的一侧 |
| `maintainer` 补齐 | deb 目标必需字段，缺失时 electron-builder 直接报错 |
| `artifactName` | 产出 `DeepSeek-1.0.1-amd64.deb`，与 `DEBIAN-UBUNTU-TESTING.md` §5 的命令和 CI 的 `DeepSeek-*.deb` glob 三处一致 |
| `linux-v*` 标签触发 | 与仓库既有 `win-v*` / `mac-v*` 约定一致（上游有专门提交 *Unify release tag naming to mac-v\* and win-v\**，说明这是有意维护的约定） |
| `permissions: contents: write` | `release-linux.yml` 有；`release-windows.yml` 反而没有，此处是更好的实践 |
| `fail_on_unmatched_files: true` | `.deb` 缺失时发布会失败，而不是静默少一个包 |
| wrapper 标志位置 | `--ozone-platform=x11` 在 `"$@"` 之前，用户后置参数可覆盖，与 `README.md:85-86` 的说法一致 |
| 卸载时 icon cache 处理 | 顺序正确（先删 PNG 再刷缓存），`\|\| rm -f` 降级合理，注释解释了 why |
| Arch 启动器与 AppImage wrapper 的锁清理 | 均在 XDG 回退之后计算 `CONFIG_DIR`，PID 有纯数字校验（第 2 轮判定，本轮复核未变） |

---

## 4. 声称 vs 实际

### 4.1 本轮实现方的构建与校验陈述

**统一标注：以下均为实现方在其构建机（`/home/kurt`）上的陈述，本审查环境无 `linux/dist` 产物，未独立复现。**

| # | 声称 | 判定 |
|---|---|---|
| 1 | `fakeroot` 未缺失（`1:1.37.2-3` 已装） | **采信，且据此纠正本审查方的错误假设**，见 §4.2 |
| 2 | 真实失败是 `EROFS: read-only file system, mkdir '/home/kurt/.cache/electron/...'` | **采信**。与 `install-linux.sh:102-107` 早就在处理的「只读 HOME」是同一类环境约束，自洽 |
| 3 | 用 `ELECTRON_CACHE` / `XDG_CACHE_HOME` 后单独 deb 成功 | 采信 |
| 4 | 完整 `./build-linux.sh --skip-runtime --skip-npm-install` 三种产物全部生成 | 采信；体积（AppImage 228M / tar.gz 209M / deb 166M）与内置 Node + dsh runtime 的形态相符 |
| 5 | deb `control` 的包名/版本/架构/Depends 正确 | **采信，但不构成对缺陷 3 的反驳** —— 该核对验证的是「写进去的都对」，不覆盖「该写的没写」（`libgbm1`） |
| 6 | `data.tar.xz` 中 `Exec=/opt/DeepSeek/deepseek --ozone-platform=x11 %U`、`StartupWMClass=deepseek` | 采信。这是第 3 轮建议 4 在**新产物**上的第二次确认，比第 3 轮更强 |
| 7 | unpacked / AppImage / deb 解包后三处 `deepseek` 冒烟均 `DSH_SMOKE_CLEAN`、退出码 0 | 采信。**但不覆盖缺陷 1 与缺陷 4**：构建机有图形会话（ozone `auto` 可用），与无 `DISPLAY` 的 runner 不同；且未说明 AppImage 那次是否经 wrapper、是否带 `--` |
| 8 | F3 仍无自动化用例，已在 `STARTUP-FIX-VALIDATION.md` 标为文档债 | **属实且处理得当**：不在合并里假装解决，符合前几轮一贯的诚实标注做法 |

### 4.2 本审查方上一轮的错误假设，记录在案

上一轮口头排查时，本审查方依据「本机 `fakeroot` 缺失 + `build-linux.sh` 唯一变量是新增 `deb` 目标」推断 `Error: [object Object]` 源于 deb 工具链缺 `fakeroot`。**该假设被实现方的 `DEBUG=electron-builder` 实测证伪**：真实原因是 Electron 缓存目录落在只读 HOME 上。

教训值得记进流程：`Error: [object Object]` 这类不透明错误，**先 `DEBUG=electron-builder` 拿到真实堆栈再假设**，环境差异（本审查机 `/home/licha` vs 构建机 `/home/kurt`）会让「本机缺什么」这类推断失效。

---

## 5. GitHub 官方规范与礼仪对照

依据 GitHub 官方文档：《About merge methods on GitHub》《Best practices for pull requests》《About releases》。

### 5.1 PR

- **小而聚焦。** 官方原话 "Small, focused pull requests are easier to review and safer to merge"。PR #5 目前 43 文件 / +6044 / -41，再并入 curated 的 5 个提交会更大。**建议：** 把「`.deb` 打包 + CI」与「Wayland 启动生命周期修复」拆成两个 PR —— 后者是 bugfix、有实机证据链，前者是 feature、需要多发行版验证，评审关注点完全不同，捆在一起会让任一方拖住另一方。
- **标题与描述要说清 why / what / where。** PR #5 标题仍是 *"Add Linux desktop shell (Electron) for Garuda/Arch"*，而分支早已把 Garuda 措辞泛化为 Arch（`d6bd9b8`），现在又加了 Debian/Ubuntu 的 `.deb`。**标题已过期两轮**；由于上游用 squash（见 §5.2），这个过期标题会作为提交信息永久留在 main 的历史里。合并前必须改。
- **改动 workflow 要主动说明安全面。** 官方特别点名涉及 dependencies / workflows / permissions 的 PR。`65d14e9` 动了两个工作流，其中 `release-linux.yml` 带 `contents: write`，应在 PR 描述里主动交代。
- **同步 base。** 上游 main 已前进 6 个提交（Windows 1.0.2 那批）。本轮逐 hunk 核对过：上游改的是根 `README.md` 的 Windows 段（33、73 行），curated 改的是 Linux 表格与 Linux 段（19、38-54 行），**不重叠，可干净自动合并**，所以不构成阻塞；但 PR 页面显示 16 个提交、按当前 base 实为 8 个的口径差异会一直在，同步一次即可对齐。

### 5.2 合并

官方三种方式：merge commit 保留全部提交并留下显式合并点；squash 压成单个提交，适合短命分支；rebase 逐个提交线性接到 base 上、不留合并点但重写为新提交。

**关键事实：上游 main 20 个提交、0 个 merge commit** —— 该仓库事实上使用 squash 或 rebase。

由此得出两条对本次合并有直接影响的结论：

1. **curated 分支精心切分的 5 个提交，在 squash 下会被压成 1 个。** 这份 curation 的价值主要在**评审阶段**（让审查者能按主题分块读），而非最终历史。若希望这 5 个提交在 main 上留存，需要在 PR 中明确请求维护者使用 **rebase merge**。
2. **官方明确警告的 squash 陷阱正是本仓库的形状：** squash 合并后若继续使用同一 head 分支开新 PR，后续 PR 会带上已被压进 base 的提交，同一批冲突要解两遍。PR #5 的 head 是长命分支 `linux`，且 fork 的 main 上已自行合入同一批 Linux 提交（`55d0ef3` … `243c87c`，均**不在**上游 main 上）。**建议：** 上游 squash 合并 PR #5 之后，fork 的 main 不要去 merge 上游，直接 `reset --hard` 到上游 main，否则同一份改动会在历史里存在两套提交。

### 5.3 Release

官方要点：release 建立在 git tag 之上，tag 创建时间与发布时间可不同；release notes 可手写或自动生成；单个 release 最多 1000 个资产、单文件上限 2 GiB。

对照本仓库：

- 标签 `linux-v*` 与既有 `win-v*` / `mac-v*` 一致 ✅
- `generate_release_notes: true` 即官方自动生成 ✅
- `.deb` 已加入 `files` 且 `fail_on_unmatched_files: true` ✅；三个产物合计约 600 MB，单文件 228 MB，远低于 2 GiB 上限 ✅
- **建议补一步：先发 pre-release。** `.deb` 是全新分发形态，缺陷 3 那类依赖问题只会在真实用户机上暴露。先打 `linux-v1.0.1-rc1` 并标记 pre-release，验证后再发正式版；`softprops/action-gh-release` 支持 `prerelease:` 参数。
- **仓库无 `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md`。** 作为外部贡献者向他人仓库提 PR，在没有成文规范时，把「怎么构建、怎么测、我测了什么」写进 PR 描述本身就是最实用的礼仪 —— `linux/STARTUP-FIX-VALIDATION.md` 正好可以在 PR 描述里链过去。

---

## 6. 总评

**代码主体可以合入 `linux`；阻塞项全部集中在 CI 与打包元数据，不在产品代码。**

第 3 轮的两项门禁已关闭，两条 P3 也被顺手收掉，`main.js` 的退出路径本轮无新发现。本轮四条实质缺陷里，两条（缺陷 1、2）让新加的 CI 验证要么直接红、要么永远不红，正好把「新增 `.deb` 分发」这件事最需要的自动化保障抵消掉了；另两条（缺陷 3、4）是真实用户机上才会暴露的运行时风险。

### 6.1 最短必须再改

**合并前必改（3 项，都是几行）：**

- [ ] **缺陷 1** — 两个工作流的 `Smoke test installed deb` 补 `--ozone-platform=headless`，与相邻步骤对齐。**否则 `release-linux.yml` 会在发版时中断。**
- [ ] **缺陷 2** — `grep Exec ...` 改为 `grep -q -- '--ozone-platform=x11' ...`，让这一步真正能失败。
- [ ] **缺陷 3** — `deb.depends` 加 `libgbm1`。

**合并前应验一次（1 项，已有产物，成本极低）：**

- [ ] **缺陷 4** — 经 `~/.local/bin/deepseek` wrapper 起一次 GUI，读 `/proc/<pid>/cmdline` 确认含 `--ozone-platform=x11`。若确认透传正常，顺带修正 `DEBIAN-UBUNTU-TESTING.md:81` 关于 `--` 的表述；若被吃掉，wrapper 需要加 `--`。

**强烈建议在合并前做（一条命令，能一次性验掉缺陷 1、2 与整条打包链）：**

```bash
gh workflow run "Build Linux" --repo ArKurt/DeepSeek-Harness-Desktop --ref merge/debian-ubuntu-curated
```

`build-linux.yml` 的分支触发条件只有 `main` / `linux`，所以这段 CI 在合并前**永远不会自己跑**；但该工作流带 `workflow_dispatch` 且在 fork 上处于 active，可以手动指定 ref 跑。这是唯一能在合并**之前**看到新 CI 步骤真实结果的办法。

**PR / 发布流程（见 §5）：**

- [ ] 改 PR #5 标题与描述（当前标题已过期两轮，squash 后会永久留在 main）
- [ ] 在 PR 中明确希望的合并方式（默认 squash 会压掉 curated 的 5 个提交）
- [ ] 发布先走 `linux-v1.0.1-rc1` pre-release

### 6.2 维持文档债

- F3：`main.js` 窗口生命周期 / 退出竞态仍无自动化用例（实现方已在 `STARTUP-FIX-VALIDATION.md` 明确标注，本轮认可这一处理）
- 缺陷 5 — 安装时 icon cache 刷新空转
- 缺陷 6 — `kill -0` 的 EPERM 分支；锁的 TOCTOU / PID 复用
- 缺陷 7 — `desktopName` 层级（当前无影响）
- 缺陷 8 — CI 产物上传顺序
- 前几轮遗留且本轮复核未变：`install-linux.sh:102` 系统 prefix 不可写时的只读 HOME 边角；非符号链接的 `Singleton*` 残留；`skipTaskbar` / niri workspace

---

## 附：本轮未做的验证

1. **未独立复现实现方的构建与产物校验**（本审查环境无 `linux/dist`，构建发生在另一台机器 `/home/kurt`）。
2. **未实机运行任何产物**，包括缺陷 4 所需的 wrapper GUI 验证。
3. 未在 Debian 13 / Ubuntu 24.04 上实际 `apt install` 该 `.deb`，缺陷 3 是配置与仓库自身文档的比对结论，非实测。
4. 未运行 CI，缺陷 1 是依据「相邻步骤为何显式传 `headless`」与「runner 无 `DISPLAY`」的推理结论。
5. 未读 Electron v43.4.0 的 C++ 源码（沿用前两轮同一披露）。
6. 未修改任何被审文件、未合并任何分支、未触碰 `origin/linux` 与 PR #5。
