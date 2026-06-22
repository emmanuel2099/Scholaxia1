const PAGE_TITLES = {
  live: "Live Class",
  school: "Scholaxia Exams",
  "school-portal": "School Exam",
  cbt: "CBT",
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
let timerEndsAt = 0;
let secondsLeft = 0;
let pendingSchoolExamId = null;
let cameraStream = null;
let activeSubjectTab = "";

function cbtOfflineCacheKey(examId, year) {
  return `sia_cbt_pack_${examId}_${year || "any"}`;
}

function loadOfflineCbtPack(examId, year) {
  try {
    const raw = localStorage.getItem(cbtOfflineCacheKey(examId, year));
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function saveOfflineCbtPack(examId, year, portal) {
  try {
    localStorage.setItem(cbtOfflineCacheKey(examId, year), JSON.stringify({
      ...portal,
      cached_at: Date.now(),
      examId,
      year: year || "",
    }));
  } catch (e) {
    console.warn("Could not cache CBT offline", e);
  }
}

async function startPortalExamCached(examId, opts) {
  const year = (opts && opts.year) || "";
  if (navigator.onLine) {
    try {
      const portal = await beginPortalExam(examId, opts);
      saveOfflineCbtPack(examId, year, portal);
      return portal;
    } catch (e) {
      const cached = loadOfflineCbtPack(examId, year);
      if (cached) return cached;
      throw e;
    }
  }
  const cached = loadOfflineCbtPack(examId, year);
  if (cached) return cached;
  throw new Error("You are offline. Download this exam year once while online, then practice without data.");
}

function applyExamYearLabel(utmeYear, portal) {
  const year = utmeYear || portal?.selected_year || portal?.exam?.selected_year || "";
  const titleEl = document.getElementById("exam-title");
  const metaEl = document.getElementById("exam-meta");
  if (!titleEl || !metaEl || !currentExam) return;
  const examLabel = formatExamType(currentExam.exam_type || portal?.exam?.exam_type || getUser().examType);
  const yearPrefix = currentExam.exam_type === "JAMB" ? "UTME" : examLabel;
  if (year) {
    titleEl.textContent = `${currentExam.title} — ${yearPrefix} ${year}`;
    metaEl.textContent = portal.meta && portal.meta.includes(String(year))
      ? portal.meta
      : `${yearPrefix} ${year} · ${portal.meta || ""}`.replace(/ · $/, "");
  } else {
    titleEl.textContent = currentExam.title;
    metaEl.textContent = portal.meta || "";
  }
}

function subjectLabelFromTopic(topic) {
  return String(topic || "Subject").replace(/\s*\(\d{4}\)\s*$/, "").trim() || "Subject";
}

function getActiveSectionIndex() {
  if (!currentExam || !currentExam.sections) return -1;
  return currentExam.sections.findIndex(
    (sec) => currentQ >= sec.start && currentQ < sec.start + sec.count
  );
}

function buildSubjectTabs() {
  const el = document.getElementById("subject-tabs");
  if (!el || !currentExam || !currentExam.sections || currentExam.sections.length < 2) {
    if (el) { el.innerHTML = ""; el.classList.add("hidden"); }
    return;
  }
  el.classList.remove("hidden");
  const activeIdx = getActiveSectionIndex();
  el.innerHTML = currentExam.sections.map((sec, idx) => {
    const answered = Array.from({ length: sec.count }, (_, i) => answers[sec.start + i]).filter(Boolean).length;
    return `<button type="button" class="subject-tab ${idx === activeIdx ? "active" : ""}"
      onclick="goToSubject(${sec.start})">${escHtml(sec.subject)} <span class="subj-count">${answered}/${sec.count}</span></button>`;
  }).join("");
}

function showSubjectStartPicker() {
  const picker = document.getElementById("subject-start-picker");
  const list = document.getElementById("subject-start-list");
  if (!picker || !list || !currentExam?.sections?.length) return;
  list.innerHTML = currentExam.sections.map((sec) => `
    <button type="button" class="subject-start-btn" onclick="startWithSubject(${sec.start})">
      <strong>${escHtml(sec.subject)}</strong>
      <span>${sec.count} questions</span>
    </button>
  `).join("");
  picker.classList.remove("hidden");
}

function hideSubjectStartPicker() {
  const picker = document.getElementById("subject-start-picker");
  if (picker) picker.classList.add("hidden");
}

function startWithSubject(index) {
  currentQ = index;
  hideSubjectStartPicker();
  renderQuestion();
}

function goToSubject(index) {
  currentQ = index;
  renderQuestion();
}

window.onload = async () => {
  if (!getToken()) {
    window.location.href = "index.html";
    return;
  }
  initUserUI();
  bindCbtGridClicks();
  await syncStudentProfile();
  loadSubjects();
  refreshPage();
};

function showCbtLoadingOverlay(message) {
  let el = document.getElementById("cbt-loading-overlay");
  if (!el) {
    el = document.createElement("div");
    el.id = "cbt-loading-overlay";
    el.className = "cbt-loading-overlay hidden";
    document.getElementById("page-cbt").appendChild(el);
  }
  el.innerHTML = `<div class="cbt-loading-box"><div class="cbt-spinner"></div><p>${escHtml(message || "Loading exam…")}</p></div>`;
  el.classList.remove("hidden");
}

function hideCbtLoadingOverlay() {
  const el = document.getElementById("cbt-loading-overlay");
  if (el) el.classList.add("hidden");
}

function bindCbtGridClicks() {
  const grid = document.getElementById("cbt-grid");
  if (!grid || grid.dataset.clickBound) return;
  grid.dataset.clickBound = "1";
  grid.addEventListener("click", (ev) => {
    const btn = ev.target.closest("[data-exam-id]");
    if (!btn || btn.disabled) return;
    ev.preventDefault();
    const card = btn.closest(".card");
    const year = card?.querySelector(".cbt-year-select")?.value || "";
    beginExam(btn.dataset.examId, false, year);
  });
}

function showCbtExamView() {
  const hero = document.getElementById("cbt-page-hero");
  if (hero) hero.classList.add("hidden");
  document.getElementById("cbt-grid").classList.add("hidden");
  document.getElementById("result-screen").classList.add("hidden");
  const screen = document.getElementById("exam-screen");
  screen.classList.remove("hidden");
  const main = document.querySelector(".main-content-topnav");
  if (main) main.scrollTop = 0;
  screen.scrollIntoView({ behavior: "smooth", block: "start" });
}

function showCbtListView() {
  const hero = document.getElementById("cbt-page-hero");
  if (hero) hero.classList.remove("hidden");
  document.getElementById("exam-screen").classList.add("hidden");
  document.getElementById("result-screen").classList.add("hidden");
  document.getElementById("cbt-grid").classList.remove("hidden");
}

function setCbtStartLoading(loading) {
  document.querySelectorAll("#cbt-grid [data-exam-id]").forEach((btn) => {
    btn.disabled = loading;
    if (loading) {
      if (!btn.dataset.label) btn.dataset.label = btn.textContent;
      btn.textContent = "Please wait…";
    } else if (btn.dataset.label) {
      btn.textContent = btn.dataset.label;
    }
  });
}

async function syncStudentProfile() {
  try {
    const p = await api("/api/v1/students/me");
    if (!p) return null;
    if (p.full_name) localStorage.setItem("sia_name", p.full_name);
    if (p.exam_type) localStorage.setItem("sia_exam_type", formatExamType(p.exam_type));
    localStorage.setItem("sia_subjects", JSON.stringify(p.selected_subjects || []));
    if (p.education_level) localStorage.setItem("sia_education_level", p.education_level);
    document.getElementById("sidebar-exam").textContent = formatExamType(p.exam_type);
    return p;
  } catch (e) {
    return null;
  }
}

function formatExamType(value) {
  const raw = String(value || "").replace(/^ExamType\./i, "").replace(/-/g, "_").toUpperCase();
  if (raw === "POST_UTME" || raw === "POSTUTME") return "POST-UTME";
  return raw || "Student";
}

function subjectLimitForExamType(examType) {
  const t = formatExamType(examType).toUpperCase().replace("-", "_");
  if (t === "JAMB" || t === "POST_UTME") return 4;
  return 9;
}

function subjectMinimumForExamType(examType) {
  const t = formatExamType(examType).toUpperCase().replace("-", "_");
  if (t === "JAMB" || t === "POST_UTME") return 4;
  return 1;
}

function initUserUI() {
  const user = getUser();
  const initial = firstName(user.name)[0].toUpperCase();
  document.getElementById("sidebar-name").textContent = firstName(user.name);
  document.getElementById("sidebar-exam").textContent = formatExamType(user.examType);
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
  if (isCbtExamActive() && page !== "cbt") {
    if (!confirm("Leave the exam? Your timer will keep running.")) return;
  }
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
  else if (currentPage === "cbt") {
    if (!isCbtExamActive()) loadCbtExams();
  }
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

function stripSeedPracticeExams(list, examType) {
  const type = formatExamType(examType || "").toUpperCase();
  if (type !== "JAMB" && type !== "WAEC" && type !== "NECO" && type !== "POST_UTME" && type !== "POST-UTME") return list;
  if (!window.CBT_PORTAL_CONFIG) return list;
  return (list || []).filter((p) => p.is_school_exam);
}

async function loadCbtExams() {
  if (isCbtExamActive()) return;
  showCbtListView();
  document.getElementById("cbt-grid").innerHTML = `<div class="loading">Loading…</div>`;
  await syncStudentProfile();
  const user = getUser();
  let profileComplete = false;
  try {
    const data = await api("/api/v1/cbt/exams/for-me");
    if (!data) return;
    profileComplete = true;
    practiceExams = stripSeedPracticeExams(data.practice_exams || [], data.exam_type || user.examType);
    schoolExams = data.school_exams || [];
    if (typeof loadPortalPracticeExams === "function") {
      const portalExams = await loadPortalPracticeExams();
      const combined = portalExams.find((e) => e.is_combined);
      if (combined) {
        practiceExams = practiceExams.filter((p) => p.is_school_exam);
        practiceExams.unshift(combined);
      } else if (portalExams.length) {
        practiceExams = practiceExams.filter((p) => p.is_school_exam);
        practiceExams.push(...portalExams);
      }
    }
    renderCbtGrid({ profileComplete: true });
  } catch (e) {
    const profile = await syncStudentProfile();
    profileComplete = !!(profile && profile.setup_complete);
    if (typeof loadPortalPracticeExams === "function") {
      try {
        practiceExams = await loadPortalPracticeExams(profile);
        if (practiceExams.length) {
          renderCbtGrid({ profileComplete: true });
          return;
        }
      } catch (portalErr) {
        console.warn("Portal CBT fallback failed", portalErr);
      }
    }
    if (!profileComplete) {
      const msg = e.message.includes("setup") ? `${e.message} Go to Profile to complete setup.` : e.message;
      document.getElementById("cbt-grid").innerHTML = `<div class="empty">${escHtml(msg)}</div>`;
      return;
    }
    renderCbtGrid({ profileComplete: true });
  }
}

function renderCbtYearPicker(exam) {
  if (!exam.is_aloc || !exam.available_years || !exam.available_years.length) return "";
  const yearTag = exam.exam_type === "JAMB" ? "UTME"
    : (exam.exam_type === "POST_UTME" ? "POST-UTME" : (exam.exam_type || "Exam"));
  const bySubject = exam.years_by_subject || {};
  const subjectRows = Object.keys(bySubject).map((s) => {
    const years = bySubject[s] || [];
    const recent = years.filter((y) => Number(y) >= 2020).slice(0, 6).map((y) => `<span class="year-mini">${escHtml(y)}</span>`).join("");
    const older = years.filter((y) => Number(y) < 2020).length
      ? `<span class="year-mini muted">+${years.filter((y) => Number(y) < 2020).length} older</span>`
      : "";
    return `<div class="year-subject-row"><span class="year-subject-name">${escHtml(s)}</span><div class="year-mini-row">${recent}${older}</div></div>`;
  }).join("");
  const common = (exam.common_years || []).length
    ? `<p class="year-common-note"><strong>All 4 subjects available:</strong> ${exam.common_years.slice(0, 10).map((y) => escHtml(y)).join(", ")}</p>`
    : "";
  const commonSet = new Set(exam.common_years || []);
  const yearOptions = exam.available_years.map((y) => {
    const tag = commonSet.has(y) ? " ✓ all subjects" : "";
    return `<option value="${escHtml(y)}">${escHtml(yearTag)} ${escHtml(y)}${tag}</option>`;
  }).join("");
  const options = [
    `<option value="">Any year — mixed past papers</option>`,
    ...yearOptions,
  ].join("");
  return `
    <div class="cbt-year-picker">
      <div class="year-picker-row">
        <label class="year-picker-label" for="cbt-utme-year">Exam year</label>
        <select class="cbt-year-select" aria-label="Choose UTME year">${options}</select>
      </div>
      <p class="year-picker-hint">Pick a year — only questions from that UTME paper will load.</p>
      <details class="year-details">
        <summary>View years per subject</summary>
        <div class="year-subject-grid">${subjectRows}</div>
      </details>
      ${common}
    </div>`;
}

function renderCbtGrid(opts) {
  opts = opts || {};
  const el = document.getElementById("cbt-grid");
  const user = getUser();
  const hasSetup = opts.profileComplete || (user.examType && user.subjects && user.subjects.length > 0);
  if (!practiceExams.length) {
    if (!hasSetup) {
      el.innerHTML = `
        <div class="empty-state-premium">
          <div class="empty-icon">&#127891;</div>
          <h3>Complete your exam setup</h3>
          <p>Go to <strong>Profile</strong> and pick JAMB, WAEC, NECO or POST-UTME plus your subjects.</p>
          <button type="button" class="btn-action" onclick="showPage('profile')">Set up subjects</button>
        </div>`;
      return;
    }
    el.innerHTML = `
      <div class="empty-state-premium">
        <div class="empty-icon">&#128218;</div>
        <h3>No CBT papers loaded</h3>
        <p>Your profile is set (${escHtml(formatExamType(user.examType))} — ${escHtml((user.subjects || []).join(", "))}). Tap refresh or check your connection.</p>
        <button type="button" class="btn-action" onclick="refreshPage()">Refresh</button>
      </div>`;
    return;
  }
  el.innerHTML = practiceExams.map((e) => {
    const combinedClass = e.is_combined ? " card-combined" : "";
    const subjectMeta = e.is_combined && e.subjects
      ? `<span class="subject-chips">${e.subjects.map((s) => `<span class="subject-chip">${escHtml(s)}</span>`).join("")}</span>`
      : escHtml(e.subject);
    const durationLabel = e.duration_minutes >= 240 ? "4 hrs"
      : (e.duration_minutes >= 120 ? "2 hrs" : `${e.duration_minutes} min`);
    const startLabel = e.is_combined
      ? `Start Full ${escHtml(formatExamType(e.exam_type))} CBT`
      : "Start Exam";
    const missingNote = e.missing_subjects && e.missing_subjects.length
      ? `<p class="meta-warn">Not in your CBT bank yet: ${e.missing_subjects.map((s) => escHtml(s)).join(", ")} — pick a bank subject in Profile.</p>`
      : "";
    return `
    <div class="card${combinedClass}">
      <div class="time-badge">${escHtml(e.source || e.exam_type + " Practice")}</div>
      <h3>${escHtml(e.title)}</h3>
      <p class="meta">${subjectMeta} · ${e.total_questions} questions · ${durationLabel}</p>
      ${missingNote}
      ${renderCbtYearPicker(e)}
      <p class="cbt-offline-note">&#128241; After first download, exam works offline — no data needed during practice.</p>
      <button type="button" class="btn-join" data-exam-id="${escHtml(e.id)}">${startLabel}</button>
    </div>`;
  }).join("");
}

async function beginExam(examId, isSchool, utmeYear) {
  if (!examId) {
    alert("Exam not found. Refresh the page and try again.");
    return;
  }
  setCbtStartLoading(true);
  const user = getUser();
  const examLabel = formatExamType(user.examType || "JAMB");
  const yearLabel = utmeYear ? `${examLabel} ${utmeYear}` : `mixed ${examLabel} years`;
  showCbtLoadingOverlay(`Loading ${examLabel} CBT (${yearLabel})… This can take up to a minute.`);
  try {
    if (typeof isPortalExamId === "function" && isPortalExamId(examId)) {
      const portal = await startPortalExamCached(examId, { year: utmeYear || "" });
      currentSession = portal.session;
      currentExam = portal.exam;
      answers = {};
      currentQ = 0;
      secondsLeft = resolveExamDurationSeconds(portal.exam, portal);

      showCbtExamView();
      applyExamYearLabel(utmeYear, portal);
      buildSubjectTabs();
      if (currentExam.sections && currentExam.sections.length > 1) {
        showSubjectStartPicker();
      }
      buildQNav();
      renderQuestion();
      startTimer();
      return;
    }
    const session = await api(`/api/v1/cbt/sessions/${examId}/start`, { method: "POST" });
    const exam = await api(`/api/v1/cbt/exams/${examId}/download`);
    if (!exam.questions || !exam.questions.length) {
      throw new Error("This exam has no questions yet. Try another subject or refresh.");
    }
    currentSession = { ...session, is_school_exam: isSchool };
    currentExam = exam;
    answers = {};
    currentQ = 0;
    secondsLeft = resolveExamDurationSeconds(exam, {
      secondsLeft: (session.duration_minutes || exam.duration_minutes || 30) * 60,
    });

    showCbtExamView();
    document.getElementById("exam-title").textContent = exam.title;
    document.getElementById("exam-meta").textContent =
      `${exam.subject} · ${exam.questions.length} questions · ${isSchool ? "School (proctored)" : "Practice"}`;

    buildQNav();
    renderQuestion();
    startTimer();
  } catch (e) {
    const offline = typeof navigator !== "undefined" && !navigator.onLine;
    const msg = offline
      ? "You are offline. Open this exam once while online to download it — then you can practice without mobile data."
      : (e.message || "Could not start exam. Check your connection and try again.");
    alert(msg);
    stopCamera();
  } finally {
    hideCbtLoadingOverlay();
    setCbtStartLoading(false);
  }
}

function isCbtExamActive() {
  const screen = document.getElementById("exam-screen");
  return !!(currentExam && screen && !screen.classList.contains("hidden"));
}

function resolveExamDurationSeconds(exam, portal) {
  const mins = Number(exam && exam.duration_minutes) || 120;
  const fromPortal = portal && portal.secondsLeft;
  const parsed = Number(fromPortal);
  if (Number.isFinite(parsed) && parsed > 0) return Math.floor(parsed);
  return Math.floor(mins) * 60;
}

function stopCbtTimer() {
  if (timerInterval) {
    clearInterval(timerInterval);
    timerInterval = null;
  }
  timerEndsAt = 0;
}

function tickCbtTimer() {
  if (!timerEndsAt) return;
  secondsLeft = Math.max(0, Math.ceil((timerEndsAt - Date.now()) / 1000));
  updateTimerDisplay();
  if (secondsLeft <= 0) {
    stopCbtTimer();
    submitExam(true);
  }
}

function startTimer() {
  stopCbtTimer();
  if (!Number.isFinite(secondsLeft) || secondsLeft <= 0) {
    secondsLeft = resolveExamDurationSeconds(currentExam, null);
  }
  timerEndsAt = Date.now() + secondsLeft * 1000;
  updateTimerDisplay();
  timerInterval = setInterval(tickCbtTimer, 250);
}

function updateTimerDisplay() {
  const el = document.getElementById("exam-timer");
  if (!el) return;
  const safe = Number.isFinite(secondsLeft) ? Math.max(0, secondsLeft) : 0;
  const m = Math.floor(safe / 60);
  const s = safe % 60;
  el.textContent = `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  el.className = "exam-timer";
  if (safe <= 300 && safe > 60) el.classList.add("warning");
  if (safe <= 60) el.classList.add("danger");
}

function buildQNav() {
  if (!currentExam || !currentExam.questions) return;
  const nav = document.getElementById("q-nav");
  const sections = currentExam.sections || [];
  nav.innerHTML = currentExam.questions.map((q, i) => {
    const sec = sections.find((s) => i >= s.start && i < s.start + s.count);
    const secClass = sec ? ` sec-${sections.indexOf(sec)}` : "";
    return `<button type="button" class="q-btn ${i === currentQ ? "current" : ""} ${answers[i] ? "answered" : ""}${secClass}"
      onclick="goToQuestion(${i})">${i + 1}</button>`;
  }).join("");
  buildSubjectTabs();
}

function renderQuestion() {
  if (!currentExam || !currentExam.questions) return;
  const q = currentExam.questions[currentQ];
  if (!q) return;
  document.getElementById("q-num").textContent =
    `Question ${currentQ + 1} of ${currentExam.questions.length}${q.topic ? " · " + subjectLabelFromTopic(q.topic) : ""}`;
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

async function submitExam(force) {
  if (!currentExam || !currentExam.questions) {
    if (!force) alert("No exam loaded.");
    return;
  }
  if (!force && !confirm("Submit your exam now? You cannot change answers after submitting.")) return;

  stopCbtTimer();
  hideSubjectStartPicker();

  if (currentSession && currentSession.is_portal && typeof scorePortalExam === "function") {
    showResult(scorePortalExam(currentExam, answers));
    return;
  }
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
  hideSubjectStartPicker();
  hideCbtLoadingOverlay();
  document.getElementById("exam-screen").classList.add("hidden");
  const resultEl = document.getElementById("result-screen");
  resultEl.classList.remove("hidden");
  resultEl.scrollIntoView({ behavior: "smooth", block: "start" });
  const raw = result.score_percent != null ? result.score_percent : result.percentage;
  const pct = raw != null ? Math.round(raw) : "—";
  document.getElementById("score-display").textContent = `${pct}%`;
  const correct = result.correct ?? result.total_correct ?? 0;
  const wrong = result.wrong ?? result.total_wrong ?? 0;
  const total = result.total ?? (correct + wrong);
  const lines = [`${correct} correct · ${wrong} wrong · ${total} total`];
  if (result.by_subject) {
    const subs = Object.keys(result.by_subject).map((k) => {
      const s = result.by_subject[k];
      return `${escHtml(k)}: ${s.correct}/${s.total}`;
    });
    lines.push(subs.join(" · "));
  }
  document.getElementById("result-detail").innerHTML = lines.join("<br>");
  stopCamera();
}

function closeExam() {
  stopCbtTimer();
  stopCamera();
  hideSubjectStartPicker();
  hideCbtLoadingOverlay();
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
    localStorage.setItem("sia_exam_type", formatExamType(p.exam_type) || "");
    localStorage.setItem("sia_subjects", JSON.stringify(p.selected_subjects || []));
    if (p.education_level) localStorage.setItem("sia_education_level", p.education_level);
    document.getElementById("sidebar-exam").textContent = formatExamType(p.exam_type);

    const setupCard = document.getElementById("setup-card");
    const setupTitle = document.getElementById("setup-card-title");
    if (setupCard) setupCard.style.display = "block";
    if (setupTitle) {
      setupTitle.textContent = p.setup_complete ? "Update exam profile" : "Exam setup & subjects";
    }
    const examSel = document.getElementById("setup-exam-type");
    if (examSel && p.exam_type) {
      const et = String(p.exam_type).replace(/-/g, "_").toUpperCase();
      examSel.value = et === "POSTUTME" ? "POST_UTME" : et;
    }
    const levelSel = document.getElementById("setup-level");
    if (levelSel && p.education_level) levelSel.value = p.education_level;
    selectedSubjects = [...(p.selected_subjects || [])];
    if (allSubjects.length) renderSubjectPicker();
    else loadSubjects().then(() => renderSubjectPicker());
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
  const max = subjectLimitForExamType(examType);
  const el = document.getElementById("subject-picker");
  const hint = document.getElementById("setup-subject-hint");
  if (hint) {
    const min = subjectMinimumForExamType(examType);
    hint.textContent = min === max
      ? `Select exactly ${max} subjects.`
      : `Select ${min} to ${max} subjects.`;
  }
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
  else alert(`You can select at most ${max} subjects for ${formatExamType(document.getElementById("setup-exam-type").value)}.`);
  renderSubjectPicker();
}

document.addEventListener("DOMContentLoaded", () => {
  const sel = document.getElementById("setup-exam-type");
  if (sel) sel.addEventListener("change", () => { selectedSubjects = []; renderSubjectPicker(); });
});

document.addEventListener("visibilitychange", () => {
  if (!document.hidden && timerEndsAt) tickCbtTimer();
});

async function saveSetup() {
  const examType = document.getElementById("setup-exam-type").value;
  const level = document.getElementById("setup-level").value;
  const min = subjectMinimumForExamType(examType);
  const max = subjectLimitForExamType(examType);
  const err = document.getElementById("setup-error");
  if (selectedSubjects.length < min || selectedSubjects.length > max) {
    err.textContent = min === max
      ? `Select exactly ${max} subjects for ${formatExamType(examType)}.`
      : `Select ${min} to ${max} subjects for ${formatExamType(examType)}.`;
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
    alert("Exam profile saved! Your CBT practice will use " + formatExamType(examType) + " subjects.");
    loadProfile();
    refreshPage();
  } catch (e) {
    err.textContent = e.message;
  }
}

window.beginExam = beginExam;
window.closeExam = closeExam;
window.submitExam = submitExam;
window.goToQuestion = goToQuestion;
window.goToSubject = goToSubject;
window.startWithSubject = startWithSubject;
window.prevQuestion = prevQuestion;
window.nextQuestion = nextQuestion;
window.selectAnswer = selectAnswer;
window.showCbtExamView = showCbtExamView;
window.showCbtListView = showCbtListView;
