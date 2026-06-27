/**
 * Scholaxia Community — opens Discord app directly on same server (/discord-app).
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

  window.openDiscordCommunityPage = function () {
    if (typeof markCommunityRead === "function") markCommunityRead();

    if (!isStudentLoggedIn || !isStudentLoggedIn()) {
      if (typeof goToLogin === "function") goToLogin("community");
      else if (typeof showPage === "function") showPage("community");
      return;
    }

    if (window.location.href.indexOf("/discord-app/scholaxia") >= 0) return;

    window.location.assign(buildDiscordUrl());
  };

  window.loadDiscordCommunity = function () {
    openDiscordCommunityPage();
  };

  window.discordSelectHomeChannel = function () { openDiscordCommunityPage(); };
  window.openGroupChat = function () { openDiscordCommunityPage(); };
  window.openDiscordCreateModal = function () { openDiscordCommunityPage(); };
  window.closeDiscordModal = function () {};
  window.discordCreateGroup = function () {};
  window.sendDiscordMessage = function () {};
})();
