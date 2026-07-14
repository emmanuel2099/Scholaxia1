var currentAdminPage = "dashboard";

document.addEventListener("DOMContentLoaded", function () {
  if (getAdminToken()) {
    showApp();
    loadDashboard();
  } else {
    showAuth();
  }

  document.getElementById("tab-login").addEventListener("click", function () { switchAuthTab("login"); });
  document.getElementById("tab-register").addEventListener("click", function () { switchAuthTab("register"); });
  document.getElementById("form-login").addEventListener("submit", adminLogin);
  document.getElementById("form-register").addEventListener("submit", adminRegister);
});

function showAuth() {
  document.getElementById("auth-screen").classList.remove("hidden");
  document.getElementById("app-screen").classList.add("hidden");
}

function showApp() {
  document.getElementById("auth-screen").classList.add("hidden");
  document.getElementById("app-screen").classList.remove("hidden");
  var u = getAdminUser();
  document.getElementById("admin-user-label").textContent = u.name + " · " + u.email;
}

function switchAuthTab(tab) {
  var isLogin = tab === "login";
  document.getElementById("tab-login").classList.toggle("active", isLogin);
  document.getElementById("tab-register").classList.toggle("active", !isLogin);
  document.getElementById("form-login").classList.toggle("hidden", !isLogin);
  document.getElementById("form-register").classList.toggle("hidden", isLogin);
  document.getElementById("login-error").textContent = "";
  document.getElementById("register-error").textContent = "";
}

async function adminLogin(e) {
  e.preventDefault();
  var email = document.getElementById("login-email").value.trim();
  var password = document.getElementById("login-password").value;
  var err = document.getElementById("login-error");
  var btn = document.getElementById("btn-login");
  err.textContent = "";
  btn.disabled = true;
  try {
    var res = await fetch(API_BASE + "/api/v1/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password }),
      signal: fetchTimeout(45000),
    });
    var data = await res.json();
    if (!res.ok) { err.textContent = formatApiError(data.detail) || "Login failed."; return; }
    if (data.role !== "admin") {
      err.textContent = "This email is a " + data.role + " account, not an admin. Open the Register tab to create an admin account (use a different email if this one is already taken).";
      return;
    }
    saveAdminSession(data, email, data.user && data.user.full_name);
    showApp();
    loadDashboard();
  } catch (ex) {
    err.textContent = "Network error. Check your connection.";
  } finally {
    btn.disabled = false;
  }
}

async function adminRegister(e) {
  e.preventDefault();
  var name = document.getElementById("reg-name").value.trim();
  var email = document.getElementById("reg-email").value.trim();
  var password = document.getElementById("reg-password").value;
  var err = document.getElementById("register-error");
  var btn = document.getElementById("btn-register");
  err.textContent = "";
  btn.disabled = true;
  try {
    var res = await fetch(API_BASE + "/api/v1/admin/register", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password, full_name: name }),
      signal: fetchTimeout(45000),
    });
    var data = await res.json();
    if (!res.ok) { err.textContent = formatApiError(data.detail) || "Registration failed."; return; }
    saveAdminSession(data, email, name);
    showApp();
    loadDashboard();
  } catch (ex) {
    err.textContent = "Network error. Check your connection.";
  } finally {
    btn.disabled = false;
  }
}

function adminLogout() {
  clearAdminSession();
  showAuth();
}

function showAdminPage(page) {
  currentAdminPage = page;
  document.querySelectorAll(".admin-page").forEach(function (p) { p.classList.remove("active"); });
  document.querySelectorAll(".nav-btn").forEach(function (n) { n.classList.remove("active"); });
  document.getElementById("page-" + page).classList.add("active");
  document.querySelector('[data-page="' + page + '"]').classList.add("active");
  if (page === "dashboard") loadDashboard();
  else if (page === "students") loadStudents();
  else if (page === "teachers") loadTeachers();
  else if (page === "kind") loadKind();
  else if (page === "kind-games") loadKindGamesAdmin();
  else if (page === "requests") loadRequests();
  else if (page === "live-subs") loadLiveSubscriptions();
  else if (page === "skills-enroll") loadSkillsEnrollments();
  else if (page === "cbt") { initCbtBuilder(); loadCbt(); }
  else if (page === "library") loadLibraryAdmin();
  else if (page === "internal-exams") loadInternalExamsAdmin();
  else if (page === "recommendations") loadRecommendations();
  else if (page === "student-groups") loadPendingStudentGroups();
  else if (page === "community") loadCommunityPosts();
  else if (page === "marketplace") loadMarketplace();
}

/* ── Dashboard ── */
async function loadDashboard() {
  var el = document.getElementById("stats-grid");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var d = await adminApi("/api/v1/admin/overview");
    if (!d) return;
    var items = [
      { n: d.students, l: "Students" },
      { n: d.students_with_subjects, l: "With subjects set" },
      { n: d.teachers, l: "Teachers" },
      { n: d.kind_learners, l: "Kind (kids)" },
      { n: d.cbt_exams, l: "CBT exams" },
      { n: d.live_classes_now, l: "Live now" },
      { n: d.pending_session_requests, l: "Pending requests" },
    ];
    el.innerHTML = items.map(function (i) {
      return '<div class="stat-card"><div class="num">' + i.n + '</div><div class="lbl">' + i.l + '</div></div>';
    }).join("");
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

/* ── Students ── */
async function loadStudents() {
  var el = document.getElementById("students-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/students?active_only=true");
    if (!rows) return;
    rows = rows.filter(function (s) { return s.is_active; });
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No students yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Name</th><th>Email</th><th>Exam</th><th>Level</th><th>Subjects</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (s) {
        var subs = (s.selected_subjects || []).map(function (x) {
          return '<span class="subj-tag">' + escHtml(x) + '</span>';
        }).join("");
        var exam = (s.exam_type || "—").replace(/^ExamType\./, "");
        return '<tr><td>' + escHtml(s.full_name) + '</td><td>' + escHtml(s.email) + '</td>' +
          '<td>' + escHtml(exam) + '</td><td>' + escHtml(s.education_level || "—") + '</td>' +
          '<td><div class="subj-tags">' + (subs || "—") + '</div></td>' +
          '<td><span class="badge ' + (s.is_active ? "ok" : "muted") + '">' + (s.is_active ? "Active" : "Disabled") + '</span></td>' +
          '<td class="actions">' + (s.is_active ? '<button class="btn-sm danger" onclick="deleteStudent(\'' + s.id + '\')">Remove</button>' : '') + '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function refreshDashboardStats() {
  if (currentAdminPage === "dashboard") {
    await loadDashboard();
  }
}

async function deleteStudent(id) {
  if (!confirm("Delete this student permanently? They will be removed from the list.")) return;
  try {
    await adminApi("/api/v1/admin/students/" + id, { method: "DELETE" });
    loadStudents();
    refreshDashboardStats();
  } catch (e) { alert(e.message); }
}

async function removeAllStudents() {
  if (!confirm("DELETE ALL students permanently? This cannot be undone. Every student email will be removed.")) return;
  try {
    var r = await adminApi("/api/v1/admin/students/remove-all", { method: "POST" });
    alert("Deleted " + (r.removed || 0) + " student(s).");
    loadStudents();
    refreshDashboardStats();
  } catch (e) { alert(e.message); }
}

async function purgeAllUsers() {
  if (!confirm("DELETE ALL student, teacher, and kid accounts?\n\nEvery email will be permanently removed from the database. Admin accounts are kept. This cannot be undone.")) return;
  try {
    var r = await adminApi("/api/v1/admin/users/purge-all", { method: "POST" });
    alert(
      "Purged:\n" +
      "Students: " + (r.students || 0) + "\n" +
      "Teachers: " + (r.teachers || 0) + "\n" +
      "Kids: " + (r.kind || 0) + "\n" +
      "Total: " + (r.total || 0)
    );
    loadStudents();
    loadTeachers();
    refreshDashboardStats();
  } catch (e) { alert(e.message); }
}

/* ── Teachers ── */
async function loadTeachers() {
  var el = document.getElementById("teachers-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/teachers");
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No teachers yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Name</th><th>Email</th><th>Subjects</th><th></th></tr></thead><tbody>' +
      rows.map(function (t) {
        var subs = (t.subjects || []).map(function (x) {
          return '<span class="subj-tag">' + escHtml(x) + '</span>';
        }).join("");
        return '<tr><td>' + escHtml(t.full_name) + '</td><td>' + escHtml(t.email) + '</td>' +
          '<td><div class="subj-tags">' + subs + '</div></td>' +
          '<td class="actions"><button class="btn-sm danger" onclick="deleteTeacher(\'' + t.id + '\')">Remove</button></td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function createTeacher() {
  var err = document.getElementById("teacher-form-error");
  err.textContent = "";
  var subjects = document.getElementById("t-subjects").value.split(",").map(function (s) { return s.trim(); }).filter(Boolean);
  try {
    await adminApi("/api/v1/admin/teachers", {
      method: "POST",
      body: JSON.stringify({
        full_name: document.getElementById("t-name").value.trim(),
        email: document.getElementById("t-email").value.trim(),
        password: document.getElementById("t-password").value,
        subjects: subjects,
      }),
    });
    document.getElementById("t-name").value = "";
    document.getElementById("t-email").value = "";
    document.getElementById("t-password").value = "";
    document.getElementById("t-subjects").value = "";
    loadTeachers();
  } catch (e) {
    err.textContent = e.message;
  }
}

async function deleteTeacher(id) {
  if (!confirm("Remove this teacher? They will not be able to log in.")) return;
  try {
    await adminApi("/api/v1/admin/teachers/" + id, { method: "DELETE" });
    loadTeachers();
  } catch (e) { alert(e.message); }
}

async function removeAllTeachers() {
  if (!confirm("Remove ALL teachers? This disables every teacher account.")) return;
  try {
    var r = await adminApi("/api/v1/admin/teachers/remove-all", { method: "POST" });
    alert("Removed " + (r.removed || 0) + " teacher(s).");
    loadTeachers();
  } catch (e) { alert(e.message); }
}

/* ── Kind ── */
async function loadKind() {
  var el = document.getElementById("kind-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/kind-learners");
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No kind learners yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Name</th><th>Email</th><th>Age</th><th>Grade</th><th>Parent</th><th>Interests</th></tr></thead><tbody>' +
      rows.map(function (k) {
        var subs = (k.favorite_subjects || []).map(function (x) {
          return '<span class="subj-tag">' + escHtml(x) + '</span>';
        }).join("");
        return '<tr><td>' + escHtml(k.full_name) + '</td><td>' + escHtml(k.email) + '</td>' +
          '<td>' + escHtml(k.age_group || "—") + '</td><td>' + escHtml(k.grade_level || "—") + '</td>' +
          '<td>' + escHtml(k.parent_email || "—") + '</td>' +
          '<td><div class="subj-tags">' + (subs || "—") + '</div></td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

/* ── Kids game questions (admin) ── */
var kindGamesCatalog = [];

async function loadKindGamesAdmin() {
  try {
    var data = await adminApi("/api/v1/admin/kind-games/catalog");
    kindGamesCatalog = (data && data.games) || [];
    var opts = kindGamesCatalog.map(function (g) {
      return '<option value="' + escHtml(g.id) + '">' + escHtml(g.title) +
        " (" + (g.admin_questions || 0) + " admin Qs)</option>";
    }).join("");
    document.getElementById("kg-game").innerHTML = opts;
    document.getElementById("kg-filter").innerHTML =
      '<option value="">All games</option>' + opts;
    loadKindGameQuestions();
  } catch (e) {
    document.getElementById("kg-questions").innerHTML =
      '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadKindGameQuestions() {
  var el = document.getElementById("kg-questions");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var gid = document.getElementById("kg-filter").value;
    var url = "/api/v1/admin/kind-games/questions";
    if (gid) url += "?game_id=" + encodeURIComponent(gid);
    var rows = await adminApi(url);
    if (!rows) return;
    if (!rows.length) {
      el.innerHTML = '<div class="empty-state">No admin questions yet. Add some above — kids also keep their 50 built-in questions.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Game</th><th>Prompt</th><th>Options</th><th>Correct</th><th></th></tr></thead><tbody>' +
      rows
        .map(function (q) {
          var opts = (q.options || [])
            .map(function (o, i) {
              return (i === q.correct_index ? "<strong>" : "") +
                escHtml(o) +
                (i === q.correct_index ? "</strong>" : "");
            })
            .join(" · ");
          return (
            "<tr><td>" +
            escHtml(q.game_id) +
            "</td><td>" +
            escHtml((q.prompt || "").slice(0, 120)) +
            "</td><td>" +
            opts +
            "</td><td>" +
            String.fromCharCode(65 + (q.correct_index || 0)) +
            '</td><td class="actions"><button class="btn-sm danger" onclick="deleteKindGameQuestion(\'' +
            q.id +
            "')\">Delete</button></td></tr>"
          );
        })
        .join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function createKindGameQuestion() {
  var msg = document.getElementById("kg-msg");
  var gameId = document.getElementById("kg-game").value;
  var prompt = (document.getElementById("kg-prompt").value || "").trim();
  var opts = [0, 1, 2, 3]
    .map(function (i) {
      return (document.getElementById("kg-opt" + i).value || "").trim();
    })
    .filter(Boolean);
  var correct = parseInt(document.getElementById("kg-correct").value, 10) || 0;
  var speak = (document.getElementById("kg-speak").value || "").trim();
  if (!prompt || opts.length < 2) {
    msg.textContent = "Need a prompt and at least 2 options.";
    return;
  }
  if (correct >= opts.length) correct = 0;
  msg.textContent = "Saving…";
  try {
    await adminApi("/api/v1/admin/kind-games/questions", {
      method: "POST",
      body: JSON.stringify({
        game_id: gameId,
        prompt: prompt,
        options: opts,
        correct_index: correct,
        speak_word: speak || null,
      }),
    });
    document.getElementById("kg-prompt").value = "";
    [0, 1, 2, 3].forEach(function (i) {
      document.getElementById("kg-opt" + i).value = "";
    });
    document.getElementById("kg-speak").value = "";
    msg.textContent = "Question added to " + gameId + ".";
    loadKindGamesAdmin();
  } catch (e) {
    msg.textContent = e.message || "Failed.";
  }
}

async function deleteKindGameQuestion(id) {
  if (!confirm("Remove this question?")) return;
  try {
    await adminApi("/api/v1/admin/kind-games/questions/" + id, { method: "DELETE" });
    loadKindGameQuestions();
  } catch (e) {
    alert(e.message);
  }
}

/* ── Live classes ── */
async function adminHostClass(startNow) {
  var title = document.getElementById("host-title").value.trim();
  var subject = document.getElementById("host-subject").value.trim();
  var err = document.getElementById("host-error");
  err.textContent = "";
  if (!title || !subject) {
    err.textContent = "Enter a title and subject.";
    return;
  }
  if (!getAdminToken()) {
    err.textContent = "Session expired. Please sign in again.";
    return;
  }
  var scheduleBtn = document.querySelector(".host-actions .btn-sm:not(.primary)");
  var liveBtn = document.querySelector(".host-actions .btn-sm.primary");
  if (scheduleBtn) scheduleBtn.disabled = true;
  if (liveBtn) liveBtn.disabled = true;
  err.textContent = "Connecting to server…";
  try {
    await wakeAdminServer();
    var created = await adminApi("/api/v1/admin/live-classes", {
      method: "POST",
      timeout: 120000,
      body: JSON.stringify({
        title: title,
        subject: subject,
        start_now: startNow,
      }),
    });
    if (!created || !created.id) throw new Error("Could not create class.");
    document.getElementById("host-title").value = "";
    document.getElementById("host-subject").value = "";
    err.textContent = "";
    loadLiveClasses();
    if (startNow && created && created.id) {
      if (confirm("Class is live! Open the classroom now?")) {
        adminEnterClassroom(created.id, title, subject);
      }
    } else {
      alert("Class scheduled.");
    }
  } catch (e) {
    err.textContent = e.message;
  } finally {
    if (scheduleBtn) scheduleBtn.disabled = false;
    if (liveBtn) liveBtn.disabled = false;
  }
}

async function adminStartClass(id) {
  try {
    await adminApi("/api/v1/admin/live-classes/" + id + "/start", { method: "POST" });
    loadLiveClasses();
  } catch (e) { alert(e.message); }
}

async function adminEndClass(id) {
  try {
    await adminApi("/api/v1/admin/live-classes/" + id + "/end", { method: "POST" });
    loadLiveClasses();
  } catch (e) { alert(e.message); }
}

async function adminEnterClassroom(classId, title, subject) {
  try {
    var token = await adminApi("/api/v1/live-classes/" + classId + "/token");
    if (!token) return;
    localStorage.setItem("live_session", JSON.stringify({
      class_id: classId,
      classId: classId,
      room_id: token.channel_id,
      channel_id: token.channel_id,
      livekit_token: token.token,
      livekit_url: token.livekit_url,
      identity: token.identity,
      title: title || "Live Class",
      subject: subject || "",
      teacher_name: getAdminUser().name,
      role: "teacher",
    }));
    window.location.href = "classroom.html";
  } catch (e) {
    alert(e.message);
  }
}

async function adminDeleteLiveClass(id) {
  if (!confirm("Delete this class permanently?")) return;
  try {
    await adminApi("/api/v1/admin/live-classes/" + id, { method: "DELETE" });
    loadLiveClasses();
  } catch (e) { alert(e.message); }
}

async function adminRemoveAllLiveClasses() {
  if (!confirm("Remove ALL live classes from the platform? Students will see an empty list until someone hosts a new class.")) return;
  try {
    var res = await adminApi("/api/v1/admin/live-classes/remove-all", { method: "DELETE" });
    loadLiveClasses();
    alert("Removed " + (res && res.removed != null ? res.removed : 0) + " class(es).");
  } catch (e) { alert(e.message); }
}

async function loadLiveClasses() {
  var el = document.getElementById("live-table");
  var status = document.getElementById("live-filter").value;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var url = "/api/v1/live-classes/?limit=50";
    if (status) url += "&status=" + status;
    var rows = await adminApi(url);
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No live classes. Use "Host a live class" above to create one.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Teacher</th><th>Start</th><th>Status</th><th>Actions</th></tr></thead><tbody>' +
      rows.map(function (c) {
        var badge = c.is_live ? '<span class="badge live">LIVE</span>' : '<span class="badge muted">Scheduled</span>';
        var actions = '<div class="actions">';
        if (!c.is_live) {
          actions += '<button class="btn-sm" onclick="adminStartClass(\'' + c.id + '\')">Start</button>';
        } else {
          actions += '<button class="btn-sm secondary" onclick="adminEndClass(\'' + c.id + '\')">End</button>';
          actions += '<button class="btn-sm" onclick="adminEnterClassroom(\'' + c.id + '\', \'' + escHtml(c.title).replace(/'/g, "\\'") + '\', \'' + escHtml(c.subject).replace(/'/g, "\\'") + '\')">Enter</button>';
        }
        actions += '<button class="btn-sm secondary" onclick="adminDeleteLiveClass(\'' + c.id + '\')">Delete</button></div>';
        return '<tr><td>' + escHtml(c.title) + '</td><td>' + escHtml(c.subject) + '</td>' +
          '<td>' + escHtml(c.teacher_name) + '</td><td>' + fmtDate(c.start_time) + '</td><td>' + badge + '</td>' +
          '<td>' + actions + '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

/* ── Session requests ── */
async function loadRequests() {
  var el = document.getElementById("requests-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/live-classes/requests?limit=50");
    var teachers = await adminApi("/api/v1/admin/teachers") || [];
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No session requests.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Student</th><th>Subject</th><th>Topic</th><th>Status</th><th>Teacher</th><th></th></tr></thead><tbody>' +
      rows.map(function (r) {
        var teacherCell = "—";
        if (r.assigned_teacher_name) {
          teacherCell = escHtml(r.assigned_teacher_name);
        } else if (r.status === "pending") {
          var opts = teachers.map(function (t) {
            return '<option value="' + escHtml(t.id) + '">' + escHtml(t.full_name) + '</option>';
          }).join("");
          teacherCell = '<select class="assign-teacher-select" id="assign-teach-' + escHtml(r.id) + '"><option value="">Choose teacher…</option>' + opts + '</select>';
        }
        var actions = "";
        if (r.status === "pending") {
          actions =
            '<button class="btn-sm" onclick="assignRequest(\'' + r.id + '\')">Assign</button> ' +
            '<button class="btn-sm secondary" onclick="updateRequest(\'' + r.id + '\',\'dismissed\')">Dismiss</button>';
        } else if (r.assigned_teacher_name) {
          actions = '<span class="badge ok">Assigned</span>';
        }
        return '<tr><td>' + escHtml(r.student_name || r.student_id) + '</td>' +
          '<td>' + escHtml(r.subject) + '</td><td>' + escHtml(r.topic || r.message || "—") + '</td>' +
          '<td><span class="badge muted">' + escHtml(r.status) + '</span></td>' +
          '<td>' + teacherCell + '</td>' +
          '<td class="actions">' + actions + '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function assignRequest(id) {
  var sel = document.getElementById("assign-teach-" + id);
  if (!sel || !sel.value) { alert("Choose a teacher first."); return; }
  try {
    await adminApi("/api/v1/live-classes/requests/" + id + "/assign", {
      method: "POST",
      body: JSON.stringify({ teacher_id: sel.value }),
    });
    loadRequests();
    refreshDashboardStats();
  } catch (e) { alert(e.message); }
}

async function loadLiveSubscriptions() {
  var el = document.getElementById("live-subs-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  await Promise.all([fillSubStudents(), fillSubPlans()]);
  try {
    var rows = await adminApi("/api/v1/admin/live-subscriptions");
    if (!rows) return;
    if (!rows.length) {
      el.innerHTML = '<div class="empty-state">No live subscriptions yet. Grant one above.</div>';
      return;
    }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Student</th><th>Email</th><th>Plan</th><th>Paid</th><th>Sessions</th><th>Expires</th><th>Last payment</th><th></th></tr></thead><tbody>' +
      rows.map(function (r) {
        var exp = r.expires_at ? formatAdminDate(r.expires_at) : "—";
        var paid = r.last_payment_at
          ? formatAdminDate(r.last_payment_at) + (r.last_payment_amount != null ? " · ₦" + r.last_payment_amount : "")
          : "—";
        var sess = r.sessions_left + " left";
        if (r.sessions_total) sess += " / " + r.sessions_total;
        sess += " (used " + r.sessions_used + ")";
        return '<tr><td>' + escHtml(r.full_name) + '</td><td>' + escHtml(r.email) + '</td>' +
          '<td>' + escHtml(r.plan_name || r.plan_id || "—") + '</td>' +
          '<td><span class="badge ' + (r.paid ? "ok" : "muted") + '">' + (r.paid ? "Yes" : "No") + '</span></td>' +
          '<td>' + escHtml(sess) + '</td>' +
          '<td>' + escHtml(exp) + '</td><td>' + escHtml(paid) + '</td>' +
          '<td class="actions">' +
          '<button class="btn-sm" onclick="editLiveSubscription(\'' + r.id + '\',\'' +
            escHtml(r.plan_id || "") + '\',' + (r.sessions_used || 0) + ')">Edit</button> ' +
          '<button class="btn-sm danger" onclick="revokeLiveSubscription(\'' + r.id + '\')">Revoke</button>' +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function fillSubStudents() {
  var sel = document.getElementById("sub-student");
  if (!sel || sel.getAttribute("data-loaded") === "1") return;
  try {
    var rows = await adminApi("/api/v1/admin/students?active_only=true") || [];
    sel.innerHTML = '<option value="">Select student</option>' + rows.map(function (s) {
      return '<option value="' + escHtml(s.id) + '">' +
        escHtml((s.full_name || s.email) + " · " + s.email) + "</option>";
    }).join("");
    sel.setAttribute("data-loaded", "1");
  } catch (e) {
    sel.innerHTML = '<option value="">' + escHtml(e.message) + "</option>";
  }
}

async function fillSubPlans() {
  var sel = document.getElementById("sub-plan");
  if (!sel || sel.getAttribute("data-loaded") === "1") return;
  try {
    var data = await adminApi("/api/v1/admin/live-plans");
    var plans = (data && data.plans) || [];
    sel.innerHTML = '<option value="">Select plan</option>' + plans.map(function (p) {
      return '<option value="' + escHtml(p.id) + '">' +
        escHtml((p.category ? p.category + " · " : "") + p.name + " · ₦" + p.price + " · " + p.sessions + " sessions") +
        "</option>";
    }).join("");
    sel.setAttribute("data-loaded", "1");
  } catch (e) {
    sel.innerHTML = '<option value="">' + escHtml(e.message) + "</option>";
  }
}

function editLiveSubscription(studentId, planId, sessionsUsed) {
  var s = document.getElementById("sub-student");
  var p = document.getElementById("sub-plan");
  var u = document.getElementById("sub-sessions-used");
  if (s) s.value = studentId;
  if (p && planId) p.value = planId;
  if (u) u.value = String(sessionsUsed || 0);
  window.scrollTo({ top: 0, behavior: "smooth" });
}

async function grantLiveSubscription() {
  var msg = document.getElementById("sub-form-msg");
  var studentId = document.getElementById("sub-student").value;
  var planId = document.getElementById("sub-plan").value;
  var sessionsUsed = parseInt(document.getElementById("sub-sessions-used").value, 10) || 0;
  var expiresRaw = document.getElementById("sub-expires").value;
  if (!studentId || !planId) {
    msg.textContent = "Pick a student and a plan.";
    return;
  }
  msg.textContent = "Saving…";
  var body = { grant: true, plan_id: planId, sessions_used: sessionsUsed };
  if (expiresRaw) body.expires_at = new Date(expiresRaw).toISOString();
  try {
    await adminApi("/api/v1/admin/live-subscriptions/" + studentId, {
      method: "PATCH",
      body: JSON.stringify(body),
    });
    msg.textContent = "Subscription saved.";
    loadLiveSubscriptions();
  } catch (e) {
    msg.textContent = e.message || "Could not save subscription.";
  }
}

async function revokeLiveSubscription(studentId) {
  if (!confirm("Revoke this student's live subscription?")) return;
  try {
    await adminApi("/api/v1/admin/live-subscriptions/" + studentId, {
      method: "PATCH",
      body: JSON.stringify({ grant: false }),
    });
    loadLiveSubscriptions();
  } catch (e) {
    alert(e.message);
  }
}

async function loadSkillsEnrollments() {
  var el = document.getElementById("skills-enroll-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/skills-enrollments");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No skills enrollments yet.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Student</th><th>Email</th><th>Skill</th><th>Program fee</th><th>Amount paid</th><th>Status</th><th>When</th></tr></thead><tbody>' +
      rows.map(function (r) {
        var badge = r.status === "success" ? "ok" : (r.status === "pending" ? "school" : "muted");
        return "<tr><td>" + escHtml(r.student_name) + "</td><td>" + escHtml(r.email) +
          "</td><td>" + escHtml(r.skill_title) + "</td><td>" +
          (r.skill_fee != null ? "₦" + r.skill_fee : "—") + "</td><td>" +
          (r.amount_paid != null ? "₦" + r.amount_paid : "—") +
          '</td><td><span class="badge ' + badge + '">' + escHtml(r.status || "—") +
          "</span></td><td>" + escHtml(formatAdminDate(r.created_at)) + "</td></tr>";
      }).join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

function formatAdminDate(iso) {
  if (!iso) return "—";
  try {
    return new Date(iso).toLocaleString(undefined, { dateStyle: "medium", timeStyle: "short" });
  } catch (e) {
    return String(iso);
  }
}

async function updateRequest(id, status) {
  try {
    await adminApi("/api/v1/live-classes/requests/" + id, {
      method: "PATCH",
      body: JSON.stringify({ status: status }),
    });
    loadRequests();
  } catch (e) { alert(e.message); }
}

/* ── CBT Exam Builder ── */
var cbtMode = "practice";
var cbtQuestions = [];

function emptyQuestion() {
  return {
    question_text: "",
    option_a: "", option_b: "", option_c: "", option_d: "",
    correct_option: "A",
    topic: "",
    explanation: "",
    image_url: "",
    image_preview: "",
    uploading: false,
  };
}

function fillCbtYearSelects() {
  var years = [];
  for (var y = 2026; y >= 1995; y--) years.push(String(y));
  ["cbt-year", "cbt-import-year"].forEach(function (id) {
    var el = document.getElementById(id);
    if (!el || el.options.length > 1) return;
    el.innerHTML = '<option value="">Select year</option>' +
      years.map(function (yr) {
        return '<option value="' + yr + '">' + yr + "</option>";
      }).join("");
  });
}

function initCbtBuilder() {
  fillCbtYearSelects();
  if (!cbtQuestions.length) cbtQuestions = [emptyQuestion()];
  switchCbtMode(cbtMode, true);
  renderCbtQuestions();
}

function switchCbtMode(mode, skipReset) {
  cbtMode = mode;
  var isPractice = mode === "practice";
  document.getElementById("cbt-tab-practice").classList.toggle("active", isPractice);
  document.getElementById("cbt-tab-school").classList.toggle("active", !isPractice);
  document.getElementById("cbt-tab-school").classList.toggle("school-tab", !isPractice);
  document.getElementById("school-fields").classList.toggle("hidden", isPractice);
  document.getElementById("cbt-form-title").textContent = isPractice ? "New Practice CBT" : "New School Exam";
  var hint = document.getElementById("cbt-mode-hint");
  hint.className = "cbt-hint " + (isPractice ? "practice-hint" : "school-hint");
  hint.textContent = isPractice
    ? "Practice exams for JAMB / WAEC / NECO, or Primary 6 Common Entrance for the Kids app."
    : "Scheduled school exam — set open/close times. Camera proctoring is recommended.";
  document.getElementById("btn-create-cbt").textContent = isPractice ? "Create practice exam" : "Create school exam";
  if (!skipReset) {
    cbtQuestions = [emptyQuestion()];
    renderCbtQuestions();
  }
}

function addCbtQuestion() {
  cbtQuestions.push(emptyQuestion());
  renderCbtQuestions();
  var list = document.getElementById("cbt-questions-list");
  var cards = list.querySelectorAll(".q-card");
  if (cards.length) cards[cards.length - 1].scrollIntoView({ behavior: "smooth", block: "nearest" });
}

function removeCbtQuestion(idx) {
  if (cbtQuestions.length <= 1) { alert("An exam needs at least one question."); return; }
  cbtQuestions.splice(idx, 1);
  renderCbtQuestions();
}

function syncQuestionFromDom(idx) {
  var q = cbtQuestions[idx];
  var prefix = "q-" + idx + "-";
  var textEl = document.getElementById(prefix + "text");
  if (!textEl) return;
  q.question_text = textEl.value;
  q.option_a = document.getElementById(prefix + "a").value;
  q.option_b = document.getElementById(prefix + "b").value;
  q.option_c = document.getElementById(prefix + "c").value;
  q.option_d = document.getElementById(prefix + "d").value;
  var correct = document.querySelector('input[name="' + prefix + 'correct"]:checked');
  q.correct_option = correct ? correct.value : "A";
  q.topic = document.getElementById(prefix + "topic").value;
  q.explanation = document.getElementById(prefix + "explain").value;
}

function syncAllQuestions() {
  for (var i = 0; i < cbtQuestions.length; i++) syncQuestionFromDom(i);
}

function renderCbtQuestions() {
  var list = document.getElementById("cbt-questions-list");
  list.innerHTML = cbtQuestions.map(function (q, idx) {
    var prefix = "q-" + idx + "-";
    var opts = ["A", "B", "C", "D"].map(function (letter) {
      var key = "option_" + letter.toLowerCase();
      var val = escHtml(q[key] || "");
      var checked = q.correct_option === letter ? " checked" : "";
      return '<div class="q-opt-row">' +
        '<input type="radio" name="' + prefix + 'correct" value="' + letter + '"' + checked + ' title="Mark as correct" />' +
        '<input type="text" id="' + prefix + letter.toLowerCase() + '" placeholder="Option ' + letter + '" value="' + val + '" />' +
        '</div>';
    }).join("");
    var imgBlock = q.image_url || q.image_preview
      ? '<img src="' + escHtml(q.image_preview || q.image_url) + '" alt="Diagram" />'
      : "";
    var uploading = q.uploading ? '<div class="uploading">Uploading diagram…</div>' : "";
    return '<div class="q-card" data-idx="' + idx + '">' +
      '<div class="q-card-head"><strong>Question ' + (idx + 1) + '</strong>' +
      (cbtQuestions.length > 1 ? '<button type="button" class="q-remove" onclick="removeCbtQuestion(' + idx + ')">Remove</button>' : '') +
      '</div>' +
      '<textarea id="' + prefix + 'text" placeholder="Type the question here…">' + escHtml(q.question_text) + '</textarea>' +
      '<div class="q-diagram">' +
      '<label><span>Diagram / figure (optional) — JPEG, PNG, WebP</span>' +
      '<input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onchange="onQuestionImage(' + idx + ', this)" />' +
      uploading + imgBlock + '</label></div>' +
      '<div class="q-options">' + opts + '</div>' +
      '<p class="cbt-hint small">Click the circle next to the correct answer.</p>' +
      '<div class="q-meta">' +
      '<input type="text" id="' + prefix + 'topic" placeholder="Topic (optional)" value="' + escHtml(q.topic) + '" />' +
      '<input type="text" id="' + prefix + 'explain" placeholder="Explanation (optional)" value="' + escHtml(q.explanation) + '" />' +
      '</div></div>';
  }).join("");
}

async function onQuestionImage(idx, input) {
  var file = input.files && input.files[0];
  if (!file) return;
  if (file.size > 5 * 1024 * 1024) { alert("Image must be under 5MB."); input.value = ""; return; }
  syncAllQuestions();
  cbtQuestions[idx].uploading = true;
  cbtQuestions[idx].image_preview = URL.createObjectURL(file);
  renderCbtQuestions();
  try {
    var url = await uploadCbtImage(file);
    syncAllQuestions();
    cbtQuestions[idx].image_url = url;
    cbtQuestions[idx].image_preview = url;
    cbtQuestions[idx].uploading = false;
    renderCbtQuestions();
  } catch (e) {
    syncAllQuestions();
    cbtQuestions[idx].uploading = false;
    cbtQuestions[idx].image_url = "";
    cbtQuestions[idx].image_preview = "";
    renderCbtQuestions();
    alert("Diagram upload failed: " + e.message);
  }
}

async function loadCbt() {
  var el = document.getElementById("cbt-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/cbt/exams");
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No CBT exams. Create one or click Seed Exams.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Year</th><th>Type</th><th>Questions</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (e) {
        var typeBadge = e.is_school_exam
          ? '<span class="badge school">School</span>'
          : '<span class="badge ok">' + escHtml(e.exam_type) + '</span>';
        var pub = e.is_published ? '<span class="badge ok">Published</span>' : '<span class="badge muted">Draft</span>';
        return '<tr><td>' + escHtml(e.title) + '</td><td>' + escHtml(e.subject) + '</td>' +
          '<td>' + (e.year || "—") + '</td>' +
          '<td>' + typeBadge + '</td><td>' + e.total_questions + '</td><td>' + pub + '</td>' +
          '<td class="actions">' +
          '<button class="btn-sm" onclick="toggleCbtPublish(\'' + e.id + '\')">Toggle publish</button>' +
          '<button class="btn-sm danger" onclick="deleteCbt(\'' + e.id + '\')">Delete</button>' +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function createCbt() {
  var err = document.getElementById("cbt-form-error");
  var btn = document.getElementById("btn-create-cbt");
  err.textContent = "";
  syncAllQuestions();

  var title = document.getElementById("cbt-title").value.trim();
  var subject = document.getElementById("cbt-subject").value.trim();
  var yearRaw = document.getElementById("cbt-year").value.trim();
  if (!title) {
    err.textContent = "Enter an exam title.";
    return;
  }
  if (!subject) {
    err.textContent = "Pick a subject.";
    return;
  }
  if (!yearRaw) {
    err.textContent = "Pick the exam year.";
    return;
  }
  var year = parseInt(yearRaw, 10);

  var isSchool = cbtMode === "school";
  if (isSchool) {
    if (!document.getElementById("cbt-start").value || !document.getElementById("cbt-end").value) {
      err.textContent = "School exams need an open and close date/time.";
      return;
    }
  }

  var questions = [];
  for (var i = 0; i < cbtQuestions.length; i++) {
    var q = cbtQuestions[i];
    if (!q.question_text.trim()) {
      err.textContent = "Question " + (i + 1) + " is empty.";
      return;
    }
    if (!q.option_a.trim() || !q.option_b.trim() || !q.option_c.trim() || !q.option_d.trim()) {
      err.textContent = "Fill in all four options for question " + (i + 1) + ".";
      return;
    }
    if (q.uploading) {
      err.textContent = "Wait for the diagram on question " + (i + 1) + " to finish uploading.";
      return;
    }
    var item = {
      question_text: q.question_text.trim(),
      option_a: q.option_a.trim(),
      option_b: q.option_b.trim(),
      option_c: q.option_c.trim(),
      option_d: q.option_d.trim(),
      correct_option: q.correct_option,
    };
    if (q.topic.trim()) item.topic = q.topic.trim();
    if (q.explanation.trim()) item.explanation = q.explanation.trim();
    if (q.image_url) item.image_url = q.image_url;
    questions.push(item);
  }

  var body = {
    title: title,
    subject: subject,
    year: year,
    exam_type: document.getElementById("cbt-type").value,
    duration_minutes: parseInt(document.getElementById("cbt-duration").value, 10) || 30,
    is_school_exam: isSchool,
    camera_required: isSchool && document.getElementById("cbt-camera").checked,
    block_minimize: isSchool && document.getElementById("cbt-block-min").checked,
    is_published: document.getElementById("cbt-publish").checked,
    questions: questions,
  };

  if (isSchool) {
    body.scheduled_start = new Date(document.getElementById("cbt-start").value).toISOString();
    body.scheduled_end = new Date(document.getElementById("cbt-end").value).toISOString();
  }

  btn.disabled = true;
  btn.textContent = "Creating…";
  try {
    await adminApi("/api/v1/admin/cbt/exams", { method: "POST", body: JSON.stringify(body) });
    document.getElementById("cbt-title").value = "";
    document.getElementById("cbt-subject").value = "";
    document.getElementById("cbt-year").value = "";
    document.getElementById("cbt-start").value = "";
    document.getElementById("cbt-end").value = "";
    cbtQuestions = [emptyQuestion()];
    renderCbtQuestions();
    err.textContent = "";
    alert(isSchool ? "School exam created!" : "Practice CBT created!");
    loadCbt();
  } catch (e) {
    err.textContent = e.message;
  } finally {
    btn.disabled = false;
    btn.textContent = isSchool ? "Create school exam" : "Create practice exam";
  }
}

async function toggleCbtPublish(id) {
  try {
    await adminApi("/api/v1/admin/cbt/exams/" + id + "/publish", { method: "PATCH" });
    loadCbt();
  } catch (e) { alert(e.message); }
}

async function deleteCbt(id) {
  if (!confirm("Delete this exam permanently?")) return;
  try {
    await adminApi("/api/v1/admin/cbt/exams/" + id, { method: "DELETE" });
    loadCbt();
  } catch (e) { alert(e.message); }
}

async function seedCbt() {
  if (!confirm("Seed WAEC, NECO & JAMB practice exams?")) return;
  try {
    var r = await adminApi("/api/v1/admin/seed-cbt", { method: "POST" });
    alert("Created " + (r.count || 0) + " exam(s).");
    loadCbt();
  } catch (e) { alert(e.message); }
}

async function importCbtFile() {
  var err = document.getElementById("cbt-import-error");
  var ok = document.getElementById("cbt-import-success");
  var btn = document.getElementById("btn-import-cbt");
  var input = document.getElementById("cbt-import-file");
  err.textContent = "";
  ok.textContent = "";

  if (!input || !input.files || !input.files[0]) {
    err.textContent = "Choose a .json or .csv file first.";
    return;
  }

  var file = input.files[0];
  var fields = {
    title: document.getElementById("cbt-import-title").value.trim(),
    subject: document.getElementById("cbt-import-subject").value.trim(),
    year: document.getElementById("cbt-import-year").value.trim(),
    exam_type: document.getElementById("cbt-import-type").value,
    duration_minutes: parseInt(document.getElementById("cbt-import-duration").value, 10) || 60,
    is_published: document.getElementById("cbt-import-publish").checked,
    skip_duplicates: document.getElementById("cbt-import-skip-dup").checked,
  };

  if (!fields.subject) {
    err.textContent = "Pick a subject so students can find this exam.";
    return;
  }
  if (!fields.year) {
    err.textContent = "Pick the exam year so it shows under the right year filter.";
    return;
  }
  if (!fields.title) {
    fields.title = fields.exam_type + " " + fields.subject + " " + fields.year;
  }

  btn.disabled = true;
  btn.textContent = "Uploading…";
  try {
    var r = await uploadCbtExamFile(file, fields);
    if (!r) return;
    var lines = [];
    if (r.created_count) {
      lines.push("Created " + r.created_count + " exam(s) for " + fields.subject + " " + fields.year + ":");
      (r.created || []).forEach(function (e) {
        lines.push("• " + e.title + " (" + e.total_questions + " questions)");
      });
    }
    if (r.skipped_count) {
      lines.push("Skipped " + r.skipped_count + " duplicate title(s).");
    }
    ok.textContent = lines.join(" ");
    input.value = "";
    loadCbt();
  } catch (e) {
    err.textContent = e.message;
  } finally {
    btn.disabled = false;
    btn.textContent = "Upload & create exam(s)";
  }
}

async function downloadCbtTemplate() {
  try {
    await downloadCbtImportTemplate();
  } catch (e) {
    alert(e.message);
  }
}

/* ── Recommendations ── */
async function loadRecommendations() {
  var el = document.getElementById("rec-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/recommendations/admin");
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No recommendations yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Description</th><th>Target</th><th>Active</th><th></th></tr></thead><tbody>' +
      rows.map(function (r) {
        var desc = (r.description || "").slice(0, 80) + ((r.description || "").length > 80 ? "…" : "");
        return '<tr><td><strong>' + escHtml(r.title) + '</strong>' +
          (r.author ? '<br><span style="color:#6b8f75;font-size:.75rem">' + escHtml(r.author) + '</span>' : '') + '</td>' +
          '<td>' + escHtml(r.subject || "—") + '</td>' +
          '<td>' + escHtml(desc || "—") + '</td>' +
          '<td>' + escHtml(r.target) + '</td>' +
          '<td><span class="badge ' + (r.is_active ? "ok" : "muted") + '">' + (r.is_active ? "Yes" : "No") + '</span></td>' +
          '<td class="actions">' +
          '<button class="btn-sm danger" onclick="deleteRec(\'' + r.id + '\')">Delete</button>' +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function createRecommendation() {
  var err = document.getElementById("rec-form-error");
  err.textContent = "";
  var title = document.getElementById("rec-title").value.trim();
  var desc = document.getElementById("rec-desc").value.trim();
  if (!title) { err.textContent = "Enter a title."; return; }
  if (!desc) { err.textContent = "Enter a short description for students."; return; }
  var exam = document.getElementById("rec-exam").value;
  try {
    await adminApi("/api/v1/recommendations", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        author: document.getElementById("rec-author").value.trim() || null,
        subject: document.getElementById("rec-subject").value.trim() || null,
        description: desc,
        external_url: document.getElementById("rec-url").value.trim() || null,
        target: document.getElementById("rec-target").value,
        exam_type: exam || null,
      }),
    });
    document.getElementById("rec-title").value = "";
    document.getElementById("rec-author").value = "";
    document.getElementById("rec-subject").value = "";
    document.getElementById("rec-desc").value = "";
    document.getElementById("rec-url").value = "";
    loadRecommendations();
  } catch (e) { err.textContent = e.message; }
}

async function deleteRec(id) {
  if (!confirm("Delete this recommendation?")) return;
  try {
    await adminApi("/api/v1/recommendations/" + id, { method: "DELETE" });
    loadRecommendations();
  } catch (e) { alert(e.message); }
}

async function removeAllRecommendations() {
  if (!confirm("Remove ALL recommendations from the student feed?")) return;
  try {
    var rows = await adminApi("/api/v1/recommendations/admin");
    if (!rows || !rows.length) { alert("No recommendations to remove."); return; }
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].is_active) {
        await adminApi("/api/v1/recommendations/" + rows[i].id, { method: "DELETE" });
      }
    }
    loadRecommendations();
    alert("All recommendations removed.");
  } catch (e) { alert(e.message); }
}

/* ── Student group approval ── */
async function loadPendingStudentGroups() {
  var el = document.getElementById("student-groups-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/student-groups/pending");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No groups waiting for approval.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Group</th><th>Creator</th><th>Members</th><th>Listed?</th><th>Date</th><th></th></tr></thead><tbody>' +
      rows.map(function (g) {
        return (
          '<tr><td><strong>' + escHtml(g.name) + '</strong><br><span style="font-size:.8rem;color:#8aa896">' +
          escHtml(g.description || "") + '</span></td>' +
          '<td>' + escHtml(g.creator_name) + '<br><span style="font-size:.75rem;color:#6b8f75">' + escHtml(g.creator_email) + '</span></td>' +
          '<td>' + (g.member_count || 0) + '</td>' +
          '<td>' + (g.is_community_listed ? "Yes" : "No") + '</td>' +
          '<td>' + fmtDate(g.created_at) + '</td>' +
          '<td class="actions">' +
          '<button class="btn-sm primary" onclick="approveStudentGroup(\'' + g.id + '\')">Approve</button> ' +
          '<button class="btn-sm danger" onclick="rejectStudentGroup(\'' + g.id + '\')">Reject</button>' +
          '</td></tr>'
        );
      }).join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function approveStudentGroup(id) {
  if (!confirm("Approve this group? Students can chat once approved.")) return;
  try {
    var res = await adminApi("/api/v1/admin/student-groups/" + id + "/approve", { method: "POST" });
    alert((res && res.message) || "Group approved.");
    loadPendingStudentGroups();
  } catch (e) {
    alert(e.message);
  }
}

async function rejectStudentGroup(id) {
  if (!confirm("Reject this group? It will stay inactive.")) return;
  try {
    var res = await adminApi("/api/v1/admin/student-groups/" + id + "/reject", { method: "POST" });
    alert((res && res.message) || "Group rejected.");
    loadPendingStudentGroups();
  } catch (e) {
    alert(e.message);
  }
}

/* ── Community moderation ── */
var communityChannelsLoaded = false;

async function loadCommunityPosts() {
  var el = document.getElementById("community-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    if (!communityChannelsLoaded) {
      var channels = await adminApi("/api/v1/community/channels");
      var sel = document.getElementById("community-channel-filter");
      if (channels && channels.length) {
        sel.innerHTML = '<option value="">All channels</option>' +
          channels.map(function (c) {
            return '<option value="' + c.id + '">' + escHtml(c.name) + '</option>';
          }).join("");
      }
      communityChannelsLoaded = true;
    }
    var ch = document.getElementById("community-channel-filter").value;
    var url = "/api/v1/admin/community/posts?limit=50";
    if (ch) url += "&channel_id=" + ch;
    var rows = await adminApi(url);
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No community posts yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Student</th><th>Channel</th><th>Post</th><th>Date</th><th></th></tr></thead><tbody>' +
      rows.map(function (p) {
        var content = escHtml((p.content || "").slice(0, 120)) + ((p.content || "").length > 120 ? "…" : "");
        var media = p.media_url ? '<br><a href="' + escHtml(p.media_url) + '" target="_blank" style="color:#7dd3a0;font-size:.75rem">View attachment</a>' : "";
        return '<tr><td>' + escHtml(p.author_name) + '<br><span style="font-size:.75rem;color:#6b8f75">' + escHtml(p.author_email) + '</span></td>' +
          '<td>' + escHtml(p.channel_name) + '</td>' +
          '<td>' + content + media + '</td>' +
          '<td>' + fmtDate(p.created_at) + '</td>' +
          '<td class="actions"><button class="btn-sm danger" onclick="deleteCommunityPost(\'' + p.id + '\')">Delete</button></td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function deleteCommunityPost(id) {
  if (!confirm("Delete this post from the community?")) return;
  try {
    await adminApi("/api/v1/admin/community/posts/" + id, { method: "DELETE" });
    loadCommunityPosts();
  } catch (e) { alert(e.message); }
}

/* ── Marketplace ── */
async function loadMarketplace() {
  await Promise.all([loadMarketplaceProducts(), loadMarketplaceBookings()]);
}

async function loadMarketplaceProducts() {
  var el = document.getElementById("marketplace-products");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/marketplace/products");
    if (!rows) return;
    if (!rows.length) {
      el.innerHTML = '<div class="empty-state">No products yet. Add one above.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th></th><th>Title</th><th>Category</th><th>Price</th><th>Available</th><th></th></tr></thead><tbody>' +
      rows
        .map(function (p) {
          var thumb = p.image_url
            ? '<img class="mp-image-preview" src="' +
              escHtml(p.image_url) +
              '" alt="" />'
            : '<span class="cbt-hint small">No image</span>';
          return (
            "<tr><td>" +
            thumb +
            "</td><td>" +
            escHtml(p.title) +
            "</td><td>" +
            escHtml(p.category) +
            "</td><td>₦" +
            Number(p.price || 0).toLocaleString() +
            "</td><td>" +
            (p.is_available ? "Yes" : "No") +
            '</td><td class="actions"><button class="btn-sm danger" onclick="deleteMarketplaceProduct(\'' +
            p.id +
            "')\">Remove</button></td></tr>"
          );
        })
        .join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadMarketplaceBookings() {
  var el = document.getElementById("marketplace-bookings");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/marketplace/bookings");
    if (!rows) return;
    if (!rows.length) {
      el.innerHTML = '<div class="empty-state">No bookings yet.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Product</th><th>Student</th><th>WhatsApp</th><th>Phone</th><th>Email</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows
        .map(function (b) {
          var wa = (b.whatsapp || "").replace(/\D/g, "");
          var waLink = wa
            ? '<a href="https://wa.me/' +
              escHtml(wa) +
              '" target="_blank" style="color:#7dd3a0">' +
              escHtml(b.whatsapp) +
              "</a>"
            : escHtml(b.whatsapp || "—");
          var contactedBtn =
            b.status === "pending"
              ? '<button class="btn-sm" onclick="markMarketplaceContacted(\'' +
                b.id +
                "')\">Mark contacted</button>"
              : "";
          return (
            "<tr><td>" +
            escHtml(b.product_title || "—") +
            "<br><span style=\"font-size:.75rem;color:#6b8f75\">₦" +
            Number(b.product_price || 0).toLocaleString() +
            "</span></td><td>" +
            escHtml(b.full_name) +
            "</td><td>" +
            waLink +
            "</td><td>" +
            escHtml(b.phone || "—") +
            "</td><td>" +
            escHtml(b.email || "—") +
            "</td><td>" +
            escHtml(b.status || "pending") +
            '</td><td class="actions">' +
            contactedBtn +
            "</td></tr>"
          );
        })
        .join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

function previewMarketplaceImage(input) {
  var img = document.getElementById("mp-image-preview");
  if (!img) return;
  if (img._blobUrl) {
    try {
      URL.revokeObjectURL(img._blobUrl);
    } catch (_) {}
    img._blobUrl = null;
  }
  if (!input.files || !input.files[0]) {
    var urlField = document.getElementById("mp-image");
    var url = urlField && (urlField.value || "").trim();
    if (url) {
      previewMarketplaceImageUrl(url);
      return;
    }
    img.classList.add("hidden");
    img.removeAttribute("src");
    return;
  }
  img._blobUrl = URL.createObjectURL(input.files[0]);
  img.src = img._blobUrl;
  img.classList.remove("hidden");
}

function previewMarketplaceImageUrl(url) {
  var img = document.getElementById("mp-image-preview");
  if (!img) return;
  var fileInput = document.getElementById("mp-image-file");
  if (fileInput && fileInput.files && fileInput.files[0]) return;
  if (img._blobUrl) {
    try {
      URL.revokeObjectURL(img._blobUrl);
    } catch (_) {}
    img._blobUrl = null;
  }
  url = (url || "").trim();
  if (!url) {
    img.classList.add("hidden");
    img.removeAttribute("src");
    return;
  }
  img.src = url;
  img.classList.remove("hidden");
}

async function createMarketplaceProduct() {
  var msg = document.getElementById("mp-product-msg");
  var title = (document.getElementById("mp-title").value || "").trim();
  var category = document.getElementById("mp-category").value;
  var price = parseFloat(document.getElementById("mp-price").value || "0");
  var image = (document.getElementById("mp-image").value || "").trim();
  var desc = (document.getElementById("mp-desc").value || "").trim();
  var fileInput = document.getElementById("mp-image-file");
  if (!title) {
    msg.textContent = "Title is required.";
    return;
  }
  var hasFile = fileInput && fileInput.files && fileInput.files[0];
  if (!hasFile && !image) {
    msg.textContent = "Add a product image (file or URL).";
    return;
  }
  msg.textContent = "Saving…";
  try {
    if (hasFile) {
      msg.textContent = "Uploading image…";
      var up = await uploadMarketplaceImage(fileInput.files[0]);
      if (!up) return;
      image = up.image_url || image;
    }
    if (!image) {
      msg.textContent = "Image upload failed — try again or paste a URL.";
      return;
    }
    await adminApi("/api/v1/admin/marketplace/products", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        category: category,
        price: price,
        description: desc || null,
        image_url: image,
        currency: "NGN",
        is_available: true,
      }),
    });
    document.getElementById("mp-title").value = "";
    document.getElementById("mp-price").value = "";
    document.getElementById("mp-image").value = "";
    document.getElementById("mp-desc").value = "";
    if (fileInput) fileInput.value = "";
    var prev = document.getElementById("mp-image-preview");
    if (prev) {
      if (prev._blobUrl) {
        try {
          URL.revokeObjectURL(prev._blobUrl);
        } catch (_) {}
        prev._blobUrl = null;
      }
      prev.classList.add("hidden");
      prev.removeAttribute("src");
    }
    msg.textContent = "Product posted.";
    loadMarketplaceProducts();
  } catch (e) {
    msg.textContent = e.message || "Failed to post product.";
  }
}

async function deleteMarketplaceProduct(id) {
  if (!confirm("Remove this product from the marketplace?")) return;
  try {
    await adminApi("/api/v1/admin/marketplace/products/" + id, { method: "DELETE" });
    loadMarketplaceProducts();
  } catch (e) {
    alert(e.message);
  }
}

async function markMarketplaceContacted(id) {
  try {
    await adminApi(
      "/api/v1/admin/marketplace/bookings/" + id + "/status?status=contacted",
      { method: "PATCH" }
    );
    loadMarketplaceBookings();
  } catch (e) {
    alert(e.message);
  }
}

/* ── Internal exams (admin) ── */
var _ieStudentsCache = [];

function toggleIeStudentPick() {
  var all = document.getElementById("ie-all-subject");
  var wrap = document.getElementById("ie-student-wrap");
  if (!wrap) return;
  wrap.classList.toggle("hidden", !all || all.checked);
}

function _csvSplitLine(line) {
  var out = [];
  var cur = "";
  var inQ = false;
  for (var i = 0; i < line.length; i++) {
    var ch = line[i];
    if (ch === '"') {
      if (inQ && line[i + 1] === '"') {
        cur += '"';
        i++;
      } else inQ = !inQ;
    } else if (ch === "," && !inQ) {
      out.push(cur);
      cur = "";
    } else cur += ch;
  }
  out.push(cur);
  return out;
}

function parseQuestionsFromCbtFile(text, filename) {
  var name = (filename || "").toLowerCase();
  if (name.endsWith(".json") || text.trim().charAt(0) === "{" || text.trim().charAt(0) === "[") {
    var data = JSON.parse(text);
    var exams = Array.isArray(data) ? data : data.exams || [data];
    var questions = [];
    exams.forEach(function (ex) {
      (ex.questions || []).forEach(function (q) {
        questions.push({
          question_text: q.question_text || q.question || q.text || "",
          option_a: q.option_a || q.a || "",
          option_b: q.option_b || q.b || "",
          option_c: q.option_c || q.c || "",
          option_d: q.option_d || q.d || "",
          correct_option: String(q.correct_option || q.answer || q.correct || "A").toUpperCase().charAt(0),
          explanation: q.explanation || null,
          topic: q.topic || null,
          image_url: q.image_url || null,
        });
      });
    });
    return questions;
  }
  var lines = text.replace(/\r\n/g, "\n").replace(/\r/g, "\n").split("\n").filter(function (l) {
    return l.trim();
  });
  if (lines.length < 2) throw new Error("CSV needs a header row and at least one question.");
  var headers = _csvSplitLine(lines[0]).map(function (h) {
    return h.trim().toLowerCase().replace(/\s+/g, "_");
  });
  function col() {
    for (var i = 0; i < arguments.length; i++) {
      var idx = headers.indexOf(arguments[i]);
      if (idx >= 0) return idx;
    }
    return -1;
  }
  var qi = col("question_text", "question", "text", "q");
  var ai = col("option_a", "a");
  var bi = col("option_b", "b");
  var ci = col("option_c", "c");
  var di = col("option_d", "d");
  var ans = col("correct_option", "answer", "correct", "correct_answer");
  if (qi < 0 || ai < 0 || bi < 0 || ci < 0 || di < 0 || ans < 0) {
    throw new Error("CSV needs question_text, option_a–d, and correct_option columns.");
  }
  var questions = [];
  for (var r = 1; r < lines.length; r++) {
    var cells = _csvSplitLine(lines[r]);
    questions.push({
      question_text: (cells[qi] || "").trim(),
      option_a: (cells[ai] || "").trim(),
      option_b: (cells[bi] || "").trim(),
      option_c: (cells[ci] || "").trim(),
      option_d: (cells[di] || "").trim(),
      correct_option: String(cells[ans] || "A").toUpperCase().charAt(0),
    });
  }
  return questions.filter(function (q) { return q.question_text; });
}

async function loadInternalExamsAdmin() {
  await Promise.all([fillIeTeachers(), fillIeStudents(), loadIeExamsTable(), loadIeSubmissionsTable()]);
  toggleIeStudentPick();
}

async function fillIeTeachers() {
  var sel = document.getElementById("ie-teacher");
  if (!sel) return;
  try {
    var rows = await adminApi("/api/v1/admin/teachers") || [];
    sel.innerHTML = '<option value="">Select teacher</option>' + rows.map(function (t) {
      return '<option value="' + escHtml(t.id) + '">' + escHtml(t.full_name || t.email) + "</option>";
    }).join("");
  } catch (e) {
    sel.innerHTML = '<option value="">' + escHtml(e.message) + "</option>";
  }
}

async function fillIeStudents() {
  var box = document.getElementById("ie-students");
  if (!box) return;
  try {
    var rows = await adminApi("/api/v1/admin/students?active_only=true") || [];
    _ieStudentsCache = rows;
    renderIeStudentChecks();
  } catch (e) {
    box.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

function renderIeStudentChecks() {
  var box = document.getElementById("ie-students");
  var subject = (document.getElementById("ie-subject").value || "").toLowerCase();
  if (!box) return;
  var rows = _ieStudentsCache || [];
  var filtered = rows.filter(function (s) {
    if (!subject) return true;
    var subs = (s.selected_subjects || []).map(function (x) {
      return String(x).toLowerCase();
    });
    return !subs.length || subs.some(function (x) { return x.indexOf(subject) >= 0 || subject.indexOf(x) >= 0; });
  });
  if (!filtered.length) {
    box.innerHTML = '<div class="empty-state">No students match this subject yet.</div>';
    return;
  }
  box.innerHTML = filtered.map(function (s) {
    var label = (s.full_name || s.email || "Student") +
      (s.selected_subjects && s.selected_subjects.length
        ? " — " + s.selected_subjects.join(", ")
        : "");
    return '<label><input type="checkbox" class="ie-student-cb" value="' +
      escHtml(s.id) + '" /> ' + escHtml(label) + "</label>";
  }).join("");
}

async function loadIeExamsTable() {
  var el = document.getElementById("ie-exams-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/internal-exams");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No internal exams yet.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Teacher</th><th>Q</th><th>Target</th><th>Notes</th><th>Status</th></tr></thead><tbody>' +
      rows.map(function (e) {
        var target = e.assign_mode === "selected_students"
          ? e.assigned_count + " student(s)"
          : "By subject";
        return "<tr><td>" + escHtml(e.title) + "</td><td>" + escHtml(e.subject) +
          "</td><td>" + escHtml(e.teacher_name) + "</td><td>" + e.total_questions +
          "</td><td>" + escHtml(target) + "</td><td>" +
          (e.notes_url ? "Yes" : "—") + "</td><td>" +
          (e.is_published ? '<span class="badge ok">Published</span>' : '<span class="badge muted">Draft</span>') +
          "</td></tr>";
      }).join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadIeSubmissionsTable() {
  var el = document.getElementById("ie-submissions-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/internal-exams/submissions");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No submissions yet.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Student</th><th>Exam</th><th>Subject</th><th>Teacher</th><th>Score</th><th>Submitted</th></tr></thead><tbody>' +
      rows.map(function (r) {
        return "<tr><td>" + escHtml(r.student_name) + "</td><td>" + escHtml(r.exam_title) +
          "</td><td>" + escHtml(r.subject) + "</td><td>" + escHtml(r.teacher_name) +
          "</td><td>" + (r.percentage != null ? r.percentage + "%" : "—") +
          "</td><td>" + escHtml((r.submitted_at || "").replace("T", " ").slice(0, 16)) +
          "</td></tr>";
      }).join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function createInternalExamAdmin() {
  var err = document.getElementById("ie-form-error");
  var ok = document.getElementById("ie-form-ok");
  var btn = document.getElementById("btn-ie-create");
  err.textContent = "";
  ok.textContent = "";

  var title = document.getElementById("ie-title").value.trim();
  var subject = document.getElementById("ie-subject").value.trim();
  var teacherId = document.getElementById("ie-teacher").value;
  var duration = parseInt(document.getElementById("ie-duration").value, 10) || 45;
  var fileInput = document.getElementById("ie-file");
  var notesInput = document.getElementById("ie-notes");
  var allSubject = document.getElementById("ie-all-subject").checked;

  if (!title || !subject || !teacherId) {
    err.textContent = "Title, subject, and teacher are required.";
    return;
  }
  if (!fileInput.files || !fileInput.files[0]) {
    err.textContent = "Choose a JSON or CSV questions file.";
    return;
  }

  var studentIds = [];
  if (!allSubject) {
    Array.prototype.forEach.call(document.querySelectorAll(".ie-student-cb:checked"), function (cb) {
      studentIds.push(cb.value);
    });
    if (!studentIds.length) {
      err.textContent = "Pick at least one student, or leave “All students…” checked.";
      return;
    }
  }

  btn.disabled = true;
  btn.textContent = "Uploading…";
  try {
    var text = await fileInput.files[0].text();
    var questions = parseQuestionsFromCbtFile(text, fileInput.files[0].name);
    if (!questions.length) throw new Error("No questions found in the file.");

    var notesUrl = null;
    var notesTitle = null;
    if (notesInput.files && notesInput.files[0]) {
      var notes = await uploadInternalNotes(notesInput.files[0]);
      if (!notes) return;
      notesUrl = notes.notes_url;
      notesTitle = notes.notes_title;
    }

    await adminApi("/api/v1/admin/internal-exams", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        subject: subject,
        teacher_id: teacherId,
        duration_minutes: duration,
        questions: questions,
        student_ids: studentIds,
        notes_url: notesUrl,
        notes_title: notesTitle,
        is_published: true,
      }),
    });

    document.getElementById("ie-title").value = "";
    fileInput.value = "";
    if (notesInput) notesInput.value = "";
    ok.textContent = "Internal exam published. Matching students can download it offline and submit.";
    loadIeExamsTable();
    loadIeSubmissionsTable();
  } catch (e) {
    err.textContent = e.message || "Could not create internal exam.";
  } finally {
    btn.disabled = false;
    btn.textContent = "Upload & publish";
  }
}

document.addEventListener("change", function (ev) {
  if (ev.target && ev.target.id === "ie-subject") renderIeStudentChecks();
});

/* ── Library ── */
async function loadLibraryAdmin() {
  var el = document.getElementById("library-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/library/books");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No library books yet.</div>';
      return;
    }
    el.innerHTML =
      '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Board</th><th>Target</th><th></th></tr></thead><tbody>' +
      rows.map(function (b) {
        return "<tr><td>" + escHtml(b.title) + "</td><td>" + escHtml(b.subject || "—") +
          "</td><td>" + escHtml(b.exam_type || "—") + "</td><td>" + escHtml(b.library_target || "student") +
          '</td><td class="actions"><button class="btn-sm danger" onclick="deleteLibraryBook(\'' +
          b.id + "')\">Remove</button></td></tr>";
      }).join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function uploadLibraryBook() {
  var err = document.getElementById("lib-form-error");
  var ok = document.getElementById("lib-form-ok");
  var btn = document.getElementById("btn-lib-upload");
  err.textContent = "";
  ok.textContent = "";
  var title = document.getElementById("lib-title").value.trim();
  var subject = document.getElementById("lib-subject").value.trim();
  var exam = document.getElementById("lib-exam").value;
  var author = document.getElementById("lib-author").value.trim();
  var desc = document.getElementById("lib-desc").value.trim();
  var fileInput = document.getElementById("lib-file");
  if (!title || !subject) {
    err.textContent = "Title and subject are required.";
    return;
  }
  if (!fileInput.files || !fileInput.files[0]) {
    err.textContent = "Choose a PDF file.";
    return;
  }
  btn.disabled = true;
  btn.textContent = "Uploading…";
  try {
    var up = await uploadLibraryPdf(fileInput.files[0]);
    if (!up || !up.file_key) throw new Error("Upload did not return a file key.");
    await adminApi("/api/v1/admin/library/books", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        author: author || null,
        subject: subject,
        exam_type: exam,
        file_key: up.file_key,
        description: desc || null,
        library_target: "student",
        is_free: true,
        price: 0,
      }),
    });
    document.getElementById("lib-title").value = "";
    document.getElementById("lib-author").value = "";
    document.getElementById("lib-desc").value = "";
    fileInput.value = "";
    ok.textContent = "Book uploaded to the student library.";
    loadLibraryAdmin();
  } catch (e) {
    err.textContent = e.message || "Upload failed.";
  } finally {
    btn.disabled = false;
    btn.textContent = "Upload to library";
  }
}

async function deleteLibraryBook(id) {
  if (!confirm("Remove this book from the library?")) return;
  try {
    await adminApi("/api/v1/admin/library/books/" + id, { method: "DELETE" });
    loadLibraryAdmin();
  } catch (e) {
    alert(e.message);
  }
}

