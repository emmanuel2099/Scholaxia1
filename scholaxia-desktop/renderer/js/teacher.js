var currentTeacherPage = "live";

window.onload = function () {
  if (!getTeacherToken()) {
    document.getElementById("auth-screen").classList.remove("hidden");
    document.getElementById("app-screen").classList.add("hidden");
    return;
  }
  document.getElementById("auth-screen").classList.add("hidden");
  document.getElementById("app-screen").classList.remove("hidden");
  initTeacherUI();
  showTeacherPage("live");
};

function initTeacherUI() {
  var user = getTeacherUser();
  document.getElementById("teacher-name-label").textContent = user.name;
  document.getElementById("teacher-email-label").textContent = user.email;
}

function teacherNetworkMessage(err) {
  var msg = (err && err.message) ? String(err.message) : "";
  if (err && (err.name === "AbortError" || err.name === "TimeoutError")) {
    return "Server is waking up — wait a moment and try again.";
  }
  if (msg === "Failed to fetch" || msg.indexOf("NetworkError") >= 0 || msg.indexOf("network") >= 0) {
    return "Cannot reach Scholaxia server. Restart the app and check your internet.";
  }
  return msg || "Login failed. Please try again.";
}

function formatTeacherApiError(data, status) {
  var detail = data && data.detail;
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) return detail.map(function (d) { return d.msg || d; }).join(", ");
  if (detail && typeof detail === "object") return detail.msg || JSON.stringify(detail);
  if (status === 401) return "Wrong email or password.";
  if (status === 403) return "Account disabled.";
  if (status === 502) return "Server proxy error — fully close the app and open TEACHER.bat again.";
  if (status === 501) return "Old desktop server still running. Close ALL Scholaxia windows, then open TEACHER.bat again.";
  return "Login failed (HTTP " + status + ").";
}

async function teacherLogin(ev) {
  if (ev) ev.preventDefault();
  var email = document.getElementById("teacher-login-email").value.trim();
  var password = document.getElementById("teacher-login-password").value;
  var err = document.getElementById("teacher-login-error");
  var btn = document.getElementById("teacher-login-btn");
  err.textContent = "";
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Logging in…";
  }
  try {
    var signal = typeof fetchTimeout === "function" ? fetchTimeout(45000) : teacherFetchTimeout(45000);
    var res = await fetch(API_BASE + "/api/v1/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password }),
      signal: signal,
    });
    var data = await res.json().catch(function () { return {}; });
    if (!res.ok) {
      throw new Error(formatTeacherApiError(data, res.status));
    }
    var role = data.role || (data.user && data.user.role) || "";
    if (role !== "teacher" && role !== "admin") {
      throw new Error("This portal is for teachers only. Use the student or admin app.");
    }
    saveTeacherSession(data, email, data.user && data.user.full_name);
    try {
      var profile = await teacherApi("/api/v1/teachers/me");
      if (profile && profile.subjects) {
        localStorage.setItem("sia_teacher_subjects", JSON.stringify(profile.subjects));
      }
    } catch (e) { /* optional */ }
    window.location.reload();
  } catch (e) {
    err.textContent = teacherNetworkMessage(e);
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = "LOG IN";
    }
  }
}

function teacherLogout() {
  clearTeacherSession();
  window.location.reload();
}

function showTeacherPage(page) {
  currentTeacherPage = page;
  document.querySelectorAll(".teacher-page").forEach(function (p) { p.classList.remove("active"); });
  document.querySelectorAll(".topnav-btn").forEach(function (b) { b.classList.remove("active"); });
  var pg = document.getElementById("page-" + page);
  if (pg) pg.classList.add("active");
  var btn = document.querySelector('.topnav-btn[data-page="' + page + '"]');
  if (btn) btn.classList.add("active");
  if (page === "live") loadTeacherLive();
  else if (page === "requests") loadTeacherRequests();
  else if (page === "materials") loadTeacherMaterials();
  else if (page === "curriculum") loadTeacherCurriculum();
  else if (page === "notes") loadTeacherNotes();
}

function getSchedulePayload(goLiveNow) {
  var title = document.getElementById("host-title").value.trim();
  var subject = document.getElementById("host-subject").value.trim();
  var date = document.getElementById("host-date").value;
  var startTime = document.getElementById("host-start").value;
  var endTime = document.getElementById("host-end").value;
  var duration = parseInt(document.getElementById("host-duration").value, 10) || 60;
  if (!title || !subject) throw new Error("Title and subject are required");

  var body = {
    title: title,
    subject: subject,
    duration_minutes: duration,
    go_live_now: goLiveNow,
  };

  if (!goLiveNow) {
    if (!date || !startTime) throw new Error("Pick a date and start time to schedule");
    body.start_time = new Date(date + "T" + startTime).toISOString();
    if (endTime) body.end_time = new Date(date + "T" + endTime).toISOString();
  } else if (endTime && date) {
    body.end_time = new Date(date + "T" + endTime).toISOString();
  }
  return body;
}

async function teacherHostClass(goLiveNow) {
  var err = document.getElementById("host-error");
  err.textContent = "";
  try {
    var body = getSchedulePayload(goLiveNow);
    var created = await teacherApi("/api/v1/live-classes/", { method: "POST", body: JSON.stringify(body) });
    document.getElementById("host-title").value = "";
    loadTeacherLive();
    if (goLiveNow && created && created.id) {
      if (confirm("Class is live! Students with " + body.subject + " were notified. Open classroom?")) {
        teacherEnterClassroom(created.id, body.title, body.subject, created.end_time);
      }
    } else {
      alert("Class scheduled. Students with this subject will see it under Upcoming.");
    }
  } catch (e) {
    err.textContent = e.message;
  }
}

async function teacherStartClass(id) {
  try {
    await teacherApi("/api/v1/live-classes/" + id + "/start", { method: "POST" });
    loadTeacherLive();
    alert("Class started — students notified.");
  } catch (e) { alert(e.message); }
}

async function teacherEndClass(id) {
  try {
    await teacherApi("/api/v1/live-classes/" + id + "/end", { method: "POST" });
    loadTeacherLive();
  } catch (e) { alert(e.message); }
}

async function teacherEnterClassroom(classId, title, subject, endTime) {
  try {
    var token = await teacherApi("/api/v1/live-classes/" + classId + "/token");
    if (!token) return;
    localStorage.setItem("live_session", JSON.stringify({
      class_id: classId,
      classId: classId,
      room_id: token.channel_id,
      channel_id: token.channel_id,
      agora_token: token.token,
      uid: token.uid,
      app_id: token.app_id,
      title: title || "Live Class",
      subject: subject || "",
      teacher_name: getTeacherUser().name,
      role: "teacher",
      end_time: endTime || token.end_time || null,
    }));
    window.location.href = "classroom.html";
  } catch (e) {
    alert(e.message);
  }
}

async function loadTeacherLive() {
  var el = document.getElementById("live-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var status = document.getElementById("live-filter").value;
    var url = "/api/v1/live-classes/?limit=50";
    if (status) url += "&status=" + status;
    var rows = await teacherApi(url);
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No classes yet. Schedule or go live above.</div>';
      return;
    }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Title</th><th>Subject</th><th>Schedule</th><th>End</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (c) {
        var badge = c.is_live ? '<span class="badge live">LIVE</span>' : '<span class="badge muted">Scheduled</span>';
        var actions = "";
        if (c.is_live) {
          actions += '<button type="button" class="btn-sm" data-action="enter" data-id="' + escHtml(c.id) + '" data-title="' + escHtml(c.title) + '" data-subject="' + escHtml(c.subject) + '" data-end="' + escHtml(c.end_time || "") + '">Enter</button> ';
          actions += '<button type="button" class="btn-sm danger" data-action="end" data-id="' + escHtml(c.id) + '">End</button>';
        } else {
          actions += '<button type="button" class="btn-sm" data-action="start" data-id="' + escHtml(c.id) + '">Start</button> ';
          actions += '<button type="button" class="btn-sm" data-action="enter" data-id="' + escHtml(c.id) + '" data-title="' + escHtml(c.title) + '" data-subject="' + escHtml(c.subject) + '" data-end="' + escHtml(c.end_time || "") + '">Enter</button>';
        }
        return "<tr><td>" + escHtml(c.title) + "</td><td>" + escHtml(c.subject) + "</td>" +
          "<td>" + formatDateTime(c.start_time) + "</td><td>" + formatDateTime(c.end_time) + "</td>" +
          "<td>" + badge + "</td><td class=\"actions\">" + actions + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

async function loadTeacherRequests() {
  var el = document.getElementById("requests-table");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await teacherApi("/api/v1/live-classes/requests");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state-premium"><div class="empty-icon">&#128172;</div><h3>No session requests</h3><p>When students request a live session, they will appear here.</p></div>';
      return;
    }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Student</th><th>Subject</th><th>Topic</th><th>When</th><th>Status</th><th></th></tr></thead><tbody>' +
      rows.map(function (r) {
        var status = String(r.status || "pending");
        var badgeClass = status === "approved" ? "approved" : (status === "dismissed" ? "muted" : "pending");
        var actions = "";
        if (status === "pending") {
          actions =
            '<button type="button" class="btn-sm primary" data-action="approve-request" data-id="' + escHtml(r.id) + '">Approve</button> ' +
            '<button type="button" class="btn-sm danger" data-action="dismiss-request" data-id="' + escHtml(r.id) + '">Dismiss</button>';
        }
        return "<tr><td>" + escHtml(r.student_name || "Student") + "</td><td>" + escHtml(r.subject) + "</td>" +
          "<td>" + escHtml(r.topic || r.message || "—") + "</td><td>" + formatDateTime(r.preferred_time || r.created_at) + "</td>" +
          '<td><span class="badge ' + badgeClass + '">' + escHtml(status) + "</span></td>" +
          '<td class="actions">' + actions + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state-premium"><div class="empty-icon">&#9888;</div><h3>Could not load requests</h3><p>' + escHtml(e.message) + '</p><button type="button" class="btn-action" id="requests-retry-btn">Try again</button></div>';
    var retry = document.getElementById("requests-retry-btn");
    if (retry) retry.addEventListener("click", loadTeacherRequests);
  }
}

async function updateTeacherRequest(id, status) {
  try {
    await teacherApi("/api/v1/live-classes/requests/" + id, {
      method: "PATCH",
      body: JSON.stringify({ status: status }),
    });
    loadTeacherRequests();
  } catch (e) {
    alert(e.message);
  }
}

function materialTypeIcon(type) {
  if (type === "pdf") return "&#128196;";
  if (type === "doc") return "&#128221;";
  if (type === "image") return "&#128247;";
  if (type === "video") return "&#127909;";
  return "&#128279;";
}

function materialTypeLabel(type) {
  if (type === "pdf") return "PDF";
  if (type === "doc") return "Document";
  if (type === "image") return "Image";
  if (type === "video") return "Video";
  return "Link";
}

function getLocalMaterials() {
  try {
    return JSON.parse(localStorage.getItem("sia_teacher_materials_v1") || "[]");
  } catch (e) {
    return [];
  }
}

function setLocalMaterials(list) {
  localStorage.setItem("sia_teacher_materials_v1", JSON.stringify(list));
}

function getTeacherSubjects() {
  var user = getTeacherUser();
  return Array.isArray(user.subjects) && user.subjects.length ? user.subjects : ["Mathematics", "Physics", "Chemistry"];
}

function populateSubjectFilters() {
  var subjects = getTeacherSubjects();
  var filter = document.getElementById("materials-subject-filter");
  var datalist = document.getElementById("mat-subject-list");
  if (filter) {
    var current = filter.value;
    filter.innerHTML = '<option value="">All subjects</option>' +
      subjects.map(function (s) { return '<option value="' + escHtml(s) + '">' + escHtml(s) + "</option>"; }).join("");
    if (current) filter.value = current;
  }
  if (datalist) {
    datalist.innerHTML = subjects.map(function (s) { return '<option value="' + escHtml(s) + '">'; }).join("");
  }
  var matSub = document.getElementById("mat-subject");
  if (matSub && !matSub.value && subjects[0]) matSub.value = subjects[0];
}

function openMaterialModal() {
  document.getElementById("mat-error").textContent = "";
  document.getElementById("mat-title").value = "";
  document.getElementById("mat-desc").value = "";
  document.getElementById("mat-file").value = "";
  document.getElementById("mat-url").value = "";
  populateSubjectFilters();
  toggleMaterialInputs();
  document.getElementById("material-modal").classList.remove("hidden");
}

function closeMaterialModal() {
  document.getElementById("material-modal").classList.add("hidden");
}

function toggleMaterialInputs() {
  var type = document.getElementById("mat-type").value;
  var isLink = type === "link" || type === "video";
  document.querySelector(".mat-file-wrap").classList.toggle("hidden", isLink);
  document.querySelector(".mat-link-wrap").classList.toggle("hidden", !isLink);
}

async function saveTeacherMaterial() {
  var err = document.getElementById("mat-error");
  var btn = document.getElementById("mat-save-btn");
  err.textContent = "";
  var title = document.getElementById("mat-title").value.trim();
  var subject = document.getElementById("mat-subject").value.trim();
  var type = document.getElementById("mat-type").value;
  var desc = document.getElementById("mat-desc").value.trim();
  if (!title || !subject) {
    err.textContent = "Title and subject are required.";
    return;
  }
  var url = "";
  btn.disabled = true;
  btn.textContent = "Saving…";
  try {
    if (type === "link" || type === "video") {
      url = document.getElementById("mat-url").value.trim();
      if (!url) throw new Error("Enter a URL for this material.");
    } else {
      var fileInput = document.getElementById("mat-file");
      if (!fileInput.files || !fileInput.files[0]) throw new Error("Choose a file to upload.");
      var uploaded = await teacherApiUpload("/api/v1/community/upload", fileInput.files[0]);
      url = uploaded.file_url;
      if (uploaded.file_type === "pdf") type = "pdf";
      else if (uploaded.file_type === "doc") type = "doc";
      else if (uploaded.file_type === "image") type = "image";
    }
    var list = getLocalMaterials();
    list.unshift({
      id: "mat-" + Date.now(),
      title: title,
      subject: subject,
      type: type,
      url: url,
      description: desc,
      created_at: new Date().toISOString(),
    });
    setLocalMaterials(list);
    closeMaterialModal();
    loadTeacherMaterials();
  } catch (e) {
    err.textContent = e.message;
  } finally {
    btn.disabled = false;
    btn.textContent = "Save material";
  }
}

function deleteTeacherMaterial(id) {
  if (!confirm("Remove this material?")) return;
  setLocalMaterials(getLocalMaterials().filter(function (m) { return m.id !== id; }));
  loadTeacherMaterials();
}

function openMaterialUrl(url) {
  if (!url) return;
  window.open(url, "_blank", "noopener,noreferrer");
}

async function openLibraryBook(bookId) {
  try {
    var data = await teacherApi("/api/v1/library/" + bookId + "/read");
    if (data && data.read_url) openMaterialUrl(data.read_url);
  } catch (e) {
    alert(e.message);
  }
}

async function loadTeacherMaterials() {
  var el = document.getElementById("materials-list");
  var stats = document.getElementById("materials-stats");
  if (!el) return;
  populateSubjectFilters();
  el.innerHTML = '<div class="loading">Loading materials…</div>';
  if (stats) stats.innerHTML = "";
  var subjectFilter = (document.getElementById("materials-subject-filter") || {}).value || "";
  var typeFilter = (document.getElementById("materials-type-filter") || {}).value || "";
  var local = getLocalMaterials();
  var library = [];
  try {
    library = await teacherApi("/api/v1/library/teacher") || [];
  } catch (e) {
    library = [];
  }
  var items = [];
  library.forEach(function (b) {
    items.push({
      id: "lib-" + b.id,
      title: b.title,
      subject: b.subject || "General",
      type: "pdf",
      url: "",
      description: b.description || ("By " + (b.author || "Scholaxia")),
      created_at: null,
      is_library: true,
      book_id: b.id,
      cover: b.cover_image_url,
    });
  });
  local.forEach(function (m) { items.push(m); });
  if (subjectFilter) items = items.filter(function (m) { return (m.subject || "").toLowerCase() === subjectFilter.toLowerCase(); });
  if (typeFilter) items = items.filter(function (m) { return m.type === typeFilter; });
  if (stats) {
    stats.innerHTML =
      '<div class="stat-pill"><strong>' + items.length + "</strong> materials</div>" +
      '<div class="stat-pill"><strong>' + local.length + "</strong> yours</div>" +
      '<div class="stat-pill"><strong>' + library.length + "</strong> from library</div>";
  }
  if (!items.length) {
    el.innerHTML =
      '<div class="empty-state-premium">' +
      '<div class="empty-icon">&#128218;</div>' +
      "<h3>No materials yet</h3>" +
      "<p>Upload a PDF, worksheet or link for your students. Materials are grouped by subject.</p>" +
      '<button type="button" class="btn-action" id="materials-empty-add-btn">Add your first material</button>' +
      "</div>";
    var emptyBtn = document.getElementById("materials-empty-add-btn");
    if (emptyBtn) emptyBtn.addEventListener("click", openMaterialModal);
    return;
  }
  el.innerHTML = items.map(function (m) {
    var actions = "";
    if (m.is_library) {
      actions = '<button type="button" class="btn-sm primary" data-action="open-library" data-id="' + escHtml(m.book_id) + '">Open</button>';
    } else {
      actions =
        '<button type="button" class="btn-sm primary" data-action="open-url" data-url="' + escHtml(m.url) + '">Open</button> ' +
        '<button type="button" class="btn-sm danger" data-action="delete-material" data-id="' + escHtml(m.id) + '">Delete</button>';
    }
    return (
      '<article class="material-card">' +
      (m.cover ? '<div class="material-cover" style="background-image:url(\'' + escHtml(m.cover) + '\')"></div>' : '<div class="material-icon">' + materialTypeIcon(m.type) + "</div>") +
      '<div class="material-body">' +
      '<span class="material-type">' + materialTypeLabel(m.type) + (m.is_library ? " · Library" : "") + "</span>" +
      "<h3>" + escHtml(m.title) + "</h3>" +
      '<p class="material-subject">' + escHtml(m.subject) + "</p>" +
      (m.description ? '<p class="material-desc">' + escHtml(m.description) + "</p>" : "") +
      '<div class="material-actions">' + actions + "</div>" +
      "</div></article>"
    );
  }).join("");
}

function getCurriculumWeeks() {
  try {
    var saved = JSON.parse(localStorage.getItem("sia_teacher_curriculum_v1") || "null");
    if (Array.isArray(saved) && saved.length) return saved;
  } catch (e) { /* ignore */ }
  return [
    { weeks: "Week 1–4", topic: "Introduction & fundamentals", tasks: "Diagnostic test, core concepts" },
    { weeks: "Week 5–8", topic: "Core topics & assessments", tasks: "Class tests, homework" },
    { weeks: "Week 9–12", topic: "Revision & exam prep", tasks: "Past questions, mock exam" },
  ];
}

function saveCurriculumWeeks(weeks) {
  localStorage.setItem("sia_teacher_curriculum_v1", JSON.stringify(weeks));
}

function loadTeacherCurriculum() {
  var el = document.getElementById("curriculum-list");
  if (!el) return;
  var weeks = getCurriculumWeeks();
  el.innerHTML =
    '<div class="curriculum-grid">' +
    weeks.map(function (w, i) {
      return (
        '<div class="curriculum-card">' +
        '<label><span>Period</span><input type="text" data-cur="weeks" data-i="' + i + '" value="' + escHtml(w.weeks) + '" /></label>' +
        '<label><span>Topics</span><input type="text" data-cur="topic" data-i="' + i + '" value="' + escHtml(w.topic) + '" /></label>' +
        '<label><span>Activities</span><input type="text" data-cur="tasks" data-i="' + i + '" value="' + escHtml(w.tasks) + '" /></label>' +
        '<button type="button" class="btn-sm danger" data-action="remove-week" data-i="' + i + '">Remove</button>' +
        "</div>"
      );
    }).join("") +
    '</div><button type="button" class="btn-action curriculum-save-btn" style="margin-top:16px">Save work scheme</button>';
  document.querySelectorAll("[data-action='remove-week']").forEach(function (btn) {
    btn.addEventListener("click", function () { removeCurriculumWeek(parseInt(btn.dataset.i, 10)); });
  });
  var saveBtn = document.querySelector(".curriculum-save-btn");
  if (saveBtn) saveBtn.addEventListener("click", persistCurriculumFromDom);
}

function persistCurriculumFromDom() {
  var weeks = getCurriculumWeeks();
  document.querySelectorAll("[data-cur]").forEach(function (inp) {
    var i = parseInt(inp.dataset.i, 10);
    var key = inp.dataset.cur;
    if (!weeks[i]) weeks[i] = {};
    weeks[i][key] = inp.value;
  });
  saveCurriculumWeeks(weeks);
  alert("Work scheme saved.");
}

function addCurriculumWeek() {
  var weeks = getCurriculumWeeks();
  weeks.push({ weeks: "New period", topic: "", tasks: "" });
  saveCurriculumWeeks(weeks);
  loadTeacherCurriculum();
}

function removeCurriculumWeek(index) {
  var weeks = getCurriculumWeeks();
  weeks.splice(index, 1);
  saveCurriculumWeeks(weeks);
  loadTeacherCurriculum();
}

function loadTeacherNotes() {
  var el = document.getElementById("notes-list");
  if (!el) return;
  var saved = localStorage.getItem("sia_teacher_notes_v1") || "";
  el.innerHTML =
    '<textarea id="teacher-notes-editor" class="notes-editor" placeholder="Write lesson notes for your next class…" rows="14"></textarea>' +
    '<p class="notes-hint">Tip: include objectives, key points, and homework for students.</p>';
  var editor = document.getElementById("teacher-notes-editor");
  if (editor) editor.value = saved;
}

function saveTeacherNotes() {
  var editor = document.getElementById("teacher-notes-editor");
  if (!editor) return;
  localStorage.setItem("sia_teacher_notes_v1", editor.value);
  alert("Notes saved on this device.");
}

function setDefaultScheduleDate() {
  var d = new Date();
  var dateEl = document.getElementById("host-date");
  var startEl = document.getElementById("host-start");
  var endEl = document.getElementById("host-end");
  if (dateEl && !dateEl.value) {
    dateEl.value = d.toISOString().slice(0, 10);
  }
  if (startEl && !startEl.value) {
    startEl.value = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
  }
  if (endEl && !endEl.value) {
    var end = new Date(d.getTime() + 60 * 60 * 1000);
    endEl.value = String(end.getHours()).padStart(2, "0") + ":" + String(end.getMinutes()).padStart(2, "0");
  }
}

function bindTeacherUI() {
  var loginForm = document.getElementById("teacher-login-form");
  if (loginForm) loginForm.addEventListener("submit", teacherLogin);

  var pwToggle = document.getElementById("teacher-pw-toggle");
  var pwInput = document.getElementById("teacher-login-password");
  if (pwToggle && pwInput) {
    pwToggle.addEventListener("click", function () {
      var show = pwInput.type === "password";
      pwInput.type = show ? "text" : "password";
      pwToggle.textContent = show ? "Hide" : "Show";
    });
  }

  var logoutBtn = document.getElementById("teacher-logout-btn");
  if (logoutBtn) logoutBtn.addEventListener("click", teacherLogout);

  document.querySelectorAll("#teacher-topnav .topnav-btn").forEach(function (btn) {
    btn.addEventListener("click", function () {
      if (btn.dataset.page) showTeacherPage(btn.dataset.page);
    });
  });

  var scheduleBtn = document.getElementById("host-schedule-btn");
  if (scheduleBtn) scheduleBtn.addEventListener("click", function () { teacherHostClass(false); });
  var liveBtn = document.getElementById("host-live-btn");
  if (liveBtn) liveBtn.addEventListener("click", function () { teacherHostClass(true); });
  var liveFilter = document.getElementById("live-filter");
  if (liveFilter) liveFilter.addEventListener("change", loadTeacherLive);
  var liveRefresh = document.getElementById("live-refresh-btn");
  if (liveRefresh) liveRefresh.addEventListener("click", loadTeacherLive);

  var liveTable = document.getElementById("live-table");
  if (liveTable) {
    liveTable.addEventListener("click", function (ev) {
      var btn = ev.target.closest("[data-action]");
      if (!btn) return;
      var id = btn.dataset.id;
      if (btn.dataset.action === "start") teacherStartClass(id);
      else if (btn.dataset.action === "end") teacherEndClass(id);
      else if (btn.dataset.action === "enter") {
        teacherEnterClassroom(id, btn.dataset.title, btn.dataset.subject, btn.dataset.end);
      }
    });
  }

  var openMatBtn = document.getElementById("open-material-modal-btn");
  if (openMatBtn) openMatBtn.addEventListener("click", openMaterialModal);
  var matRefresh = document.getElementById("materials-refresh-btn");
  if (matRefresh) matRefresh.addEventListener("click", loadTeacherMaterials);
  var subFilter = document.getElementById("materials-subject-filter");
  if (subFilter) subFilter.addEventListener("change", loadTeacherMaterials);
  var typeFilter = document.getElementById("materials-type-filter");
  if (typeFilter) typeFilter.addEventListener("change", loadTeacherMaterials);

  var matList = document.getElementById("materials-list");
  if (matList) {
    matList.addEventListener("click", function (ev) {
      var btn = ev.target.closest("[data-action]");
      if (!btn) return;
      if (btn.dataset.action === "open-library") openLibraryBook(btn.dataset.id);
      else if (btn.dataset.action === "open-url") openMaterialUrl(btn.dataset.url);
      else if (btn.dataset.action === "delete-material") deleteTeacherMaterial(btn.dataset.id);
    });
  }

  var matModal = document.getElementById("material-modal");
  if (matModal) {
    matModal.addEventListener("click", function (ev) {
      if (ev.target === matModal) closeMaterialModal();
    });
  }
  var matClose = document.getElementById("material-modal-close");
  if (matClose) matClose.addEventListener("click", closeMaterialModal);
  var matCancel = document.getElementById("material-modal-cancel");
  if (matCancel) matCancel.addEventListener("click", closeMaterialModal);
  var matSave = document.getElementById("mat-save-btn");
  if (matSave) matSave.addEventListener("click", saveTeacherMaterial);
  var matType = document.getElementById("mat-type");
  if (matType) matType.addEventListener("change", toggleMaterialInputs);

  var addWeekBtn = document.getElementById("add-curriculum-week-btn");
  if (addWeekBtn) addWeekBtn.addEventListener("click", addCurriculumWeek);
  var saveNotesBtn = document.getElementById("save-notes-btn");
  if (saveNotesBtn) saveNotesBtn.addEventListener("click", saveTeacherNotes);
  var reqRefresh = document.getElementById("requests-refresh-btn");
  if (reqRefresh) reqRefresh.addEventListener("click", loadTeacherRequests);

  var reqTable = document.getElementById("requests-table");
  if (reqTable) {
    reqTable.addEventListener("click", function (ev) {
      var btn = ev.target.closest("[data-action]");
      if (!btn) return;
      if (btn.dataset.action === "approve-request") updateTeacherRequest(btn.dataset.id, "approved");
      else if (btn.dataset.action === "dismiss-request") updateTeacherRequest(btn.dataset.id, "dismissed");
    });
  }
}

window.teacherLogin = teacherLogin;
window.teacherLogout = teacherLogout;
window.showTeacherPage = showTeacherPage;
window.loadTeacherLive = loadTeacherLive;
window.loadTeacherMaterials = loadTeacherMaterials;
window.loadTeacherRequests = loadTeacherRequests;
window.openMaterialModal = openMaterialModal;
window.closeMaterialModal = closeMaterialModal;
window.toggleMaterialInputs = toggleMaterialInputs;
window.saveTeacherMaterial = saveTeacherMaterial;
window.deleteTeacherMaterial = deleteTeacherMaterial;
window.openMaterialUrl = openMaterialUrl;
window.openLibraryBook = openLibraryBook;
window.addCurriculumWeek = addCurriculumWeek;
window.removeCurriculumWeek = removeCurriculumWeek;
window.persistCurriculumFromDom = persistCurriculumFromDom;
window.saveTeacherNotes = saveTeacherNotes;
window.updateTeacherRequest = updateTeacherRequest;
window.teacherHostClass = teacherHostClass;
window.teacherStartClass = teacherStartClass;
window.teacherEndClass = teacherEndClass;
window.teacherEnterClassroom = teacherEnterClassroom;

document.addEventListener("DOMContentLoaded", function () {
  bindTeacherUI();
  setDefaultScheduleDate();
});
