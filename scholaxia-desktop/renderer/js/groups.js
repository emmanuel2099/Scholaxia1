/**
 * Groups tab — student groups + school groups + feed integration.
 */
(function () {
  function escHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function safeId(id) {
    return String(id || "").replace(/'/g, "\\'");
  }

  function renderGroupCard(g, opts) {
    opts = opts || {};
    var gid = safeId(g.id);
    var initial = (g.name || "G").charAt(0).toUpperCase();
    var members = g.member_count != null ? g.member_count : 0;
    var meta = escHtml(g.description || "Student study group") +
      " · " + members + " member" + (members === 1 ? "" : "s");
    if (g.creator_name && opts.showCreator) meta += " · by " + escHtml(g.creator_name);

    var actions = "";
    if (g.is_member) {
      actions =
        '<button type="button" class="btn-action btn-sm group-open-chat" onclick="openGroupChat(\'' + gid + '\')">Open chat</button>';
      if (g.is_admin && !g.is_community_listed) {
        actions += '<button type="button" class="btn-sm" onclick="promoteGroupToCommunity(\'' + gid + '\')">List in feed</button>';
      }
      if (g.is_admin) {
        actions += '<button type="button" class="btn-sm" onclick="viewGroupRequests(\'' + gid + '\')">Requests</button>';
      }
    } else if (g.pending_request) {
      actions = '<span class="group-status-pill pending">Request pending</span>';
    } else if (opts.allowJoin) {
      actions =
        '<button type="button" class="btn-action btn-sm" onclick="requestJoinGroup(\'' + gid + '\')">Join group</button>';
    }

    var badges = "";
    if (g.is_admin) badges += '<span class="group-badge admin">Admin</span>';
    if (g.is_community_listed) badges += '<span class="group-badge listed">In feed</span>';

    var clickable = g.is_member
      ? ' group-card-clickable" onclick="openGroupChat(\'' + gid + '\')" role="button" tabindex="0"'
      : '"';

    return (
      '<article class="group-card-v2' + clickable + '>' +
      '<div class="group-card-icon">' + escHtml(initial) + "</div>" +
      '<div class="group-card-body">' +
      '<div class="group-card-top"><h4>' + escHtml(g.name) + "</h4>" + badges + "</div>" +
      '<p class="group-card-meta">' + meta + "</p>" +
      '<div class="group-card-actions" onclick="event.stopPropagation()">' + actions + "</div>" +
      "</div></article>"
    );
  }

  async function loadGroupsPage() {
    var mineEl = document.getElementById("groups-mine-list");
    var schoolEl = document.getElementById("groups-school-list");
    var communityEl = document.getElementById("groups-community-list");
    var skel = typeof showGroupsSkeleton === "function" ? showGroupsSkeleton : null;
    if (mineEl) (skel ? skel(mineEl) : (mineEl.innerHTML = '<div class="loading">Loading…</div>'));
    if (schoolEl) (skel ? skel(schoolEl) : (schoolEl.innerHTML = '<div class="loading">Loading…</div>'));
    if (communityEl) (skel ? skel(communityEl) : (communityEl.innerHTML = '<div class="loading">Loading…</div>'));

    try {
      if (typeof warmScholaxiaApi === "function") await warmScholaxiaApi().catch(function () {});
      var apiFn = typeof apiRetry === "function" ? apiRetry : api;
      var results = await Promise.all([
        apiFn("/api/v1/student-groups/mine", { attempts: 3 }),
        apiFn("/api/v1/school-groups/student/mine", { attempts: 2 }).catch(function () { return []; }),
        apiFn("/api/v1/student-groups/community-listed", { attempts: 3 }),
      ]);
      var mine = results[0] || [];
      var school = results[1] || [];
      var listed = results[2] || [];

      if (communityEl) {
        var discover = listed.filter(function (g) { return !g.is_member; });
        if (!discover.length) {
          communityEl.innerHTML = '<p class="groups-empty-hint">No open groups right now. Create one and list it in the feed!</p>';
        } else {
          communityEl.innerHTML = discover.map(function (g) {
            return renderGroupCard(g, { allowJoin: true, showCreator: true });
          }).join("");
        }
      }

      if (mineEl) {
        if (!mine.length) {
          mineEl.innerHTML = '<p class="groups-empty-hint">You have not created or joined a group yet. Use the form above to start one.</p>';
        } else {
          mineEl.innerHTML = mine.map(function (g) {
            return renderGroupCard(g, { allowJoin: false, showCreator: false });
          }).join("");
        }
      }

      if (schoolEl) {
        if (!school.length) {
          schoolEl.innerHTML = '<p class="groups-empty-hint">Your school adds you to groups — you cannot join school groups yourself.</p>';
        } else {
          schoolEl.innerHTML = school.map(function (g) {
            return (
              '<article class="group-card-v2 group-card-school">' +
              '<div class="group-card-icon school">&#127979;</div>' +
              '<div class="group-card-body">' +
              '<div class="group-card-top"><h4>' + escHtml(g.school_name) + " — " + escHtml(g.name) + "</h4></div>" +
              '<p class="group-card-meta">Teacher: ' + escHtml(g.teacher_name) + " · " + g.member_count + " students</p>" +
              '<p class="host-hint">Live class codes appear in Access Code tab.</p>' +
              "</div></article>"
            );
          }).join("");
        }
      }
    } catch (e) {
      if (mineEl) mineEl.innerHTML = '<p class="error-hint">' + escHtml(e.message) + "</p>";
    }
  }

  async function createStudentGroup() {
    var name = document.getElementById("new-group-name");
    var desc = document.getElementById("new-group-desc");
    var listFeed = document.getElementById("new-group-list-feed");
    var n = name ? name.value.trim() : "";
    if (!n) {
      alert("Enter a group name.");
      return;
    }
    var listInFeed = listFeed ? listFeed.checked : false;
    try {
      var created = await api("/api/v1/student-groups/", {
        method: "POST",
        body: JSON.stringify({
          name: n,
          description: desc ? desc.value.trim() : "",
          is_public: true,
          is_community_listed: listInFeed,
        }),
      });
      if (name) name.value = "";
      if (desc) desc.value = "";
      loadGroupsPage();
      if (typeof loadCommunity === "function") loadCommunity();
      if (listInFeed && created && created.id) {
        alert((created.message || "Group submitted for admin approval.") + " You will be notified when it is active.");
      } else {
        alert((created && created.message) || "Group submitted for admin approval.");
      }
    } catch (e) {
      alert(e.message || "Could not create group.");
    }
  }

  window.requestJoinGroup = async function (groupId) {
    try {
      var res = await api("/api/v1/student-groups/" + groupId + "/join-request", {
        method: "POST",
        body: JSON.stringify({ message: "I would like to join this group." }),
      });
      alert((res && res.message) || "Join request sent. The admin will approve you.");
      loadGroupsPage();
      if (typeof refreshDiscordGroupsPanel === "function") refreshDiscordGroupsPanel();
      if (typeof loadCommunity === "function") loadCommunity();
    } catch (e) {
      alert(e.message || "Could not send request.");
    }
  };

  window.promoteGroupToCommunity = async function (groupId) {
    if (!confirm("Post this group to the Community feed so others can join?")) return;
    try {
      await api("/api/v1/student-groups/" + groupId + "/community-list", {
        method: "PATCH",
        body: JSON.stringify({ is_community_listed: true }),
      });
      alert("Group is now on the Community feed.");
      loadGroupsPage();
      if (typeof refreshDiscordGroupsPanel === "function") refreshDiscordGroupsPanel();
      if (typeof loadCommunity === "function") loadCommunity();
    } catch (e) {
      alert(e.message || "Could not update group.");
    }
  };

  window.viewGroupRequests = async function (groupId) {
    try {
      var reqs = await api("/api/v1/student-groups/" + groupId + "/join-requests") || [];
      if (!reqs.length) {
        alert("No pending join requests.");
        return;
      }
      var lines = reqs.map(function (r, i) {
        return (i + 1) + ". " + r.name + (r.message ? " — " + r.message : "");
      }).join("\n");
      var pick = prompt("Pending requests:\n" + lines + "\n\nEnter number to approve (1-" + reqs.length + "):", "1");
      if (!pick) return;
      var idx = parseInt(pick, 10) - 1;
      if (idx < 0 || idx >= reqs.length) {
        alert("Invalid choice.");
        return;
      }
      await api("/api/v1/student-groups/" + groupId + "/join-requests/" + reqs[idx].id + "/approve", { method: "POST" });
      alert("Student approved and added to the group.");
      loadGroupsPage();
      if (typeof refreshDiscordGroupsPanel === "function") refreshDiscordGroupsPanel();
    } catch (e) {
      alert(e.message || "Could not load requests.");
    }
  };

  window.loadGroupsPage = loadGroupsPage;
  window.createStudentGroup = createStudentGroup;
})();
