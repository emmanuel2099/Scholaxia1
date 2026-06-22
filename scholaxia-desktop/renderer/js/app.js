const PAGE_TITLES = {
  live: "Live Class",
  school: "Scholaxia Exams",
  "school-portal": "Schools Exam Portal",
  cbt: "CBT Practice",
  plans: "Live Class Plans",
  sia: "Ask Sia",
  community: "Community",
  "community-create": "New Post",
  profile: "Profile",
};

const LIVE_PLANS = [
  { group: "Nursery", plans: [
    { name: "Nursery Standard", price: "₦45,000/mo", features: ["8 sessions · 45 min", "Up to 2 subjects", "Homework help", "Monthly report"] },
    { name: "Nursery Premium", price: "₦65,000/mo", features: ["12 sessions · 45 min", "Up to 4 subjects", "Weekly assessments", "Parent feedback"] },
  ]},
  { group: "Primary", plans: [
    { name: "Primary Standard", price: "₦55,000/mo", features: ["8 sessions · 1 hr", "Up to 3 subjects", "Homework support"] },
    { name: "Primary Premium", price: "₦80,000/mo", features: ["12 sessions · 1 hr", "Up to 5 subjects", "Personalized study plan"] },
    { name: "Primary Elite", price: "₦70,000/mo", features: ["16 sessions · 1 hr", "All core subjects", "Academic coach"] },
  ]},
  { group: "High School (JSS & SSS)", plans: [
    { name: "High Standard", price: "₦50,000/mo", features: ["8 sessions · 1 hr", "Up to 3 subjects"] },
    { name: "Secondary Premium", price: "₦60,000/mo", features: ["12 sessions · 1 hr", "Up to 6 subjects", "CBT practice"] },
    { name: "Secondary Elite", price: "₦80,000/mo", features: ["16 sessions · 1 hr", "All subjects", "Dedicated mentor"] },
  ]},
  { group: "Exam Prep (WAEC, NECO, JAMB)", plans: [
    { name: "Exam Intensive", price: "₦80,000", features: ["18 sessions · 1.5 hr", "JAMB prep · 4 subjects", "Mock tests"] },
    { name: "Exam Mastery", price: "₦100,000", features: ["25 sessions · 2 hr", "8 subjects", "Weekly mock CBT"] },
  ]},
];

let currentPage = "live";
let practiceExams = [];
let schoolExams = [];
let allSubjects = [];
let selectedSubjects = [];
let currentExam = null;
let currentSession = null;
let answers = {};
let currentQ = 0;
let timerInterval = null;
let secondsLeft = 0;
let pendingSchoolExamId = null;
let cameraStream = null;

window.onload = () => {
  if (!getToken()) {
    window.location.href = "index.html";
    return;
  }
  initUserUI();
  loadSubjects();
  refreshPage();
};

function initUserUI() {
  const user = getUser();
  const initial = firstName(user.name)[0].toUpperCase();
  document.getElementById("sidebar-name").textContent = firstName(user.name);
  document.getElementById("sidebar-exam").textContent = user.examType || "Student";
  document.getElementById("user-avatar").textContent = initial;
  document.getElementById("profile-avatar").textContent = initial;
  document.getElementById("profile-name").textContent = user.name;
  document.getElementById("profile-email").textContent = user.email;
}

function logout() {
  clearSession();
  window.location.href = "index.html";
}

function showPage(page) {
  currentPage = page;
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  document.querySelectorAll(".topnav-btn").forEach((n) => n.classList.remove("active"));
  document.getElementById(`page-${page}`).classList.add("active");
  const navPage = page === "community-create" ? "community" : page;
  const navEl = document.querySelector(`.topnav-btn[data-page="${navPage}"]`);
  if (navEl) navEl.classList.add("active");
  document.getElementById("page-title").textContent = PAGE_TITLES[page] || page;
  const fab = document.getElementById("community-fab");
  if (fab) fab.style.display = page === "community" ? "flex" : "none";
  refreshPage();
}

function refreshPage() {
  if (currentPage === "live") loadLive();
  else if (currentPage === "school") loadSchoolExams();
  else if (currentPage === "school-portal") { /* static */ }
  else if (currentPage === "plans") loadPlans();
  else if (currentPage === "cbt") loadCbtExams();
  else if (currentPage === "sia") loadSia();
  else if (currentPage === "community") {
    var pending = communityPendingPost;
    communityPendingPost = null;
    loadCommunity(pending);
  }
  else if (currentPage === "community-create") initCommunityCreate();
  else if (currentPage === "profile") loadProfile();
}

/* ── Live Class ── */

async function loadLive() {
  document.getElementById("live-grid").innerHTML = `<div class="loading">Loading…</div>`;
  document.getElementById("upcoming-grid").innerHTML = `<div class="loading">Loading…</div>`;
  try {
    const [live, upcoming, feed] = await Promise.all([
      api("/api/v1/live-classes/?status=live"),
      api("/api/v1/live-classes/?status=upcoming"),
      api("/api/v1/home/feed").catch(() => null),
    ]);

    renderLive(live || []);
    renderUpcoming(upcoming || []);

    if (feed?.my_session_requests) renderRequests(feed.my_session_requests);
    else loadMyRequests();
  } catch (e) {
    document.getElementById("live-grid").innerHTML = `<div class="empty">${escHtml(e.message)}</div>`;
  }
}

function renderLive(sessions) {
  document.getElementById("live-count").textContent = sessions.length;
  const el = document.getElementById("live-grid");
  if (!sessions.length) {
    el.innerHTML = `<div class="empty">No live classes right now. Check upcoming sessions below.</div>`;
    return;
  }
  el.innerHTML = sessions.map((s) => `
    <div class="card">
      <div class="live-pill">LIVE</div>
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">${escHtml(s.subject)} · ${escHtml(s.teacher_name)}</p>
      <button class="btn-join" data-id="${s.id}" data-title="${escHtml(s.title)}" data-subject="${escHtml(s.subject)}" data-teacher="${escHtml(s.teacher_name)}" onclick="joinClass(this)">Join Class</button>
    </div>
  `).join("");
}

function renderUpcoming(sessions) {
  const el = document.getElementById("upcoming-grid");
  if (!sessions.length) {
    el.innerHTML = `<div class="empty">No upcoming classes scheduled for your subjects yet.</div>`;
    return;
  }
  el.innerHTML = sessions.map((s) => `
    <div class="card upcoming-card">
      <div class="time-badge">Upcoming</div>
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">${escHtml(s.subject)} · ${escHtml(s.teacher_name)}</p>
      <p class="schedule-meta">&#128197; ${formatDate(s.start_time)}${s.end_time ? " → " + formatDate(s.end_time) : ""}</p>
      ${s.is_live ? `<button class="btn-join" onclick="joinClass(this)" data-id="${s.id}" data-title="${escHtml(s.title)}" data-subject="${escHtml(s.subject)}" data-teacher="${escHtml(s.teacher_name)}">Join</button>` : `<p class="notify-hint">You'll be notified when class starts</p>`}
    </div>
  `).join("");
}

function loadPlans() {
  const el = document.getElementById("plans-grid");
  if (!el) return;
  el.innerHTML = LIVE_PLANS.map((g) => `
    <div class="plan-group">
      <h3>${escHtml(g.group)}</h3>
      <div class="card-grid">
        ${g.plans.map((p) => `
          <div class="card plan-card">
            <h4>${escHtml(p.name)}</h4>
            <p class="plan-price">${escHtml(p.price)}</p>
            <ul>${p.features.map((f) => `<li>${escHtml(f)}</li>`).join("")}</ul>
            <button class="btn-action" onclick="alert('Payment via Flutterwave coming soon. Contact Scholaxia admin to subscribe.')">Subscribe</button>
          </div>
        `).join("")}
      </div>
    </div>
  `).join("");
}

async function joinClass(btn) {
  const classId = typeof btn === "string" ? btn : btn.dataset.id;
  const card = typeof btn === "string" ? null : btn;
  try {
    const data = await api(`/api/v1/live-classes/${classId}/join`, { method: "POST" });
    localStorage.setItem("live_session", JSON.stringify({
      class_id: classId,
      classId: classId,
      room_id: data.room_id,
      channel_id: data.channel_id,
      agora_token: data.agora_token,
      uid: data.uid,
      app_id: data.app_id,
      title: data.title || (card && card.dataset.title) || "Live Class",
      subject: data.subject || (card && card.dataset.subject) || "",
      teacher_name: (card && card.dataset.teacher) || "",
      role: "student",
    }));
    window.location.href = "classroom.html";
  } catch (e) {
    alert(e.message);
  }
}

async function loadMyRequests() {
  try {
    const reqs = await api("/api/v1/live-classes/requests/mine");
    renderRequests(reqs || []);
  } catch { /* ignore */ }
}

function renderRequests(reqs) {
  const el = document.getElementById("my-requests");
  if (!reqs.length) { el.innerHTML = ""; return; }
  el.innerHTML = reqs.slice(0, 5).map((r) => `
    <div class="req-item">
      <span>${escHtml(r.subject)} — ${escHtml(r.topic || r.description || "")}</span>
      <span>${escHtml(r.status)}</span>
    </div>
  `).join("");
}

async function submitSessionRequest() {
  const subject = document.getElementById("req-subject").value.trim();
  const topic = document.getElementById("req-topic").value.trim();
  if (!subject || !topic) { alert("Fill in subject and topic."); return; }
  try {
    await api("/api/v1/live-classes/requests", {
      method: "POST",
      body: JSON.stringify({ subject, topic, description: topic }),
    });
    document.getElementById("req-topic").value = "";
    alert("Request sent! A teacher will review it.");
    loadMyRequests();
  } catch (e) {
    alert(e.message);
  }
}

/* ── School Exam ── */

async function loadSchoolExams() {
  document.getElementById("school-grid").innerHTML = `<div class="loading">Loading…</div>`;
  try {
    const data = await api("/api/v1/cbt/exams/for-me");
    if (!data) return;
    schoolExams = data.school_exams || [];
    renderSchoolGrid();
  } catch (e) {
    const msg = e.message.includes("setup") ? `${e.message} Go to Profile to complete setup.` : e.message;
    document.getElementById("school-grid").innerHTML = `<div class="empty">${escHtml(msg)}</div>`;
  }
}

function renderSchoolGrid() {
  const el = document.getElementById("school-grid");
  if (!schoolExams.length) {
    el.innerHTML = `<div class="empty">No school exams scheduled for your subjects.</div>`;
    return;
  }
  el.innerHTML = schoolExams.map((e) => `
    <div class="card">
      <div class="time-badge">&#128248; School Exam</div>
      <h3>${escHtml(e.title)}</h3>
      <p class="meta">${escHtml(e.subject)} · ${e.total_questions} questions · ${e.duration_minutes} min</p>
      ${e.scheduled_start ? `<p class="meta">${formatDate(e.scheduled_start)} – ${formatDate(e.scheduled_end)}</p>` : ""}
      <button class="btn-join" onclick="openSchoolExam('${e.id}')">Enter Exam</button>
    </div>
  `).join("");
}

function openSchoolExam(examId) {
  pendingSchoolExamId = examId;
  document.getElementById("camera-modal").classList.remove("hidden");
  navigator.mediaDevices.getUserMedia({ video: true })
    .then((stream) => {
      cameraStream = stream;
      document.getElementById("camera-preview").srcObject = stream;
    })
    .catch(() => alert("Camera access is required for school exams."));
}

function closeCameraModal() {
  document.getElementById("camera-modal").classList.add("hidden");
  pendingSchoolExamId = null;
  stopCamera();
}

function stopCamera() {
  if (cameraStream) {
    cameraStream.getTracks().forEach((t) => t.stop());
    cameraStream = null;
  }
}

async function startSchoolExam() {
  const examId = pendingSchoolExamId;
  closeCameraModal();
  await beginExam(examId, true);
}

/* ── CBT Practice ── */

async function loadCbtExams() {
  document.getElementById("cbt-grid").classList.remove("hidden");
  document.getElementById("exam-screen").classList.add("hidden");
  document.getElementById("result-screen").classList.add("hidden");
  document.getElementById("cbt-grid").innerHTML = `<div class="loading">Loading…</div>`;
  try {
    const data = await api("/api/v1/cbt/exams/for-me");
    if (!data) return;
    practiceExams = data.practice_exams || [];
    schoolExams = data.school_exams || [];
    renderCbtGrid();
  } catch (e) {
    const msg = e.message.includes("setup") ? `${e.message} Go to Profile to complete setup.` : e.message;
    document.getElementById("cbt-grid").innerHTML = `<div class="empty">${escHtml(msg)}</div>`;
  }
}

function renderCbtGrid() {
  const el = document.getElementById("cbt-grid");
  if (!practiceExams.length) {
    el.innerHTML = `<div class="empty">No practice exams for your subjects yet. Complete exam setup in Profile.</div>`;
    return;
  }
  el.innerHTML = practiceExams.map((e) => `
    <div class="card">
      <div class="time-badge">${escHtml(e.exam_type)} Practice</div>
      <h3>${escHtml(e.title)}</h3>
      <p class="meta">${escHtml(e.subject)} · ${e.total_questions} questions · ${e.duration_minutes} min</p>
      <button class="btn-join" onclick="beginExam('${e.id}', false)">Start Exam</button>
    </div>
  `).join("");
}

async function beginExam(examId, isSchool) {
  try {
    const session = await api(`/api/v1/cbt/sessions/${examId}/start`, { method: "POST" });
    const exam = await api(`/api/v1/cbt/exams/${examId}/download`);
    currentSession = { ...session, is_school_exam: isSchool };
    currentExam = exam;
    answers = {};
    currentQ = 0;
    secondsLeft = (exam.duration_minutes || 30) * 60;

    document.getElementById("cbt-grid").classList.add("hidden");
    document.getElementById("result-screen").classList.add("hidden");
    document.getElementById("exam-screen").classList.remove("hidden");
    document.getElementById("exam-title").textContent = exam.title;
    document.getElementById("exam-meta").textContent =
      `${exam.subject} · ${exam.questions.length} questions · ${isSchool ? "School (proctored)" : "Practice"}`;

    buildQNav();
    renderQuestion();
    startTimer();
  } catch (e) {
    alert(e.message);
    stopCamera();
  }
}

function startTimer() {
  clearInterval(timerInterval);
  updateTimerDisplay();
  timerInterval = setInterval(() => {
    secondsLeft--;
    updateTimerDisplay();
    if (secondsLeft <= 0) submitExam();
  }, 1000);
}

function updateTimerDisplay() {
  const m = Math.floor(secondsLeft / 60);
  const s = secondsLeft % 60;
  document.getElementById("exam-timer").textContent =
    `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
}

function buildQNav() {
  const nav = document.getElementById("q-nav");
  nav.innerHTML = currentExam.questions.map((_, i) => `
    <button class="q-btn ${i === currentQ ? "current" : ""} ${answers[i] ? "answered" : ""}"
      onclick="goToQuestion(${i})">${i + 1}</button>
  `).join("");
}

function renderQuestion() {
  const q = currentExam.questions[currentQ];
  if (!q) return;
  document.getElementById("q-num").textContent = `Question ${currentQ + 1} of ${currentExam.questions.length}`;
  document.getElementById("q-text").textContent = q.question_text;
  const imgEl = document.getElementById("q-image");
  if (q.image_url) {
    imgEl.classList.remove("hidden");
    imgEl.innerHTML = `<img src="${escHtml(q.image_url)}" alt="Question diagram" />`;
  } else {
    imgEl.classList.add("hidden");
    imgEl.innerHTML = "";
  }
  const opts = ["A", "B", "C", "D"];
  document.getElementById("q-options").innerHTML = opts.map((k) => {
    const text = q[`option_${k.toLowerCase()}`] || q.options?.[k] || "";
    if (!text) return "";
    return `
      <div class="opt ${answers[currentQ] === k ? "selected" : ""}" onclick="selectAnswer('${k}')">
        <span class="opt-key">${k}</span>
        <span>${escHtml(text)}</span>
      </div>
    `;
  }).join("");
  buildQNav();
}

function selectAnswer(key) {
  answers[currentQ] = key;
  renderQuestion();
}

function goToQuestion(i) {
  currentQ = i;
  renderQuestion();
}

function prevQuestion() {
  if (currentQ > 0) { currentQ--; renderQuestion(); }
}

function nextQuestion() {
  if (currentQ < currentExam.questions.length - 1) { currentQ++; renderQuestion(); }
}

async function submitExam() {
  clearInterval(timerInterval);
  const answerMap = {};
  currentExam.questions.forEach((q, i) => {
    if (answers[i]) answerMap[q.id] = answers[i];
  });

  try {
    const result = await api("/api/v1/cbt/sessions/submit", {
      method: "POST",
      body: JSON.stringify({
        session_id: currentSession.session_id,
        answers: answerMap,
        is_auto_submit: secondsLeft <= 0,
      }),
    });
    showResult(result);
  } catch (e) {
    alert(e.message);
    closeExam();
  }
}

function showResult(result) {
  document.getElementById("exam-screen").classList.add("hidden");
  document.getElementById("result-screen").classList.remove("hidden");
  const pct = result.score_percent != null ? Math.round(result.score_percent) : "—";
  document.getElementById("score-display").textContent = `${pct}%`;
  document.getElementById("result-detail").textContent =
    `${result.correct || 0} correct · ${result.wrong || 0} wrong · ${result.total || 0} total`;
  stopCamera();
}

function closeExam() {
  clearInterval(timerInterval);
  stopCamera();
  currentExam = null;
  currentSession = null;
  loadCbtExams();
}

/* ── Profile ── */

async function loadProfile() {
  try {
    const p = await api("/api/v1/students/me");
    document.getElementById("profile-name").textContent = p.full_name || "—";
    document.getElementById("profile-email").textContent = p.email || getUser().email;
    document.getElementById("pf-exam").textContent = p.exam_type || "Not set";
    document.getElementById("pf-level").textContent = p.education_level || "—";
    document.getElementById("pf-subjects").textContent = (p.selected_subjects || []).join(", ") || "—";
    document.getElementById("pf-sub").textContent = p.has_active_subscription ? "Active" : "Free";
    localStorage.setItem("sia_exam_type", p.exam_type || "");
    localStorage.setItem("sia_subjects", JSON.stringify(p.selected_subjects || []));
    if (p.education_level) localStorage.setItem("sia_education_level", p.education_level);
    document.getElementById("sidebar-exam").textContent = p.exam_type || "Student";

    if (p.setup_complete) {
      document.getElementById("setup-card").style.display = "none";
    } else {
      document.getElementById("setup-card").style.display = "block";
      renderSubjectPicker();
    }
  } catch (e) {
    alert(e.message);
  }
}

async function loadSubjects() {
  try {
    const data = await api("/api/v1/students/subjects");
    allSubjects = data.subjects || [];
  } catch { /* ignore */ }
}

function renderSubjectPicker() {
  const examType = document.getElementById("setup-exam-type").value;
  const max = examType === "JAMB" ? 4 : 9;
  const el = document.getElementById("subject-picker");
  el.innerHTML = allSubjects.map((s, i) => `
    <span class="subj-chip ${selectedSubjects.includes(s) ? "selected" : ""}"
      data-idx="${i}" onclick="toggleSubjectByIdx(${i}, ${max})">${escHtml(s)}</span>
  `).join("");
}

function toggleSubjectByIdx(idx, max) {
  const subject = allSubjects[idx];
  if (!subject) return;
  toggleSubject(subject, max);
}

function toggleSubject(subject, max) {
  const idx = selectedSubjects.indexOf(subject);
  if (idx >= 0) selectedSubjects.splice(idx, 1);
  else if (selectedSubjects.length < max) selectedSubjects.push(subject);
  else alert(`Select exactly ${max} subjects for ${document.getElementById("setup-exam-type").value}.`);
  renderSubjectPicker();
}

document.addEventListener("DOMContentLoaded", () => {
  const sel = document.getElementById("setup-exam-type");
  if (sel) sel.addEventListener("change", () => { selectedSubjects = []; renderSubjectPicker(); });
});

async function saveSetup() {
  const examType = document.getElementById("setup-exam-type").value;
  const level = document.getElementById("setup-level").value;
  const needed = examType === "JAMB" ? 4 : 9;
  const err = document.getElementById("setup-error");
  if (selectedSubjects.length !== needed) {
    err.textContent = `Select exactly ${needed} subjects.`;
    return;
  }
  try {
    await api("/api/v1/students/setup-exam", {
      method: "POST",
      body: JSON.stringify({
        exam_type: examType,
        subjects: selectedSubjects,
        education_level: level,
      }),
    });
    localStorage.setItem("sia_exam_type", examType);
    localStorage.setItem("sia_subjects", JSON.stringify(selectedSubjects));
    err.textContent = "";
    alert("Exam setup saved!");
    loadProfile();
    refreshPage();
  } catch (e) {
    err.textContent = e.message;
  }
}
