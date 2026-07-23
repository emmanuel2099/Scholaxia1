/** External / Internal School Exams — download offline, submit when back online */

var internalExamsList = [];
var INTERNAL_CACHE_PREFIX = "sia_internal_exam_pack_";
var INTERNAL_PENDING_KEY = "sia_internal_pending_submits";

function ieEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function getInternalPack(examId) {
  try {
    var raw = localStorage.getItem(INTERNAL_CACHE_PREFIX + examId);
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

function saveInternalPack(examId, pack) {
  localStorage.setItem(INTERNAL_CACHE_PREFIX + examId, JSON.stringify(pack));
}

function getPendingSubmits() {
  try {
    return JSON.parse(localStorage.getItem(INTERNAL_PENDING_KEY) || "[]");
  } catch (e) {
    return [];
  }
}

function savePendingSubmits(list) {
  localStorage.setItem(INTERNAL_PENDING_KEY, JSON.stringify(list));
}

function queueInternalSubmit(examId, answers) {
  var list = getPendingSubmits();
  list = list.filter(function (x) { return x.exam_id !== examId; });
  list.push({ exam_id: examId, answers: answers, queued_at: new Date().toISOString() });
  savePendingSubmits(list);
}

async function flushPendingInternalSubmits() {
  if (!isStudentLoggedIn() || typeof navigator !== "undefined" && !navigator.onLine) return;
  var list = getPendingSubmits();
  if (!list.length) return;
  var remaining = [];
  for (var i = 0; i < list.length; i++) {
    var item = list[i];
    try {
      await api("/api/v1/cbt/external-exams/" + item.exam_id + "/submit", {
        method: "POST",
        body: JSON.stringify({ answers: item.answers, is_auto_submit: false }),
      });
    } catch (e) {
      remaining.push(item);
    }
  }
  savePendingSubmits(remaining);
  if (list.length > remaining.length && typeof loadInternalExamsPage === "function") {
    loadInternalExamsPage();
  }
}

async function loadInternalExamsPage() {
  var el = document.getElementById("internal-exams-list");
  var banner = document.getElementById("internal-pending-banner");
  if (!el) return;

  if (!isStudentLoggedIn()) {
    el.innerHTML = '<div class="empty-state-premium"><h3>Sign in required</h3><p>Log in to see school exams uploaded by admin.</p></div>';
    return;
  }

  await flushPendingInternalSubmits();

  var pending = getPendingSubmits();
  if (banner) {
    if (pending.length) {
      banner.classList.remove("hidden");
      banner.innerHTML = "&#128228; " + pending.length + " exam submission(s) waiting to sync — connect to internet and tap Refresh.";
    } else {
      banner.classList.add("hidden");
    }
  }

  el.innerHTML = '<div class="loading">Loading school exams…</div>';
  try {
    var data = await api("/api/v1/cbt/external-exams/for-me");
    internalExamsList = (data && data.exams) || [];
    renderInternalExamsList();
  } catch (e) {
    el.innerHTML = '<div class="empty-state-premium"><h3>Could not load exams</h3><p>' + ieEsc(e.message) + "</p>";
    var cached = listCachedInternalExams();
    if (cached.length) {
      el.innerHTML += "<p>You have " + cached.length + " downloaded exam(s) available offline.</p>";
    }
    el.innerHTML += "</div>";
  }
}

function listCachedInternalExams() {
  var out = [];
  for (var i = 0; i < localStorage.length; i++) {
    var k = localStorage.key(i);
    if (k && k.indexOf(INTERNAL_CACHE_PREFIX) === 0) {
      out.push(k.replace(INTERNAL_CACHE_PREFIX, ""));
    }
  }
  return out;
}

function renderInternalExamsList() {
  var el = document.getElementById("internal-exams-list");
  if (!el) return;

  if (!internalExamsList.length) {
    el.innerHTML =
      '<div class="empty-state-premium">' +
      '<div class="empty-icon">&#127979;</div>' +
      "<h3>No school exams yet</h3>" +
      "<p>When admin uploads an external school exam, it will appear here. Download it while online, take it offline, then submit your answers.</p></div>";
    return;
  }

  el.innerHTML = internalExamsList.map(function (e) {
    var cached = !!getInternalPack(e.id);
    var taken = e.already_taken;
    var pending = getPendingSubmits().some(function (p) { return p.exam_id === e.id; });
    return (
      '<div class="card sx-card">' +
      '<div class="time-badge">' + (taken ? "Submitted" : "School exam") + "</div>" +
      "<h3>" + ieEsc(e.title) + "</h3>" +
      '<p class="meta">' + ieEsc(e.subject) + " · " + ieEsc(e.teacher_name || "Admin") + " · " + (e.total_questions || "?") + " questions · " + (e.duration_minutes || 60) + " min</p>" +
      (cached ? '<p class="meta sx-meta-ok">&#10003; Downloaded — ready for offline use</p>' : "") +
      (pending ? '<p class="meta sx-meta-warn">&#128228; Answers saved — will submit when online</p>' : "") +
      (e.notes_url ? '<a href="' + ieEsc(e.notes_url) + '" target="_blank" rel="noopener" class="btn-secondary btn-sm">View notes / PDF</a> ' : "") +
      '<div class="card-actions-row">' +
      (!taken && !cached ? '<button type="button" class="btn-action btn-sm" onclick="downloadInternalExam(\'' + ieEsc(String(e.id)) + '\')">Download for offline</button>' : "") +
      (!taken && cached ? '<button type="button" class="btn-join" onclick="startInternalExam(\'' + ieEsc(String(e.id)) + '\')">Take exam</button>' : "") +
      (taken
        ? '<span class="meta">Submitted' +
          (e.my_score_percent != null
            ? ' · Your score: <strong>' + Math.round(Number(e.my_score_percent)) + "%</strong>"
            : " — awaiting board publish") +
          "</span>"
        : "") +
      "</div></div>"
    );
  }).join("");
}

async function downloadInternalExam(examId) {
  try {
    var pack = await api("/api/v1/cbt/exams/" + examId + "/download");
    if (!pack.questions || !pack.questions.length) {
      alert("This exam has no questions yet.");
      return;
    }
    saveInternalPack(examId, pack);
    alert("Downloaded! You can take this exam offline anytime.");
    renderInternalExamsList();
  } catch (e) {
    alert(e.message || "Download failed. Stay online and try again.");
  }
}

async function startInternalExam(examId) {
  var pack = getInternalPack(examId);
  if (!pack) {
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      alert("Download this exam first while you have internet.");
      return;
    }
    await downloadInternalExam(examId);
    pack = getInternalPack(examId);
  }
  if (!pack || !pack.questions || !pack.questions.length) {
    alert("Exam pack not found. Download again.");
    return;
  }

  if (typeof showCbtExamView !== "function") {
    alert("Exam viewer not ready. Refresh the page.");
    return;
  }

  currentExam = pack;
  currentSession = { is_internal: true, exam_id: examId, is_school_exam: true };
  answers = {};
  currentQ = 0;
  secondsLeft = (pack.duration_minutes || 60) * 60;

  showCbtExamView();
  document.getElementById("exam-title").textContent = pack.title || "School Exam";
  document.getElementById("exam-meta").textContent =
    (pack.subject || "Exam") + " · " + pack.questions.length + " questions · Offline mode (submit when done)";

  if (typeof buildQNav === "function") buildQNav();
  if (typeof renderQuestion === "function") renderQuestion();
  if (typeof startTimer === "function") startTimer();
  if (typeof setExamLockMode === "function") setExamLockMode(true);
}

if (typeof window !== "undefined") {
  window.loadInternalExamsPage = loadInternalExamsPage;
  window.downloadInternalExam = downloadInternalExam;
  window.startInternalExam = startInternalExam;
  window.flushPendingInternalSubmits = flushPendingInternalSubmits;
  window.queueInternalSubmit = queueInternalSubmit;
}
