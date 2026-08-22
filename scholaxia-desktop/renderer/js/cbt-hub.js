/** CBT Practice hub — exam-type packages (JAMB / WAEC / NECO) via practice attempts. */

var cbtHubState = {
  home: null,
  view: "types", // types | board
  board: null,
  jambPicked: {},
  busy: false,
};

var DEFAULT_JAMB_SUBJECTS = [
  "Use of English", "Mathematics", "Physics", "Chemistry", "Biology",
  "Economics", "Government", "Literature in English", "Geography",
  "Christian Religious Studies", "Islamic Religious Studies", "Commerce", "Accounting",
];
var DEFAULT_SSCE_SUBJECTS = [
  "English Language", "Mathematics", "Biology", "Chemistry", "Physics",
  "Economics", "Government", "Literature in English", "Geography",
  "Agricultural Science", "Further Mathematics", "Commerce", "Financial Accounting",
];

function cbtEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function cbtAttemptToPack(attempt) {
  var allQuestions = [];
  var sections = [];
  (attempt.sections || []).forEach(function (sec) {
    var start = allQuestions.length;
    (sec.questions || []).forEach(function (q) {
      var row = {
        id: q.id,
        question_text: q.question_text || q.text || "",
        topic: q.topic,
        image_url: q.image_url,
      };
      (q.options || []).forEach(function (opt) {
        var k = String(opt.key || "").toUpperCase();
        if (k) row["option_" + k.toLowerCase()] = opt.text || "";
      });
      allQuestions.push(row);
    });
    sections.push({
      subject: sec.subject || "Subject",
      start: start,
      count: (sec.questions || []).length,
      completed: !!sec.completed,
    });
  });
  return {
    title: (attempt.exam_type || "CBT") + " Practice",
    subject: (attempt.subjects || []).join(" · "),
    duration_minutes: attempt.duration_minutes || 60,
    questions: allQuestions,
    sections: sections,
    practice_attempt_id: attempt.attempt_id,
    exam_type: attempt.exam_type,
    seconds_left: attempt.seconds_left,
    answers: attempt.answers || {},
    section_index: attempt.section_index || 0,
  };
}

async function loadCbtHubPage() {
  var grid = document.getElementById("cbt-grid");
  var tabsEl = document.getElementById("cbt-hub-tabs");
  var subjEl = document.getElementById("cbt-hub-subjects");
  if (!grid) return;
  if (typeof isCbtExamActive === "function" && isCbtExamActive()) return;
  if (typeof showCbtListView === "function") showCbtListView();
  if (tabsEl) {
    tabsEl.innerHTML = "";
    tabsEl.classList.add("hidden");
  }
  if (subjEl) {
    subjEl.innerHTML = "";
    subjEl.classList.add("hidden");
  }
  grid.innerHTML = '<div class="loading">Loading CBT practice…</div>';
  cbtHubState.view = "types";
  cbtHubState.board = null;
  try {
    var data = await api("/api/v1/cbt/practice/home");
    cbtHubState.home = data || {};
    renderCbtHub();
  } catch (e) {
    grid.innerHTML =
      '<div class="empty-state-premium"><h3>Could not load CBT</h3><p>' +
      cbtEsc(e.message) +
      '</p><button type="button" class="btn-action" onclick="loadCbtHubPage()">Retry</button></div>';
  }
}

function renderCbtHub() {
  var grid = document.getElementById("cbt-grid");
  if (!grid) return;
  var home = cbtHubState.home || {};
  var settings = home.settings || {};
  if (settings.cbt_enabled === false) {
    grid.innerHTML = '<div class="empty-state-premium"><h3>CBT disabled</h3><p>Admin has turned off CBT practice.</p></div>';
    return;
  }
  if (cbtHubState.view === "board" && cbtHubState.board) {
    renderCbtBoard(grid);
    return;
  }
  var types = home.exam_types || [];
  if (!types.length) {
    grid.innerHTML = '<div class="empty-state-premium"><h3>No exam types</h3><p>CBT is not configured yet.</p></div>';
    return;
  }
  grid.innerHTML =
    '<p class="cbt-hub-note">Choose <strong>JAMB</strong>, <strong>WAEC</strong>, or <strong>NECO</strong>. Question counts and timers come from admin CBT Settings.</p>' +
    '<div class="card-grid card-grid-premium">' +
    types
      .map(function (t) {
        var locked = !t.has_access;
        return (
          '<div class="card sx-card cbt-exam-card" style="cursor:pointer" onclick="cbtHubOpenBoard(\'' +
          cbtEsc(t.exam_type) +
          "')\">" +
          '<div class="time-badge">' +
          cbtEsc(t.exam_type) +
          "</div>" +
          "<h3>" +
          cbtEsc(t.exam_type) +
          "</h3>" +
          '<p class="meta">' +
          (locked ? "Locked — pay or redeem coupon" : "Unlocked") +
          "</p>" +
          '<p class="meta">' +
          (t.exam_type === "JAMB"
            ? "Combined package · pick " + (settings.jamb_subjects_required || 4) + " subjects"
            : "Subject practice from your registered list") +
          "</p></div>"
        );
      })
      .join("") +
    "</div>";
}

function cbtHubOpenBoard(board) {
  cbtHubState.board = board;
  cbtHubState.view = "board";
  cbtHubState.jambPicked = {};
  renderCbtHub();
}

function renderCbtBoard(grid) {
  var board = cbtHubState.board;
  var home = cbtHubState.home || {};
  var settings = home.settings || {};
  var profile = home.profile || {};
  var info = (home.exam_types || []).find(function (t) {
    return t.exam_type === board;
  }) || { has_access: false };

  var html =
    '<p class="cbt-hub-note"><button type="button" class="btn-secondary btn-sm" onclick="loadCbtHubPage()">← Exam types</button></p>' +
    "<h3 style=\"margin:8px 0\">" +
    cbtEsc(board) +
    " CBT</h3>";

  if (!info.has_access) {
    html +=
      '<div class="empty-state-premium"><h3>Package required</h3><p>Unlock ' +
      cbtEsc(board) +
      " with Paystack or a coupon.</p>" +
      '<button type="button" class="btn-join" onclick="cbtHubUnlockBoard()">Unlock ' +
      cbtEsc(board) +
      "</button></div>";
    grid.innerHTML = html;
    return;
  }

  if (board === "JAMB") {
    var need = settings.jamb_subjects_required || 4;
    var jambSubs =
      profile.jamb_subjects && profile.jamb_subjects.length
        ? profile.jamb_subjects
        : DEFAULT_JAMB_SUBJECTS;
    html +=
      '<p class="cbt-hub-note">Select exactly <strong>' +
      need +
      "</strong> subjects, then START CBT. Subjects run as separate sections in one exam.</p>";
    html += jambSubs
      .map(function (s) {
        var on = !!cbtHubState.jambPicked[s];
        return (
          '<label class="card sx-card" style="display:flex;gap:10px;align-items:center;padding:12px;cursor:pointer">' +
          '<input type="checkbox" ' +
          (on ? "checked " : "") +
          'onchange="cbtHubToggleJamb(\'' +
          cbtEsc(s).replace(/'/g, "\\'") +
          "', this.checked)\" /> <span>" +
          cbtEsc(s) +
          "</span></label>"
        );
      })
      .join("");
    html +=
      '<div style="margin-top:14px"><button type="button" class="btn-join" onclick="cbtHubStartJambPractice()">START CBT</button></div>';
    grid.innerHTML = html;
    return;
  }

  var registered =
    profile.ssce_subjects && profile.ssce_subjects.length
      ? profile.ssce_subjects
      : DEFAULT_SSCE_SUBJECTS;
  html +=
    '<p class="cbt-hub-note">Choose one subject to practice. Only your registered subjects are listed.</p>';
  html += registered
    .map(function (s) {
      return (
        '<div class="card sx-card cbt-exam-card"><div class="time-badge">' +
        cbtEsc(board) +
        "</div><h3>" +
        cbtEsc(s) +
        '</h3><div class="card-actions-row">' +
        '<button type="button" class="btn-join" onclick="cbtHubStartSubject(\'' +
        cbtEsc(s).replace(/'/g, "\\'") +
        "')\">START CBT</button></div></div>"
      );
    })
    .join("");
  grid.innerHTML = html;
}

function cbtHubToggleJamb(subject, on) {
  if (on) cbtHubState.jambPicked[subject] = true;
  else delete cbtHubState.jambPicked[subject];
}

function cbtHubUnlockBoard() {
  if (typeof openCbtUnlockModal === "function") {
    openCbtUnlockModal(function () {
      loadCbtHubPage().then(function () {
        if (cbtHubState.board) cbtHubOpenBoard(cbtHubState.board);
      });
    });
  } else if (typeof showPage === "function") {
    showPage("cbt-packages");
  }
}

async function cbtHubStartJambPractice() {
  var settings = (cbtHubState.home && cbtHubState.home.settings) || {};
  var need = settings.jamb_subjects_required || 4;
  var picked = Object.keys(cbtHubState.jambPicked || {});
  if (picked.length !== need) {
    alert("Select exactly " + need + " JAMB subjects.");
    return;
  }
  await cbtHubStartPractice("JAMB", picked);
}

async function cbtHubStartSubject(subject) {
  await cbtHubStartPractice(cbtHubState.board, [subject]);
}

async function cbtHubStartPractice(examType, subjects) {
  if (cbtHubState.busy) return;
  cbtHubState.busy = true;
  try {
    var attempt = await api("/api/v1/cbt/practice/start", {
      method: "POST",
      body: JSON.stringify({ exam_type: examType, subjects: subjects }),
    });
    launchPracticeAttempt(attempt);
  } catch (e) {
    var msg = (e && e.message) || "";
    if (/402|cbt_package|package|paid|required/i.test(msg) || (e && e.status === 402)) {
      if (typeof openCbtUnlockModal === "function") {
        openCbtUnlockModal(function () {
          cbtHubStartPractice(examType, subjects);
        });
      } else {
        alert(msg);
      }
    } else {
      alert(msg || "Could not start CBT.");
    }
  } finally {
    cbtHubState.busy = false;
  }
}

function launchPracticeAttempt(attempt) {
  var pack = cbtAttemptToPack(attempt);
  if (!pack.questions.length) {
    alert("No questions generated. Ask admin to upload bank questions for these subjects.");
    return;
  }
  currentExam = pack;
  currentSession = {
    session_id: null,
    practice_attempt_id: attempt.attempt_id,
    is_practice: true,
  };
  answers = {};
  // Restore saved answers by question index
  (pack.questions || []).forEach(function (q, i) {
    if (pack.answers && pack.answers[q.id]) answers[i] = pack.answers[q.id];
  });
  currentQ = 0;
  if (pack.sections && pack.sections.length > 1 && pack.section_index) {
    var sec = pack.sections[pack.section_index];
    if (sec) currentQ = sec.start || 0;
  }
  secondsLeft =
    typeof pack.seconds_left === "number" ? pack.seconds_left : (pack.duration_minutes || 60) * 60;

  if (typeof showCbtExamView === "function") showCbtExamView();
  document.getElementById("exam-title").textContent = pack.title;
  document.getElementById("exam-meta").textContent =
    (pack.subject || examTypeLabel(attempt.exam_type)) +
    " · " +
    pack.questions.length +
    " questions · Settings timer";
  if (typeof buildSubjectTabs === "function") buildSubjectTabs();
  if (typeof buildQNav === "function") buildQNav();
  if (typeof renderQuestion === "function") renderQuestion();
  if (typeof startTimer === "function") startTimer();
}

function examTypeLabel(t) {
  return t || "CBT";
}

// Legacy stubs so old onclick handlers do not crash
function cbtHubSetTab() {}
function cbtHubSetSubject() {}
function cbtHubDownload() {
  alert("Download offline packs will sync with practice attempts in a follow-up update. Start CBT online for now.");
}
function cbtHubDownloadJamb() {
  cbtHubDownload();
}
function cbtHubStart() {
  alert("Use START CBT from the JAMB / WAEC / NECO flow.");
}
function cbtHubStartJamb() {
  alert("Select your 4 subjects, then tap START CBT.");
}

if (typeof window !== "undefined") {
  window.loadCbtHubPage = loadCbtHubPage;
  window.cbtHubOpenBoard = cbtHubOpenBoard;
  window.cbtHubToggleJamb = cbtHubToggleJamb;
  window.cbtHubUnlockBoard = cbtHubUnlockBoard;
  window.cbtHubStartJambPractice = cbtHubStartJambPractice;
  window.cbtHubStartSubject = cbtHubStartSubject;
  window.cbtHubSetTab = cbtHubSetTab;
  window.cbtHubSetSubject = cbtHubSetSubject;
  window.cbtHubDownload = cbtHubDownload;
  window.cbtHubDownloadJamb = cbtHubDownloadJamb;
  window.cbtHubStart = cbtHubStart;
  window.cbtHubStartJamb = cbtHubStartJamb;
}
