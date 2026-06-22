const { app, BrowserWindow, shell, screen } = require("electron");
const path = require("path");
const { setup: setupPushReceiver } = require("@cuj1559/electron-push-receiver");

let mainWindow;

const isAdminMode = process.argv.includes("--admin");

function getWindowSize() {
  const display = screen.getPrimaryDisplay();
  const { width: sw, height: sh } = display.workAreaSize;
  const width = Math.min(1280, Math.max(900, Math.floor(sw * 0.92)));
  const height = Math.min(860, Math.max(640, Math.floor(sh * 0.9)));
  const minWidth = Math.min(768, width);
  const minHeight = Math.min(600, height);
  return { width, height, minWidth, minHeight };
}

function createWindow() {
  const size = getWindowSize();
  mainWindow = new BrowserWindow({
    width: size.width,
    height: size.height,
    minWidth: size.minWidth,
    minHeight: size.minHeight,
    title: isAdminMode ? "Scholaxia Admin Console" : "Scholaxia Student Portal",
    icon: path.join(__dirname, "assets", "logo.png"),
    webPreferences: {
      preload: path.join(__dirname, "preload.js"),
      contextIsolation: true,
      nodeIntegration: false,
    },
    autoHideMenuBar: true,
    backgroundColor: isAdminMode ? "#0a1410" : "#0d1f14",
    resizable: true,
    fullscreenable: true,
  });

  setupPushReceiver(mainWindow.webContents);

  const page = isAdminMode ? "admin.html" : "index.html";
  mainWindow.loadFile(path.join(__dirname, "renderer", page));

  if (size.width >= screen.getPrimaryDisplay().workAreaSize.width * 0.95) {
    mainWindow.maximize();
  }

  mainWindow.webContents.setWindowOpenHandler(({ url }) => {
    shell.openExternal(url);
    return { action: "deny" };
  });
}

app.whenReady().then(() => {
  createWindow();
  app.on("activate", () => {
    if (BrowserWindow.getAllWindows().length === 0) createWindow();
  });
});

app.on("window-all-closed", () => {
  if (process.platform !== "darwin") app.quit();
});
