const { contextBridge } = require("electron");

contextBridge.exposeInMainWorld("scholaxia", {
  platform: process.platform,
});
