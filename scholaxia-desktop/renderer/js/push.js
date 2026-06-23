(function () {
  var cfg = window.FIREBASE_CONFIG;
  if (!cfg || typeof getToken !== "function") return;

  function requestPermission() {
    if (typeof Notification === "undefined") return;
    if (Notification.permission === "default") {
      Notification.requestPermission().catch(function () {});
    }
  }

  function showNativeNotification(payload) {
    if (!payload) return;
    if (typeof payload === "string") {
      try { payload = JSON.parse(payload); } catch (e) { return; }
    }
    var note = payload.notification || {};
    var data = payload.data || payload;
    var title = note.title || data.title || "Scholaxia";
    var body = note.body || data.body || "";
    if (typeof Notification === "undefined" || Notification.permission !== "granted") return;
    try {
      var n = new Notification(title, { body: body, icon: "assets/logo.png" });
      n.onclick = function () {
        window.focus();
        if (typeof showPage !== "function") return;
        var t = (data.type || data.notification_type || "").toLowerCase();
        if (t.indexOf("live") >= 0) showPage("live");
        else if (t.indexOf("cbt") >= 0 || t.indexOf("exam") >= 0) showPage("school");
        else if (t.indexOf("community") >= 0 || t.indexOf("announcement") >= 0) showPage("community");
        else showPage("live");
      };
    } catch (e) {
      console.warn("Notification display failed", e);
    }
  }

  async function registerToken(token) {
    if (!token || !getToken()) return;
    var saved = localStorage.getItem("sia_fcm_token");
    if (saved === token) return;
    try {
      await api("/api/v1/notifications/device-token", {
        method: "POST",
        body: JSON.stringify({ token: token, platform: "web" }),
      });
      localStorage.setItem("sia_fcm_token", token);
    } catch (e) {
      console.warn("FCM token registration failed", e);
    }
  }

  function initElectronPush() {
    var push = window.scholaxia && window.scholaxia.push;
    if (!push) return false;
    push.onTokenUpdated(registerToken);
    push.onStarted(registerToken);
    push.onRestarted(registerToken);
    push.onNotification(showNativeNotification);
    push.onError(function (err) {
      console.warn("Push service error", err);
    });
    push.start(cfg.appId, cfg.projectId, cfg.apiKey, cfg.vapidKey || "");
    return true;
  }

  var pollTimer = null;
  function initPollingFallback() {
    var lastId = localStorage.getItem("sia_last_notif_id") || "";

    async function poll() {
      if (!getToken()) return;
      try {
        var list = await api("/api/v1/notifications/");
        if (!list || !list.length) return;
        var newest = list[0];
        if (lastId && newest.id !== lastId && !newest.is_read) {
          showNativeNotification({
            notification: { title: newest.title, body: newest.body },
            data: { type: newest.type },
          });
          if (typeof window.scholaxiaNotifyIncoming === "function") {
            window.scholaxiaNotifyIncoming(newest);
          }
        }
        lastId = newest.id;
        localStorage.setItem("sia_last_notif_id", newest.id);
      } catch (e) {
        /* ignore transient errors */
      }
    }

    poll();
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(poll, 45000);
  }

  function init() {
    if (!getToken()) return;
    requestPermission();
    if (!initElectronPush()) {
      initPollingFallback();
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
