/**
 * Group chat room — open from Groups tab or feed group cards.
 */
(function () {
  var activeGroupId = null;
  var activeGroupMeta = null;
  var pollTimer = null;

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

  function renderMessages(messages) {
    var el = document.getElementById("group-chat-messages");
    if (!el) return;
    if (!messages || !messages.length) {
      el.innerHTML = '<div class="group-chat-empty">No messages yet. Say hello to your group!</div>';
      return;
    }
    el.innerHTML = messages.map(function (m) {
      var mine = m.is_mine ? " group-msg-mine" : "";
      return (
        '<div class="group-msg' + mine + '">' +
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
      var members = await api("/api/v1/student-groups/" + activeGroupId + "/members");
      renderMembers(members);
    } catch (e) {
      var list = document.getElementById("group-chat-members-list");
      if (list) list.innerHTML = '<p class="error-hint">' + escHtml(e.message) + "</p>";
    }
  }

  async function refreshMessages() {
    if (!activeGroupId) return;
    try {
      var messages = await api("/api/v1/student-groups/" + activeGroupId + "/messages?limit=120");
      renderMessages(messages);
    } catch (e) {
      var el = document.getElementById("group-chat-messages");
      if (el) el.innerHTML = '<div class="empty">' + escHtml(e.message) + "</div>";
    }
  }

  function startPoll() {
    if (pollTimer) clearInterval(pollTimer);
    pollTimer = setInterval(refreshMessages, 8000);
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
    stopPoll();
    showPage("group-chat");

    var title = document.getElementById("group-chat-title");
    var sub = document.getElementById("group-chat-subtitle");
    var addBox = document.getElementById("group-chat-add-member");
    var input = document.getElementById("group-chat-input");
    var msgs = document.getElementById("group-chat-messages");
    if (msgs) msgs.innerHTML = '<div class="loading">Loading chat…</div>';
    if (input) input.value = "";

    try {
      var info = meta || (await api("/api/v1/student-groups/" + groupId));
      activeGroupMeta = info;
      if (title) title.textContent = info.name || "Group chat";
      if (sub) {
        sub.textContent = (info.member_count || 0) + " member" + ((info.member_count || 0) === 1 ? "" : "s") +
          (info.description ? " · " + info.description : "");
      }
      if (addBox) addBox.classList.toggle("hidden", !info.is_admin);
      if (!info.is_member) {
        if (msgs) {
          msgs.innerHTML = '<div class="empty">Join this group first to open the chat room.</div>';
        }
        return;
      }
      await refreshMessages();
      await loadMembers();
      startPoll();
      if (input) input.focus();
    } catch (e) {
      if (msgs) msgs.innerHTML = '<div class="empty">' + escHtml(e.message) + "</div>";
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
    try {
      await api("/api/v1/student-groups/" + activeGroupId + "/messages", {
        method: "POST",
        body: JSON.stringify({ content: text }),
      });
      await refreshMessages();
    } catch (e) {
      alert(e.message || "Could not send message.");
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
      var res = await api("/api/v1/student-groups/" + activeGroupId + "/members", {
        method: "POST",
        body: JSON.stringify({ email: email }),
      });
      emailInput.value = "";
      alert((res && res.message) || "Member added.");
      await loadMembers();
      await refreshMessages();
    } catch (e) {
      alert(e.message || "Could not add member.");
    }
  };

  window.addEventListener("beforeunload", stopPoll);
})();
