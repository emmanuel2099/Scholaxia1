/**
 * Group chat room — open from Groups tab or feed group cards.
 */
(function () {
  var activeGroupId = null;
  var activeGroupMeta = null;
  var pollTimer = null;
  var localMessages = [];

  function apiFn() {
    return typeof apiRetry === "function" ? apiRetry : api;
  }

  function escHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function formatChatTime(iso) {
    if (!iso) return "";
    try {
      var d = new Date(iso);
      return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
    } catch (e) {
      return "";
    }
  }

  function showChatSkeleton() {
    var el = document.getElementById("group-chat-messages");
    if (!el) return;
    el.innerHTML =
      '<div class="feed-skeleton chat-skeleton" aria-busy="true">' +
      '<div class="skel-bubble skel-left"></div><div class="skel-bubble skel-right"></div>' +
      '<div class="skel-bubble skel-left skel-short"></div>' +
      '<p class="skel-label">Loading messages…</p></div>';
  }

  function renderMessages(messages) {
    var el = document.getElementById("group-chat-messages");
    if (!el) return;
    var list = messages || localMessages;
    if (!list.length) {
      el.innerHTML = '<div class="group-chat-empty">No messages yet. Say hello to your group!</div>';
      return;
    }
    el.innerHTML = list.map(function (m) {
      var mine = m.is_mine ? " group-msg-mine" : "";
      var pending = m._pending ? " group-msg-pending" : "";
      return (
        '<div class="group-msg' + mine + pending + '">' +
        '<div class="group-msg-meta"><strong>' + escHtml(m.author_name || "Student") + "</strong>" +
        "<span>" + escHtml(formatChatTime(m.created_at)) + "</span></div>" +
        '<p class="group-msg-text">' + escHtml(m.content) + "</p></div>"
      );
    }).join("");
    el.scrollTop = el.scrollHeight;
  }

  function renderMembers(members) {
    var list = document.getElementById("group-chat-members-list");
    if (!list) return;
    if (!members || !members.length) {
      list.innerHTML = '<p class="host-hint">No members yet.</p>';
      return;
    }
    list.innerHTML = members.map(function (m) {
      var badge = m.role === "admin" ? '<span class="access-code-pill">Admin</span>' : "";
      return (
        '<div class="group-member-row">' +
        '<div class="group-member-avatar">' + escHtml((m.name || "S").charAt(0).toUpperCase()) + "</div>" +
        "<div><strong>" + escHtml(m.name) + "</strong> " + badge +
        '<p class="host-hint">' + escHtml(m.email || "") + "</p></div></div>"
      );
    }).join("");
  }

  async function loadMembers() {
    if (!activeGroupId) return;
    try {
      var members = await apiFn()("/api/v1/student-groups/" + activeGroupId + "/members", { attempts: 2 });
      renderMembers(members);
    } catch (e) {
      var list = document.getElementById("group-chat-members-list");
      if (list) list.innerHTML = '<p class="error-hint">' + escHtml(e.message) + "</p>";
    }
  }

  async function refreshMessages(silent) {
    if (!activeGroupId) return;
    if (!silent) showChatSkeleton();
    try {
      var messages = await apiFn()("/api/v1/student-groups/" + activeGroupId + "/messages?limit=120", { attempts: 3 });
      localMessages = messages || [];
      renderMessages(localMessages);
    } catch (e) {
      if (localMessages.length) {
        renderMessages(localMessages);
        return;
      }
      var el = document.getElementById("group-chat-messages");
      if (el) {
        el.innerHTML =
          '<div class="group-chat-retry">' +
          '<p>' + escHtml(/failed to fetch|timed out/i.test(e.message || "") ? "Server is waking up…" : e.message) + "</p>" +
          '<button type="button" class="btn-sm" onclick="loadGroupChatPage()">Try again</button></div>';
      }
    }
  }

  function startPoll() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(function () { refreshMessages(true); }, 10000);
  }

  function stopPoll() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  async function openGroupChat(groupId, meta) {
    activeGroupId = groupId;
    activeGroupMeta = meta || null;
    localMessages = [];
    stopPoll();
    showPage("group-chat");

    var title = document.getElementById("group-chat-title");
    var sub = document.getElementById("group-chat-subtitle");
    var addBox = document.getElementById("group-chat-add-member");
    var input = document.getElementById("group-chat-input");
    if (meta && meta.name && title) title.textContent = meta.name;
    if (meta && sub) {
      sub.textContent = (meta.member_count || 0) + " member" + ((meta.member_count || 0) === 1 ? "" : "s") +
        (meta.description ? " · " + meta.description : "");
    }
    showChatSkeleton();
    if (input) input.value = "";

    try {
      if (typeof warmScholaxiaApi === "function") await warmScholaxiaApi().catch(function () {});
      var info = meta && meta.is_member != null
        ? meta
        : await apiFn()("/api/v1/student-groups/" + groupId, { attempts: 3 });
      activeGroupMeta = info;
      if (title) title.textContent = info.name || "Group chat";
      if (sub) {
        sub.textContent = (info.member_count || 0) + " member" + ((info.member_count || 0) === 1 ? "" : "s") +
          (info.description ? " · " + info.description : "");
      }
      if (addBox) addBox.classList.toggle("hidden", !info.is_admin);
      if (!info.is_member) {
        var msgs = document.getElementById("group-chat-messages");
        if (msgs) msgs.innerHTML = '<div class="empty">Join this group first to open the chat room.</div>';
        return;
      }
      await Promise.all([refreshMessages(true), loadMembers()]);
      startPoll();
      if (input) input.focus();
    } catch (e) {
      var msgsEl = document.getElementById("group-chat-messages");
      if (msgsEl) {
        msgsEl.innerHTML =
          '<div class="group-chat-retry"><p>' + escHtml(e.message) + '</p>' +
          '<button type="button" class="btn-sm" onclick="openGroupChat(\'' + String(groupId).replace(/'/g, "\\'") + '\')">Try again</button></div>';
      }
    }
  }

  window.openGroupChat = openGroupChat;

  window.loadGroupChatPage = function () {
    if (activeGroupId) openGroupChat(activeGroupId, activeGroupMeta);
  };

  window.sendGroupChatMessage = async function () {
    var input = document.getElementById("group-chat-input");
    if (!input || !activeGroupId) return;
    var text = input.value.trim();
    if (!text) return;
    input.value = "";
    var optimistic = {
      id: "local-" + Date.now(),
      author_name: (typeof getUser === "function" ? getUser().name : null) || "You",
      content: text,
      created_at: new Date().toISOString(),
      is_mine: true,
      _pending: true,
    };
    localMessages = (localMessages || []).concat([optimistic]);
    renderMessages(localMessages);
    try {
      var sent = await apiFn()("/api/v1/student-groups/" + activeGroupId + "/messages", {
        method: "POST",
        body: JSON.stringify({ content: text }),
        attempts: 3,
      });
      localMessages = localMessages.filter(function (m) { return m.id !== optimistic.id; });
      if (sent) localMessages.push(sent);
      renderMessages(localMessages);
    } catch (e) {
      localMessages = localMessages.filter(function (m) { return m.id !== optimistic.id; });
      renderMessages(localMessages);
      alert(e.message || "Could not send message. Tap Try again or wait a moment.");
      input.value = text;
    }
  };

  window.toggleGroupMembersPanel = function () {
    var panel = document.getElementById("group-chat-members-panel");
    if (panel) panel.classList.toggle("hidden");
  };

  window.addGroupMemberByEmail = async function () {
    var emailInput = document.getElementById("group-add-email");
    if (!emailInput || !activeGroupId) return;
    var email = emailInput.value.trim();
    if (!email) {
      alert("Enter the student's email.");
      return;
    }
    try {
      var res = await apiFn()("/api/v1/student-groups/" + activeGroupId + "/members", {
        method: "POST",
        body: JSON.stringify({ email: email }),
        attempts: 2,
      });
      emailInput.value = "";
      alert((res && res.message) || "Member added.");
      await loadMembers();
    } catch (e) {
      alert(e.message || "Could not add member.");
    }
  };

  window.addEventListener("beforeunload", stopPoll);
})();
