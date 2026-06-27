/**
 * Scholaxia Community — Discord-style UI using Scholaxia APIs (no Stream / Next.js).
 */
(function () {
  var pollTimer = null;
  var booted = false;
  var loading = false;

  var state = {
    server: "scholaxia",
    groupId: null,
    groupMeta: null,
    channel: "general",
    channels: {},
    groups: [],
    messages: [],
  };

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

  function formatTime(iso) {
    if (!iso) return "";
    try {
      var d = new Date(iso);
      return d.toLocaleString(undefined, { month: "short", day: "numeric", hour: "2-digit", minute: "2-digit" });
    } catch (e) {
      return "";
    }
  }

  function hubEl() {
    return document.getElementById("discord-hub");
  }

  function showStatus(msg) {
    var hub = hubEl();
    var status = document.getElementById("discord-hub-status");
    if (hub) hub.classList.add("hidden");
    if (status) {
      status.classList.remove("hidden");
      status.innerHTML = "<p>" + escHtml(msg || "") + "</p>";
    }
  }

  function showHubLoading() {
    showHub();
    var el = document.getElementById("discord-messages");
    if (el) el.innerHTML = '<div class="discord-empty">Loading…</div>';
  }

  function showHub() {
    var hub = hubEl();
    var status = document.getElementById("discord-hub-status");
    if (status) status.classList.add("hidden");
    if (hub) hub.classList.remove("hidden");
  }

  function stopPoll() {
    if (pollTimer) {
      clearInterval(pollTimer);
      pollTimer = null;
    }
  }

  function startPoll(fn) {
    stopPoll();
    pollTimer = setInterval(fn, 10000);
  }

  function scholaxiaChannels() {
    return [
      { id: "general", label: "general", type: "posts" },
      { id: "groups", label: "groups", type: "groups" },
      { id: "announcements", label: "announcements", type: "announcements" },
    ];
  }

  function renderGroupRow(g, opts) {
    opts = opts || {};
    var gid = String(g.id || "").replace(/'/g, "\\'");
    var initial = escHtml((g.name || "G").charAt(0).toUpperCase());
    var members = g.member_count != null ? g.member_count : 0;
    var desc = escHtml(g.description || "Student study group");
    var meta = desc + " · " + members + " member" + (members === 1 ? "" : "s");
    if (g.creator_name && opts.showCreator) meta += " · by " + escHtml(g.creator_name);

    var actions = "";
    if (g.is_member) {
      if (!g.is_approved) {
        actions = '<span class="discord-group-pill">Waiting for admin approval</span>';
      } else {
        actions =
          '<button type="button" class="discord-group-btn discord-group-btn-primary" onclick="openGroupChat(\'' +
          gid +
          '\')">Open chat</button>';
        if (g.is_admin) {
          actions +=
            '<button type="button" class="discord-group-btn discord-group-btn-secondary" onclick="viewGroupRequests(\'' +
            gid +
            '\')">Manage requests</button>';
          actions +=
            '<button type="button" class="discord-group-btn discord-group-btn-secondary" onclick="discordRenameGroup(\'' +
            gid +
            '\')">Rename</button>';
          actions +=
            '<button type="button" class="discord-group-btn discord-group-btn-secondary" onclick="discordDeleteGroup(\'' +
            gid +
            '\')">Delete</button>';
        }
      }
    } else if (g.pending_request) {
      actions = '<span class="discord-group-pill">Request pending</span>';
    } else if (opts.allowJoin) {
      actions =
        '<button type="button" class="discord-group-btn discord-group-btn-primary" onclick="requestJoinGroup(\'' +
        gid +
        '\')">Join group</button>';
    }

    var badges = "";
    if (!g.is_approved) badges += '<span class="discord-group-badge pending">Pending approval</span>';
    if (g.is_admin) badges += '<span class="discord-group-badge">Admin</span>';
    if (g.is_community_listed) badges += '<span class="discord-group-badge listed">Listed</span>';

    return (
      '<article class="discord-group-card">' +
      '<div class="discord-group-card-icon">' +
      initial +
      "</div>" +
      '<div class="discord-group-card-body">' +
      '<div class="discord-group-card-top"><strong>' +
      escHtml(g.name) +
      "</strong>" +
      badges +
      "</div>" +
      '<p class="discord-group-card-desc">' +
      meta +
      "</p>" +
      '<div class="discord-group-card-actions">' +
      actions +
      "</div></div></article>"
    );
  }

  function groupChannels() {
    return [{ id: "chat", label: "general", type: "group-chat" }];
  }

  function renderRail() {
    var rail = document.getElementById("discord-rail");
    if (!rail) return;
    var html =
      '<button type="button" class="discord-rail-icon' +
      (state.server === "scholaxia" ? " active" : "") +
      '" onclick="discordSelectScholaxia()" title="Scholaxia Community">S</button>' +
      '<div class="discord-rail-divider"></div>';
    (state.groups || []).forEach(function (g) {
      var active = state.server === "group" && state.groupId === g.id;
      var letter = escHtml((g.name || "G").charAt(0).toUpperCase());
      html +=
        '<button type="button" class="discord-rail-icon group-icon' +
        (active ? " active" : "") +
        '" onclick="discordSelectGroup(\'' +
        String(g.id).replace(/'/g, "\\'") +
        '\')" title="' +
        escHtml(g.name) +
        '">' +
        letter +
        "</button>";
    });
    rail.innerHTML = html;
  }

  function renderChannelList() {
    var list = document.getElementById("discord-channels-list");
    var head = document.getElementById("discord-server-name");
    if (!list) return;

    var channels = state.server === "scholaxia" ? scholaxiaChannels() : groupChannels();
    if (head) {
      head.textContent =
        state.server === "scholaxia"
          ? "Scholaxia"
          : (state.groupMeta && state.groupMeta.name) || "Group";
    }

    var html = '<div class="discord-ch-section">Text channels</div>';
    channels.forEach(function (ch) {
      html +=
        '<button type="button" class="discord-ch-item' +
        (state.channel === ch.id ? " active" : "") +
        '" onclick="discordSelectChannel(\'' +
        ch.id +
        '\')"><span class="discord-ch-hash">#</span> ' +
        escHtml(ch.label) +
        "</button>";
    });
    list.innerHTML = html;
  }

  function updateHeader() {
    var title = document.getElementById("discord-channel-title");
    var channels = state.server === "scholaxia" ? scholaxiaChannels() : groupChannels();
    var ch = channels.find(function (c) { return c.id === state.channel; }) || channels[0];
    if (title && ch) title.textContent = ch.label;

    var input = document.getElementById("discord-message-input");
    var composer = document.getElementById("discord-composer");
    var isReadonly =
      state.channel === "announcements" ||
      state.channel === "groups" ||
      (state.server === "group" && state.groupMeta && (!state.groupMeta.is_member || !state.groupMeta.is_approved));
    if (composer) composer.classList.toggle("hidden", isReadonly);
    if (input && ch) {
      if (isReadonly) input.placeholder = "";
      else if (state.channel === "general" && state.server === "scholaxia") input.placeholder = "Write a post in #" + ch.label + "…";
      else input.placeholder = "Message #" + ch.label;
    }
  }

  function renderChatMessages(messages) {
    var el = document.getElementById("discord-messages");
    if (!el) return;
    var list = messages || [];
    if (!list.length) {
      el.innerHTML = '<div class="discord-empty">No messages yet. Say hello!</div>';
      return;
    }
    el.innerHTML = list
      .map(function (m) {
        var name = m.sender_name || m.author_name || "User";
        var mine = m.is_mine ? " discord-msg-mine" : "";
        var pending = m._pending ? " opacity-60" : "";
        return (
          '<div class="discord-msg' +
          mine +
          pending +
          '">' +
          '<div class="discord-msg-avatar">' +
          escHtml(name.charAt(0).toUpperCase()) +
          "</div>" +
          '<div class="discord-msg-body">' +
          '<div class="discord-msg-meta"><strong>' +
          escHtml(name) +
          "</strong><time>" +
          escHtml(formatTime(m.created_at)) +
          "</time></div>" +
          '<p class="discord-msg-text">' +
          escHtml(m.content) +
          "</p></div></div>"
        );
      })
      .join("");
    el.scrollTop = el.scrollHeight;
  }

  async function loadGeneralPostsPanel(newPost) {
    var el = document.getElementById("discord-messages");
    if (!el) return;
    el.innerHTML =
      '<div id="community-feed" class="community-feed discord-posts-feed"><div class="loading">Loading posts…</div></div>';
    stopPoll();
    window.communityPostUiMode = "emoji";
    if (typeof loadCommunityPostsFeed === "function") await loadCommunityPostsFeed(newPost);
    startPoll(function () {
      if (typeof loadCommunityPostsFeed === "function") loadCommunityPostsFeed(null);
    });
  }

  async function loadGroupPostsPanel() {
    var el = document.getElementById("discord-messages");
    if (!state.groupId) return;

    try {
      if (!state.groupMeta || state.groupMeta.is_member == null) {
        state.groupMeta = await apiFn()("/api/v1/student-groups/" + state.groupId, { attempts: 3 });
        renderChannelList();
        updateHeader();
      }
      if (!state.groupMeta.is_member) {
        if (el) {
          el.innerHTML =
            '<div class="discord-empty">Join this group first.<br>' +
            '<button type="button" class="discord-group-btn discord-group-btn-primary" style="margin-top:12px" onclick="discordSelectScholaxia(); discordSelectChannel(\'groups\')">Browse groups</button></div>';
        }
        stopPoll();
        return;
      }
      if (!state.groupMeta.is_approved) {
        if (el) {
          el.innerHTML =
            '<div class="discord-empty">This group is waiting for admin approval. Chat opens once approved.</div>';
        }
        stopPoll();
        return;
      }
    } catch (e) {
      if (el) el.innerHTML = '<div class="discord-error">' + escHtml(e.message) + "</div>";
      return;
    }

    el.innerHTML =
      '<div id="community-feed" class="community-feed discord-posts-feed"><div class="loading">Loading posts…</div></div>';

    try {
      window.communityPostUiMode = "comments";
      if (typeof ensureCommunityChannel === "function") await ensureCommunityChannel();
      var posts = await apiFn()(
        "/api/v1/student-groups/" + state.groupId + "/posts?limit=50",
        { attempts: 3 }
      );
      if (typeof fetchPostComments === "function" && typeof attachComments === "function") {
        var commentsByPost = await fetchPostComments();
        posts = attachComments(posts || [], commentsByPost);
      }
      if (typeof renderCommunityPosts === "function") renderCommunityPosts(posts || []);
      else if (el) el.innerHTML = '<div class="discord-empty">No posts yet.</div>';
      startPoll(function () { loadGroupPostsPanel(); });
    } catch (e) {
      if (el) {
        el.innerHTML =
          '<div class="discord-error">' + escHtml(e.message || "Could not load group posts.") + "</div>";
      }
    }
  }

  async function loadGroupsPanel() {
    var el = document.getElementById("discord-messages");
    if (!el) return;
    el.innerHTML =
      '<div class="discord-groups-panel">' +
      '<div class="discord-groups-create">' +
      '<input type="text" id="discord-new-group-name" placeholder="New group name" maxlength="80" />' +
      '<input type="text" id="discord-new-group-desc" placeholder="Description (optional)" maxlength="200" />' +
      '<label class="discord-groups-create-check"><input type="checkbox" id="discord-new-group-list" checked /> List for others to join after admin approval</label>' +
      '<p class="discord-groups-hint" style="padding:0;margin:0;flex:1 1 100%">New groups need admin approval before they become active.</p>' +
      '<button type="button" class="discord-group-btn discord-group-btn-primary" onclick="discordCreateGroupFromHub()">Create group</button>' +
      "</div>" +
      '<div class="discord-groups-section"><h3>Your groups</h3><div id="discord-groups-mine" class="discord-groups-list"><div class="loading">Loading…</div></div></div>' +
      '<div class="discord-groups-section"><h3>Discover groups</h3><div id="discord-groups-discover" class="discord-groups-list"><div class="loading">Loading…</div></div></div>' +
      "</div>";
    stopPoll();

    try {
      if (typeof warmScholaxiaApi === "function") await warmScholaxiaApi().catch(function () {});
      var results = await Promise.all([
        apiFn()("/api/v1/student-groups/mine", { attempts: 3 }),
        apiFn()("/api/v1/student-groups/community-listed", { attempts: 3 }),
      ]);
      var mine = results[0] || [];
      var listed = results[1] || [];
      state.groups = mine.filter(function (g) { return g.is_approved; });
      state.allGroups = mine;
      renderRail();

      var mineEl = document.getElementById("discord-groups-mine");
      var discoverEl = document.getElementById("discord-groups-discover");
      if (mineEl) {
        mineEl.innerHTML = mine.length
          ? mine.map(function (g) { return renderGroupRow(g, { allowJoin: false }); }).join("")
          : '<p class="discord-groups-hint">You have not joined a group yet. Create one above or join below.</p>';
      }
      if (discoverEl) {
        var discover = listed.filter(function (g) { return !g.is_member; });
        discoverEl.innerHTML = discover.length
          ? discover.map(function (g) { return renderGroupRow(g, { allowJoin: true, showCreator: true }); }).join("")
          : '<p class="discord-groups-hint">No open groups right now. Create one and list it for others.</p>';
      }
    } catch (e) {
      if (el) {
        el.innerHTML =
          '<div class="discord-error">' + escHtml(e.message || "Could not load groups.") + "</div>";
      }
    }
  }

  window.refreshDiscordGroupsPanel = function () {
    if (state.server === "scholaxia" && state.channel === "groups") loadGroupsPanel();
    loadGroups().then(function () { renderRail(); });
  };

  window.discordRenameGroup = async function (groupId) {
    var name = prompt("New group name:");
    if (!name || !name.trim()) return;
    try {
      await apiFn()("/api/v1/student-groups/" + groupId, {
        method: "PATCH",
        body: JSON.stringify({ name: name.trim() }),
        attempts: 2,
      });
      await loadGroupsPanel();
      loadGroups().then(function () { renderRail(); });
    } catch (e) {
      alert(e.message || "Could not rename group.");
    }
  };

  window.discordDeleteGroup = async function (groupId) {
    if (!confirm("Delete this group permanently? This cannot be undone.")) return;
    try {
      await apiFn()("/api/v1/student-groups/" + groupId, { method: "DELETE", attempts: 2 });
      if (state.groupId === groupId) {
        window.discordSelectScholaxia();
        window.discordSelectChannel("groups");
      }
      await loadGroupsPanel();
      loadGroups().then(function () { renderRail(); });
    } catch (e) {
      alert(e.message || "Could not delete group.");
    }
  };

  window.discordCreateGroupFromHub = async function () {
    var nameEl = document.getElementById("discord-new-group-name");
    var descEl = document.getElementById("discord-new-group-desc");
    var listEl = document.getElementById("discord-new-group-list");
    var n = nameEl ? nameEl.value.trim() : "";
    if (!n) {
      alert("Enter a group name.");
      return;
    }
    try {
      var created = await apiFn()("/api/v1/student-groups/", {
        method: "POST",
        body: JSON.stringify({
          name: n,
          description: descEl ? descEl.value.trim() : "",
          is_public: true,
          is_community_listed: listEl ? listEl.checked : true,
        }),
        attempts: 2,
      });
      if (nameEl) nameEl.value = "";
      if (descEl) descEl.value = "";
      await loadGroupsPanel();
      alert((created && created.message) || "Group submitted for admin approval.");
    } catch (e) {
      alert(e.message || "Could not create group.");
    }
  };

  async function loadAnnouncementsPanel() {
    var el = document.getElementById("discord-messages");
    if (!el) return;
    el.innerHTML =
      '<div id="community-announcements" class="community-feed discord-posts-feed discord-announcements-feed"><div class="loading">Loading announcements…</div></div>';
    stopPoll();
    window.communityPostUiMode = "comments";
    if (typeof loadCommunityAnnouncements === "function") await loadCommunityAnnouncements();
  }

  async function loadGroupChat(silent) {
    await loadGroupPostsPanel();
  }

  async function refreshActivePanel(silent) {
    if (state.server === "group") {
      await loadGroupChat(silent);
      return;
    }
    if (state.channel === "general") {
      await loadGeneralPostsPanel();
    } else if (state.channel === "groups") {
      await loadGroupsPanel();
    } else if (state.channel === "announcements") {
      await loadAnnouncementsPanel();
    }
  }

  async function loadChannelsMeta() {
    try {
      var chs = await apiFn()("/api/v1/community/channels", { attempts: 2 });
      (chs || []).forEach(function (c) {
        if (c.type === "general") state.channels.general = c;
        if (c.type === "teacher_announcement") state.channels.announcements = c;
      });
    } catch (e) { /* optional */ }
  }

  async function loadGroups() {
    try {
      var all = (await apiFn()("/api/v1/student-groups/mine", { attempts: 2 })) || [];
      state.groups = all.filter(function (g) { return g.is_approved; });
      state.allGroups = all;
    } catch (e) {
      state.groups = [];
      state.allGroups = [];
    }
  }

  window.discordSelectScholaxia = function () {
    state.server = "scholaxia";
    state.groupId = null;
    state.groupMeta = null;
    if (!state.channel || state.channel === "chat") state.channel = "general";
    renderRail();
    renderChannelList();
    updateHeader();
    refreshActivePanel(false);
  };

  window.discordSelectGroup = function (groupId, meta) {
    state.server = "group";
    state.groupId = groupId;
    state.groupMeta = meta || null;
    state.channel = "chat";
    if (typeof showPage === "function") showPage("community");
    renderRail();
    renderChannelList();
    updateHeader();
    refreshActivePanel(false);
  };

  window.discordSelectChannel = function (channelId) {
    state.channel = channelId;
    renderChannelList();
    updateHeader();
    refreshActivePanel(false);
  };

  window.discordSelectHomeChannel = function () {
    window.discordSelectScholaxia();
    window.discordSelectChannel("general");
  };

  window.sendDiscordHubMessage = async function () {
    var input = document.getElementById("discord-message-input");
    if (!input) return;
    var text = input.value.trim();
    if (!text) return;

    if (state.server === "group") {
      if (!state.groupId || !state.groupMeta || !state.groupMeta.is_member || !state.groupMeta.is_approved) return;
      input.value = "";
      try {
        await apiFn()("/api/v1/student-groups/" + state.groupId + "/posts", {
          method: "POST",
          body: JSON.stringify({ content: text }),
          attempts: 3,
        });
        await loadGroupPostsPanel();
      } catch (e) {
        alert(e.message || "Post blocked or could not send.");
        input.value = text;
      }
      return;
    }

    if (state.channel !== "general") return;
    input.value = "";
    try {
      if (typeof ensureCommunityChannel === "function") await ensureCommunityChannel();
      var channelId =
        (state.channels.general && state.channels.general.id) ||
        (typeof communityChannelId !== "undefined" ? communityChannelId : null);
      if (!channelId) throw new Error("Community channel not available.");
      await apiFn()("/api/v1/community/posts", {
        method: "POST",
        body: JSON.stringify({ channel_id: channelId, content: text }),
        attempts: 3,
      });
      await loadGeneralPostsPanel();
    } catch (e) {
      alert(e.message || "Post blocked or could not send.");
      input.value = text;
    }
  };

  window.openDiscordCommunityPage = function () {
    if (typeof showPage === "function") showPage("community");
  };

  window.loadDiscordCommunity = async function () {
    if (loading) return;
    if (typeof markCommunityRead === "function") markCommunityRead();

    if (!isStudentLoggedIn || !isStudentLoggedIn()) {
      showStatus("Log in to open Community.");
      return;
    }

    if (!hubEl()) return;

    loading = true;
    showHubLoading();

    try {
      if (typeof warmScholaxiaApi === "function") await warmScholaxiaApi().catch(function () {});
      await Promise.all([loadChannelsMeta(), loadGroups()]);
      if (typeof ensureCommunityChannel === "function") await ensureCommunityChannel().catch(function () {});

      if (!booted) {
        state.server = "scholaxia";
        state.channel = "general";
        booted = true;
      }
      if (state.channel === "feed" || state.channel === "posts") state.channel = "general";

      showHub();
      renderRail();
      renderChannelList();
      updateHeader();
      await refreshActivePanel(false);

      var input = document.getElementById("discord-message-input");
      if (input && state.channel === "general" && state.server === "scholaxia") input.focus();
    } catch (e) {
      showHub();
      var errEl = document.getElementById("discord-messages");
      if (errEl) {
        errEl.innerHTML = '<div class="discord-error">' + escHtml(e.message || "Could not load Community.") + "</div>";
      }
    } finally {
      loading = false;
    }
  };

  window.openGroupChat = function (groupId, meta) {
    window.discordSelectGroup(groupId, meta);
  };

  window.openDiscordCreateModal = function () {
    if (typeof openCommunityCreate === "function") openCommunityCreate();
  };
  window.closeDiscordModal = function () {};
  window.discordCreateGroup = function () {
    if (typeof showPage === "function") {
      showPage("groups");
      if (typeof loadGroupsPage === "function") loadGroupsPage();
    }
  };
  window.sendDiscordMessage = window.sendDiscordHubMessage;

  document.addEventListener("keydown", function (e) {
    if (e.key !== "Enter" || e.shiftKey) return;
    var input = document.getElementById("discord-message-input");
    if (!input || document.activeElement !== input) return;
    e.preventDefault();
    window.sendDiscordHubMessage();
  });

  function autoLoadIfCommunityTab() {
    try {
      if (sessionStorage.getItem("sia_current_page") === "community" && isStudentLoggedIn && isStudentLoggedIn()) {
        loadDiscordCommunity();
      }
    } catch (e) { /* ignore */ }
  }

  window.addEventListener("beforeunload", stopPoll);

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", autoLoadIfCommunityTab);
  } else {
    autoLoadIfCommunityTab();
  }
})();
