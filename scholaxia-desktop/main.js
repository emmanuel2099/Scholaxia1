const { app, BrowserWindow, shell, screen, session, desktopCapturer } = require("electron");
const path = require("path");
const { startDesktopServer, stopDesktopServer } = require("./desktop-server");
let mainWindow;
let appBaseUrl = "";

function getWindowSize() {
  const display = screen.getPrimaryDisplay();
  const { width: sw, height: sh } = display.workAreaSize;
  const width = Math.min(1280, Math.max(900, Math.floor(sw * 0.92)));
  const height = Math.min(860, Math.max(640, Math.floor(sh * 0.9)));
  const minWidth = Math.min(768, width);
  const minHeight = Math.min(600, height);
  return { width, height, minWidth, minHeight };
}

/** Allow mic/camera/screen-share so live class A/V works in Electron. */
function enableLiveClassMediaPermissions() {
  const ses = session.defaultSession;
  ses.setPermissionRequestHandler((_wc, permission, callback) => {
    const allow = new Set([
      "media",
      "display-capture",
      "fullscreen",
      "notifications",
      "clipboard-sanitized-write",
    ]);
    callback(allow.has(permission));
  });
  ses.setPermissionCheckHandler((_wc, permission) => {
    return (
      permission === "media" ||
      permission === "display-capture" ||
      permission === "fullscreen" ||
      permission === "notifications"
    );
  });
  // Electron 28+: without this, getDisplayMedia / LiveKit screen share often fails.
  try {
    ses.setDisplayMediaRequestHandler(async (_request, callback) => {
      try {
        const sources = await desktopCapturer.getSources({
          types: ["screen", "window"],
          thumbnailSize: { width: 0, height: 0 },
        });
        if (!sources.length) {
          callback({});
          return;
        }
        callback({ video: sources[0], audio: "loopback" });
      } catch (_e) {
        callback({});
      }
    });
  } catch (_e) {
    /* older Electron without setDisplayMediaRequestHandler */
  }
}

function createWindow() {
  const size = getWindowSize();
  mainWindow = new BrowserWindow({
    width: size.width,
    height: size.height,
    minWidth: size.minWidth,
    minHeight: size.minHeight,
    title: "Scholaxia Student",
    icon: path.join(__dirname, "assets", "logo.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
    autoHideMenuBar: true,
    backgroundColor: "#0d1f14",
    resizable: true,
    fullscreenable: true,
  });

  const startUrl = appBaseUrl ? `${appBaseUrl}/app.html` : path.join(__dirname, "renderer", "app.html");
  if (appBaseUrl) mainWindow.loadURL(startUrl);
  else mainWindow.loadFile(startUrl);
  if (size.width >= screen.getPrimaryDisplay().workAreaSize.width * 0.95) {
    mainWindow.maximize();
  }

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });
}

app.whenReady().then(async () => {
  enableLiveClassMediaPermissions();
  try {
    appBaseUrl = await startDesktopServer();
  } catch (err) {
    console.error("Desktop server failed, falling back to file://", err);
    appBaseUrl = "";
  }
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("before-quit", () => {
  stopDesktopServer();
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
