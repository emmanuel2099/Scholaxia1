const { contextBridge, ipcRenderer } = require("electron");
const {
  START_NOTIFICATION_SERVICE,
  NOTIFICATION_SERVICE_STARTED,
  NOTIFICATION_SERVICE_RESTARTED,
  NOTIFICATION_SERVICE_ERROR,
  NOTIFICATION_RECEIVED,
  TOKEN_UPDATED,
} = require("@cuj1559/electron-push-receiver/src/constants");

contextBridge.exposeInMainWorld("scholaxia", {
  platform: process.platform,
  push: {
    start: function (appId, projectId, apiKey, vapidKey) {
      ipcRenderer.send(START_NOTIFICATION_SERVICE, appId, projectId, apiKey, vapidKey || "");
    },
    onStarted: function (cb) {
      ipcRenderer.on(NOTIFICATION_SERVICE_STARTED, function (_e, token) {
        cb(token);
      });
    },
    onRestarted: function (cb) {
      ipcRenderer.on(NOTIFICATION_SERVICE_RESTARTED, function (_e, token) {
        cb(token);
      });
    },
    onTokenUpdated: function (cb) {
      ipcRenderer.on(TOKEN_UPDATED, function (_e, token) {
        cb(token);
      });
    },
    onNotification: function (cb) {
      ipcRenderer.on(NOTIFICATION_RECEIVED, function (_e, payload) {
        cb(payload);
      });
    },
    onError: function (cb) {
      ipcRenderer.on(NOTIFICATION_SERVICE_ERROR, function (_e, err) {
        cb(err);
      });
    },
  },
});
