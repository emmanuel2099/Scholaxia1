/**
 * Scholaxia Community — embedded Discord clone (same-origin iframe).
 */
(function () {
  var DISCORD_PREFIX = "/discord-app";
  var loadTimer = null;

  function scholaxiaUserId() {
    try {
      var tok = localStorage.getItem("sia_token") || localStorage.getItem("sia_teacher_token") || "";
      if (tok) {
        var parts = tok.split(".");
        if (parts.length >= 2) {
          var payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
          if (payload.sub) return String(payload.sub);
          if (payload.user_id) return String(payload.user_id);
        }
      }
    } catch (e) { /* ignore */ }
    var email = localStorage.getItem("sia_email");
    if (email) return email.replace(/[^a-zA-Z0-9_-]/g, "_");
    return "scholaxia-student";
  }

  function scholaxiaUserName() {
    if (typeof getUser === "function") return getUser().name || "Student";
    return localStorage.getItem("sia_name") || "Student";
  }

  function buildDiscordPath() {
    var uid = scholaxiaUserId();
    var name = scholaxiaUserName();
    return (
      DISCORD_PREFIX +
      "/scholaxia?embed=1&userId=" +
      encodeURIComponent(uid) +
      "&name=" +
      encodeURIComponent(name)
    );
  }

  function showStatus(message, hint) {
    var status = document.getElementById("discord-embed-status");
    var frame = document.getElementById("discord-community-frame");
    if (frame) frame.classList.add("hidden");
    if (!status) return;
    status.classList.remove("hidden");
    status.innerHTML =
      "<p>" + (message || "Loading Community…") + "</p>" +
      (hint ? '<p class="discord-embed-hint">' + hint + "</p>" : "") +
      '<button type="button" class="btn-action btn-sm" style="margin-top:8px" onclick="loadDiscordCommunity(true)">Retry</button>';
  }

  function hideStatusShowFrame() {
    var status = document.getElementById("discord-embed-status");
    var frame = document.getElementById("discord-community-frame");
    if (status) status.classList.add("hidden");
    if (frame) frame.classList.remove("hidden");
  }

  window.openDiscordCommunityPage = function () {
    if (typeof showPage === "function") showPage("community");
  };

  window.loadDiscordCommunity = function () {
    if (typeof markCommunityRead === "function") markCommunityRead();

    if (!isStudentLoggedIn || !isStudentLoggedIn()) {
      showStatus("Log in to open Community.", "Sign in from the home screen first.");
      return;
    }

    var path = buildDiscordPath();
    var frame = document.getElementById("discord-community-frame");
    if (!frame) return;

    if (loadTimer) {
      clearTimeout(loadTimer);
      loadTimer = null;
    }

    showStatus("Loading Community…", "Discord chat loads inside this tab.");

    frame.onload = function () {
      if (loadTimer) {
        clearTimeout(loadTimer);
        loadTimer = null;
      }
      hideStatusShowFrame();
    };

    if (frame.getAttribute("data-src") === path && frame.src) {
      hideStatusShowFrame();
      return;
    }

    frame.setAttribute("data-src", path);
    frame.src = path;

    loadTimer = setTimeout(function () {
      var status = document.getElementById("discord-embed-status");
      if (status && !status.classList.contains("hidden")) {
        showStatus(
          "Community is taking longer than expected.",
          "Check scholaxia-desktop/stream.env has STREAM_CHAT_SECRET, then restart Scholaxia."
        );
      }
    }, 15000);
  };

  window.discordSelectHomeChannel = function () { loadDiscordCommunity(); };
  window.openGroupChat = function () { loadDiscordCommunity(); };
  window.openDiscordCreateModal = function () { loadDiscordCommunity(); };
  window.closeDiscordModal = function () {};
  window.discordCreateGroup = function () {};
  window.sendDiscordMessage = function () {};
})();
