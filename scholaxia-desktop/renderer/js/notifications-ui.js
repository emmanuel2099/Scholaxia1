/**
 * In-app notifications: badge counter, list screen, live-class ring sound.
 */
(function () {
  var pollTimer = null;
  var livePollTimer = null;
  var ringTimer = null;
  var audioCtx = null;
  var notifications = [];
  var knownIds = {};
  var notificationsInitialized = false;
  var liveClassActive = false;
  var ringSnoozeUntil = 0;
  var snoozeWakeTimer = null;
  var RING_SNOOZE_MS = 90000;

  function isRingSnoozed() {
    return ringSnoozeUntil && Date.now() < ringSnoozeUntil;
  }

  function scheduleSnoozeWake() {
    if (snoozeWakeTimer) clearTimeout(snoozeWakeTimer);
    if (!ringSnoozeUntil || Date.now() >= ringSnoozeUntil) return;
    var wait = ringSnoozeUntil - Date.now() + 300;
    snoozeWakeTimer = setTimeout(function () {
      snoozeWakeTimer = null;
      syncRingWithLiveStatus();
    }, wait);
  }

  function stopRingWithSnooze() {
    ringSnoozeUntil = Date.now() + RING_SNOOZE_MS;
    stopRing(true);
    scheduleSnoozeWake();
  }

  function getBell() {
    return document.getElementById("topbar-bell");
  }

  function unreadCount() {
    return notifications.filter(function (n) { return !n.is_read; }).length;
  }

  function updateBadge() {
    var bell = getBell();
    if (!bell) return;
    var count = unreadCount();
    var badge = bell.querySelector(".notif-badge");
    if (!badge) {
      badge = document.createElement("span");
      badge.className = "notif-badge hidden";
      bell.appendChild(badge);
    }
    if (count > 0) {
      badge.textContent = count > 99 ? "99+" : String(count);
      badge.classList.remove("hidden");
    } else {
      badge.classList.add("hidden");
    }
  }

  function formatNotifTime(iso) {
    if (!iso) return "";
    try {
      var d = new Date(iso);
      var now = new Date();
      var diff = (now - d) / 1000;
      if (diff < 60) return "Just now";
      if (diff < 3600) return Math.floor(diff / 60) + "m ago";
      if (diff < 86400) return Math.floor(diff / 3600) + "h ago";
      return d.toLocaleDateString();
    } catch (e) {
      return "";
    }
  }

  function isLiveNotif(n) {
    var t = String(n.type || "").toLowerCase();
    if (t.indexOf("live") < 0) return false;
    try {
      var data = n.data ? (typeof n.data === "string" ? JSON.parse(n.data) : n.data) : {};
      if (data && data.event === "class_ended") return false;
    } catch (e) { /* ignore */ }
    var body = String(n.body || "").toLowerCase();
    var title = String(n.title || "").toLowerCase();
    if (body.indexOf("has ended") >= 0 || title.indexOf("ended") >= 0) return false;
    return true;
  }

  function startRing() {
    if (isRingSnoozed()) return;
    var hasUnreadLive = notifications.some(function (n) { return isLiveNotif(n) && !n.is_read; });
    if (!liveClassActive && !hasUnreadLive) return;
    stopRing(false);
    try {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      if (audioCtx.state === "suspended") audioCtx.resume();

      function playIphoneRingBurst() {
        if (!liveClassActive && !notifications.some(function (n) { return isLiveNotif(n) && !n.is_read; })) {
          stopRing();
          return;
        }
        var t0 = audioCtx.currentTime;
        var segments = [
          { start: 0, dur: 0.55 },
          { start: 0.75, dur: 0.55 },
        ];
        segments.forEach(function (seg) {
          [698.46, 880.0].forEach(function (freq) {
            var osc = audioCtx.createOscillator();
            var gain = audioCtx.createGain();
            osc.type = "sine";
            osc.frequency.value = freq;
            gain.gain.setValueAtTime(0, t0 + seg.start);
            gain.gain.linearRampToValueAtTime(0.22, t0 + seg.start + 0.03);
            gain.gain.setValueAtTime(0.22, t0 + seg.start + seg.dur - 0.04);
            gain.gain.exponentialRampToValueAtTime(0.001, t0 + seg.start + seg.dur);
            osc.connect(gain);
            gain.connect(audioCtx.destination);
            osc.start(t0 + seg.start);
            osc.stop(t0 + seg.start + seg.dur + 0.02);
          });
        });
      }

      playIphoneRingBurst();
      ringTimer = setInterval(playIphoneRingBurst, 3200);
      var bar = document.getElementById("notif-ring-bar");
      if (bar) bar.classList.remove("hidden");
    } catch (e) {
      console.warn("Notification ring failed", e);
    }
  }

  function stopRing(hideBar) {
    if (ringTimer) {
      clearInterval(ringTimer);
      ringTimer = null;
    }
    if (hideBar !== false) {
      var bar = document.getElementById("notif-ring-bar");
      if (bar) bar.classList.add("hidden");
    }
  }

  async function dismissStaleLiveAlerts() {
    var stale = notifications.some(function (n) { return isLiveNotif(n) && !n.is_read; });
    if (!stale) return;
    try {
      await api("/api/v1/notifications/read-all", { method: "POST" });
      notifications.forEach(function (n) { n.is_read = true; });
      updateBadge();
      if (typeof currentPage !== "undefined" && currentPage === "notifications") {
        renderNotificationsList();
      }
    } catch (e) { /* ignore */ }
  }

  async function syncRingWithLiveStatus() {
    if (typeof getToken !== "function" || !getToken()) return;
    try {
      var live = await api("/api/v1/live-classes/?status=live&limit=50");
      var count = (live || []).length;
      liveClassActive = count > 0;

      if (!liveClassActive) {
        stopRing();
        await dismissStaleLiveAlerts();
        return;
      }

      if (!isRingSnoozed() && ringTimer === null) {
        startRing();
      }
    } catch (e) { /* ignore */ }
  }

  function onNewNotifications(newOnes) {
    var hasLive = newOnes.some(function (n) { return isLiveNotif(n) && !n.is_read; });
    if (hasLive) {
      liveClassActive = true;
      startRing();
    }
    updateBadge();
    if (typeof currentPage !== "undefined" && currentPage === "notifications") {
      renderNotificationsList();
    }
  }

  function detectNew(list) {
    if (!notificationsInitialized) {
      (list || []).forEach(function (n) { knownIds[n.id] = true; });
      notificationsInitialized = true;
      return [];
    }
    var fresh = [];
    (list || []).forEach(function (n) {
      if (!knownIds[n.id]) {
        knownIds[n.id] = true;
        if (!n.is_read) fresh.push(n);
      }
    });
    return fresh;
  }

  async function fetchNotifications() {
    if (typeof getToken !== "function" || !getToken()) return;
    try {
      var list = await api("/api/v1/notifications/");
      notifications = list || [];
      await syncRingWithLiveStatus();
      var fresh = detectNew(notifications);
      if (fresh.length) onNewNotifications(fresh);
      else updateBadge();
      if (typeof currentPage !== "undefined" && currentPage === "notifications") {
        renderNotificationsList();
      }
    } catch (e) { /* ignore */ }
  }

  async function markNotificationRead(id) {
    if (!id) return;
    var n = notifications.find(function (x) { return x.id === id; });
    if (n && n.is_read) return;
    if (n) n.is_read = true;
    updateBadge();
    if (typeof currentPage !== "undefined" && currentPage === "notifications") {
      renderNotificationsList();
    }
    try {
      await api("/api/v1/notifications/" + id + "/read", { method: "POST" });
    } catch (e) { /* keep local read state */ }
  }

  async function markCommunityNotificationsRead() {
    notifications.forEach(function (n) {
      var t = String(n.type || "").toLowerCase();
      if (t.indexOf("community") >= 0 || t.indexOf("announcement") >= 0) n.is_read = true;
    });
    updateBadge();
    try {
      await api("/api/v1/notifications/mark-types-read", {
        method: "POST",
        body: JSON.stringify({ types: ["community_mention", "announcement"] }),
      });
    } catch (e) { /* local badge already cleared */ }
  }

  function notifAction(n) {
    stopRing();
    if (n && n.id && !n.is_read) markNotificationRead(n.id);
    var t = String(n.type || "").toLowerCase();
    var data = {};
    try {
      data = n.data ? (typeof n.data === "string" ? JSON.parse(n.data) : n.data) : {};
    } catch (e) { /* ignore */ }

    if (t.indexOf("live") >= 0 && isLiveNotif(n)) {
      if (typeof showPage === "function") showPage("access-code");
      if (typeof loadAccessCodes === "function") loadAccessCodes();
      return;
    }
    if (t.indexOf("cbt") >= 0 || t.indexOf("exam") >= 0) {
      if (typeof showPage === "function") showPage("school");
      return;
    }
    if (t.indexOf("community") >= 0 || t.indexOf("announcement") >= 0) {
      markCommunityNotificationsRead();
      if (typeof markCommunityRead === "function") markCommunityRead();
      if (typeof showPage === "function") showPage("community");
      if (typeof loadDiscordCommunity === "function") loadDiscordCommunity();
      return;
    }
    if (typeof showPage === "function") showPage("access-code");
  }

  function renderNotificationsList() {
    var el = document.getElementById("notifications-list");
    if (!el) return;

    if (!notifications.length) {
      el.innerHTML =
        '<div class="empty-state-premium">' +
        '<div class="empty-icon">&#128276;</div>' +
        "<h3>No notifications yet</h3>" +
        "<p>When your teacher goes live for your subject, you will see an alert here.</p>" +
        "</div>";
      return;
    }

    el.innerHTML = notifications.map(function (n) {
      var live = isLiveNotif(n);
      return (
        '<article class="notif-card' + (n.is_read ? "" : " unread") + (live ? " notif-live" : "") + '" data-id="' + escHtml(n.id) + '">' +
        '<div class="notif-card-icon">' + (live ? "&#128308;" : "&#128276;") + "</div>" +
        '<div class="notif-card-body">' +
        "<h4>" + escHtml(n.title || "Notification") + "</h4>" +
        "<p>" + escHtml(n.body || "") + "</p>" +
        '<span class="notif-time">' + escHtml(formatNotifTime(n.created_at)) + "</span>" +
        "</div>" +
        (live && liveClassActive ? '<button type="button" class="btn-sm primary notif-open-btn">Join class</button>' : "") +
        "</article>"
      );
    }).join("");

    el.querySelectorAll(".notif-card").forEach(function (card) {
      card.addEventListener("click", function (e) {
        if (e.target.closest(".notif-open-btn") || !e.target.closest("button")) {
          var id = card.dataset.id;
          var n = notifications.find(function (x) { return x.id === id; });
          if (n) notifAction(n);
        }
      });
    });
  }

  async function markAllRead() {
    try {
      await api("/api/v1/notifications/read-all", { method: "POST" });
      notifications.forEach(function (n) { n.is_read = true; });
      stopRing();
      updateBadge();
      renderNotificationsList();
    } catch (e) {
      alert(e.message || "Could not mark notifications as read.");
    }
  }

  function openNotifications() {
    stopRing();
    if (typeof showPage === "function") showPage("notifications");
  }

  function bindBell() {
    var bell = getBell();
    if (!bell || bell.dataset.bound) return;
    bell.dataset.bound = "1";
    bell.addEventListener("click", function (e) {
      e.preventDefault();
      openNotifications();
    });
  }

  function checkStopRingFlag() {
    try {
      if (localStorage.getItem("sia_stop_live_ring")) {
        localStorage.removeItem("sia_stop_live_ring");
        ringSnoozeUntil = Date.now() + 45 * 60 * 1000;
        stopRing(true);
      }
    } catch (e) { /* ignore */ }
  }

  function init() {
    bindBell();
    checkStopRingFlag();
    document.addEventListener("click", function unlockRingAudio() {
      if (audioCtx && audioCtx.state === "suspended") audioCtx.resume();
    }, { once: true });
    if (typeof isStudentLoggedIn === "function" && !isStudentLoggedIn()) return;
    try {
      var raw = localStorage.getItem("sia_known_notif_ids");
      if (raw) JSON.parse(raw).forEach(function (id) { knownIds[id] = true; });
    } catch (e) { /* ignore */ }

    fetchNotifications();
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(fetchNotifications, 20000);
    if (livePollTimer) clearInterval(livePollTimer);
    livePollTimer = setInterval(syncRingWithLiveStatus, 15000);
  }

  window.loadNotifications = function () {
    renderNotificationsList();
    fetchNotifications();
  };
  window.markAllNotificationsRead = markAllRead;
  window.markNotificationRead = markNotificationRead;
  window.markCommunityNotificationsRead = markCommunityNotificationsRead;
  window.stopNotificationRing = stopRingWithSnooze;
  window.scholaxiaNotifyRefresh = fetchNotifications;
  window.scholaxiaSyncLiveRing = syncRingWithLiveStatus;
  window.scholaxiaNotifyIncoming = function (payload) {
    fetchNotifications();
    if (payload && (payload.type || "").toLowerCase().indexOf("live") >= 0 && isLiveNotif(payload)) {
      liveClassActive = true;
      startRing();
    }
  };

  window.addEventListener("beforeunload", function () {
    try {
      localStorage.setItem("sia_known_notif_ids", JSON.stringify(Object.keys(knownIds).slice(-100)));
    } catch (e) { /* ignore */ }
  });

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
