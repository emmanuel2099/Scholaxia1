/**
 * Community: one short ping on new posts + unread badge on Community nav.
 */
(function () {
  var pollTimer = null;
  var lastTopPostId = null;
  var unreadCount = 0;
  var audioCtx = null;

  function playCommunityPing() {
    try {
      if (!audioCtx) audioCtx = new (window.AudioContext || window.webkitAudioContext)();
      if (audioCtx.state === "suspended") audioCtx.resume();
      var t0 = audioCtx.currentTime;
      var osc = audioCtx.createOscillator();
      var gain = audioCtx.createGain();
      osc.type = "sine";
      osc.frequency.value = 880;
      gain.gain.setValueAtTime(0, t0);
      gain.gain.linearRampToValueAtTime(0.15, t0 + 0.02);
      gain.gain.exponentialRampToValueAtTime(0.001, t0 + 0.35);
      osc.connect(gain);
      gain.connect(audioCtx.destination);
      osc.start(t0);
      osc.stop(t0 + 0.4);
    } catch (e) { /* ignore */ }
  }

  function updateCommunityBadge() {
    var badge = document.getElementById("community-badge");
    if (!badge) return;
    if (unreadCount > 0) {
      badge.textContent = unreadCount > 99 ? "99+" : String(unreadCount);
      badge.classList.remove("hidden");
    } else {
      badge.classList.add("hidden");
    }
  }

  function markCommunityRead() {
    unreadCount = 0;
    updateCommunityBadge();
    try {
      if (lastTopPostId) localStorage.setItem("sia_community_last_post", lastTopPostId);
    } catch (e) { /* ignore */ }
  }

  async function checkCommunityUpdates() {
    if (typeof getToken !== "function" || !getToken()) return;
    if (typeof isStudentLoggedIn === "function" && !isStudentLoggedIn()) return;
    try {
      var posts = await api("/api/v1/community/feed?limit=5");
      if (!posts || !posts.length) return;
      var topId = String(posts[0].id || "");
      if (!topId) return;
      var stored = "";
      try { stored = localStorage.getItem("sia_community_last_post") || ""; } catch (e) { /* ignore */ }
      if (!lastTopPostId) lastTopPostId = stored || topId;
      if (topId !== lastTopPostId && stored && topId !== stored) {
        var onCommunity = typeof currentPage !== "undefined" && currentPage === "community";
        if (!onCommunity) {
          unreadCount = Math.min(unreadCount + 1, 99);
          updateCommunityBadge();
          playCommunityPing();
        } else {
          markCommunityRead();
        }
      }
      lastTopPostId = topId;
    } catch (e) { /* ignore */ }
  }

  function startCommunityNotifyPoll() {
    if (pollTimer) clearInterval(pollTimer);
    try {
      lastTopPostId = localStorage.getItem("sia_community_last_post") || null;
    } catch (e) { /* ignore */ }
    checkCommunityUpdates();
    pollTimer = setInterval(checkCommunityUpdates, 25000);
  }

  window.markCommunityRead = markCommunityRead;
  window.startCommunityNotifyPoll = startCommunityNotifyPoll;
  window.playCommunityPing = playCommunityPing;

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      if (typeof isStudentLoggedIn === "function" && isStudentLoggedIn()) startCommunityNotifyPoll();
    });
  } else if (typeof isStudentLoggedIn === "function" && isStudentLoggedIn()) {
    startCommunityNotifyPoll();
  }
})();
