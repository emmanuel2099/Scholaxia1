var currentAdminPage = "dashboard";

document.addEventListener("DOMContentLoaded", function () {
  if (getAdminToken()) {
    showApp();
    var role = localStorage.getItem("sia_admin_role") || "admin";
    if (role === "school_admin") {
      showAdminPage("school-office");
    } else {
      loadDashboard();
    }
  } else {
    showAuth();
  }

  document.getElementById("tab-login").addEventListener("click", function () { switchAuthTab("login"); });
  document.getElementById("tab-register").addEventListener("click", function () { switchAuthTab("register"); });
  document.getElementById("form-login").addEventListener("submit", adminLogin);
  document.getElementById("form-register").addEventListener("submit", adminRegister);
  syncMarketplaceFileFields();
});

function showAuth() {
  document.getElementById("auth-screen").classList.remove("hidden");
  document.getElementById("app-screen").classList.add("hidden");
}

function showApp() {
  document.getElementById("auth-screen").classList.add("hidden");
  document.getElementById("app-screen").classList.remove("hidden");
  var u = getAdminUser();
  var role = localStorage.getItem("sia_admin_role") || "admin";
  var school = localStorage.getItem("sia_school_name") || "";
  document.getElementById("admin-user-label").textContent = (role === "school_admin" ? (school || "School admin") + " · " : "") + u.name + " · " + u.email;
  document.body.classList.toggle("school-admin-mode", role === "school_admin");
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
  btn.textContent = "Signing in…";
  try {
    if (typeof wakeAdminServer === "function") {
      try { await wakeAdminServer(); } catch (wakeErr) { /* continue */ }
    }
    var res = await fetch(API_BASE + "/api/v1/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password }),
      signal: fetchTimeout(90000),
    });
    var data = await res.json().catch(function () { return {}; });
    if (!res.ok) { err.textContent = formatApiError(data.detail) || "Login failed."; return; }
    var role = String(data.role || (data.user && data.user.role) || "").toLowerCase().replace(/^userrole\./, "");
    if (role !== "admin" && role !== "school_admin") {
      err.textContent = "This email is a " + (role || "unknown") + " account, not an admin. Use the student/teacher sign-in on the website.";
      return;
    }
    saveAdminSession(data, email, (data.user && data.user.full_name) || email);
    if (data.user && data.user.school_id) {
      localStorage.setItem("sia_school_id", data.user.school_id);
    }
    if (data.user && data.user.school_name) {
      localStorage.setItem("sia_school_name", data.user.school_name);
    }
    showApp();
    if (role === "school_admin") {
      showAdminPage("school-office");
    } else {
      loadDashboard();
    }
  } catch (ex) {
    if (ex && ex.name === "AbortError") {
      err.textContent = "Server took too long (waking up). Wait 20 seconds and try again.";
    } else {
      err.textContent = "Network error. Check your connection and try again.";
    }
  } finally {
    btn.disabled = false;
    btn.textContent = "LOG IN";
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
  else if (page === "vendors") loadVendors();
  else if (page === "kind") loadKind();
  else if (page === "kind-games") loadKindGamesAdmin();
  else if (page === "kind-library") loadKindLibraryAdmin();
  else if (page === "kind-videos") loadKindVideosAdmin();
  else if (page === "requests") loadRequests();
  else if (page === "live-subs") loadLiveSubscriptions();
  else if (page === "skills-enroll") loadSkillsEnrollments();
  else if (page === "cbt-settings") { loadCbtSettings(); }
  else if (page === "cbt") { cbtMode = "practice"; initCbtBuilder(); loadCbt(); }
  else if (page === "coupons") loadCbtCoupons();
  else if (page === "past-questions") { cbtMode = "past"; loadPastQuestionsAdmin(); }
  else if (page === "library") loadLibraryAdmin();
  else if (page === "videos") loadAdminVideos();
  else if (page === "schools") loadSchoolsAdmin();
  else if (page === "school-office") loadSchoolOffice();
  else if (page === "internal-exams") loadInternalExamsAdmin();
  else if (page === "recommendations") loadRecommendations();
  else if (page === "student-groups") loadStudentGroupsAdmin();
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
var _studentsCache = [];

async function loadStudents() {
  var el = document.getElementById("students-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var q = ((document.getElementById("students-search") || {}).value || "").trim();
    var url = "/api/v1/admin/students?active_only=true";
    if (q) url += "&q=" + encodeURIComponent(q);
    var rows = await adminApi(url);
    if (!rows) return;
    rows = rows.filter(function (s) { return s.is_active; });
    _studentsCache = rows;
    renderStudentsTable(rows);
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

function filterStudentsTable() {
  var q = ((document.getElementById("students-search") || {}).value || "").trim().toLowerCase();
  if (!q) {
    renderStudentsTable(_studentsCache);
    return;
  }
  renderStudentsTable(_studentsCache.filter(function (s) {
    return String(s.email || "").toLowerCase().indexOf(q) >= 0 ||
      String(s.full_name || "").toLowerCase().indexOf(q) >= 0;
  }));
}

function renderStudentsTable(rows) {
  var el = document.getElementById("students-table");
  if (!el) return;
  if (!rows.length) { el.innerHTML = '<div class="empty-state">No matching students.</div>'; return; }
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
}

async function refreshDashboardStats() {
  if (currentAdminPage === "dashboard") {
    await loadDashboard();
  }
}

async function deleteStudent(id) {
  if (!confirm("Delete this student permanently? They will be removed from the database.")) return;
  try {
    await adminApi("/api/v1/admin/students/" + id, { method: "DELETE" });
    alert("Student deleted.");
    loadStudents();
    refreshDashboardStats();
  } catch (e) {
    alert((e && e.message) || "Could not delete this student. They may have linked records — try again or contact support.");
  }
}

async function removeAllStudents() {
  alert("Bulk delete is disabled so staff cannot wipe student accounts by mistake.");
}

async function purgeAllUsers() {
  alert("Bulk delete is disabled so staff cannot wipe all accounts by mistake.");
}

/* ── Teachers ── */
async function loadTeachers() {
  var el = document.getElementById("teachers-table");
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var data = await adminApi("/api/v1/admin/teachers");
    var rows = Array.isArray(data) ? data : (data && (data.teachers || data.items)) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No teacher signups yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Name</th><th>Email</th><th>WhatsApp</th><th>Subjects</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (t) {
        var subs = (t.subjects || []).map(function (x) {
          return '<span class="subj-tag">' + escHtml(x) + '</span>';
        }).join("");
        var wa = escHtml(t.phone || t.whatsapp || '');
        var status = t.is_approved ? 'Approved' : 'Pending approval';
        return '<tr><td>' + escHtml(t.full_name) + '</td><td>' + escHtml(t.email) + '</td>' +
          '<td>' + (wa || '—') + '</td>' +
          '<td><div class="subj-tags">' + (subs || '—') + '</div></td>' +
          '<td>' + escHtml(status) + '</td>' +
          '<td class="actions">' +
          (t.is_approved
            ? '<button class="btn-sm danger" onclick="rejectTeacher(\'' + t.id + '\')">Lock</button>'
            : '<button class="btn-sm" onclick="approveTeacher(\'' + t.id + '\')">Approve</button>') +
          ' <button class="btn-sm danger" onclick="deleteTeacher(\'' + t.id + '\')">Remove</button></td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function approveTeacher(id) {
  if (!confirm("Approve this teacher?")) return;
  try {
    await adminApi("/api/v1/admin/teachers/" + id + "/approve", { method: "POST" });
    loadTeachers();
  } catch (e) { alert(e.message); }
}

async function rejectTeacher(id) {
  if (!confirm("Lock this teacher account?")) return;
  try {
    await adminApi("/api/v1/admin/teachers/" + id + "/reject", { method: "POST" });
    loadTeachers();
  } catch (e) { alert(e.message); }
}

async function deleteTeacher(id) {
  if (!confirm("Remove this teacher? They will not be able to log in.")) return;
  try {
    await adminApi("/api/v1/admin/teachers/" + id, { method: "DELETE" });
    loadTeachers();
  } catch (e) { alert(e.message); }
}

/* ── Vendors ── */
async function loadVendors() {
  var el = document.getElementById("vendors-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/vendors");
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No vendors yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Business</th><th>Name</th><th>Email</th><th>WhatsApp</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (v) {
        var status = v.is_approved
          ? ('Approved' + (v.kyc_completed ? ' · KYC done' : ' · KYC pending'))
          : 'Pending approval';
        var wa = escHtml(v.whatsapp || v.phone || '');
        return '<tr><td>' + escHtml(v.business_name) + '</td><td>' + escHtml(v.full_name) + '</td>' +
          '<td>' + escHtml(v.email) + '</td><td>' + (wa || '—') + '</td><td>' + escHtml(status) + '</td>' +
          '<td class="actions">' +
          (v.is_approved
            ? '<button class="btn-sm danger" onclick="rejectVendor(\'' + v.id + '\')">Lock</button>'
            : '<button class="btn-sm" onclick="approveVendor(\'' + v.id + '\',\'' + wa.replace(/'/g, '') + '\')">Approve</button>') +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function approveVendor(id, existingWa) {
  var wa = prompt("Enter vendor WhatsApp number (required):", existingWa || "");
  if (wa == null) return;
  wa = String(wa).trim();
  if (wa.length < 7) { alert("WhatsApp number is required."); return; }
  try {
    await adminApi("/api/v1/admin/vendors/" + id + "/approve", {
      method: "POST",
      body: JSON.stringify({ whatsapp: wa, is_approved: true }),
    });
    loadVendors();
  } catch (e) { alert(e.message); }
}

async function rejectVendor(id) {
  if (!confirm("Lock this vendor account?")) return;
  try {
    await adminApi("/api/v1/admin/vendors/" + id + "/reject", { method: "POST" });
    loadVendors();
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
    el.innerHTML = '<table class="data-table"><thead><tr><th>Name</th><th>Email</th><th>Age</th><th>Grade</th><th>Parent</th><th>Status</th><th>Actions</th></tr></thead><tbody>' +
      rows.map(function (k) {
        var active = k.is_active !== false;
        return '<tr><td>' + escHtml(k.full_name) + '</td><td>' + escHtml(k.email) + '</td>' +
          '<td>' + escHtml(k.age_group || "—") + '</td><td>' + escHtml(k.grade_level || "—") + '</td>' +
          '<td>' + escHtml(k.parent_email || "—") + '</td>' +
          '<td>' + (active ? "Active" : '<span style="color:#b91c1c;font-weight:700">Restricted</span>') + '</td>' +
          '<td>' +
          (active
            ? '<button class="btn-sm" onclick="restrictKindLearner(\'' + k.id + '\', true)">Restrict</button> '
            : '<button class="btn-sm primary" onclick="restrictKindLearner(\'' + k.id + '\', false)">Unrestrict</button> ') +
          '<button class="btn-sm danger" onclick="deleteKindLearner(\'' + k.id + '\', ' + JSON.stringify(k.full_name || k.email || "learner") + ')">Delete</button>' +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function restrictKindLearner(id, restricted) {
  try {
    await adminApi("/api/v1/admin/kind-learners/" + id + "/restrict?restricted=" + (restricted ? "true" : "false"), { method: "POST" });
    loadKind();
  } catch (e) { alert(e.message); }
}

async function deleteKindLearner(id, name) {
  if (!confirm("Permanently delete kind learner \"" + name + "\"?")) return;
  try {
    await adminApi("/api/v1/admin/kind-learners/" + id, { method: "DELETE" });
    loadKind();
  } catch (e) { alert(e.message); }
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
  cbtMode = "practice";
  if (!cbtQuestions.length) cbtQuestions = [emptyQuestion()];
  renderCbtQuestions();
}

function switchCbtMode(mode, skipReset) {
  cbtMode = mode === "past" ? "past" : "practice";
}

function addCbtQuestion() {
  syncAllQuestions();
  cbtQuestions.push(emptyQuestion());
  renderCbtQuestions();
  var list = document.getElementById("cbt-questions-list");
  if (!list) return;
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
  if (!list) return;
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
      ? '<img src="' + escHtml(q.image_preview || q.image_url) + '" alt="Diagram" />' +
        '<button type="button" class="btn-sm" style="margin-top:6px" onclick="clearQuestionImage(' + idx + ')">Remove diagram</button>'
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

function clearQuestionImage(idx) {
  syncAllQuestions();
  if (!cbtQuestions[idx]) return;
  cbtQuestions[idx].image_url = "";
  cbtQuestions[idx].image_preview = "";
  cbtQuestions[idx].uploading = false;
  renderCbtQuestions();
}

var cbtEditExamId = null;
var cbtEditQuestions = [];

function syncEditQuestionFromDom(idx) {
  var q = cbtEditQuestions[idx];
  if (!q) return;
  var prefix = "eq-" + idx + "-";
  var textEl = document.getElementById(prefix + "text");
  if (!textEl) return;
  q.question_text = textEl.value;
  q.option_a = document.getElementById(prefix + "a").value;
  q.option_b = document.getElementById(prefix + "b").value;
  q.option_c = document.getElementById(prefix + "c").value;
  q.option_d = document.getElementById(prefix + "d").value;
  var correct = document.querySelector('input[name="' + prefix + 'correct"]:checked');
  q.correct_option = correct ? correct.value : "A";
  q.topic = (document.getElementById(prefix + "topic") || {}).value || "";
  q.explanation = (document.getElementById(prefix + "explain") || {}).value || "";
}

function syncAllEditQuestions() {
  for (var i = 0; i < cbtEditQuestions.length; i++) syncEditQuestionFromDom(i);
}

function renderCbtEditQuestions() {
  var list = document.getElementById("cbt-edit-questions-list");
  if (!list) return;
  list.innerHTML = cbtEditQuestions.map(function (q, idx) {
    var prefix = "eq-" + idx + "-";
    var opts = ["A", "B", "C", "D"].map(function (letter) {
      var key = "option_" + letter.toLowerCase();
      var val = escHtml(q[key] || "");
      var checked = q.correct_option === letter ? " checked" : "";
      return '<div class="q-opt-row">' +
        '<input type="radio" name="' + prefix + 'correct" value="' + letter + '"' + checked + ' />' +
        '<input type="text" id="' + prefix + letter.toLowerCase() + '" placeholder="Option ' + letter + '" value="' + val + '" />' +
        '</div>';
    }).join("");
    var imgBlock = q.image_url || q.image_preview
      ? '<img src="' + escHtml(q.image_preview || q.image_url) + '" alt="Diagram" />' +
        '<button type="button" class="btn-sm" style="margin-top:6px" onclick="clearEditQuestionImage(' + idx + ')">Remove diagram</button>'
      : "";
    var uploading = q.uploading ? '<div class="uploading">Uploading diagram…</div>' : "";
    return '<div class="q-card" data-idx="' + idx + '">' +
      '<div class="q-card-head"><strong>Question ' + (idx + 1) + '</strong>' +
      (cbtEditQuestions.length > 1 ? '<button type="button" class="q-remove" onclick="removeCbtEditQuestion(' + idx + ')">Delete question</button>' : '') +
      '</div>' +
      '<textarea id="' + prefix + 'text" placeholder="Type the question here…">' + escHtml(q.question_text || "") + '</textarea>' +
      '<div class="q-diagram">' +
      '<label><span>Diagram / figure (optional) — JPEG, PNG, WebP</span>' +
      '<input type="file" accept="image/jpeg,image/png,image/webp,image/gif" onchange="onEditQuestionImage(' + idx + ', this)" />' +
      uploading + imgBlock + '</label></div>' +
      '<div class="q-options">' + opts + '</div>' +
      '<p class="cbt-hint small">Click the circle next to the correct answer.</p>' +
      '<div class="q-meta">' +
      '<input type="text" id="' + prefix + 'topic" placeholder="Topic (optional)" value="' + escHtml(q.topic || "") + '" />' +
      '<input type="text" id="' + prefix + 'explain" placeholder="Explanation (optional)" value="' + escHtml(q.explanation || "") + '" />' +
      '</div></div>';
  }).join("");
}

function addCbtEditQuestion() {
  syncAllEditQuestions();
  cbtEditQuestions.push(emptyQuestion());
  renderCbtEditQuestions();
}

function removeCbtEditQuestion(idx) {
  if (cbtEditQuestions.length <= 1) {
    alert("Keep at least one question, or leave the exam unpublished.");
    return;
  }
  if (!confirm("Remove question " + (idx + 1) + "?")) return;
  syncAllEditQuestions();
  cbtEditQuestions.splice(idx, 1);
  renderCbtEditQuestions();
}

async function onEditQuestionImage(idx, input) {
  var file = input.files && input.files[0];
  if (!file) return;
  if (file.size > 5 * 1024 * 1024) { alert("Image must be under 5MB."); input.value = ""; return; }
  syncAllEditQuestions();
  cbtEditQuestions[idx].uploading = true;
  cbtEditQuestions[idx].image_preview = URL.createObjectURL(file);
  renderCbtEditQuestions();
  try {
    var url = await uploadCbtImage(file);
    syncAllEditQuestions();
    cbtEditQuestions[idx].image_url = url;
    cbtEditQuestions[idx].image_preview = url;
    cbtEditQuestions[idx].uploading = false;
    renderCbtEditQuestions();
  } catch (e) {
    syncAllEditQuestions();
    cbtEditQuestions[idx].uploading = false;
    cbtEditQuestions[idx].image_url = "";
    cbtEditQuestions[idx].image_preview = "";
    renderCbtEditQuestions();
    alert("Diagram upload failed: " + e.message);
  }
}

function clearEditQuestionImage(idx) {
  syncAllEditQuestions();
  if (!cbtEditQuestions[idx]) return;
  cbtEditQuestions[idx].image_url = "";
  cbtEditQuestions[idx].image_preview = "";
  cbtEditQuestions[idx].uploading = false;
  renderCbtEditQuestions();
}

async function openCbtExamEdit(id) {
  var panel = document.getElementById("cbt-edit-panel");
  var err = document.getElementById("cbt-edit-error");
  if (err) err.textContent = "";
  try {
    var data = await adminApi("/api/v1/admin/cbt/exams/" + encodeURIComponent(id));
    cbtEditExamId = id;
    document.getElementById("cbt-edit-title").value = data.title || "";
    document.getElementById("cbt-edit-duration").value = data.duration_minutes || 30;
    document.getElementById("cbt-edit-publish").checked = !!data.is_published;
    document.getElementById("cbt-edit-heading").textContent =
      "Preview / edit — " + (data.subject || "") + " (" + (data.exam_type || "") + ")";
    cbtEditQuestions = (data.questions || []).map(function (q) {
      return {
        question_text: q.question_text || "",
        option_a: q.option_a || "",
        option_b: q.option_b || "",
        option_c: q.option_c || "",
        option_d: q.option_d || "",
        correct_option: (q.correct_option || "A").toUpperCase().slice(0, 1),
        topic: q.topic || "",
        explanation: q.explanation || "",
        image_url: q.image_url || "",
        image_preview: q.image_url || "",
        uploading: false,
      };
    });
    if (!cbtEditQuestions.length) cbtEditQuestions = [emptyQuestion()];
    renderCbtEditQuestions();
    if (panel) {
      panel.style.display = "block";
      panel.scrollIntoView({ behavior: "smooth", block: "start" });
    }
  } catch (e) {
    alert(e.message || "Could not load exam");
  }
}

function cancelCbtExamEdit() {
  cbtEditExamId = null;
  cbtEditQuestions = [];
  var panel = document.getElementById("cbt-edit-panel");
  if (panel) panel.style.display = "none";
}

async function saveCbtExamEdit() {
  var err = document.getElementById("cbt-edit-error");
  var btn = document.getElementById("btn-save-cbt-edit");
  if (!cbtEditExamId) return;
  if (err) err.textContent = "";
  syncAllEditQuestions();
  var title = (document.getElementById("cbt-edit-title").value || "").trim();
  if (!title) {
    if (err) err.textContent = "Enter an exam title.";
    return;
  }
  var questions = [];
  for (var i = 0; i < cbtEditQuestions.length; i++) {
    var q = cbtEditQuestions[i];
    if (!q.question_text.trim()) {
      if (err) err.textContent = "Question " + (i + 1) + " is empty.";
      return;
    }
    if (!q.option_a.trim() || !q.option_b.trim() || !q.option_c.trim() || !q.option_d.trim()) {
      if (err) err.textContent = "Fill in all four options for question " + (i + 1) + ".";
      return;
    }
    if (q.uploading) {
      if (err) err.textContent = "Wait for the diagram on question " + (i + 1) + " to finish uploading.";
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
    if ((q.topic || "").trim()) item.topic = q.topic.trim();
    if ((q.explanation || "").trim()) item.explanation = q.explanation.trim();
    if (q.image_url) item.image_url = q.image_url;
    questions.push(item);
  }
  if (btn) { btn.disabled = true; btn.textContent = "Saving…"; }
  try {
    await adminApi("/api/v1/admin/cbt/exams/" + encodeURIComponent(cbtEditExamId), {
      method: "PUT",
      body: JSON.stringify({
        title: title,
        duration_minutes: parseInt(document.getElementById("cbt-edit-duration").value, 10) || 30,
        is_published: !!document.getElementById("cbt-edit-publish").checked,
        questions: questions,
      }),
    });
    alert("Exam updated.");
    cancelCbtExamEdit();
    if (currentAdminPage === "past-questions") loadPastQuestionsAdmin();
    else loadCbt();
  } catch (e) {
    if (err) err.textContent = e.message;
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = "Save changes"; }
  }
}

async function loadCbtSettings() {
  var msg = document.getElementById("cbt-settings-msg");
  var bankEl = document.getElementById("cbt-bank-table");
  try {
    var data = await adminApi("/api/v1/admin/cbt-settings");
    var s = (data && data.settings) || {};
    function setSel(id, val) {
      var el = document.getElementById(id);
      if (el) el.value = val ? "true" : "false";
    }
    function setNum(id, val) {
      var el = document.getElementById(id);
      if (el) el.value = val != null ? val : "";
    }
    setSel("cbt-set-enabled", s.cbt_enabled !== false);
    setSel("cbt-set-rand-q", s.randomize_questions !== false);
    setSel("cbt-set-rand-opt", s.randomize_options !== false);
    setSel("cbt-set-resume", s.allow_resume !== false);
    setSel("cbt-set-autosubmit", s.auto_submit_on_timeout !== false);
    setNum("cbt-set-jamb-q", s.jamb_questions_per_subject);
    setNum("cbt-set-jamb-eng", s.jamb_english_questions);
    setNum("cbt-set-jamb-dur", s.jamb_duration_minutes);
    setNum("cbt-set-jamb-subj", s.jamb_subjects_required);
    setNum("cbt-set-waec-q", s.waec_questions_per_subject);
    setNum("cbt-set-waec-dur", s.waec_duration_minutes);
    setNum("cbt-set-neco-q", s.neco_questions_per_subject);
    setNum("cbt-set-neco-dur", s.neco_duration_minutes);
    var bank = (data && data.question_bank) || [];
    if (bankEl) {
      if (!bank.length) {
        bankEl.innerHTML = '<div class="empty-state">No published practice questions in the bank yet.</div>';
      } else {
        bankEl.innerHTML = '<table class="data-table"><thead><tr><th>Exam</th><th>Subject</th><th>Questions in bank</th></tr></thead><tbody>' +
          bank.map(function (r) {
            return "<tr><td>" + escHtml(r.exam_type) + "</td><td>" + escHtml(r.subject) + "</td><td>" +
              escHtml(r.total_questions) + "</td></tr>";
          }).join("") + "</tbody></table>";
      }
    }
    if (msg) msg.textContent = "";
  } catch (e) {
    if (msg) msg.textContent = e.message;
    if (bankEl) bankEl.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function saveCbtSettings() {
  var msg = document.getElementById("cbt-settings-msg");
  function boolVal(id) {
    return (document.getElementById(id) || {}).value === "true";
  }
  function numVal(id) {
    return parseInt((document.getElementById(id) || {}).value || "0", 10);
  }
  try {
    await adminApi("/api/v1/admin/cbt-settings", {
      method: "PUT",
      body: JSON.stringify({
        cbt_enabled: boolVal("cbt-set-enabled"),
        randomize_questions: boolVal("cbt-set-rand-q"),
        randomize_options: boolVal("cbt-set-rand-opt"),
        allow_resume: boolVal("cbt-set-resume"),
        auto_submit_on_timeout: boolVal("cbt-set-autosubmit"),
        jamb_questions_per_subject: numVal("cbt-set-jamb-q"),
        jamb_english_questions: numVal("cbt-set-jamb-eng"),
        jamb_duration_minutes: numVal("cbt-set-jamb-dur"),
        jamb_subjects_required: numVal("cbt-set-jamb-subj"),
        waec_questions_per_subject: numVal("cbt-set-waec-q"),
        waec_duration_minutes: numVal("cbt-set-waec-dur"),
        neco_questions_per_subject: numVal("cbt-set-neco-q"),
        neco_duration_minutes: numVal("cbt-set-neco-dur"),
      }),
    });
    if (msg) msg.textContent = "Settings saved.";
    loadCbtSettings();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function loadCbt() {
  var el = document.getElementById("cbt-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/cbt/exams");
    if (!rows) return;
    rows = rows.filter(function (e) {
      return !e.is_school_exam && e.paper_kind !== "past_questions";
    });
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No CBT practice exams yet. Upload questions above.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Type</th><th>Questions</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (e) {
        var typeBadge = '<span class="badge ok">' + escHtml(e.exam_type) + '</span>';
        var pub = e.is_published ? '<span class="badge ok">Published</span>' : '<span class="badge muted">Draft</span>';
        return '<tr><td>' + escHtml(e.title) + '</td><td>' + escHtml(e.subject) + '</td>' +
          '<td>' + typeBadge + '</td><td>' + e.total_questions + '</td><td>' + pub + '</td>' +
          '<td class="actions">' +
          '<button class="btn-sm" onclick="openCbtExamEdit(\'' + e.id + '\')">Edit questions &amp; images</button>' +
          '<button class="btn-sm" onclick="toggleCbtPublish(\'' + e.id + '\')">Toggle publish</button>' +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function loadPastQuestionsAdmin() {
  var el = document.getElementById("pq-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await adminApi("/api/v1/admin/cbt/exams");
    if (!rows) return;
    rows = rows.filter(function (e) { return e.paper_kind === "past_questions"; });
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No past question papers yet. Upload one above.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Board</th><th>Questions</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (e) {
        var pub = e.is_published ? '<span class="badge ok">Published</span>' : '<span class="badge muted">Draft</span>';
        return '<tr><td>' + escHtml(e.title) + '</td><td>' + escHtml(e.subject) + '</td>' +
          '<td><span class="badge ok">' + escHtml(e.exam_type) + '</span></td><td>' + e.total_questions + '</td><td>' + pub + '</td>' +
          '<td class="actions">' +
          '<button class="btn-sm" onclick="openCbtExamEdit(\'' + e.id + '\')">Edit questions &amp; images</button>' +
          '<button class="btn-sm" onclick="toggleCbtPublish(\'' + e.id + '\')">Toggle publish</button>' +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function createCbt() {
  var err = document.getElementById("cbt-form-error");
  var btn = document.getElementById("btn-create-cbt");
  if (!err || !btn) return;
  err.textContent = "";
  syncAllQuestions();

  var title = (document.getElementById("cbt-title") || {}).value || "";
  var subject = (document.getElementById("cbt-subject") || {}).value || "";
  title = String(title).trim();
  subject = String(subject).trim();
  if (!title) {
    err.textContent = "Enter an exam title.";
    return;
  }
  if (!subject) {
    err.textContent = "Pick a subject.";
    return;
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
    exam_type: (document.getElementById("cbt-type") || {}).value || "JAMB",
    duration_minutes: parseInt((document.getElementById("cbt-duration") || {}).value, 10) || 30,
    is_school_exam: false,
    paper_kind: "cbt_practice",
    is_published: !!(document.getElementById("cbt-publish") || {}).checked,
    questions: questions,
  };

  btn.disabled = true;
  btn.textContent = "Creating…";
  try {
    await adminApi("/api/v1/admin/cbt/exams", { method: "POST", body: JSON.stringify(body) });
    document.getElementById("cbt-title").value = "";
    document.getElementById("cbt-subject").value = "";
    cbtQuestions = [emptyQuestion()];
    renderCbtQuestions();
    err.textContent = "";
    alert("Practice CBT created!");
    loadCbt();
  } catch (e) {
    err.textContent = e.message;
  } finally {
    btn.disabled = false;
    btn.textContent = "Create practice exam";
  }
}

async function toggleCbtPublish(id) {
  try {
    await adminApi("/api/v1/admin/cbt/exams/" + id + "/publish", { method: "PATCH" });
    if (currentAdminPage === "past-questions") loadPastQuestionsAdmin();
    else loadCbt();
  } catch (e) { alert(e.message); }
}

async function deleteCbt(id) {
  if (!confirm("Delete this exam permanently?")) return;
  try {
    await adminApi("/api/v1/admin/cbt/exams/" + id, { method: "DELETE" });
    if (currentAdminPage === "past-questions") loadPastQuestionsAdmin();
    else loadCbt();
  } catch (e) { alert(e.message); }
}

async function deleteAllCbt() {
  if (!confirm("Delete ALL CBT exams permanently? This cannot be undone.")) return;
  if (!confirm("Are you sure? Every practice and school exam will be removed.")) return;
  try {
    var r = await adminApi("/api/v1/admin/cbt/exams", { method: "DELETE", timeout: 180000 });
    alert("Deleted " + ((r && r.deleted_count) || 0) + " exam(s).");
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
  cbtMode = "practice";
  return importPaperFile({
    prefix: "cbt",
    paperKind: "cbt_practice",
    btnLabel: "Upload & create exam(s)",
    afterSave: loadCbt,
  });
}

async function importPastQuestionsFile() {
  cbtMode = "past";
  return importPaperFile({
    prefix: "pq",
    paperKind: "past_questions",
    btnLabel: "Upload & create paper(s)",
    afterSave: loadPastQuestionsAdmin,
  });
}

async function importPaperFile(opts) {
  var prefix = opts.prefix;
  var err = document.getElementById(prefix + "-import-error");
  var ok = document.getElementById(prefix + "-import-success");
  var btn = document.getElementById(prefix === "pq" ? "btn-import-pq" : "btn-import-cbt");
  var input = document.getElementById(prefix + "-import-file");
  if (err) err.textContent = "";
  if (ok) ok.textContent = "";

  if (!input || !input.files || !input.files[0]) {
    if (err) err.textContent = "Choose a .json, .csv, .pdf, or .docx file first.";
    return;
  }

  var file = input.files[0];
  var fields = {
    title: (document.getElementById(prefix + "-import-title") || {}).value || "",
    subject: (document.getElementById(prefix + "-import-subject") || {}).value || "",
    year: "",
    exam_type: (document.getElementById(prefix + "-import-type") || {}).value || "JAMB",
    duration_minutes: parseInt((document.getElementById(prefix + "-import-duration") || {}).value, 10) || 60,
    is_published: !!(document.getElementById(prefix + "-import-publish") || {}).checked,
    skip_duplicates: !!(document.getElementById(prefix + "-import-skip-dup") || {}).checked,
    paper_kind: opts.paperKind,
  };
  fields.title = String(fields.title).trim();
  fields.subject = String(fields.subject).trim();

  if (!fields.subject) {
    if (err) err.textContent = "Pick a subject so students can find this exam.";
    return;
  }
  if (!fields.title) {
    fields.title = fields.exam_type + " " + fields.subject;
  }

  var needsPreview = /\.(pdf|docx)$/i.test(file.name || "");
  if (needsPreview) {
    if (btn) { btn.disabled = true; btn.textContent = "Extracting questions…"; }
    try {
      var preview = await previewCbtFile(file);
      if (!preview) return;
      renderPaperPreview(prefix, preview);
      if (ok) ok.textContent = "Review the extracted questions below, then click Confirm & save.";
    } catch (e) {
      if (err) err.textContent = e.message;
    } finally {
      if (btn) { btn.disabled = false; btn.textContent = opts.btnLabel; }
    }
    return;
  }

  if (btn) { btn.disabled = true; btn.textContent = "Uploading…"; }
  try {
    var r = await uploadCbtExamFile(file, fields);
    if (!r) return;
    var lines = [];
    if (r.created_count) {
      lines.push("Created " + r.created_count + " exam(s) for " + fields.subject + ":");
      (r.created || []).forEach(function (e) {
        lines.push("• " + e.title + " (" + e.total_questions + " questions)");
      });
    }
    if (r.skipped_count) {
      lines.push("Skipped " + r.skipped_count + " duplicate title(s).");
    }
    if (ok) ok.textContent = lines.join(" ");
    input.value = "";
    if (opts.afterSave) opts.afterSave();
  } catch (e) {
    if (err) err.textContent = e.message;
  } finally {
    if (btn) { btn.disabled = false; btn.textContent = opts.btnLabel; }
  }
}

async function downloadCbtTemplate() {
  try {
    await downloadCbtImportTemplate();
  } catch (e) {
    alert(e.message);
  }
}

/* ── PDF import preview / confirm ── */
var cbtPreviewData = null;
var cbtPreviewPrefix = "cbt";

function renderCbtPreview(preview) {
  renderPaperPreview("cbt", preview);
}

function renderPaperPreview(prefix, preview) {
  cbtPreviewData = preview;
  cbtPreviewPrefix = prefix || "cbt";
  var panel = document.getElementById(prefix + "-preview-panel");
  var list = document.getElementById(prefix + "-preview-list");
  var summary = document.getElementById(prefix + "-preview-summary");
  var warnBox = document.getElementById(prefix + "-preview-warnings");
  var errEl = document.getElementById(prefix + "-preview-error");
  if (errEl) errEl.textContent = "";

  var lowConf = preview.low_confidence_count || 0;
  if (summary) {
    summary.textContent = preview.total_questions + " question(s) extracted" +
      (preview.answer_key_found ? " (answer key found)" : " (no answer key found)") +
      (lowConf ? " — " + lowConf + " need review" : "");
  }

  if (warnBox) {
    warnBox.innerHTML = (preview.warnings || []).map(function (w) {
      return '<p class="cbt-hint small" style="color:#c47f17">&#9888; ' + escHtml(w) + '</p>';
    }).join("");
  }

  var threshold = preview.low_confidence_threshold || 0;
  var idPrefix = prefix + "-pv";
  if (list) {
    list.innerHTML = (preview.questions || []).map(function (q, i) {
      var flagged = (q.confidence != null && q.confidence < threshold) || (q.issues || []).length > 0;
      var issues = (q.issues || []).map(function (s) {
        return '<p class="cbt-hint small" style="color:#c47f17;margin:2px 0">&#9888; ' + escHtml(s) + '</p>';
      }).join("");
      var optSel = ["", "A", "B", "C", "D"].map(function (o) {
        var label = o || "— pick answer —";
        var sel = (q.correct_option || "") === o ? " selected" : "";
        return '<option value="' + o + '"' + sel + ">" + label + "</option>";
      }).join("");
      return '<div class="panel" style="margin:10px 0;padding:12px;' +
        (flagged ? "border:1px solid #e8a33d" : "") + '" id="' + idPrefix + '-q-' + i + '">' +
        '<div class="form-row" style="justify-content:space-between;align-items:center">' +
          '<label class="chk-label"><input type="checkbox" id="' + idPrefix + '-inc-' + i + '" checked /> ' +
          "Question " + escHtml(String(q.number || i + 1)) +
          (q.confidence != null ? ' <span class="cbt-hint small">(confidence ' + Math.round(q.confidence * 100) + "%)</span>" : "") +
          "</label>" +
        "</div>" +
        issues +
        '<label><span>Question</span><textarea id="' + idPrefix + '-text-' + i + '" rows="2" style="width:100%">' + escHtml(q.question_text) + "</textarea></label>" +
        '<div class="form-grid">' +
          '<label><span>Option A</span><input id="' + idPrefix + '-a-' + i + '" value="' + escHtml(q.option_a) + '" /></label>' +
          '<label><span>Option B</span><input id="' + idPrefix + '-b-' + i + '" value="' + escHtml(q.option_b) + '" /></label>' +
          '<label><span>Option C</span><input id="' + idPrefix + '-c-' + i + '" value="' + escHtml(q.option_c) + '" /></label>' +
          '<label><span>Option D</span><input id="' + idPrefix + '-d-' + i + '" value="' + escHtml(q.option_d) + '" /></label>' +
          '<label><span>Correct option</span><select id="' + idPrefix + '-ans-' + i + '">' + optSel + "</select></label>" +
        "</div>" +
      "</div>";
    }).join("");
  }

  if (panel) {
    panel.style.display = "";
    panel.scrollIntoView({ behavior: "smooth", block: "start" });
  }
}

function cancelCbtPreview() {
  cancelPaperPreview("cbt");
}

function cancelPastPreview() {
  cancelPaperPreview("pq");
}

function cancelPaperPreview(prefix) {
  cbtPreviewData = null;
  var panel = document.getElementById(prefix + "-preview-panel");
  var list = document.getElementById(prefix + "-preview-list");
  if (panel) panel.style.display = "none";
  if (list) list.innerHTML = "";
}

async function confirmCbtPreviewUi() {
  return confirmPaperPreviewUi("cbt", "cbt_practice", loadCbt);
}

async function confirmPastPreviewUi() {
  return confirmPaperPreviewUi("pq", "past_questions", loadPastQuestionsAdmin);
}

async function confirmPaperPreviewUi(prefix, paperKind, afterSave) {
  if (!cbtPreviewData) return;
  var err = document.getElementById(prefix + "-preview-error");
  var btn = document.getElementById(prefix === "pq" ? "btn-confirm-pq-preview" : "btn-confirm-cbt-preview");
  if (err) err.textContent = "";

  var subject = ((document.getElementById(prefix + "-import-subject") || {}).value || "").trim();
  var examType = (document.getElementById(prefix + "-import-type") || {}).value || "JAMB";
  var title = ((document.getElementById(prefix + "-import-title") || {}).value || "").trim() ||
    (examType + " " + subject);
  if (!subject) {
    if (err) err.textContent = "Pick a subject in the upload form above.";
    return;
  }

  var threshold = cbtPreviewData.low_confidence_threshold || 0;
  var questions = [];
  var idPrefix = prefix + "-pv";
  for (var i = 0; i < cbtPreviewData.questions.length; i++) {
    var inc = document.getElementById(idPrefix + "-inc-" + i);
    if (!inc || !inc.checked) continue;
    var orig = cbtPreviewData.questions[i];
    var q = {
      question_text: document.getElementById(idPrefix + "-text-" + i).value.trim(),
      option_a: document.getElementById(idPrefix + "-a-" + i).value.trim(),
      option_b: document.getElementById(idPrefix + "-b-" + i).value.trim(),
      option_c: document.getElementById(idPrefix + "-c-" + i).value.trim(),
      option_d: document.getElementById(idPrefix + "-d-" + i).value.trim(),
      correct_option: document.getElementById(idPrefix + "-ans-" + i).value,
    };
    if (!q.question_text || !q.option_a || !q.option_b || !q.option_c || !q.option_d || !q.correct_option) {
      if (err) {
        err.textContent = "Question " + (orig.number || i + 1) +
          " is incomplete — fill in the text, all four options, and the correct answer (or untick it).";
      }
      return;
    }
    var edited = q.question_text !== (orig.question_text || "").trim() ||
      q.correct_option !== (orig.correct_option || "");
    if (orig.confidence != null && orig.confidence < threshold && !edited) {
      q.confidence = orig.confidence;
    }
    questions.push(q);
  }
  if (!questions.length) {
    if (err) err.textContent = "Keep at least one question ticked.";
    return;
  }

  var payload = {
    title: title,
    subject: subject,
    year: null,
    exam_type: examType,
    duration_minutes: parseInt((document.getElementById(prefix + "-import-duration") || {}).value, 10) || 60,
    is_published: !!(document.getElementById(prefix + "-import-publish") || {}).checked,
    skip_duplicates: !!(document.getElementById(prefix + "-import-skip-dup") || {}).checked,
    paper_kind: paperKind,
    questions: questions,
  };

  if (btn) { btn.disabled = true; btn.textContent = "Saving…"; }
  try {
    var r = await confirmCbtImport(payload);
    if (!r) return;
    var msg = "Created \"" + r.title + "\" with " + r.total_questions + " question(s)." +
      (r.is_published ? "" : " Saved unpublished.");
    if (r.note) msg += " " + r.note;
    var ok = document.getElementById(prefix + "-import-success");
    if (ok) ok.textContent = msg;
    var fileInput = document.getElementById(prefix + "-import-file");
    if (fileInput) fileInput.value = "";
    cancelPaperPreview(prefix);
    if (afterSave) afterSave();
  } catch (e) {
    if (err) err.textContent = e.message;
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = prefix === "pq" ? "Confirm & save paper" : "Confirm & save exam";
    }
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

/* ── Student group management ── */
var sgGroupsCache = [];
var sgSearchTimer = null;

function debounceStudentGroupsSearch() {
  if (sgSearchTimer) clearTimeout(sgSearchTimer);
  sgSearchTimer = setTimeout(loadStudentGroupsAdmin, 300);
}

function renderStudentGroupsTable(rows) {
  var el = document.getElementById("student-groups-table");
  if (!el) return;
  if (!rows || !rows.length) {
    el.innerHTML = '<div class="empty-state">No groups match this filter.</div>';
    return;
  }
  el.innerHTML =
    '<table class="data-table"><thead><tr><th>Group</th><th>Creator</th><th>Status</th><th>Members</th><th>Listed?</th><th>Created</th><th>Actions</th></tr></thead><tbody>' +
    rows.map(function (g) {
      var status = g.is_approved
        ? '<span style="color:#15803d;font-weight:700">Approved</span>'
        : '<span style="color:#b45309;font-weight:700">Pending</span>';
      if (g.is_restricted) status += '<br><span style="color:#b91c1c;font-weight:700">Restricted</span>';
      var actions =
        '<button class="btn-sm" onclick="viewGroupChat(\'' + g.id + '\', ' + JSON.stringify(g.name || "Group") + ')">View chat</button> ';
      if (!g.is_approved) {
        actions +=
          '<button class="btn-sm primary" onclick="approveStudentGroup(\'' + g.id + '\')">Approve</button> ' +
          '<button class="btn-sm" onclick="rejectStudentGroup(\'' + g.id + '\')">Reject</button> ';
      }
      actions += g.is_restricted
        ? '<button class="btn-sm primary" onclick="restrictStudentGroup(\'' + g.id + '\', false)">Unrestrict</button> '
        : '<button class="btn-sm" onclick="restrictStudentGroup(\'' + g.id + '\', true)">Restrict</button> ';
      actions += '<button class="btn-sm danger" onclick="deleteStudentGroup(\'' + g.id + '\', ' + JSON.stringify(g.name || "Group") + ')">Delete</button>';
      return (
        '<tr><td><strong>' + escHtml(g.name) + '</strong><br><span style="font-size:.8rem;color:#8aa896">' +
        escHtml(g.description || "") + '</span></td>' +
        '<td>' + escHtml(g.creator_name) + '<br><span style="font-size:.75rem;color:#6b8f75">' + escHtml(g.creator_email) + '</span></td>' +
        '<td>' + status + '</td>' +
        '<td>' + (g.member_count || 0) + '</td>' +
        '<td>' + (g.is_community_listed ? "Yes" : "No") + '</td>' +
        '<td>' + fmtDate(g.created_at) + '</td>' +
        '<td class="actions">' + actions + '</td></tr>'
      );
    }).join("") +
    "</tbody></table>";
}

async function adminCreateStudentGroup() {
  var msg = document.getElementById("sg-create-msg");
  var nameEl = document.getElementById("sg-create-name");
  var descEl = document.getElementById("sg-create-desc");
  var name = ((nameEl && nameEl.value) || "").trim();
  var desc = ((descEl && descEl.value) || "").trim();
  if (msg) msg.textContent = "";
  try {
    await adminApi("/api/v1/admin/student-groups", {
      method: "POST",
      body: JSON.stringify({ name: name, description: desc, is_public: true, is_community_listed: true }),
    });
    if (nameEl) nameEl.value = "";
    if (descEl) descEl.value = "";
    if (msg) msg.textContent = "Group created and listed for students.";
    loadStudentGroupsAdmin();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function restrictStudentGroup(id, restricted) {
  try {
    await adminApi("/api/v1/admin/student-groups/" + id + "/restrict?restricted=" + (restricted ? "true" : "false"), { method: "POST" });
    loadStudentGroupsAdmin();
  } catch (e) { alert(e.message); }
}

async function loadStudentGroupsAdmin() {
  var el = document.getElementById("student-groups-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var status = ((document.getElementById("sg-filter") || {}).value || "all").trim();
    var q = ((document.getElementById("sg-search") || {}).value || "").trim();
    var url = "/api/v1/admin/student-groups?status=" + encodeURIComponent(status);
    if (q) url += "&q=" + encodeURIComponent(q);
    var rows = await adminApi(url);
    sgGroupsCache = Array.isArray(rows) ? rows : [];
    renderStudentGroupsTable(sgGroupsCache);
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
  }
}

async function loadPendingStudentGroups() {
  var filter = document.getElementById("sg-filter");
  if (filter) filter.value = "pending";
  return loadStudentGroupsAdmin();
}

function closeGroupChatPanel() {
  var panel = document.getElementById("sg-chat-panel");
  if (panel) panel.style.display = "none";
  var msgs = document.getElementById("sg-chat-messages");
  if (msgs) msgs.innerHTML = "";
  var mem = document.getElementById("sg-members-wrap");
  if (mem) mem.innerHTML = "";
}

async function viewGroupChat(id, name) {
  if (!id) return;
  var panel = document.getElementById("sg-chat-panel");
  var title = document.getElementById("sg-chat-title");
  var msgs = document.getElementById("sg-chat-messages");
  var memWrap = document.getElementById("sg-members-wrap");
  if (title) title.textContent = "Chat — " + (name || "Group");
  if (panel) panel.style.display = "block";
  if (msgs) msgs.innerHTML = '<div class="loading">Loading chat…</div>';
  if (memWrap) memWrap.innerHTML = "";
  if (panel) panel.scrollIntoView({ behavior: "smooth", block: "start" });
  try {
    var members = await adminApi("/api/v1/admin/student-groups/" + id + "/members");
    if (memWrap && Array.isArray(members) && members.length) {
      memWrap.innerHTML =
        "<strong>Members (" + members.length + "):</strong> " +
        members.map(function (m) {
          return escHtml(m.name || m.email) + (m.role === "admin" ? " (admin)" : "");
        }).join(", ");
    }
    var data = await adminApi("/api/v1/admin/student-groups/" + id + "/messages?limit=300");
    var list = (data && data.messages) || [];
    if (!msgs) return;
    if (!list.length) {
      msgs.innerHTML = '<div class="empty-state">No chat messages in this group yet.</div>';
      return;
    }
    msgs.innerHTML = list
      .map(function (m) {
        return (
          '<article class="sg-chat-msg"><div class="sg-chat-meta"><strong>' +
          escHtml(m.author_name || "User") +
          '</strong><span>' +
          escHtml(m.author_email || "") +
          " · " +
          fmtDate(m.created_at) +
          '</span></div><div class="sg-chat-body">' +
          escHtml(m.content || "") +
          "</div></article>"
        );
      })
      .join("");
    msgs.scrollTop = msgs.scrollHeight;
  } catch (e) {
    if (msgs) msgs.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function approveStudentGroup(id) {
  if (!confirm("Approve this group? The creator and members can chat once approved.")) return;
  try {
    var res = await adminApi("/api/v1/admin/student-groups/" + id + "/approve", { method: "POST" });
    alert((res && res.message) || "Group approved.");
    loadStudentGroupsAdmin();
  } catch (e) {
    alert(e.message);
  }
}

async function rejectStudentGroup(id) {
  if (!confirm("Reject this group? It will stay inactive (not deleted).")) return;
  try {
    var res = await adminApi("/api/v1/admin/student-groups/" + id + "/reject", { method: "POST" });
    alert((res && res.message) || "Group rejected.");
    loadStudentGroupsAdmin();
  } catch (e) {
    alert(e.message);
  }
}

async function deleteStudentGroup(id, name) {
  if (!confirm('Delete group "' + (name || "this group") + '" permanently? All chat and members will be removed.')) return;
  try {
    var res = await adminApi("/api/v1/admin/student-groups/" + id, { method: "DELETE" });
    alert((res && res.message) || "Group deleted.");
    closeGroupChatPanel();
    loadStudentGroupsAdmin();
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

async function clearAllConversations() {
  if (!confirm("Clear ALL conversations? This removes every announcement, community message/post, group chat, and deletes all student groups from Discover.")) return;
  if (!confirm("Are you sure? This cannot be undone.")) return;
  try {
    var r = await adminApi("/api/v1/admin/community/conversations", { method: "DELETE", timeout: 180000 });
    alert(
      "Cleared " + ((r && r.community_posts_deleted) || 0) + " post(s)/announcement(s), " +
      ((r && r.community_messages_deleted) || 0) + " message(s), " +
      ((r && r.group_messages_deleted) || 0) + " group chat message(s), and " +
      ((r && r.groups_deleted) || 0) + " group(s)."
    );
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
            b.status === "pending" || b.status === "paid"
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

function isMarketplaceDigitalCategory(category) {
  return category === "soft_copy" || category === "software";
}

function syncMarketplaceFileFields() {
  var sel = document.getElementById("mp-category");
  var pdfWrap = document.getElementById("mp-pdf-wrap");
  var imageLabel = document.getElementById("mp-image-label");
  var digital = sel && isMarketplaceDigitalCategory(sel.value);
  if (pdfWrap) pdfWrap.classList.toggle("hidden", !digital);
  if (imageLabel) {
    var span = imageLabel.querySelector("span");
    if (span) span.textContent = digital ? "Cover image (optional)" : "Product image *";
  }
  if (!digital) {
    var pdfInput = document.getElementById("mp-pdf-file");
    var pdfName = document.getElementById("mp-pdf-name");
    if (pdfInput) pdfInput.value = "";
    if (pdfName) {
      pdfName.textContent = "";
      pdfName.classList.add("hidden");
    }
  }
}

function previewMarketplacePdf(input) {
  var nameEl = document.getElementById("mp-pdf-name");
  if (!nameEl) return;
  var file = input && input.files && input.files[0];
  if (!file) {
    nameEl.textContent = "";
    nameEl.classList.add("hidden");
    return;
  }
  nameEl.textContent = "Selected: " + file.name;
  nameEl.classList.remove("hidden");
}

function buildMarketplaceDescription(text, meta) {
  var clean = String(text || "").trim();
  if (!meta) return clean || null;
  return (clean ? clean + "\n\n" : "") + "---\nSIA_META:" + JSON.stringify(meta);
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
  var pdfInput = document.getElementById("mp-pdf-file");
  var digital = isMarketplaceDigitalCategory(category);
  if (!title) {
    msg.textContent = "Title is required.";
    return;
  }
  var hasFile = fileInput && fileInput.files && fileInput.files[0];
  var hasPdf = pdfInput && pdfInput.files && pdfInput.files[0];
  if (digital && !hasPdf) {
    msg.textContent = "Upload a PDF (or ZIP) for this soft copy.";
    return;
  }
  if (!digital && !hasFile && !image) {
    msg.textContent = "Add a product image (file or URL).";
    return;
  }
  msg.textContent = "Saving…";
  try {
    var digitalUrl = "";
    var digitalName = "";
    if (hasPdf) {
      msg.textContent = "Uploading PDF…";
      var pdfUp = await uploadMarketplaceFile(pdfInput.files[0]);
      if (!pdfUp) return;
      digitalUrl = (pdfUp.file_url || pdfUp.image_url || pdfUp.secure_url || "").trim();
      digitalName = pdfUp.filename || pdfInput.files[0].name || "file.pdf";
      if (!digitalUrl) {
        msg.textContent = "PDF upload failed — try again.";
        return;
      }
    }
    if (hasFile) {
      msg.textContent = "Uploading image…";
      var up = await uploadMarketplaceImage(fileInput.files[0]);
      if (!up) return;
      image = (up.image_url || up.secure_url || image || "").trim();
    }
    if (!digital && !image) {
      msg.textContent = "Image upload failed — try again or paste a URL.";
      return;
    }
    var meta = digital
      ? {
          product_type: "digital",
          digital_url: digitalUrl,
          digital_name: digitalName,
          images: image ? [image] : [],
        }
      : null;
    var created = await adminApi("/api/v1/admin/marketplace/products", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        category: category,
        price: price,
        description: buildMarketplaceDescription(desc, meta),
        image_url: image || null,
        currency: "NGN",
        is_available: true,
        is_free: !!(document.getElementById("mp-free") && document.getElementById("mp-free").checked) || price <= 0,
      }),
    });
    if (!created) {
      msg.textContent = "Could not save product.";
      return;
    }
    if (!digital && !(created.image_url || image)) {
      msg.textContent = "Product saved but image URL missing — re-upload the photo.";
      loadMarketplaceProducts();
      return;
    }
    document.getElementById("mp-title").value = "";
    document.getElementById("mp-price").value = "";
    document.getElementById("mp-image").value = "";
    document.getElementById("mp-desc").value = "";
    if (fileInput) fileInput.value = "";
    if (pdfInput) pdfInput.value = "";
    var pdfName = document.getElementById("mp-pdf-name");
    if (pdfName) {
      pdfName.textContent = "";
      pdfName.classList.add("hidden");
    }
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
    msg.textContent = digital
      ? "Soft copy posted — it should appear in the student Marketplace now."
      : "Product posted with image — it should appear in the student Marketplace now.";
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
var librarySearchTimer = null;
var kindLibrarySearchTimer = null;
var kindVideosSearchTimer = null;

function onLibraryAdminSearchInput() {
  clearTimeout(librarySearchTimer);
  librarySearchTimer = setTimeout(loadLibraryAdmin, 300);
}

function onKindLibrarySearchInput() {
  clearTimeout(kindLibrarySearchTimer);
  kindLibrarySearchTimer = setTimeout(loadKindLibraryAdmin, 300);
}

function onKindVideosSearchInput() {
  clearTimeout(kindVideosSearchTimer);
  kindVideosSearchTimer = setTimeout(loadKindVideosAdmin, 300);
}

function renderLibraryAdminTable(el, rows, reloadFn) {
  if (!el) return;
  if (!rows || !rows.length) {
    el.innerHTML = '<div class="empty-state">No materials match your search.</div>';
    return;
  }
  el.innerHTML =
    '<table class="data-table"><thead><tr><th>Title</th><th>Audience</th><th>Type</th><th>Subject</th><th>Board</th><th>Access</th><th>Download</th><th></th></tr></thead><tbody>' +
    rows.map(function (b) {
      var access = b.is_free ? "Free" : "₦" + Number(b.price || 0).toLocaleString();
      var dl = !!b.is_downloadable;
      var aud = (b.library_target && (b.library_target.value || b.library_target)) || "student";
      return "<tr><td>" + escHtml(b.title) + "</td><td>" + escHtml(String(aud)) + "</td><td>" + escHtml(b.category || "Books") +
        "</td><td>" + escHtml(b.subject || "—") +
        "</td><td>" + escHtml(b.exam_type || "—") + "</td><td>" + escHtml(access) +
        '</td><td><span class="badge ' + (dl ? "ok" : "muted") + '">' + (dl ? "Downloadable" : "Read only") +
        '</span></td><td class="actions"><button class="btn-sm" onclick=\'changeLibraryCategory(' +
        JSON.stringify(String(b.id)) +
        ", " +
        JSON.stringify(String(b.category || "Books")) +
        ")\'>Change type</button> <button class=\"btn-sm\" onclick=\"toggleLibraryDownloadable('" +
        b.id + "', " + (dl ? "true" : "false") + ')">' +
        (dl ? "Make read-only" : "Allow download") +
        '</button> <button class="btn-sm" onclick="replaceLibraryPdf(\'' +
        b.id +
        "')\">Replace PDF</button> <button class=\"btn-sm danger\" onclick=\"deleteLibraryBook('" +
        b.id + "')\">Remove</button></td></tr>";
    }).join("") +
    "</tbody></table>";
}

async function loadLibraryAdmin() {
  var el = document.getElementById("library-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var target = (document.getElementById("lib-target-filter") || {}).value || "student";
    var q = ((document.getElementById("lib-search") || {}).value || "").trim();
    var path = "/api/v1/admin/library/books?library_target=" + encodeURIComponent(target);
    if (q) path += "&q=" + encodeURIComponent(q);
    var rows = await adminApi(path);
    renderLibraryAdminTable(el, rows, loadLibraryAdmin);
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadKindLibraryAdmin() {
  var el = document.getElementById("kind-library-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var q = ((document.getElementById("klib-search") || {}).value || "").trim();
    var path = "/api/v1/admin/library/books?library_target=kind";
    if (q) path += "&q=" + encodeURIComponent(q);
    var rows = await adminApi(path);
    renderLibraryAdminTable(el, rows, loadKindLibraryAdmin);
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function uploadKindLibraryBook() {
  var err = document.getElementById("klib-form-error");
  var ok = document.getElementById("klib-form-ok");
  if (err) err.textContent = "";
  if (ok) ok.textContent = "";
  var title = ((document.getElementById("klib-title") || {}).value || "").trim();
  var subject = ((document.getElementById("klib-subject") || {}).value || "").trim();
  var category = (document.getElementById("klib-category") || {}).value || "Books";
  var level = (document.getElementById("klib-level") || {}).value || "";
  var desc = ((document.getElementById("klib-desc") || {}).value || "").trim();
  var fileInput = document.getElementById("klib-file");
  var file = fileInput && fileInput.files && fileInput.files[0];
  var isFree = (document.getElementById("klib-access") || {}).value !== "paid";
  var price = Number((document.getElementById("klib-price") || {}).value || 0);
  if (!title || !subject) {
    if (err) err.textContent = "Title and subject are required.";
    return;
  }
  if (!file) {
    if (err) err.textContent = "Choose a PDF file.";
    return;
  }
  try {
    var up = await uploadLibraryPdf(file);
    if (!up || !up.file_key) throw new Error("Upload did not return a file key.");
    await adminApi("/api/v1/admin/library/books", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        subject: subject,
        file_key: up.file_key,
        description: desc || null,
        category: category,
        education_level: level || null,
        library_target: "kind",
        is_free: isFree,
        price: isFree ? 0 : price,
        is_downloadable: true,
      }),
    });
    if (fileInput) fileInput.value = "";
    if (ok) ok.textContent = "Uploaded to Kids Library.";
    loadKindLibraryAdmin();
  } catch (e) {
    if (err) err.textContent = e.message || "Upload failed.";
  }
}

function onLibraryCategoryChange() {
  var cat = (document.getElementById("lib-category") || {}).value || "";
  if (/past/i.test(cat)) {
    var access = document.getElementById("lib-access");
    if (access) access.value = "paid";
    if (typeof toggleLibraryPrice === "function") toggleLibraryPrice();
  }
}

function toggleLibraryPrice() {
  var paid = document.getElementById("lib-access").value === "paid";
  document.getElementById("lib-price-wrap").style.display = paid ? "" : "none";
}

function onLibraryPdfPicked(input) {
  var nameEl = document.getElementById("lib-file-name");
  var err = document.getElementById("lib-form-error");
  var titleEl = document.getElementById("lib-title");
  var file = input && input.files && input.files[0];
  if (!file) {
    if (nameEl) nameEl.textContent = "Choose a .pdf (not a photo).";
    return;
  }
  var name = (file.name || "").toLowerCase();
  var type = (file.type || "").toLowerCase();
  var isPdf = name.endsWith(".pdf") || type === "application/pdf" || type === "application/x-pdf";
  if (!isPdf) {
    input.value = "";
    if (nameEl) nameEl.textContent = "Choose a .pdf (not a photo).";
    if (err) err.textContent = "Library needs a PDF file, not an image.";
    return;
  }
  if (err) err.textContent = "";
  if (nameEl) nameEl.textContent = "Selected: " + file.name;
  // Auto-fill title from filename when Title is still empty
  if (titleEl && !String(titleEl.value || "").trim()) {
    titleEl.value = String(file.name || "")
      .replace(/\.pdf$/i, "")
      .replace(/[_]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
  }
}

function showLibraryFormMsg(kind, text) {
  var err = document.getElementById("lib-form-error");
  var ok = document.getElementById("lib-form-ok");
  if (err) err.textContent = kind === "err" ? text || "" : "";
  if (ok) ok.textContent = kind === "ok" ? text || "" : "";
  var el = kind === "ok" ? ok : err;
  try {
    if (el && el.scrollIntoView) el.scrollIntoView({ behavior: "smooth", block: "nearest" });
  } catch (e0) {}
}

async function uploadLibraryBook() {
  var err = document.getElementById("lib-form-error");
  var ok = document.getElementById("lib-form-ok");
  var btn = document.getElementById("btn-lib-upload");
  var nameEl = document.getElementById("lib-file-name");
  if (err) err.textContent = "";
  if (ok) ok.textContent = "";
  var titleEl = document.getElementById("lib-title");
  var title = (titleEl && titleEl.value || "").trim();
  var subject = document.getElementById("lib-subject").value.trim();
  var exam = document.getElementById("lib-exam").value;
  var author = document.getElementById("lib-author").value.trim();
  var desc = document.getElementById("lib-desc").value.trim();
  var category = document.getElementById("lib-category").value;
  var level = document.getElementById("lib-level").value;
  var term = document.getElementById("lib-term").value;
  var week = Number(document.getElementById("lib-week").value || 0);
  var topic = document.getElementById("lib-topic").value.trim();
  var isFree = document.getElementById("lib-access").value === "free";
  var price = Number(document.getElementById("lib-price").value || 0);
  var isDownloadable = (document.getElementById("lib-downloadable") || {}).value === "yes";
  var fileInput = document.getElementById("lib-file");
  var file = fileInput && fileInput.files && fileInput.files[0];

  if (!file) {
    showLibraryFormMsg("err", "Choose a PDF file again (the file box is empty).");
    if (nameEl) nameEl.textContent = "Choose a .pdf (not a photo).";
    return;
  }
  if (!title) {
    title = String(file.name || "")
      .replace(/\.pdf$/i, "")
      .replace(/[_]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (titleEl) titleEl.value = title;
  }
  if (!title || !subject) {
    showLibraryFormMsg("err", "Title and subject are required.");
    return;
  }
  if (!category) {
    showLibraryFormMsg("err", "Choose Material type (e.g. Lesson Notes).");
    return;
  }
  if (!exam) {
    showLibraryFormMsg("err", "Choose Class / level (e.g. SS2).");
    return;
  }
  var pdfName = (file.name || "").toLowerCase();
  var pdfType = (file.type || "").toLowerCase();
  if (!pdfName.endsWith(".pdf") && pdfType !== "application/pdf" && pdfType !== "application/x-pdf") {
    showLibraryFormMsg("err", "Library needs a PDF file, not an image.");
    return;
  }
  if (category === "Past Questions") {
    isFree = false;
    if (price <= 0) {
      showLibraryFormMsg("err", "Past Questions must be paid. Enter a price greater than zero.");
      return;
    }
  }
  if (!isFree && price <= 0) {
    showLibraryFormMsg("err", "Enter a price greater than zero.");
    return;
  }
  btn.disabled = true;
  btn.textContent = "Uploading…";
  try {
    var up = await uploadLibraryPdf(file);
    if (!up || !up.file_key) throw new Error("Upload did not return a file key.");
    var created = await adminApi("/api/v1/admin/library/books", {
      method: "POST",
      body: JSON.stringify({
        title: title,
        author: author || null,
        subject: subject,
        exam_type: exam || null,
        file_key: up.file_key,
        description: desc || null,
        category: category,
        education_level: level || null,
        term: term || null,
        scheme_week: week || null,
        scheme_topic: topic || null,
        library_target: "student",
        is_free: isFree,
        price: isFree ? 0 : price,
        is_downloadable: isDownloadable,
      }),
    });
    if (!created || !created.id) {
      throw new Error("Server did not confirm the upload. Try again.");
    }
    document.getElementById("lib-title").value = "";
    document.getElementById("lib-author").value = "";
    document.getElementById("lib-desc").value = "";
    document.getElementById("lib-price").value = "";
    document.getElementById("lib-week").value = "";
    document.getElementById("lib-topic").value = "";
    fileInput.value = "";
    if (nameEl) nameEl.textContent = "Choose a .pdf (not a photo).";
    var dlSel = document.getElementById("lib-downloadable");
    if (dlSel) dlSel.value = "no";
    var catSel = document.getElementById("lib-category");
    if (catSel) catSel.value = category;
    var savedCat = created.category || category;
    var savedTitle = created.title || title;
    showLibraryFormMsg(
      "ok",
      "Saved «" + savedTitle + "» as " + savedCat + ". Refreshing list…"
    );
    await loadLibraryAdmin();
    showLibraryFormMsg(
      "ok",
      "Saved «" +
        savedTitle +
        "» as " +
        savedCat +
        ". Students: Library → filter «" +
        savedCat +
        "»."
    );
  } catch (e) {
    showLibraryFormMsg("err", e.message || "Upload failed.");
  } finally {
    btn.disabled = false;
    btn.textContent = "Upload material";
  }
}

async function replaceLibraryPdf(id) {
  var input = document.createElement("input");
  input.type = "file";
  input.accept = ".pdf,application/pdf";
  input.onchange = async function () {
    var file = input.files && input.files[0];
    if (!file) return;
    var name = (file.name || "").toLowerCase();
    if (!name.endsWith(".pdf") && file.type !== "application/pdf") {
      alert("Choose a PDF file.");
      return;
    }
    try {
      await uploadAdminFile("/api/v1/admin/library/books/" + encodeURIComponent(id) + "/replace-file", file);
      alert("PDF replaced. Students can tap Read again.");
      loadLibraryAdmin();
    } catch (e) {
      alert(e.message || "Could not replace PDF.");
    }
  };
  input.click();
}

async function changeLibraryCategory(id, currentCategory) {
  var next = window.prompt(
    "Set material type:\nLesson Notes\nStudy Materials\nScheme of Work\nBooks",
    currentCategory || "Lesson Notes"
  );
  if (next == null) return;
  next = String(next || "").trim();
  if (!next) return;
  try {
    await adminApi("/api/v1/admin/library/books/" + encodeURIComponent(id), {
      method: "PATCH",
      body: JSON.stringify({ category: next }),
    });
    loadLibraryAdmin();
  } catch (e) {
    alert(e.message || "Could not change type.");
  }
}

async function toggleLibraryDownloadable(id, currentlyDownloadable) {
  try {
    await adminApi("/api/v1/admin/library/books/" + encodeURIComponent(id), {
      method: "PATCH",
      body: JSON.stringify({ is_downloadable: !currentlyDownloadable }),
    });
    loadLibraryAdmin();
  } catch (e) {
    alert(e.message || "Could not update download setting.");
  }
}

async function deleteLibraryBook(id) {
  if (!confirm("Remove this material from the library?")) return;
  try {
    await adminApi("/api/v1/admin/library/books/" + id, { method: "DELETE" });
    loadLibraryAdmin();
  } catch (e) {
    alert(e.message);
  }
}

async function generateCbtCoupons() {
  var msg = document.getElementById("coupon-msg");
  var email = ((document.getElementById("coupon-student-email") || {}).value || "").trim();
  try {
    var body = {
      package_id: document.getElementById("coupon-package").value,
      count: parseInt(document.getElementById("coupon-count").value || "1", 10),
      max_uses: parseInt(document.getElementById("coupon-uses").value || "1", 10),
    };
    if (email) body.student_email = email;
    var data = await adminApi("/api/v1/admin/cbt-coupons", {
      method: "POST",
      body: JSON.stringify(body),
    });
    var codes = ((data && data.coupons) || []).map(function (c) { return c.code; }).join(", ");
    if (msg) msg.textContent = "Created: " + codes;
    loadCbtCoupons();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function loadCbtCoupons() {
  var el = document.getElementById("coupon-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading coupons…</div>';
  try {
    var data = await adminApi("/api/v1/admin/cbt-coupons");
    var rows = (data && data.coupons) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No coupons yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Code</th><th>Package</th><th>Student / Redeemed by</th><th>Used</th><th>Active</th><th></th></tr></thead><tbody>' +
      rows.map(function (c) {
        var who = "";
        if (c.assigned_email) who += "Assigned: " + escHtml(c.assigned_email);
        var red = (c.redeemed_by || []).map(function (r) {
          return escHtml((r.name || "") + (r.email ? (" (" + r.email + ")") : ""));
        }).join("<br>");
        if (red) who += (who ? "<br>" : "") + "Used by: " + red;
        if (!who) who = "—";
        return '<tr><td><strong>' + escHtml(c.code) + '</strong></td><td>' + escHtml(c.package_id) + '</td><td>' +
          who + '</td><td>' +
          escHtml(c.used_count + " / " + c.max_uses) + '</td><td>' + (c.is_active ? "Yes" : "No") +
          '</td><td>' + (c.is_active ? '<button class="btn-sm danger" onclick="deactivateCbtCoupon('' + c.id + '')">Disable</button>' : "") + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function deactivateCbtCoupon(id) {
  try {
    await adminApi("/api/v1/admin/cbt-coupons/" + id + "/deactivate", { method: "POST" });
    loadCbtCoupons();
  } catch (e) { alert(e.message); }
}

async function loadAdminVideos() {
  var el = document.getElementById("videos-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var data = await adminApi("/api/v1/admin/videos?audience=student");
    var rows = (data && data.videos) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No student videos yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Tutor</th><th>URL</th><th></th></tr></thead><tbody>' +
      rows.map(function (v) {
        return '<tr><td>' + escHtml(v.title) + '</td><td>' + escHtml(v.subject) + '</td><td>' + escHtml(v.tutor_name || "—") +
          '</td><td>' + escHtml(v.video_url) +
          '</td><td><button class="btn-sm danger" onclick="deleteAdminVideo(\'' + v.id + '\')">Remove</button></td></tr>';
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadKindVideosAdmin() {
  var el = document.getElementById("kind-videos-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var q = ((document.getElementById("kvid-search") || {}).value || "").trim();
    var path = "/api/v1/admin/videos?audience=kind";
    if (q) path += "&q=" + encodeURIComponent(q);
    var data = await adminApi(path);
    var rows = (data && data.videos) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No kids videos yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Tutor</th><th>URL</th><th></th></tr></thead><tbody>' +
      rows.map(function (v) {
        return '<tr><td>' + escHtml(v.title) + '</td><td>' + escHtml(v.subject) + '</td><td>' + escHtml(v.tutor_name || "—") +
          '</td><td>' + escHtml(v.video_url) +
          '</td><td><button class="btn-sm danger" onclick="deleteAdminVideo(\'' + v.id + '\')">Remove</button></td></tr>';
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function createKindAdminVideo() {
  var msg = document.getElementById("kvid-msg");
  try {
    await adminApi("/api/v1/admin/videos", {
      method: "POST",
      body: JSON.stringify({
        title: (document.getElementById("kvid-title").value || "").trim(),
        subject: (document.getElementById("kvid-subject").value || "General").trim(),
        tutor_name: (document.getElementById("kvid-tutor") && document.getElementById("kvid-tutor").value || "").trim(),
        video_url: (document.getElementById("kvid-url").value || "").trim(),
        audience: "kind",
      }),
    });
    document.getElementById("kvid-title").value = "";
    document.getElementById("kvid-url").value = "";
    if (document.getElementById("kvid-tutor")) document.getElementById("kvid-tutor").value = "";
    if (msg) msg.textContent = "Published to Kids app.";
    loadKindVideosAdmin();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function createAdminVideo() {
  var msg = document.getElementById("vid-msg");
  try {
    await adminApi("/api/v1/admin/videos", {
      method: "POST",
      body: JSON.stringify({
        title: (document.getElementById("vid-title").value || "").trim(),
        subject: (document.getElementById("vid-subject").value || "General").trim(),
        tutor_name: (document.getElementById("vid-tutor") && document.getElementById("vid-tutor").value || "").trim(),
        video_url: (document.getElementById("vid-url").value || "").trim(),
        audience: "student",
      }),
    });
    document.getElementById("vid-title").value = "";
    document.getElementById("vid-url").value = "";
    if (document.getElementById("vid-tutor")) document.getElementById("vid-tutor").value = "";
    if (msg) msg.textContent = "Published to student Video Tutorials.";
    loadAdminVideos();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function deleteAdminVideo(id) {
  if (!confirm("Remove this video tutorial?")) return;
  try {
    await adminApi("/api/v1/admin/videos/" + id, { method: "DELETE" });
    loadAdminVideos();
  } catch (e) { alert(e.message); }
}

function selectedSchoolId() {
  var el = document.getElementById("so-school-id");
  return (el && el.value) || localStorage.getItem("sia_school_id") || "";
}

function schoolOfficeQuery(extra) {
  var parts = [];
  var sid = selectedSchoolId();
  if (sid) parts.push("school_id=" + encodeURIComponent(sid));
  if (extra) parts.push(extra);
  return parts.length ? "?" + parts.join("&") : "";
}

async function loadSchoolsAdmin() {
  var el = document.getElementById("schools-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var data = await adminApi("/api/v1/admin/schools");
    var rows = (data && data.schools) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No schools yet. Add the first school above.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>School</th><th>Code</th><th>City</th><th>School admins</th></tr></thead><tbody>' +
      rows.map(function (s) {
        var ads = (s.admins || []).map(function (a) { return escHtml(a.full_name) + " (" + escHtml(a.email) + ")"; }).join("<br>");
        return "<tr><td>" + escHtml(s.name) + "</td><td>" + escHtml(s.code || "—") + "</td><td>" + escHtml(s.city || "—") + "</td><td>" + (ads || "—") + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function createSchoolCampus() {
  var msg = document.getElementById("sch-msg");
  try {
    await adminApi("/api/v1/admin/schools", {
      method: "POST",
      body: JSON.stringify({
        name: document.getElementById("sch-name").value.trim(),
        city: document.getElementById("sch-city").value.trim() || null,
        state: document.getElementById("sch-state").value.trim() || null,
        admin_full_name: (document.getElementById("sch-admin-name") && document.getElementById("sch-admin-name").value.trim()) || document.getElementById("sch-admin-email").value.trim().split("@")[0],
        admin_email: document.getElementById("sch-admin-email").value.trim(),
        admin_password: document.getElementById("sch-admin-pass").value,
      }),
    });
    if (msg) msg.textContent = "School created. Send that email and password. They log in on the website Schools tab.";
    document.getElementById("sch-admin-pass").value = "";
    loadSchoolsAdmin();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function loadSchoolOffice() {
  try {
    var me = await adminApi("/api/v1/admin/school-office/me");
    var sel = document.getElementById("so-school-id");
    var lab = document.getElementById("so-school-label");
    var pick = document.getElementById("so-school-pick");
    if (me && me.role === "school_admin") {
      if (pick) pick.style.display = "none";
      if (lab) lab.textContent = me.school_name || "";
      if (me.school_id) localStorage.setItem("sia_school_id", me.school_id);
      if (me.school_name) localStorage.setItem("sia_school_name", me.school_name);
    } else if (sel) {
      if (pick) pick.style.display = "";
      var cur = sel.value;
      sel.innerHTML = '<option value="">Select a school…</option>' + ((me && me.schools) || []).map(function (s) {
        return '<option value="' + escHtml(s.id) + '">' + escHtml(s.name) + "</option>";
      }).join("");
      if (cur) sel.value = cur;
    }
  } catch (e) {
    var lab2 = document.getElementById("so-school-label");
    if (lab2) lab2.textContent = e.message || "";
  }
  loadSchoolCandidates();
  loadSchoolResults();
  loadSchoolExamCounts();
}

async function registerSchoolCandidate() {
  var msg = document.getElementById("so-reg-msg");
  var subjects = (document.getElementById("so-subjects").value || "").split(",").map(function (s) { return s.trim(); }).filter(Boolean);
  try {
    var row = await adminApi("/api/v1/admin/school-office/candidates", {
      method: "POST",
      body: JSON.stringify({
        school_id: selectedSchoolId() || null,
        class_name: document.getElementById("so-class").value,
        full_name: document.getElementById("so-name").value.trim(),
        email: document.getElementById("so-email").value.trim() || null,
        phone: document.getElementById("so-phone").value.trim() || null,
        subjects: subjects,
      }),
    });
    if (msg) msg.textContent = "Registered. Rec: " + row.rec_number + " · Access: " + row.access_code;
    printSchoolSlip(row);
    loadSchoolCandidates();
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function loadSchoolCandidates() {
  var el = document.getElementById("so-candidates");
  if (!el) return;
  var q = (document.getElementById("so-search") && document.getElementById("so-search").value) || "";
  try {
    var data = await adminApi("/api/v1/admin/school-office/candidates" + schoolOfficeQuery(q ? "q=" + encodeURIComponent(q) : ""));
    var rows = (data && data.candidates) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No registered exam students yet.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Name</th><th>Class</th><th>Email</th><th>Rec</th><th>Access</th><th></th></tr></thead><tbody>' +
      rows.map(function (r) {
        return '<tr><td>' + escHtml(r.full_name) + '</td><td>' + escHtml(r.class_name) + '</td><td>' + escHtml(r.email || "—") +
          '</td><td>' + escHtml(r.rec_number) + '</td><td>' + escHtml(r.access_code) +
          '</td><td><button class="btn-sm" onclick="printSchoolSlipById(\'' + r.id + '\')">Print slip</button></td></tr>';
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

function printSchoolSlip(row) {
  var w = window.open("", "_blank");
  if (!w) { alert("Allow pop-ups to print the slip."); return; }
  w.document.write("<html><head><title>Registration slip</title><style>body{font-family:Georgia,serif;padding:32px}h1{font-size:20px}table{border-collapse:collapse;width:100%}td{padding:8px;border-bottom:1px solid #ddd}</style></head><body>");
  w.document.write("<h1>" + (row.print_title || (row.school_name || "Scholaxia") + " — Exam registration slip") + "</h1>");
  w.document.write("<table><tr><td>Name</td><td>" + (row.full_name || "") + "</td></tr><tr><td>Class</td><td>" + (row.class_name || "") + "</td></tr><tr><td>Rec number</td><td><strong>" + (row.rec_number || "") + "</strong></td></tr><tr><td>Access code</td><td><strong>" + (row.access_code || "") + "</strong></td></tr><tr><td>Subjects</td><td>" + ((row.subjects || []).join(", ")) + "</td></tr></table><p>Keep this slip. You need the access code and rec number on exam day.</p><script>window.print()<\/script></body></html>");
  w.document.close();
}

async function printSchoolSlipById(id) {
  try {
    var row = await adminApi("/api/v1/admin/school-office/candidates/" + id + "/slip");
    printSchoolSlip(row);
  } catch (e) { alert(e.message); }
}

async function loadSchoolResults() {
  var el = document.getElementById("so-results");
  if (!el) return;
  var cls = (document.getElementById("so-res-class") || {}).value || "";
  var sub = (document.getElementById("so-res-subject") || {}).value || "";
  var qs = [];
  var sid = selectedSchoolId();
  if (sid) qs.push("school_id=" + encodeURIComponent(sid));
  if (cls) qs.push("class_name=" + encodeURIComponent(cls));
  if (sub) qs.push("subject=" + encodeURIComponent(sub));
  try {
    var data = await adminApi("/api/v1/admin/school-office/results" + (qs.length ? "?" + qs.join("&") : ""));
    var rows = (data && data.results) || [];
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No submitted school-exam results yet.</div>'; return; }
    el.innerHTML = '<p class="cbt-hint small">' + rows.length + ' result(s). Use your browser Print.</p><table class="data-table"><thead><tr><th>Student</th><th>Email</th><th>Exam</th><th>Subject</th><th>%</th></tr></thead><tbody>' +
      rows.map(function (r) {
        return '<tr><td>' + escHtml(r.student_name) + '</td><td>' + escHtml(r.email) + '</td><td>' + escHtml(r.exam_title) + '</td><td>' + escHtml(r.subject) + '</td><td>' + escHtml(r.percentage) + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadSchoolExamCounts() {
  var el = document.getElementById("so-exam-counts");
  if (!el) return;
  try {
    var data = await adminApi("/api/v1/admin/school-office/exam-counts" + schoolOfficeQuery());
    var rows = (data && data.exams) || [];
    if (!rows.length) { el.innerHTML = ""; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Exam ID</th><th>Title</th><th>Subject</th><th>Taken</th></tr></thead><tbody>' +
      rows.map(function (r) {
        return '<tr><td><code>' + escHtml(r.id) + '</code></td><td>' + escHtml(r.title) + '</td><td>' + escHtml(r.subject) + '</td><td>' + escHtml(r.taken_count) + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (_) {}
}

async function grantSchoolRetake() {
  var msg = document.getElementById("so-retake-msg");
  try {
    var data = await adminApi("/api/v1/admin/school-office/retake", {
      method: "POST",
      body: JSON.stringify({
        student_email: document.getElementById("so-retake-email").value.trim(),
        exam_id: document.getElementById("so-retake-exam").value.trim(),
      }),
    });
    if (msg) msg.textContent = data.message || "Retake granted.";
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function addSchoolTeacher() {
  var msg = document.getElementById("so-t-msg");
  try {
    await adminApi("/api/v1/admin/school-office/teachers", {
      method: "POST",
      body: JSON.stringify({
        school_id: selectedSchoolId() || null,
        full_name: document.getElementById("so-t-name").value.trim(),
        email: document.getElementById("so-t-email").value.trim(),
        password: document.getElementById("so-t-pass").value,
        subjects: (document.getElementById("so-t-subjects").value || "").split(",").map(function (s) { return s.trim(); }).filter(Boolean),
        academic_classes: (document.getElementById("so-t-classes").value || "").split(",").map(function (s) { return s.trim(); }).filter(Boolean),
      }),
    });
    if (msg) msg.textContent = "Teacher created and approved.";
    document.getElementById("so-t-pass").value = "";
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}

async function hostSchoolLiveClass(startNow) {
  var msg = document.getElementById("so-live-msg");
  try {
    var created = await adminApi("/api/v1/admin/school-office/live-classes", {
      method: "POST",
      body: JSON.stringify({
        school_id: selectedSchoolId() || null,
        title: document.getElementById("so-live-title").value.trim(),
        subject: document.getElementById("so-live-subject").value.trim(),
        start_now: startNow,
        visibility: document.getElementById("so-live-vis").value,
        academic_class: document.getElementById("so-live-class").value,
      }),
    });
    if (msg) msg.textContent = startNow ? "Class is live." : "Class created.";
    if (startNow && created && created.id && confirm("Open classroom now?")) {
      adminEnterClassroom(created.id, document.getElementById("so-live-title").value.trim(), document.getElementById("so-live-subject").value.trim());
    }
  } catch (e) {
    if (msg) msg.textContent = e.message;
  }
}


