const API = "https://scholaxia1.onrender.com";
const token = localStorage.getItem("sia_token") || "";
const userName = localStorage.getItem("sia_name") || "";

let practiceExams = [];
let schoolExams = [];
let currentTab = "practice";
let profileInfo = {};
let currentExam = null;
let currentSession = null;
let answers = {};
let currentQ = 0;
let timerInterval = null;
let secondsLeft = 0;
let isOffline = !navigator.onLine;
let lastResult = null;
let lastReviewData = null;
let pendingExamId = null;
let cameraStream = null;
let proctorInterval = null;

window.onload = async () => {
  if (!token) { window.location.href = "auth.html"; return; }
  document.getElementById("header-user").textContent = firstName(userName);

  const setupOk = await checkSetup();
  if (!setupOk) return;

  window.addEventListener("online",  () => { isOffline = false; document.getElementById("offline-banner").style.display = "none"; loadExams(); });
  window.addEventListener("offline", () => { isOffline = true;  document.getElementById("offline-banner").style.display = "block"; loadExams(); });
  document.addEventListener("visibilitychange", onVisibilityChange);

  if (isOffline) document.getElementById("offline-banner").style.display = "block";
  loadExams();
};

async function checkSetup() {
  try {
    const res = await fetch(`${API}/api/v1/students/setup-status`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 401) { window.location.href = "auth.html"; return false; }
    const data = await res.json();
    if (!data.setup_complete) {
      window.location.href = "setup.html";
      return false;
    }
    profileInfo = data;
    document.getElementById("profile-banner").textContent =
      `${data.exam_type} · ${(data.selected_subjects || []).join(", ")}`;
    return true;
  } catch {
    window.location.href = "setup.html";
    return false;
  }
}

function switchTab(tab) {
  currentTab = tab;
  document.getElementById("tab-practice").classList.toggle("active", tab === "practice");
  document.getElementById("tab-school").classList.toggle("active", tab === "school");
  document.getElementById("tab-desc").textContent = tab === "practice"
    ? "Download practice exams for offline use. Works without internet once saved."
    : "Teacher-scheduled exams. Camera required. Must be taken online during the scheduled time.";
  renderExamGrid();
}

function showScreen(id) {
  document.querySelectorAll(".screen").forEach(s => s.classList.remove("active"));
  document.getElementById(id).classList.add("active");
}

async function loadExams() {
  const grid = document.getElementById("exams-grid");

  if (isOffline && currentTab === "school") {
    grid.innerHTML = `<div class="empty-state">School exams require an internet connection.</div>`;
    return;
  }

  if (isOffline) {
    practiceExams = getOfflineExams();
    renderExamGrid();
    return;
  }

  grid.innerHTML = `<div class="loading-state">Loading exams…</div>`;
  try {
    const res = await fetch(`${API}/api/v1/cbt/exams/for-me`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (res.status === 401) { window.location.href = "auth.html"; return; }
    if (res.status === 400) { window.location.href = "setup.html"; return; }
    const data = await res.json();
    practiceExams = data.practice_exams || [];
    schoolExams = data.school_exams || [];
    profileInfo = data;
    document.getElementById("profile-banner").textContent =
      `${data.exam_type} · ${(data.selected_subjects || []).join(", ")}`;
    renderExamGrid();
  } catch {
    practiceExams = getOfflineExams();
    document.getElementById("offline-banner").style.display = "block";
    renderExamGrid();
  }
}

function renderExamGrid() {
  const grid = document.getElementById("exams-grid");
  const exams = currentTab === "practice" ? practiceExams : schoolExams;

  if (!exams.length) {
    grid.innerHTML = currentTab === "practice"
      ? `<div class="empty-state">No practice exams for your subjects yet.</div>`
      : `<div class="empty-state">No school exams scheduled for your subjects right now.</div>`;
    return;
  }

  const offlineIds = getOfflineExams().map(e => e.id);
  grid.innerHTML = exams.map(e => {
    const isLocal = offlineIds.includes(e.id);
    const isSchool = e.is_school_exam || currentTab === "school";
    const sched = e.scheduled_start
      ? `<div class="school-schedule">${formatTime(e.scheduled_start)} – ${formatTime(e.scheduled_end)}</div>`
      : "";
    return `
      <div class="exam-card ${isSchool ? "school-card" : ""} ${isLocal ? "offline-available" : ""}" onclick="startExam('${e.id}', ${isSchool})">
        <div class="exam-badge badge-${e.exam_type}">${isSchool ? "SCHOOL" : e.exam_type}</div>
        <h3>${escHtml(e.title)}</h3>
        <p>${escHtml(e.subject)}</p>
        ${sched}
        <div class="exam-card-footer">
          <div class="info">${e.total_questions} questions · ${e.duration_minutes} min${isSchool ? " · 📷 Camera" : ""}</div>
          <div style="display:flex;gap:8px">
            ${!isSchool && !isLocal ? `<button class="btn-download" onclick="event.stopPropagation();downloadForOffline('${e.id}','${escAttr(e.title)}')" title="Download for offline">📥</button>` : ""}
            <button class="btn-start">${isSchool ? "Enter" : "Start"}</button>
          </div>
        </div>
      </div>
    `;
  }).join("");
}

function getOfflineExams() {
  try { return JSON.parse(localStorage.getItem("cbt_offline_exams") || "[]"); } catch { return []; }
}

function saveOfflineExam(examData) {
  const exams = getOfflineExams();
  const idx = exams.findIndex(e => e.id === examData.id);
  if (idx >= 0) exams[idx] = examData; else exams.push(examData);
  localStorage.setItem("cbt_offline_exams", JSON.stringify(exams));
}

async function downloadForOffline(examId, title) {
  try {
    const res = await fetch(`${API}/api/v1/cbt/exams/${examId}/download`, {
      headers: { Authorization: `Bearer ${token}` },
    });
    if (!res.ok) {
      const d = await res.json();
      alert(d.detail || "Download failed.");
      return;
    }
    const data = await res.json();
    saveOfflineExam(data);
    alert(`"${title}" saved for offline use.`);
    loadExams();
  } catch {
    alert("Download failed. Check your connection.");
  }
}

function startExam(examId, isSchool) {
  pendingExamId = examId;
  if (isSchool) {
    document.getElementById("modal-camera").style.display = "flex";
    return;
  }
  beginExamFlow(examId, false);
}

function cancelSchoolExam() {
  pendingExamId = null;
  document.getElementById("modal-camera").style.display = "none";
}

async function enableCameraAndStart() {
  document.getElementById("modal-camera").style.display = "none";
  try {
    cameraStream = await navigator.mediaDevices.getUserMedia({ video: true, audio: false });
    document.getElementById("proctor-video").srcObject = cameraStream;
    await beginExamFlow(pendingExamId, true);
  } catch {
    alert("Camera access is required for school exams.");
    pendingExamId = null;
  }
}

async function beginExamFlow(examId, isSchool) {
  const offlineExams = getOfflineExams();
  const cached = offlineExams.find(e => e.id === examId);

  if (isSchool && isOffline) {
    alert("School exams require an internet connection.");
    return;
  }

  if (!isSchool && isOffline) {
    if (!cached) { alert("Download this exam first while online."); return; }
    currentExam = cached;
    currentSession = { session_id: `offline-${Date.now()}`, exam_id: examId, duration_minutes: cached.duration_minutes, offline: true, is_school_exam: false };
    answers = {}; currentQ = 0; beginExam(); return;
  }

  try {
    const sessionRes = await fetch(`${API}/api/v1/cbt/sessions/${examId}/start`, {
      method: "POST",
      headers: { Authorization: `Bearer ${token}` },
    });
    if (sessionRes.status === 401) { window.location.href = "auth.html"; return; }
    if (!sessionRes.ok) {
      const d = await sessionRes.json();
      alert(d.detail || "Could not start exam.");
      stopCamera();
      return;
    }
    const sessionData = await sessionRes.json();
    currentSession = { ...sessionData, offline: false };

    if (!isSchool && cached && cached.questions) {
      currentExam = { ...cached, ...sessionData };
    } else {
      const examRes = await fetch(`${API}/api/v1/cbt/exams/${examId}/download`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      currentExam = await examRes.json();
      if (!isSchool) saveOfflineExam(currentExam);
    }

    answers = {}; currentQ = 0;

    if (sessionData.camera_required || isSchool) {
      document.getElementById("school-camera-wrap").style.display = "flex";
      if (!cameraStream) {
        try {
          cameraStream = await navigator.mediaDevices.getUserMedia({ video: true });
          document.getElementById("proctor-video").srcObject = cameraStream;
        } catch {
          alert("Camera is required for this exam.");
          stopCamera();
          return;
        }
      }
      startProctoring(sessionData.session_id);
    }

    beginExam();
  } catch {
    if (!isSchool && cached) {
      currentExam = cached;
      currentSession = { session_id: `offline-${Date.now()}`, exam_id: examId, duration_minutes: cached.duration_minutes, offline: true };
      answers = {}; currentQ = 0; beginExam();
    } else {
      alert("Could not start exam. Check your connection.");
      stopCamera();
    }
  }
}

function startProctoring(sessionId) {
  clearInterval(proctorInterval);
  proctorInterval = setInterval(() => {
    if (!currentSession || currentSession.offline) return;
    fetch(`${API}/api/v1/cbt/proctor/event`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ session_id: sessionId, event_type: "camera_snapshot" }),
    }).catch(() => {});
  }, 60000);
}

function onVisibilityChange() {
  if (document.hidden && currentSession && !currentSession.offline && currentSession.camera_required) {
    fetch(`${API}/api/v1/cbt/proctor/event`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({ session_id: currentSession.session_id, event_type: "tab_switch" }),
    }).catch(() => {});
    alert("Warning: Do not leave the exam screen during a school exam.");
  }
}

function stopCamera() {
  clearInterval(proctorInterval);
  if (cameraStream) {
    cameraStream.getTracks().forEach(t => t.stop());
    cameraStream = null;
  }
  document.getElementById("school-camera-wrap").style.display = "none";
}

function beginExam() {
  const questions = currentExam.questions;
  const dur = currentSession.duration_minutes || currentExam.duration_minutes;

  document.getElementById("exam-title-sm").textContent = currentExam.title;
  document.getElementById("exam-title-top").textContent = currentExam.title;

  document.getElementById("q-nav").innerHTML = questions.map((_, i) => `
    <button class="q-dot" id="qdot-${i}" onclick="goToQuestion(${i})">${i + 1}</button>
  `).join("");

  secondsLeft = dur * 60;
  updateTimer();
  clearInterval(timerInterval);
  timerInterval = setInterval(() => {
    secondsLeft--;
    updateTimer();
    if (secondsLeft <= 0) { clearInterval(timerInterval); submitExam(true); }
  }, 1000);

  showQuestion(0);
  showScreen("screen-exam");
}

function updateTimer() {
  const m = Math.floor(secondsLeft / 60);
  const s = secondsLeft % 60;
  const timerEl = document.getElementById("exam-timer");
  timerEl.textContent = `${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`;
  timerEl.className = "exam-timer";
  if (secondsLeft <= 300) timerEl.classList.add("warning");
  if (secondsLeft <= 60) { timerEl.classList.remove("warning"); timerEl.classList.add("danger"); }
}

function showQuestion(idx) {
  const questions = currentExam.questions;
  const q = questions[idx];
  currentQ = idx;

  document.getElementById("q-number").textContent = `Question ${idx + 1}`;
  document.getElementById("q-text").textContent = q.question_text;
  document.getElementById("q-counter").textContent = `Q ${idx + 1} / ${questions.length}`;

  const imgWrap = document.getElementById("q-image-wrap");
  if (q.image_url) {
    document.getElementById("q-image").src = q.image_url;
    imgWrap.style.display = "block";
  } else {
    imgWrap.style.display = "none";
  }

  const opts = [
    { key: "A", text: q.option_a },
    { key: "B", text: q.option_b },
    { key: "C", text: q.option_c },
    { key: "D", text: q.option_d },
  ];
  document.getElementById("options-list").innerHTML = opts.map(o => `
    <button class="option-btn ${answers[q.id] === o.key ? "selected" : ""}" onclick="selectAnswer('${q.id}','${o.key}',this)">
      <span class="option-label">${o.key}</span>
      <span>${escHtml(o.text)}</span>
    </button>
  `).join("");

  document.getElementById("btn-prev").disabled = idx === 0;
  document.getElementById("btn-next").disabled = idx === questions.length - 1;

  document.querySelectorAll(".q-dot").forEach((dot, i) => {
    dot.classList.toggle("current", i === idx);
    dot.classList.toggle("answered", !!answers[questions[i].id] && i !== idx);
  });
  updateProgress();
}

function selectAnswer(qId, option, btn) {
  answers[qId] = option;
  document.querySelectorAll(".option-btn").forEach(b => b.classList.remove("selected"));
  btn.classList.add("selected");
  const idx = currentExam.questions.findIndex(q => q.id === qId);
  const dot = document.getElementById(`qdot-${idx}`);
  if (dot) { dot.classList.add("answered"); dot.classList.remove("current"); }
  updateProgress();
}

function updateProgress() {
  document.getElementById("progress-text").textContent =
    `${Object.keys(answers).length} / ${currentExam.questions.length} answered`;
}

function goToQuestion(idx) { showQuestion(idx); }
function prevQuestion() { if (currentQ > 0) showQuestion(currentQ - 1); }
function nextQuestion() { if (currentQ < currentExam.questions.length - 1) showQuestion(currentQ + 1); }

function confirmSubmit() {
  document.getElementById("modal-answered").textContent = Object.keys(answers).length;
  document.getElementById("modal-total").textContent = currentExam.questions.length;
  document.getElementById("modal-confirm").style.display = "flex";
}

function closeModal() {
  document.getElementById("modal-confirm").style.display = "none";
}

async function submitExam(autoSubmit = false) {
  closeModal();
  clearInterval(timerInterval);
  stopCamera();

  if (currentSession.offline) {
    scoreLocally(autoSubmit);
    return;
  }

  try {
    const res = await fetch(`${API}/api/v1/cbt/sessions/submit`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body: JSON.stringify({
        session_id: currentSession.session_id,
        answers,
        is_auto_submit: autoSubmit,
      }),
    });
    if (!res.ok) throw new Error("submit failed");
    const result = await res.json();
    lastResult = result;
    try {
      const rv = await fetch(`${API}/api/v1/cbt/sessions/${currentSession.session_id}/review`, {
        headers: { Authorization: `Bearer ${token}` },
      });
      if (rv.ok) lastReviewData = await rv.json();
    } catch {}
    showResults(result);
  } catch {
    scoreLocally(autoSubmit);
  }
}

function scoreLocally(autoSubmit) {
  const questions = currentExam.questions;
  let correct = 0, wrong = 0;
  const weakTopics = new Set();

  questions.forEach(q => {
    const chosen = answers[q.id];
    if (chosen && q.correct_option && chosen.toUpperCase() === q.correct_option.toUpperCase()) {
      correct++;
    } else {
      wrong++;
      if (q.topic) weakTopics.add(q.topic);
    }
  });

  const total = correct + wrong;
  const percentage = total > 0 ? parseFloat(((correct / total) * 100).toFixed(1)) : 0;
  lastResult = { score: correct, percentage, total_correct: correct, total_wrong: wrong, weak_topics: [...weakTopics] };
  lastReviewData = {
    percentage,
    questions: questions.map(q => ({
      ...q,
      student_answer: answers[q.id],
      is_correct: (answers[q.id] || "").toUpperCase() === (q.correct_option || "").toUpperCase(),
    })),
  };
  showResults(lastResult);
}

function showResults(result) {
  const pct = result.percentage || 0;
  document.getElementById("score-pct").textContent = pct + "%";
  document.getElementById("stat-correct").textContent = result.total_correct;
  document.getElementById("stat-wrong").textContent = result.total_wrong;
  document.getElementById("score-circle").className = "score-circle " + (pct >= 50 ? "pass" : "fail");
  document.getElementById("results-icon").textContent = pct >= 70 ? "🎉" : pct >= 50 ? "👍" : "📚";
  document.getElementById("results-title").textContent = pct >= 70 ? "Excellent work!" : pct >= 50 ? "Good effort!" : "Keep practising!";
  const weakBlock = document.getElementById("weak-topics-block");
  if (result.weak_topics && result.weak_topics.length) {
    document.getElementById("weak-topics-list").innerHTML = result.weak_topics.map(t => `<span class="weak-tag">${escHtml(t)}</span>`).join("");
    weakBlock.style.display = "block";
  } else {
    weakBlock.style.display = "none";
  }
  showScreen("screen-results");
}

function showReview() {
  if (!lastReviewData) { alert("Review not available."); return; }
  document.getElementById("review-list").innerHTML = lastReviewData.questions.map((q, i) => {
    const opts = [
      { key: "A", text: q.option_a }, { key: "B", text: q.option_b },
      { key: "C", text: q.option_c }, { key: "D", text: q.option_d },
    ];
    return `
      <div class="review-item ${q.is_correct ? "correct-item" : "wrong-item"}">
        <div class="review-q-num">Question ${i + 1} ${q.is_correct ? "✓" : "✗"}</div>
        <div class="review-q-text">${escHtml(q.question_text)}</div>
        <div class="review-options">
          ${opts.map(o => {
            let cls = "";
            if (o.key === q.correct_option) cls = "opt-correct";
            else if (o.key === q.student_answer && !q.is_correct) cls = "opt-wrong";
            return `<div class="review-option ${cls}">${o.key}. ${escHtml(o.text)}</div>`;
          }).join("")}
        </div>
        ${q.explanation ? `<div class="review-explanation">${escHtml(q.explanation)}</div>` : ""}
      </div>`;
  }).join("");
  showScreen("screen-review");
}

function backToList() {
  showScreen("screen-list");
  currentExam = null;
  currentSession = null;
  answers = {};
  clearInterval(timerInterval);
  stopCamera();
  loadExams();
}

function logout() {
  stopCamera();
  localStorage.removeItem("sia_token");
  localStorage.removeItem("sia_name");
  window.location.href = "auth.html";
}

function firstName(name) {
  if (!name) return "Student";
  if (name.includes("@")) return name.split("@")[0];
  return name.split(" ")[0];
}

function formatTime(iso) {
  if (!iso) return "";
  return new Date(iso).toLocaleString(undefined, { dateStyle: "short", timeStyle: "short" });
}

function escHtml(str) {
  return (str || "").replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;");
}

function escAttr(s) {
  return escHtml(s).replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}
