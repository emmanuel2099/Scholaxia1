/**
 * Open Discord clone on the same host/port as Scholaxia (WebView2 blocks cross-port iframes).
 */
(function () {
  var DISCORD_PREFIX = "/discord-app";

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

  function buildDiscordUrl() {
    var uid = scholaxiaUserId();
    var name = scholaxiaUserName();
    return (
      window.location.origin +
      DISCORD_PREFIX +
      "/scholaxia?userId=" +
      encodeURIComponent(uid) +
      "&name=" +
      encodeURIComponent(name)
    );
  }

  function showStatus(message, hint) {
    var status = document.getElementById("discord-embed-status");
    if (!status) return;
    status.classList.remove("hidden");
    status.innerHTML =
      "<p>" + (message || "Loading Community…") + "</p>" +
      (hint ? '<p class="discord-embed-hint">' + hint + "</p>" : "") +
      '<button type="button" class="btn-action btn-sm" onclick="loadDiscordCommunity(true)">Retry</button>';
  }

  window.loadDiscordCommunity = function () {
    if (typeof markCommunityRead === "function") markCommunityRead();

    if (!isStudentLoggedIn || !isStudentLoggedIn()) {
      showStatus("Log in to open Community.", "Sign in from the home screen first.");
      return;
    }

    var target = buildDiscordUrl();
    if (window.location.href.indexOf("/discord-app/scholaxia") >= 0) return;

    showStatus("Opening Community…", "Same server — no separate window needed.");
    window.location.assign(target);
  };

  window.discordSelectHomeChannel = function () { loadDiscordCommunity(); };
  window.openGroupChat = function () { loadDiscordCommunity(); };
  window.openDiscordCreateModal = function () { loadDiscordCommunity(); };
  window.closeDiscordModal = function () {};
  window.discordCreateGroup = function () {};
  window.sendDiscordMessage = function () {};
})();
