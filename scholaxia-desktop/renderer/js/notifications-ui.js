/**
 * In-app notifications: badge counter, list screen, live-class ring sound.
 */
(function () {
  var pollTimer = null;
  var ringTimer = null;
  var audioCtx = null;
  var notifications = [];
  var knownIds = {};
  var notificationsInitialized = false;

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
    return t.indexOf("live") >= 0;
  }

  function startRing() {
    stopRing();
    try {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      if (audioCtx.state === "suspended") audioCtx.resume();

      function beep() {
        var osc = audioCtx.createOscillator();
        var gain = audioCtx.createGain();
        osc.type = "sine";
        osc.frequency.value = 880;
        gain.gain.value = 0.12;
        osc.connect(gain);
        gain.connect(audioCtx.destination);
        osc.start();
        setTimeout(function () {
          osc.stop();
          osc.disconnect();
          gain.disconnect();
        }, 280);
      }

      beep();
      ringTimer = setInterval(beep, 900);
      var bar = document.getElementById("notif-ring-bar");
      if (bar) bar.classList.remove("hidden");
    } catch (e) {
      console.warn("Notification ring failed", e);
    }
  }

  function stopRing() {
    if (ringTimer) {
      clearInterval(ringTimer);
      ringTimer = null;
    }
    var bar = document.getElementById("notif-ring-bar");
    if (bar) bar.classList.add("hidden");
  }

  function onNewNotifications(newOnes) {
    var hasLive = newOnes.some(function (n) { return isLiveNotif(n) && !n.is_read; });
    if (hasLive) startRing();
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
      var fresh = detectNew(notifications);
      if (fresh.length) onNewNotifications(fresh);
      else updateBadge();
      if (typeof currentPage !== "undefined" && currentPage === "notifications") {
        renderNotificationsList();
      }
    } catch (e) { /* ignore */ }
  }

  function notifAction(n) {
    stopRing();
    var t = String(n.type || "").toLowerCase();
    if (t.indexOf("live") >= 0) {
      if (typeof showPage === "function") showPage("live");
      return;
    }
    if (t.indexOf("cbt") >= 0 || t.indexOf("exam") >= 0) {
      if (typeof showPage === "function") showPage("school");
      return;
    }
    if (t.indexOf("community") >= 0 || t.indexOf("announcement") >= 0) {
      if (typeof showPage === "function") showPage("community");
      return;
    }
    if (typeof showPage === "function") showPage("live");
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
        (live ? '<button type="button" class="btn-sm primary notif-open-btn">Join</button>' : "") +
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

  function init() {
    bindBell();
    try {
      var raw = localStorage.getItem("sia_known_notif_ids");
      if (raw) JSON.parse(raw).forEach(function (id) { knownIds[id] = true; });
    } catch (e) { /* ignore */ }

    fetchNotifications();
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(fetchNotifications, 20000);
  }

  window.loadNotifications = function () {
    renderNotificationsList();
    fetchNotifications();
  };
  window.markAllNotificationsRead = markAllRead;
  window.stopNotificationRing = stopRing;
  window.scholaxiaNotifyRefresh = fetchNotifications;
  window.scholaxiaNotifyIncoming = function (payload) {
    fetchNotifications();
    if (payload && (payload.type || "").toLowerCase().indexOf("live") >= 0) {
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
