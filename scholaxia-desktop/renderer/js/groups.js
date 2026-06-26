/**
 * Groups tab — student groups + school groups (teacher-added).
 */
(function () {
  function escHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function loadGroupsPage() {
    var mineEl = document.getElementById("groups-mine-list");
    var schoolEl = document.getElementById("groups-school-list");
    var communityEl = document.getElementById("groups-community-list");
    if (mineEl) mineEl.innerHTML = '<div class="loading">Loading…</div>';
    if (schoolEl) schoolEl.innerHTML = '<div class="loading">Loading…</div>';
    if (communityEl) communityEl.innerHTML = '<div class="loading">Loading…</div>';

    try {
      var mine = await api("/api/v1/student-groups/mine") || [];
      var school = await api("/api/v1/school-groups/student/mine") || [];
      var listed = await api("/api/v1/student-groups/community-listed") || [];

      if (communityEl) {
        if (!listed.length) {
          communityEl.innerHTML = '<p class="host-hint">No groups listed yet. Create a group and tap <strong>List in Community</strong>.</p>';
        } else {
          communityEl.innerHTML = listed.map(function (g) {
            var action = "";
            if (g.is_member) {
              action = g.is_admin
                ? ' <span class="access-code-pill">Admin · Listed</span>'
                : ' <span class="host-hint">Member</span>';
            } else if (g.pending_request) {
              action = '<span class="host-hint">Request pending</span>';
            } else {
              action = '<button type="button" class="btn-sm" onclick="requestJoinGroup(\'' + escHtml(g.id) + '\')">Request to join</button>';
            }
            return (
              '<div class="group-card">' +
              "<strong>" + escHtml(g.name) + "</strong>" +
              "<p>" + escHtml(g.description || "") + " · by " + escHtml(g.creator_name || "Student") + "</p>" +
              action +
              "</div>"
            );
          }).join("");
        }
      }

      if (mineEl) {
        if (!mine.length) {
          mineEl.innerHTML = '<p class="host-hint">You have not joined any student groups yet. Create one below or discover groups in Community.</p>';
        } else {
          mineEl.innerHTML = mine.map(function (g) {
            return (
              '<div class="group-card">' +
              "<strong>" + escHtml(g.name) + "</strong>" +
              (g.is_admin ? ' <span class="access-code-pill">Admin</span>' : "") +
              "<p>" + escHtml(g.description || "") + "</p>" +
              (g.is_admin ? '<button type="button" class="btn-sm" onclick="viewGroupRequests(\'' + escHtml(g.id) + '\')">Pending requests</button>' : "") +
              (g.is_admin && !g.is_community_listed ? '<button type="button" class="btn-sm" onclick="promoteGroupToCommunity(\'' + escHtml(g.id) + '\')">List in Community</button>' : "") +
              (g.is_community_listed ? ' <span class="access-code-pill">In Community</span>' : "") +
              "</div>"
            );
          }).join("");
        }
      }

      if (schoolEl) {
        if (!school.length) {
          schoolEl.innerHTML = '<p class="host-hint">Your school adds you to groups — you cannot join school groups yourself.</p>';
        } else {
          schoolEl.innerHTML = school.map(function (g) {
            return (
              '<div class="group-card group-card-school">' +
              "<strong>" + escHtml(g.school_name) + " — " + escHtml(g.name) + "</strong>" +
              "<p>Teacher: " + escHtml(g.teacher_name) + " · " + g.member_count + " students</p>" +
              "<p class=\"host-hint\">Live class codes for this group appear in Access Code tab.</p>" +
              "</div>"
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
    var n = name ? name.value.trim() : "";
    if (!n) {
      alert("Enter a group name.");
      return;
    }
    try {
      await api("/api/v1/student-groups/", {
        method: "POST",
        body: JSON.stringify({
          name: n,
          description: desc ? desc.value.trim() : "",
          is_public: true,
          is_community_listed: false,
        }),
      });
      if (name) name.value = "";
      if (desc) desc.value = "";
      alert("Group created — you are the admin.");
      loadGroupsPage();
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
      alert((res && res.message) || "Request sent.");
      loadGroupsPage();
    } catch (e) {
      alert(e.message || "Could not send request.");
    }
  };

  window.promoteGroupToCommunity = async function (groupId) {
    if (!confirm("List this group in Community so other students can request to join? You must approve each member.")) return;
    try {
      await api("/api/v1/student-groups/" + groupId + "/community-list", {
        method: "PATCH",
        body: JSON.stringify({ is_community_listed: true }),
      });
      alert("Group is now visible in the Community Groups tab.");
      loadGroupsPage();
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
      var msg = reqs.map(function (r) { return r.name + (r.message ? " — " + r.message : ""); }).join("\n");
      var pick = prompt("Pending requests:\n" + msg + "\n\nPaste request ID to approve (first: " + reqs[0].id + "):", reqs[0].id);
      if (!pick) return;
      await api("/api/v1/student-groups/" + groupId + "/join-requests/" + pick.trim() + "/approve", { method: "POST" });
      alert("Student approved.");
      loadGroupsPage();
    } catch (e) {
      alert(e.message || "Could not load requests.");
    }
  };

  window.loadGroupsPage = loadGroupsPage;
  window.createStudentGroup = createStudentGroup;
})();
