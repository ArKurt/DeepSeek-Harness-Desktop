'use strict';

const { app, BrowserWindow, dialog, Menu, shell } = require('electron');
const path = require('path');

const {
  preferredPort,
  homeOverride,
  logFile,
  findRuntimeRoot,
  findDshBin,
  findNodeBin,
} = require('./config');
const { ServerManager } = require('./server-manager');
const { verifyRuntimeIntegrity } = require('./integrity');

const SPLASH_MIN_MS = 5200;
const APP_NAME = 'DeepSeek';

let splashWindow = null;
let mainWindow = null;
let server = null;
let startupPhase = 'splash'; // splash | main | failed
let quitting = false;
let cleanedUp = false;

// ---------------------------------------------------------------------------
// 单实例：重复启动时聚焦已有窗口并退出新进程。
// ---------------------------------------------------------------------------
if (!app.requestSingleInstanceLock()) {
  app.quit();
} else {
  app.on('second-instance', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      if (mainWindow.isMinimized()) mainWindow.restore();
      mainWindow.show();
      mainWindow.focus();
    } else if (splashWindow && !splashWindow.isDestroyed()) {
      splashWindow.show();
      splashWindow.focus();
    }
  });

  app.whenReady()
    .then(() => {
      if (process.argv.includes('--smoke-test')) {
        return runSmokeTest();
      }
      return runStartupWithIntegrity();
    })
    .catch((error) => {
      dialog.showErrorBox(APP_NAME, `应用启动失败：${error.message}`);
      app.exit(1);
    });
}

function isDevMode() {
  return process.env.DSH_DESKTOP_DEV === '1';
}

function appRoot() {
  // Arch 的 electron 包在开发模式也可能把 isPackaged 报成 true，
  // 所以 runtime 搜索同时覆盖 app 根目录与 resources 目录。
  return app.getAppPath();
}

function runtimeSearchRoots() {
  return [app.getAppPath(), process.resourcesPath];
}

function findRuntime() {
  return findRuntimeRoot(runtimeSearchRoots());
}

function sendSplashStatus(message) {
  if (splashWindow && !splashWindow.isDestroyed()) {
    splashWindow.webContents.send('splash:status', message);
  }
}

function buildServerManager() {
  const port = preferredPort();
  const root = appRoot();
  const runtimeRoot = findRuntime();
  const nodeBin = findNodeBin(runtimeRoot);
  const dshBin = findDshBin(runtimeRoot);
  const home = homeOverride();

  return new ServerManager({
    port,
    nodeBin,
    dshBin,
    cwd: runtimeRoot ? path.join(runtimeRoot, 'bundle') : root,
    logFile: logFile(),
    timeoutMs: 25000,
    extraEnv: home ? { DSH_HOME: home } : {},
  });
}

function createSplashWindow() {
  splashWindow = new BrowserWindow({
    width: 760,
    height: 420,
    frame: false,
    resizable: false,
    fullscreenable: false,
    maximizable: false,
    minimizable: false,
    skipTaskbar: true,
    backgroundColor: '#ffffff',
    show: false,
    title: APP_NAME,
    webPreferences: {
      preload: path.join(__dirname, 'preload-splash.js'),
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  splashWindow.loadFile(path.join(__dirname, '..', 'assets', 'splash.html'));
  splashWindow.once('ready-to-show', () => {
    if (splashWindow && !splashWindow.isDestroyed()) splashWindow.show();
  });

  splashWindow.on('closed', () => {
    splashWindow = null;
    // 用户强制关闭启动动画（如 Alt+F4）且还没进入主界面时直接退出。
    if (!quitting && startupPhase === 'splash') {
      app.quit();
    }
  });
}

function createMainWindow(url) {
  mainWindow = new BrowserWindow({
    width: 1200,
    height: 800,
    minWidth: 1000,
    minHeight: 640,
    backgroundColor: '#ffffff',
    show: false,
    title: APP_NAME,
    autoHideMenuBar: false,
    icon: path.join(__dirname, '..', 'assets', 'icon.png'),
    webPreferences: {
      contextIsolation: true,
      sandbox: true,
      nodeIntegration: false,
    },
  });

  mainWindow.loadURL(url);
  mainWindow.once('ready-to-show', () => {
    if (mainWindow && !mainWindow.isDestroyed()) {
      mainWindow.show();
      mainWindow.focus();
    }
  });

  // 兜底显示：Harness UI 等页面在窗口隐藏（show:false）时可能不绘制首帧，
  // 导致 ready-to-show 永不触发、窗口永远无法显示（死锁）。
  // 3 秒后若仍未显示则强制显示，页面绘制后 ready-to-show 会照常触发。
  const showFallbackTimer = setTimeout(() => {
    if (mainWindow && !mainWindow.isDestroyed() && !mainWindow.isVisible()) {
      mainWindow.show();
    }
  }, 3000);
  mainWindow.once('ready-to-show', () => clearTimeout(showFallbackTimer));
  mainWindow.on('closed', () => clearTimeout(showFallbackTimer));

  mainWindow.webContents.setWindowOpenHandler(({ url: target }) => {
    openExternalSafe(target);
    return { action: 'deny' };
  });

  const port = preferredPort();
  const baseUrl = `http://127.0.0.1:${port}`;
  const localhostUrl = `http://localhost:${port}`;
  mainWindow.webContents.on('will-navigate', (event, target) => {
    const allowed = target === baseUrl
      || target.startsWith(`${baseUrl}/`)
      || target === localhostUrl
      || target.startsWith(`${localhostUrl}/`);
    if (!allowed) {
      event.preventDefault();
      openExternalSafe(target);
    }
  });

  let reloadTimer = null;
  mainWindow.webContents.on('did-fail-load', (_event, code, description, url, isMainFrame) => {
    if (!isMainFrame || code === -3) return; // -3 = 用户/导航取消
    if (reloadTimer) clearTimeout(reloadTimer);
    reloadTimer = setTimeout(() => {
      if (mainWindow && !mainWindow.isDestroyed()) {
        mainWindow.loadURL(url);
      }
    }, 1500);
  });

  mainWindow.on('closed', () => {
    if (reloadTimer) clearTimeout(reloadTimer);
    mainWindow = null;
    if (!quitting) app.quit();
  });
}

function openExternalSafe(target) {
  try {
    const parsed = new URL(target);
    if (['http:', 'https:', 'mailto:'].includes(parsed.protocol)) {
      shell.openExternal(target);
    }
  } catch {
    // 非法 URL 忽略
  }
}

function installMenu() {
  const template = [
    {
      label: '文件',
      submenu: [{ role: 'quit', label: '退出' }],
    },
    {
      label: '编辑',
      submenu: [
        { role: 'undo', label: '撤销' },
        { role: 'redo', label: '重做' },
        { type: 'separator' },
        { role: 'cut', label: '剪切' },
        { role: 'copy', label: '复制' },
        { role: 'paste', label: '粘贴' },
        { role: 'selectAll', label: '全选' },
      ],
    },
    {
      label: '视图',
      submenu: [
        { role: 'reload', label: '刷新' },
        { role: 'forceReload', label: '强制刷新' },
        { type: 'separator' },
        { role: 'resetZoom', label: '实际大小' },
        { role: 'zoomIn', label: '放大' },
        { role: 'zoomOut', label: '缩小' },
        { type: 'separator' },
        { role: 'togglefullscreen', label: '切换全屏' },
      ],
    },
  ];

  if (isDevMode()) {
    template.push({
      label: '调试',
      submenu: [{ role: 'toggleDevTools', label: '开发者工具' }],
    });
  }

  Menu.setApplicationMenu(Menu.buildFromTemplate(template));
}

async function waitMinSplash(startedAt) {
  const remaining = SPLASH_MIN_MS - (Date.now() - startedAt);
  if (remaining > 0) {
    await new Promise((resolve) => setTimeout(resolve, remaining));
  }
}

async function showStartupErrorAndMaybeRetry(error) {
  startupPhase = 'failed';
  if (splashWindow && !splashWindow.isDestroyed()) {
    splashWindow.close();
  }

  const { response } = await dialog.showMessageBox({
    type: 'error',
    title: APP_NAME,
    message: 'DeepSeek 启动失败',
    detail: `${error.message}\n\n日志：${logFile()}`,
    buttons: ['重试', '退出'],
    defaultId: 0,
    cancelId: 1,
    noLink: true,
  });

  if (response === 0) {
    startupPhase = 'splash';
    await runStartup();
  } else {
    await quitApp();
  }
}

async function runStartup() {
  const startedAt = Date.now();
  if (!splashWindow || splashWindow.isDestroyed()) {
    createSplashWindow();
  }

  // 重试/二次启动前先清掉上一次可能仍在运行、但未就绪的进程。
  if (server) {
    await server.shutdown().catch(() => {});
  }
  server = buildServerManager();
  server.on('status', (message) => sendSplashStatus(message));

  const outcome = await server.ensureServer().then(
    (result) => ({ ok: true, result }),
    (error) => ({ ok: false, error })
  );

  await waitMinSplash(startedAt);

  if (!outcome.ok) {
    await showStartupErrorAndMaybeRetry(outcome.error);
    return;
  }

  startupPhase = 'main';
  if (splashWindow && !splashWindow.isDestroyed()) {
    splashWindow.close();
  }
  const url = `http://127.0.0.1:${outcome.result.port}`;
  createMainWindow(url);
}

async function shutdownServer() {
  if (server) {
    await server.shutdown().catch(() => {});
  }
}

async function quitApp() {
  if (quitting) return;
  quitting = true;
  await shutdownServer();
  cleanedUp = true;
  app.quit();
}

app.on('before-quit', (event) => {
  if (cleanedUp) return;
  event.preventDefault();
  quitApp();
});

// kill/系统注销时也走正常清理流程。
for (const signal of ['SIGTERM', 'SIGINT', 'SIGHUP']) {
  process.on(signal, () => {
    app.quit();
  });
}

async function runSmokeTest() {
  const runtimeRoot = findRuntime();
  const integrity = await verifyRuntimeIntegrity(runtimeRoot, { required: true });
  if (!integrity.ok) {
    console.error(`DSH_SMOKE_INTEGRITY_FAIL: ${integrity.reason}`);
    app.exit(2);
    return;
  }

  server = buildServerManager();
  try {
    const result = await server.ensureServer();
    console.log(`DSH_SMOKE_READY port=${result.port} reused=${result.reused}`);
    await server.shutdown();
    console.log('DSH_SMOKE_CLEAN');
    app.exit(0);
  } catch (error) {
    console.error(`DSH_SMOKE_FAIL: ${error.message}`);
    app.exit(1);
  }
}

async function runStartupWithIntegrity() {
  const runtimeRoot = findRuntime();
  const required = !isDevMode();
  const integrity = await verifyRuntimeIntegrity(runtimeRoot, { required });

  if (!integrity.ok) {
    dialog.showErrorBox(
      APP_NAME,
      `应用文件校验失败，拒绝启动。\n\n${integrity.reason}\n\n请重新下载安装包。`
    );
    app.exit(1);
    return;
  }

  installMenu();
  createSplashWindow();
  await runStartup();
}
