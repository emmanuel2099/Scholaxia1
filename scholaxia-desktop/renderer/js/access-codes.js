/**
 * Access Code tab — codes delivered when teacher hosts a class (copy only).
 */
(function () {
  var accessCodePollTimer = null;

  function updateAccessCodeBadge(count) {
    var badge = document.getElementById("access-code-badge");
    if (!badge) return;
    if (count > 0) {
      badge.textContent = count > 99 ? "99+" : String(count);
      badge.classList.remove("hidden");
    } else {
      badge.classList.add("hidden");
    }
  }

  async function refreshAccessCodeBadge() {
    try {
      var data = await api("/api/v1/live-classes/access-codes/mine");
      updateAccessCodeBadge((data && data.unread_count) || 0);
    } catch (e) { /* ignore */ }
  }

  function escHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function visibilityLabel(v) {
    if (v === "private") return "Private";
    if (v === "school_group") return "School";
    if (v === "public") return "Public";
    return "Class";
  }

  async function loadAccessCodesPage() {
    var list = document.getElementById("access-codes-list");
    if (!list) return;
    list.innerHTML = '<div class="loading">Loading access codes…</div>';
    try {
      var data = await api("/api/v1/live-classes/access-codes/mine");
      var codes = (data && data.codes) || [];
      updateAccessCodeBadge((data && data.unread_count) || 0);
      if (!codes.length) {
        list.innerHTML =
          '<div class="empty-state">' +
          "<h3>No access codes yet</h3>" +
          "<p>When your teacher hosts a class for you, the unique code appears here. Copy it, then tap <strong>Join Live</strong> and paste once.</p>" +
          "</div>";
        return;
      }
      list.innerHTML = codes.map(function (c) {
        var unread = !c.is_read ? " access-code-card-new" : "";
        return (
          '<article class="access-code-card' + unread + '" data-code="' + escHtml(c.join_code) + '">' +
          '<div class="access-code-card-head">' +
          "<strong>" + escHtml(c.title) + "</strong>" +
          '<span class="access-code-pill">' + escHtml(visibilityLabel(c.visibility)) + "</span>" +
          "</div>" +
          '<p class="access-code-meta">' + escHtml(c.subject || "") + " · " + escHtml(c.teacher_name || "Teacher") + "</p>" +
          '<div class="access-code-value"><code>' + escHtml(c.join_code) + "</code>" +
          '<button type="button" class="btn-sm" onclick="copyAccessCode(\'' + escHtml(c.join_code) + '\')">Copy</button></div>' +
          (c.is_used ? '<p class="access-code-used">Already used to join</p>' : "") +
          "</article>"
        );
      }).join("");
      if (data.unread_count > 0) {
        api("/api/v1/live-classes/access-codes/mark-read", { method: "POST" }).catch(function () {});
        updateAccessCodeBadge(0);
      }
    } catch (e) {
      list.innerHTML = '<p class="error-hint">' + escHtml(e.message || "Could not load codes.") + "</p>";
    }
  }

  window.copyAccessCode = function (code) {
    var text = String(code || "").trim();
    if (!text) return;
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(text).then(function () {
        alert("Code copied: " + text + "\n\nTap Join Live and paste when asked.");
      }).catch(function () {
        prompt("Copy this code:", text);
      });
    } else {
      prompt("Copy this code:", text);
    }
  };

  function startAccessCodePoll() {
    if (accessCodePollTimer) clearInterval(accessCodePollTimer);
    refreshAccessCodeBadge();
    accessCodePollTimer = setInterval(refreshAccessCodeBadge, 45000);
  }

  window.loadAccessCodesPage = loadAccessCodesPage;
  window.refreshAccessCodeBadge = refreshAccessCodeBadge;
  window.startAccessCodePoll = startAccessCodePoll;
})();
