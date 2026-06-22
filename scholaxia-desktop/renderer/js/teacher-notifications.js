(function () {
  var pollTimer = null;
  var lastId = localStorage.getItem("sia_teacher_last_notif_id") || "";

  function getTeacherAuthToken() {
    return localStorage.getItem("sia_teacher_token") || localStorage.getItem("sia_admin_token") || "";
  }

  function showTeacherNotification(item) {
    if (!item) return;
    if (typeof Notification !== "undefined" && Notification.permission === "granted") {
      try {
        var n = new Notification(item.title || "Scholaxia", {
          body: item.body || "",
          icon: "assets/logo.png",
        });
        n.onclick = function () {
          window.focus();
          if (typeof showTeacherPage === "function") {
            var t = (item.type || "").toLowerCase();
            if (t.indexOf("community") >= 0 || t.indexOf("announcement") >= 0) {
              showTeacherPage("community");
            } else if (t.indexOf("live") >= 0) {
              showTeacherPage("live");
            }
          }
        };
      } catch (e) { /* ignore */ }
    }
  }

  async function pollTeacherNotifications() {
    if (!getTeacherAuthToken()) return;
    try {
      var list = await teacherApi("/api/v1/notifications/");
      if (!list || !list.length) return;
      var newest = list[0];
      if (lastId && newest.id !== lastId && !newest.is_read) {
        showTeacherNotification(newest);
      }
      lastId = newest.id;
      localStorage.setItem("sia_teacher_last_notif_id", newest.id);
      var badge = document.getElementById("teacher-notif-badge");
      if (badge) {
        var unread = list.filter(function (n) { return !n.is_read; }).length;
        badge.textContent = unread > 0 ? String(unread) : "";
        badge.classList.toggle("hidden", unread === 0);
      }
    } catch (e) { /* ignore */ }
  }

  window.startTeacherNotifications = function () {
    if (typeof Notification !== "undefined" && Notification.permission === "default") {
      Notification.requestPermission().catch(function () {});
    }
    pollTeacherNotifications();
    if (!pollTimer) pollTimer = setInterval(pollTeacherNotifications, 45000);
  };
})();
