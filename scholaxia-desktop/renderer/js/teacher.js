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

async function teacherLogin(ev) {
  ev.preventDefault();
  var email = document.getElementById("teacher-login-email").value.trim();
  var password = document.getElementById("teacher-login-password").value;
  var err = document.getElementById("teacher-login-error");
  err.textContent = "";
  try {
    var res = await fetch("https://scholaxia1.onrender.com/api/v1/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password }),
    });
    var data = await res.json();
    if (!res.ok) throw new Error(data.detail || "Login failed");
    if (data.role !== "teacher" && data.role !== "admin") {
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
    err.textContent = e.message;
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
          actions += '<button class="btn-sm" onclick="teacherEnterClassroom(\'' + c.id + '\',\'' + escHtml(c.title).replace(/'/g, "\\'") + '\',\'' + escHtml(c.subject).replace(/'/g, "\\'") + '\',\'' + (c.end_time || "") + '\')">Enter</button> ';
          actions += '<button class="btn-sm danger" onclick="teacherEndClass(\'' + c.id + '\')">End</button>';
        } else {
          actions += '<button class="btn-sm" onclick="teacherStartClass(\'' + c.id + '\')">Start</button> ';
          actions += '<button class="btn-sm" onclick="teacherEnterClassroom(\'' + c.id + '\',\'' + escHtml(c.title).replace(/'/g, "\\'") + '\',\'' + escHtml(c.subject).replace(/'/g, "\\'") + '\',\'' + (c.end_time || "") + '\')">Enter</button>';
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
  el.innerHTML = '<div class="loading">Loading…</div>';
  try {
    var rows = await teacherApi("/api/v1/live-classes/requests");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty-state">No session requests.</div>';
      return;
    }
    el.innerHTML = '<table class="data-table"><thead><tr><th>Student</th><th>Subject</th><th>Topic</th><th>Status</th></tr></thead><tbody>' +
      rows.map(function (r) {
        return "<tr><td>" + escHtml(r.student_name || "—") + "</td><td>" + escHtml(r.subject) + "</td>" +
          "<td>" + escHtml(r.topic || r.message || "—") + "</td><td>" + escHtml(r.status) + "</td></tr>";
      }).join("") + "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message) + "</div>";
  }
}

function loadTeacherMaterials() {
  document.getElementById("materials-list").innerHTML =
    '<div class="info-banner">Upload PDFs, videos, and worksheets for your students. Full upload coming with Cloudinary.</div>' +
    '<div class="card-grid"><div class="card"><h3>Mathematics</h3><p>Algebra notes, practice sheets</p></div>' +
    '<div class="card"><h3>Sciences</h3><p>Lab guides &amp; diagrams</p></div></div>';
}

function loadTeacherCurriculum() {
  document.getElementById("curriculum-list").innerHTML =
    '<div class="info-banner">Term work scheme — align lessons with WAEC/NECO/JAMB curriculum.</div>' +
    '<ul class="plain-list"><li>Week 1–4: Introduction &amp; fundamentals</li><li>Week 5–8: Core topics &amp; assessments</li><li>Week 9–12: Revision &amp; exam prep</li></ul>';
}

function loadTeacherNotes() {
  document.getElementById("notes-list").innerHTML =
    '<div class="info-banner">Learn Notes — lesson plans and teaching guides for tutors.</div>' +
    '<textarea class="notes-editor" placeholder="Write lesson notes for your next class…" rows="8"></textarea>' +
    '<button class="btn-action" style="margin-top:12px">Save draft (local)</button>';
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

document.addEventListener("DOMContentLoaded", setDefaultScheduleDate);
