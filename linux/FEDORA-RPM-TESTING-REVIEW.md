# Fedora / RPM 测试计划 — 交叉验证审查报告

对 `linux/FEDORA-RPM-TESTING.md` §6「建议的交叉验证问题」的回复。

只读审查：未修改被审文档、未改打包配置、未打包、未合并任何分支。

- **审查对象：** `fedora-rpm-test-plan` @ `1d854d2` *Add Fedora/RPM cross-validation test plan.*
- **基线：** `origin/linux` @ `6f67e6a`（已含 Debian/Ubuntu 那条线的全部合并结果）
- **前置：** `HEADLESS-CROSS-VALIDATION-ROUND2/3/4-REPORT.md`（Debian/Ubuntu 与启动生命周期线，位于 `debian-ubuntu-test-plan`）

被审文档明确要求「审查通过前不要改仓库」，本报告遵守：以下所有配置建议均为**待落地**，本轮未改 `package.json` / `build-linux.sh` / CI。

---

## 0. 已核实的仓库事实

| 项 | 值 | 核实方式 |
|---|---|---|
| 分支基点 | `origin/linux` = `6f67e6a`，`merge-base` 一致 | `git merge-base` |
| 本分支提交 | 仅 `1d854d2`，只增 `linux/FEDORA-RPM-TESTING.md`（+276） | `git diff --stat origin/linux...` |
| 无夹带文件 | 是 | 同上 |

顺带复核第 4 轮的四项必改（现已在 `origin/linux` 上），**全部落地，且强于原要求**：

| 第 4 轮项 | 现状 | 位置 |
|---|---|---|
| 缺陷 1：CI `.deb` 冒烟缺 headless ozone | 已补，且两处冒烟都加了 `\| tee` + `grep -q DSH_SMOKE_CLEAN`，不再只信退出码 | `build-linux.yml:54-58, 67-69` |
| 缺陷 2：`grep Exec` 不是断言 | 已改为 `grep -q -- '^Exec=.*--ozone-platform=x11'`，且锚定行首 | `build-linux.yml:65` |
| 缺陷 3：`deb.depends` 缺 `libgbm1` | 已加 | `package.json` `build.deb.depends` |
| 缺陷 4：AppImage wrapper 透传未验证 | 已实测并修正文档 | `bcfdb73` |

本轮据此认为 Debian/Ubuntu 线的审查闭环已完成，Fedora 线可以在同一套模式上推进。

---

## 1. 缺陷：拟议 `rpm.depends` 有两条永远匹配不到

### 1.1 上游默认值（已核对源码）

electron-builder `FpmTarget.ts` 的 `getDefaultDepends()`：

```js
case "rpm":
  return ["gtk3", "libnotify", "nss", "libXScrnSaver",
          "(libXtst or libXtst6)", "xdg-utils", "at-spi2-core",
          "(libuuid or libuuid1)"]
```

**关键认知修正：`(A or B)` 里的第二个名字不是 Debian 名，是 openSUSE 名。** `libXtst6` / `libuuid1` / `libasound2` / `libgbm1` / `libsecret-1-0` 都是 openSUSE 的包名。也就是说 electron-builder 既有写法本身就是「Fedora 名 or openSUSE 名」的 RPM rich dependency，一份清单覆盖两个发行版。这直接决定了 Q3 的答案（见 §2）。

同时注意：`depends` 是**整体替换**默认值而非追加 —— 与 `.deb` 侧同一规则，第 4 轮 `libgbm1` 漏写就是这么来的。

### 1.2 缺陷 1（P1）：`(mesa-libgbm or libgbm.so.1)` 的第二分支在 x86_64 上恒不匹配

RPM 对 64 位共享库自动生成的 Provides 带 `()(64bit)` 后缀，形如：

```
libgbm.so.1()(64bit)
```

裸写 `libgbm.so.1` 只会匹配 **32 位**提供者。在 x86_64 Fedora 上该分支永远为假，等于整条 `or` 退化成只有 `mesa-libgbm` 一个候选 —— 在 Fedora 上仍能解析，但预期中的 openSUSE 兼容性并没有拿到。

**改法：** `(mesa-libgbm or libgbm1)`。

### 1.3 缺陷 2（P1）：`(libXtst or libXtst.so.6)` 同样的毛病，且偏离上游

上游写的是 `(libXtst or libXtst6)`。拟议清单把它改成了 soname 形式，既踩了 §1.2 的 `()(64bit)` 问题，又丢掉了 openSUSE 的包名匹配。

**改法：** 回到 `(libXtst or libXtst6)`。

### 1.4 一致性建议（P3）：`libsecret` 补 openSUSE 侧别名

`libsecret` 在 openSUSE 叫 `libsecret-1-0`。若采用 §2 Q3 的结论（统一 rich deps 风格），应写成 `(libsecret or libsecret-1-0)`。

`(alsa-lib or libasound2)`、`(libuuid or libuuid1)` 两条写法正确，无需改。

---

## 2. 对 §6 八个问题的逐条表态

### Q1 阶段顺序（先 AppImage/tar.gz 基线，再打 RPM）—— **同意**

这个顺序能把「Fedora 上根本跑不起来」和「RPM 依赖没写对」两类问题分离。基线一旦通过，之后所有失败都可以直接归因到打包配置，省掉一轮二分。无修改意见。

### Q2 `libXScrnSaver` 是否省略 —— **不要靠推测决定，用一条命令定；并且两端必须一致**

文档给出的动机（RHEL 10 / 部分环境该包不可用，装不上）是合理的，但不能替代实测。**决定性检查**（产物已在手）：

```bash
ldd linux/dist/linux-unpacked/deepseek | grep -iE 'Xss|Xscrn'
```

- 有输出 → 两端都必须留：`rpm` 写回 `libXScrnSaver`，`deb` 保留 `libxss1`；
- 无输出 → 两端一起去掉：`rpm` 不写，`deb` 同步删掉 `libxss1`。

**当前 `deb` 有 `libxss1` 而 `rpm` 提议不写，这个不对称本身就是缺陷。** 同一个 Electron 二进制不可能在两个发行版上有不同的链接需求；不对称说明至少有一边是错的。文档 §0.1 已经自己察觉到这点（「若审查认为应两端一致，再定」）——结论是：应当一致，且由 `ldd` 定夺。

### Q3 `depends` 风格：Fedora 包名 vs soname / rich deps —— **用上游的 rich deps 风格**

理由三条：

1. 这就是 electron-builder 自己的写法（§1.1），跟着走不需要论证；
2. `(Fedora名 or openSUSE名)` 一份清单同时覆盖两边，边际成本为零；
3. soname 写法必须带 `()(64bit)` 才正确，容易写错 —— **本次拟议清单里已经因此写错了两条**（§1.2、§1.3），这就是最好的反例。

### Q4 构建机 Arch 打 rpm + Fedora 只装测 —— **可接受，但构建依赖清单多了一项**

- **不需要**另外安装 `fpm`：electron-builder 自带并下载 fpm，文档里 `libxcrypt-compat` 正是给它的 `libcrypt.so.1` 用的，这本身就说明用的是内置 fpm。
- **真正必需**：`rpm-tools`（提供 `rpmbuild`）+ `libxcrypt-compat`。
- 佐证：`FpmTarget.ts` 的错误分支在缺 `rpmbuild` 时提示安装 `rpm` 包（`sudo apt-get install rpm`），从未提示安装 fpm。

建议把 §1「本地日后打 RPM」里的 `# fpm：按团队现有方式安装（gem / AUR）` 改成一句「fpm 由 electron-builder 自带下载，不需要单独安装；只需确认 `which rpmbuild`」。

### Q5 CI：只构建上传 vs 加 Fedora job —— **选 B，加 Fedora container job**

理由：`.deb` 那条线已经证明「装完能不能起来」是唯一能挡住依赖漏写的关卡（第 4 轮缺陷 3 `libgbm1` 就是靠这个思路发现的），而依赖漏写恰恰是 RPM 这条线最可能出的问题。只构建不装测，等于把 §1 那两条缺陷类问题留给用户去发现。

- ubuntu-latest 上**打包**只需 `sudo apt-get install -y rpm`；
- **安装冒烟**另起一个 job，与刚给 `.deb` 建立的模式完全对称：

```yaml
smoke-rpm:
  needs: build
  runs-on: ubuntu-latest
  container: fedora:41          # 固定版本，不要用 latest
  steps:
    - uses: actions/download-artifact@v4
    - run: dnf install -y ./DeepSeek-*.rpm
    - run: grep -q -- '^Exec=.*--ozone-platform=x11' /usr/share/applications/deepseek.desktop
    - run: |
        deepseek --smoke-test --ozone-platform=headless --no-sandbox --disable-gpu | tee /tmp/rpm.log
        grep -q DSH_SMOKE_CLEAN /tmp/rpm.log
```

注意点：容器内无 user namespace / SUID 沙箱，必须 `--no-sandbox`（文档里的命令已带）；无 `DISPLAY`，必须 `--ozone-platform=headless`（这正是第 4 轮缺陷 1）。

### Q6 产物命名 `DeepSeek-${version}-x86_64.rpm` —— **够用，无冲突**

`${arch}` 在 rpm 目标下确实解析为 `x86_64`（与 deb 的 `amd64` 不同，文档 §0.1 的判断正确）。与 AppImage 的 `DeepSeek-1.0.1-x86_64.AppImage` 只差后缀，Release 资产列表里不会撞名。

唯一建议：人眼容易看混，Release notes 里写清哪个是哪个（`generate_release_notes: true` 不会自动区分资产用途）。

### Q7 是否把 openSUSE / RHEL 写进承诺范围 —— **README 只承诺 Fedora + AppImage 兜底**

采用 §2 Q3 的 rich deps 之后，openSUSE 大概率能装 —— 但「能装」和「承诺支持」是两回事：没有 openSUSE 测试环境，写进 README 等于承诺一条无人验证的路径。

建议在 `linux/README.md` 写一句：「openSUSE 未经测试，rpm 依赖理论上可解析，遇到问题请提 issue」。**RHEL 建议完全不提** —— 正因为 `libXScrnSaver` 这类包在 RHEL 上的可用性正是本次争议点，承诺它只会把一个未知变成一个义务。

### Q8 SELinux —— **风险低，但应落成一条实机检查，而不是一段说明文字**

Fedora 默认允许 unconfined 用户执行 `/opt` 下的程序，Electron 装在 `/opt/DeepSeek` 通常无碍；真正可能触发 AVC 的是 `chrome-sandbox` 的 SUID 位。

**建议加入 §5 的检查清单：**

```bash
DSH_DESKTOP_HOME=/tmp/dsh-rpm-gui deepseek          # 故意不加 --no-sandbox
sudo ausearch -m AVC -ts recent | grep -i deepseek || echo "无 AVC 拒绝"
```

有拒绝再谈策略；没有就在文档里写一句「Fedora enforcing 下实测无 AVC」结案。**不要**预先写一段 SELinux 说明 —— 没有实测支撑的安全说明是负债。

---

## 3. 文档自身的一致性问题

本分支基于 `6f67e6a`，已经包含 Debian 线的 `59cc830`（AppImage 参数措辞修正）与 `52b9a5b`（冒烟断言强化），但新文档没有跟上这两处：

| # | 位置 | 问题 | 改法 |
|---|---|---|---|
| 1 | §3 AppImage | 措辞退回旧说法「electron-builder 26 运行时多数参数可直传；保险写法加 `--`」，含糊 | 直接采用 `DEBIAN-UBUNTU-TESTING.md` 已修正的表述：应用参数 `--smoke-test` 必须加 `--`；wrapper 注入的 `--ozone-platform=x11` 属运行时参数、已实测可透传 |
| 2 | §5 第 205 行 | 又出现无断言能力的 `grep Exec /usr/share/applications/deepseek.desktop` —— 这正是第 4 轮缺陷 2，CI 里已修 | 改为 `grep -q -- '^Exec=.*--ozone-platform=x11' /usr/share/applications/deepseek.desktop` |
| 3 | §7 通过标准 | §3 已很好地写了「仅看退出码不够，单实例锁命中时也会返回 0」，但 §7 勾选项只写 `DSH_SMOKE_CLEAN` | 把 §3 的两条 stdout 断言（`DSH_SMOKE_READY port=3099 reused=false` 与 `DSH_SMOKE_CLEAN`）原样搬进 §7 |

### 3.1 值得保留的部分

- **§5 的 `rpm -qpR` 人工核对这一步请务必保留。** fpm 生成的 spec 是否开启 rpmbuild 的自动 soname 依赖生成，直接决定手写 `depends` 是**唯一防线**还是**双保险**。第一次打出包时看 `rpm -qpR` 里有没有 `libgbm.so.1()(64bit)` 这类自动生成条目即可判定 —— 若没有，则 §1 的两条缺陷严重度上升。
- §3「仅看退出码不够」的提醒、§1「不要在小规格 VM 上跑完整构建」、§1「不要用 `--nodeps` 当通过标准」三条都写得对，与前几轮的经验一致。
- Fedora 包名核对无误：`xorg-x11-server-Xvfb`、`fuse` / `fuse-libs`（AppImage type-2 需 `libfuse.so.2`）、`google-noto-sans-cjk-fonts` 均为正确的 Fedora 包名。
- §0.1 关于 RPM 包名取自顶层 `name`（`deepseek-harness-desktop`）、`${arch}` 为 `x86_64` 的判断正确。

---

## 4. 修正后的配置建议（待落地，本轮未改仓库）

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

`libXScrnSaver` 一行**待 Q2 的 `ldd` 结果决定**：需要则加回本清单并保留 deb 的 `libxss1`；不需要则本清单不写、同时删掉 deb 的 `libxss1`。

构建机（Arch / CachyOS）：`sudo pacman -S libxcrypt-compat rpm-tools`，**不需要**单独装 fpm。

CI：打包机 `sudo apt-get install -y rpm`；安装冒烟用 `container: fedora:41` 的独立 job（§2 Q5）。

---

## 5. 总评

**测试计划的结构和阶段划分是对的，可以按 §2 的表态推进；落地前必须先修 `rpm.depends` 的两条硬伤。**

这份计划最值得肯定的是它把「配置定稿」与「实机验证」分成了两个阶段，并且主动把有争议的点（`libXScrnSaver`、包名风格、CI 策略）列出来求裁决，而不是先改了再说 —— 这正是前四轮反复付出代价才建立的做法。

### 5.1 落地前必改

- [ ] **缺陷 1** — `(mesa-libgbm or libgbm.so.1)` → `(mesa-libgbm or libgbm1)`
- [ ] **缺陷 2** — `(libXtst or libXtst.so.6)` → `(libXtst or libXtst6)`
- [ ] **Q2** — 跑一次 `ldd linux/dist/linux-unpacked/deepseek | grep -iE 'Xss|Xscrn'`，据此**同时**决定 rpm 的 `libXScrnSaver` 与 deb 的 `libxss1`，消除两端不对称

### 5.2 文档改动（与被审文档同批次即可）

- [ ] §3 AppImage 措辞对齐 `DEBIAN-UBUNTU-TESTING.md` 的已修正版本
- [ ] §5 的 `grep Exec` 改为带 `-q --` 的断言
- [ ] §7 通过标准补上 §3 的两条 stdout 断言
- [ ] §1 删掉「单独安装 fpm」的指引（§2 Q4）
- [ ] §5 加入 SELinux AVC 检查（§2 Q8）

### 5.3 采纳但可延后

- `(libsecret or libsecret-1-0)` 的风格对齐（§1.4）
- Release notes 里区分 `.rpm` 与 `.AppImage` 资产（§2 Q6）
- `linux/README.md` 关于 openSUSE 的一句免责说明（§2 Q7）

---

## 附：本轮未做的验证与引用

**未做的验证：**

1. **未在 Fedora 上运行任何东西** —— 无 Fedora 环境，§2 的全部结论均为配置与文档层面的推理。
2. **未打 `.rpm`** —— 本审查环境无 `linux/dist` 产物（构建发生在另一台机器），`rpm -qpR` 的实际输出、fpm 是否开启自动依赖生成，均未验证。
3. **未运行 `ldd`** —— Q2 的决定性检查需要 unpacked 产物，本环境没有；结论形式是「按 `ldd` 结果二选一」而非直接定论。
4. **未验证 `fedora:41` 容器内 `dnf install` 能否解析上述依赖** —— §2 Q5 的 YAML 是建议，未实跑。
5. 未修改被审文档、未改打包配置、未合并任何分支。

**引用来源：**

- electron-builder `FpmTarget.ts`（`getDefaultDepends()`，rpm 默认依赖与 `rpmbuild` 缺失时的错误提示），查阅于 2026-08-20，文件当时最新提交 `b276f7a`：
  https://github.com/electron-userland/electron-builder/blob/master/packages/app-builder-lib/src/targets/linux/FpmTarget.ts
- 本仓库 `origin/linux` @ `6f67e6a` 的 `.github/workflows/build-linux.yml`、`linux/package.json`、`linux/DEBIAN-UBUNTU-TESTING.md`
