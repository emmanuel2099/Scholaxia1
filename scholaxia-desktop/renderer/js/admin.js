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
  else if (page === "live") loadLiveClasses();
  else if (page === "requests") loadRequests();
  else if (page === "cbt") { initCbtBuilder(); loadCbt(); }
  else if (page === "recommendations") loadRecommendations();
  else if (page === "community") loadCommunityPosts();
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
    var rows = await adminApi("/api/v1/admin/students");
    if (!rows) return;
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

async function deleteStudent(id) {
  if (!confirm("Remove this student? They will not be able to log in.")) return;
  try {
    await adminApi("/api/v1/admin/students/" + id, { method: "DELETE" });
    loadStudents();
  } catch (e) { alert(e.message); }
}

async function removeAllStudents() {
  if (!confirm("Remove ALL students? This disables every student account.")) return;
  try {
    var r = await adminApi("/api/v1/admin/students/remove-all", { method: "POST" });
    alert("Removed " + (r.removed || 0) + " student(s).");
    loadStudents();
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
    alert(startNow ? "Class is live! Students can join from Live Class." : "Class scheduled.");
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
    if (!rows) return;
    if (!rows.length) { el.innerHTML = '<div class="empty-state">No session requests.</div>'; return; }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Student</th><th>Subject</th><th>Topic</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (r) {
        return '<tr><td>' + escHtml(r.student_name || r.student_id) + '</td>' +
          '<td>' + escHtml(r.subject) + '</td><td>' + escHtml(r.topic || r.message || "—") + '</td>' +
          '<td><span class="badge muted">' + escHtml(r.status) + '</span></td>' +
          '<td class="actions">' +
          (r.status === "pending" ? '<button class="btn-sm" onclick="updateRequest(\'' + r.id + '\',\'approved\')">Approve</button>' +
            '<button class="btn-sm secondary" onclick="updateRequest(\'' + r.id + '\',\'dismissed\')">Dismiss</button>' : "") +
          '</td></tr>';
      }).join("") + '</tbody></table>';
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + '</div>';
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

function initCbtBuilder() {
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
    ? "Practice exams for JAMB / WAEC / NECO — students can take these anytime to prepare."
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
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Type</th><th>Questions</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (e) {
        var typeBadge = e.is_school_exam
          ? '<span class="badge school">School</span>'
          : '<span class="badge ok">' + escHtml(e.exam_type) + '</span>';
        var pub = e.is_published ? '<span class="badge ok">Published</span>' : '<span class="badge muted">Draft</span>';
        return '<tr><td>' + escHtml(e.title) + '</td><td>' + escHtml(e.subject) + '</td>' +
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
  if (!title || !subject) {
    err.textContent = "Enter an exam title and subject.";
    return;
  }

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
