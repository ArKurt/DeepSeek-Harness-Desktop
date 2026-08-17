# Linux 桌面版：最小化到系统托盘 — 实施计划

> 状态：**计划书，尚未实现**。
> 分支：`feature/tray-minimize`（基于 `linux` 分支创建，不会影响 PR #5）。

## 1. 目标

用户点击窗口的**最小化按钮**时，窗口隐藏到系统托盘（状态栏）图标，而不是继续占用
任务栏；点击托盘图标可恢复窗口。应用与本地服务保持运行，从托盘菜单退出时才真正
退出并清理服务。

非目标（本期不做）：

- 点击关闭按钮隐藏到托盘（关闭按钮仍保持“真正退出”，避免用户找不到退出入口）
- 消息通知/未读角标
- 托盘图标动画

## 2. 交互设计（默认行为）

| 操作 | 行为 |
|------|------|
| 点击最小化按钮 | 隐藏主窗口，应用继续在托盘运行 |
| 左键单击托盘图标 | 恢复并聚焦主窗口（若已显示则保持显示） |
| 托盘菜单：显示 DeepSeek | 恢复并聚焦主窗口 |
| 托盘菜单：退出 | 走现有 `quitApp()` 流程，清理自己拉起的服务 |
| 重复启动应用 | 命中单实例锁后，恢复被隐藏的窗口（复用现有 second-instance 逻辑） |
| 点击关闭按钮 / Ctrl+Q | 与现在一致：退出应用并清理服务 |

后续可选增强（不在第一版）：

- 设置项：关闭按钮也最小化到托盘
- 托盘图标左键“显示/隐藏”切换
- 首次隐藏时气泡提示“DeepSeek 仍在托盘运行”

## 3. 技术方案

### 3.1 新增模块 `linux/src/tray.js`

职责单一，不接触 `ServerManager`：

- `createTray({ getWindow, onShow, onQuit })`
- 使用 `nativeImage.createFromPath(assets/icon.png)` 并缩放为适合托盘的尺寸
  （Linux 常见 22/24 px，KDE 可自动缩放；保留 1x/2x 图标）
- `new Tray(icon)`，设置 tooltip 为 `DeepSeek`
- 菜单：
  - `显示 DeepSeek` → 恢复并聚焦窗口
  - `退出` → 调用现有退出流程
- 左键 `click` 事件 → 恢复并聚焦窗口
- 返回 handle，供 main.js 统一销毁；重复创建前先销毁旧 handle

### 3.2 修改 `linux/src/main.js`

- 应用启动后创建托盘（`app.whenReady()` 内、创建主窗口前后均可）
- `mainWindow.on('minimize')`：
  - 若托盘可用：`mainWindow.hide()`
  - 若托盘不可用：保持系统默认最小化，**绝不隐藏到无法找回**
- `second-instance`：
  - 优先恢复已隐藏/最小化窗口（`show()` + `restore()` + `focus()`）
- `quitApp()` / `before-quit`：
  - 销毁托盘图标，避免退出后残留空图标
- 窗口状态持久化不受影响：隐藏前保存正常尺寸/位置；从托盘恢复时保持原样

### 3.3 环境变量

- `DSH_DESKTOP_TRAY=1`（默认开启；与现有环境变量风格一致）
- `DSH_DESKTOP_TRAY=0` 完全禁用托盘逻辑，便于调试和无托盘桌面

### 3.4 托盘不可用时的降级策略

Linux 桌面托盘协议不统一，必须保证退化安全：

- `Tray` 创建失败 / 图标丢失：回退为普通最小化
- GNOME 未安装 AppIndicator 扩展：回退为普通最小化
- 运行日志中记录一条可诊断信息（当前日志体系或 stderr）

## 4. 打包与依赖

| 分发形式 | 需要的托盘依赖 | 待确认项 |
|----------|----------------|----------|
| AppImage | Electron 自带 StatusNotifier 支持；若系统需要 `libayatana-appindicator3-1`，写入 README 前置说明 | 在 Garuda KDE 实测后确认是否额外依赖 |
| Arch PKGBUILD | 优先使用系统 Electron + 系统托盘库 | 确认 Arch 包名（`libayatana-appindicator` / `libappindicator-gtk3`） |
| 未来 .deb | `libayatana-appindicator3-1`（Ubuntu 22.04+ / Debian 12 名称） | 与 Debian/Ubuntu 测试计划合并验证 |

## 5. 测试计划

### 5.1 本机 Garuda KDE 手动测试

1. `DSH_DESKTOP_DEV=1 electron .` 启动
2. 点击最小化：窗口从任务栏消失，托盘出现 DeepSeek 图标
3. 左键托盘图标：窗口恢复且获得焦点
4. 托盘菜单“显示 DeepSeek”：窗口恢复
5. 隐藏窗口期间：`curl http://127.0.0.1:3080/` 仍返回 200（服务不中断）
6. 重复启动应用：已有窗口被恢复，而不是打开第二个实例
7. 托盘菜单“退出”：窗口、托盘图标、应用拉起的服务全部清理
8. `DSH_DESKTOP_TRAY=0` 启动：最小化行为回到系统默认，功能完全禁用
9. 窗口状态：恢复后位置/大小与隐藏前一致

### 5.2 自动化

- 纯逻辑部分（托盘可用性判断、状态切换）抽成可单测函数，纳入 `npm test`
- 现有 `npm test`、`server-manager` 冒烟测试、打包后 `--smoke-test` 必须保持通过
- 最终构建 AppImage 后在 Garuda KDE 复测一遍

## 6. 文档更新

- `linux/README.md`：特性列表增加“最小化到系统托盘”、环境变量说明、
  GNOME 需要 AppIndicator 扩展的提示
- 根 `README.md`：Linux 特性行同步
- 如确认系统依赖，同步更新 `linux/arch/PKGBUILD` 与 Debian/Ubuntu 测试计划

## 7. 风险与回退

| 风险 | 缓解 |
|------|------|
| 某些桌面没有托盘，用户最小化后找不到窗口 | 托盘创建失败自动回退普通最小化；第二实例始终能恢复窗口 |
| 用户误以为关闭按钮也会进托盘 | 本期关闭按钮仍退出，托盘菜单提供明确退出入口 |
| 隐藏窗口期间应用退出不干净 | 复用现有 `quitApp()` 的 SIGTERM→SIGKILL 清理链路 |
| Wayland 下托盘协议差异 | 在 Garuda KDE Wayland 与 GNOME X11 各测一次 |

## 8. 提交计划

- 分支：`feature/tray-minimize`
- 建议按以下顺序提交：
  1. `Add tray module and minimize-to-tray behavior`（实现 + main.js 接入 + 环境变量）
  2. `Add tray tests and docs`（测试 + README/PKGBUILD 依赖说明）
- 全部验证通过后再合并回 `linux` 分支；合并前不会进入 PR #5
