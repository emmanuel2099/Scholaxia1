/** CBT Practice hub — matches student website (Start auto-loads pack; Download optional for offline). */

var cbtHubState = {
  boards: [],
  activeTab: "JAMB",
  jambExams: [],
  ssceExams: [],
  allExams: [],
  jambSubjects: [],
  ssceSubjects: [],
  selectedSubject: null,
  downloaded: {},
  busyId: null,
};

var CBT_MAX_LEVELS = 30;

function cbtEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function cbtSubjectMatches(examSubject, selected) {
  if (!selected || !selected.length) return false;
  var aliases = {
    math: "mathematics", maths: "mathematics",
    "further math": "further mathematics", "further maths": "further mathematics",
    english: "english language", agric: "agricultural science", agriculture: "agricultural science",
    "c.r.s": "crs", "c.r.s.": "crs", "i.r.s": "irs", "i.r.s.": "irs",
    econs: "economics", govt: "government", geo: "geography",
  };
  var examS = String(examSubject || "").toLowerCase().trim();
  var examNorm = aliases[examS] || examS;
  for (var i = 0; i < selected.length; i++) {
    var sl = String(selected[i] || "").toLowerCase().trim();
    var slNorm = aliases[sl] || sl;
    if (examNorm === slNorm || examS === sl || examS.indexOf(sl) >= 0 || sl.indexOf(examS) >= 0 ||
        examNorm.indexOf(slNorm) >= 0 || slNorm.indexOf(examNorm) >= 0) return true;
  }
  return false;
}

function cbtExamSubject(e) {
  return String(e.subject || e.title || "").trim();
}

function cbtExamYear(e) {
  var explicit = e.year || e.exam_year;
  if (explicit) return String(explicit).trim();
  var m = String((e.title || "") + " " + (e.description || "")).match(/(20\d{2}|19\d{2})/);
  return m ? m[1] : null;
}

function cbtBoardLabel(id) {
  if (id === "JAMB") return "JAMB";
  if (id === "JUNIOR_WAEC") return "Junior WAEC";
  if (id === "COMMON_ENTRANCE") return "Common Entrance";
  return "WAEC / NECO";
}

function cbtLoadLocalPack(examId) {
  try {
    var raw = localStorage.getItem("sia_cbt_pack_" + examId + "_any");
    return raw ? JSON.parse(raw) : null;
  } catch (e) {
    return null;
  }
}

function cbtPackDownloaded(examId) {
  var pack = cbtLoadLocalPack(examId);
  if (pack && pack.questions && pack.questions.length) return true;
  if (typeof hasOfflineCbtPack === "function" && hasOfflineCbtPack(examId, "")) return true;
  return !!cbtHubState.downloaded[examId];
}

function cbtRefreshDownloadedSet() {
  cbtHubState.downloaded = {};
  try {
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (!k || k.indexOf("sia_cbt_pack_") !== 0) continue;
      var rest = k.slice("sia_cbt_pack_".length);
      var examId = rest.replace(/_any$/, "").replace(/_\d{4}$/, "");
      if (examId) cbtHubState.downloaded[examId] = true;
    }
  } catch (e) { /* ignore */ }
}

function cbtTabExams() {
  if (cbtHubState.activeTab === "JAMB") {
    return cbtHubState.jambExams.length ? cbtHubState.jambExams : cbtHubState.allExams;
  }
  if (cbtHubState.activeTab === "JUNIOR_WAEC" || cbtHubState.activeTab === "WAEC_NECO" || cbtHubState.activeTab === "COMMON_ENTRANCE") {
    return cbtHubState.ssceExams.length ? cbtHubState.ssceExams : cbtHubState.allExams;
  }
  return cbtHubState.allExams;
}

function cbtSubjectsForTab() {
  if (cbtHubState.activeTab === "WAEC_NECO" || cbtHubState.activeTab === "JUNIOR_WAEC" || cbtHubState.activeTab === "COMMON_ENTRANCE") {
    if (cbtHubState.ssceSubjects.length) return cbtHubState.ssceSubjects.slice();
  }
  var set = {};
  cbtTabExams().forEach(function (e) {
    var s = cbtExamSubject(e);
    if (s) set[s] = true;
  });
  return Object.keys(set).sort();
}

function cbtJambYears() {
  var set = {};
  cbtHubState.jambExams.forEach(function (e) {
    var y = cbtExamYear(e);
    if (y) set[y] = true;
  });
  return Object.keys(set).sort(function (a, b) { return b.localeCompare(a); });
}

function cbtJambBundleForYear(year) {
  if (cbtHubState.jambSubjects.length !== 4) return [];
  var picks = [];
  for (var i = 0; i < cbtHubState.jambSubjects.length; i++) {
    var subj = cbtHubState.jambSubjects[i];
    var found = null;
    for (var j = 0; j < cbtHubState.jambExams.length; j++) {
      var e = cbtHubState.jambExams[j];
      if (cbtExamYear(e) !== year) continue;
      if (cbtSubjectMatches(cbtExamSubject(e), [subj])) { found = e; break; }
    }
    if (!found) return [];
    picks.push(found);
  }
  return picks;
}

function cbtFilteredExams() {
  var subj = cbtHubState.selectedSubject || "";
  return cbtTabExams().filter(function (e) {
    if (!subj) return true;
    return cbtSubjectMatches(cbtExamSubject(e), [subj]);
  }).sort(function (a, b) {
    return cbtExamSubject(a).toLowerCase().localeCompare(cbtExamSubject(b).toLowerCase());
  });
}

function cbtExamCardHtml(e, opts) {
  opts = opts || {};
  var id = String(e.id);
  var cached = cbtPackDownloaded(id);
  var busy = cbtHubState.busyId === id;
  var year = cbtExamYear(e);
  var title = opts.title || e.title || cbtExamSubject(e);
  var desc = opts.description || (year ? "Year " + year + " · " + cbtExamSubject(e) : cbtExamSubject(e));
  var totalQ = opts.totalQuestions != null ? opts.totalQuestions : (e.total_questions || "?");
  var dur = opts.durationMins != null ? opts.durationMins : (e.duration_minutes || 60);
  return (
    '<div class="card sx-card cbt-exam-card">' +
    '<div class="time-badge">' + cbtEsc(cbtBoardLabel(cbtHubState.activeTab)) + "</div>" +
    "<h3>" + cbtEsc(title) + "</h3>" +
    '<p class="meta">' + cbtEsc(desc) + " · " + totalQ + " questions · " + dur + " min</p>" +
    (cached ? '<p class="meta sx-meta-ok">&#10003; Downloaded — ready offline</p>' : "") +
    '<div class="card-actions-row">' +
    (!cached ? '<button type="button" class="btn-action btn-sm"' + (busy ? " disabled" : "") + ' onclick="cbtHubDownload(\'' + cbtEsc(id) + '\')">' + (busy ? "Downloading…" : "Download") + "</button>" : "") +
    '<button type="button" class="btn-join"' + (busy ? " disabled" : "") + ' onclick="' + (opts.startFn || ("cbtHubStart('" + cbtEsc(id) + "')")) + '">Start exam</button>' +
    "</div></div>"
  );
}

function renderCbtHub() {
  var tabsEl = document.getElementById("cbt-hub-tabs");
  var subjEl = document.getElementById("cbt-hub-subjects");
  var grid = document.getElementById("cbt-grid");
  if (!grid) return;

  if (tabsEl && cbtHubState.boards.length > 1) {
    tabsEl.innerHTML = cbtHubState.boards.map(function (b) {
      return '<button type="button" class="mp-tab' + (cbtHubState.activeTab === b ? " active" : "") + '" onclick="cbtHubSetTab(\'' + b + '\')">' + cbtEsc(cbtBoardLabel(b)) + "</button>";
    }).join("");
    tabsEl.classList.remove("hidden");
  } else if (tabsEl) {
    tabsEl.innerHTML = "";
    tabsEl.classList.add("hidden");
  }

  var html = "";
  if (cbtHubState.activeTab === "JAMB") {
    html += '<p class="cbt-hub-note"><strong>JAMB</strong> — Start loads all 4 subjects (or Download first for offline).</p>';
    var years = cbtJambYears();
    var any = false;
    years.forEach(function (y) {
      var members = cbtJambBundleForYear(y);
      if (members.length !== 4) return;
      any = true;
      var allDl = members.every(function (m) { return cbtPackDownloaded(String(m.id)); });
      var totalQ = members.reduce(function (s, m) { return s + (m.total_questions || 0); }, 0);
      var dur = members.reduce(function (m, e) { return Math.max(m, e.duration_minutes || 0); }, 0);
      var busy = cbtHubState.busyId === "jamb_" + y;
      html +=
        '<div class="card sx-card cbt-exam-card">' +
        '<div class="time-badge">JAMB Full UTME</div>' +
        "<h3>JAMB Full Exam " + cbtEsc(y) + "</h3>" +
        '<p class="meta">' + cbtEsc(cbtHubState.jambSubjects.join(" · ")) + " · " + totalQ + " questions · " + (dur || 120) + " min</p>" +
        (allDl ? '<p class="meta sx-meta-ok">&#10003; All 4 subjects downloaded</p>' : "") +
        '<div class="card-actions-row">' +
        (!allDl ? '<button type="button" class="btn-action btn-sm"' + (busy ? " disabled" : "") + ' onclick="cbtHubDownloadJamb(\'' + cbtEsc(y) + '\')">' + (busy ? "Downloading…" : "Download all 4") + "</button>" : "") +
        '<button type="button" class="btn-join"' + (busy ? " disabled" : "") + ' onclick="cbtHubStartJamb(\'' + cbtEsc(y) + '\')">Start full exam</button>' +
        "</div></div>";
    });
    if (!any) {
      html += '<div class="empty-state-premium"><h3>No JAMB packs yet</h3><p>Admin must upload all 4 of your JAMB subjects for the same year. Check Profile subjects.</p></div>';
    }
  } else {
    var subjects = cbtSubjectsForTab();
    if (subjEl) {
      if (subjects.length) {
        subjEl.innerHTML = subjects.map(function (s) {
          return '<button type="button" class="mp-tab' + (cbtHubState.selectedSubject === s ? " active" : "") + '" onclick="cbtHubSetSubject(\'' + cbtEsc(s).replace(/'/g, "\\'") + '\')">' + cbtEsc(s) + "</button>";
        }).join("");
        subjEl.classList.remove("hidden");
      } else {
        subjEl.innerHTML = "";
        subjEl.classList.add("hidden");
      }
    }
    html += '<p class="cbt-hub-note">Tap <strong>Start exam</strong> to begin. Download is optional for offline use.</p>';
    var exams = cbtFilteredExams();
    if (!exams.length) {
      html += '<div class="empty-state-premium"><h3>No exams for this subject</h3><p>Admin-uploaded papers for your profile will appear here.</p></div>';
    } else {
      html += exams.map(function (e) { return cbtExamCardHtml(e); }).join("");
    }
  }
  grid.innerHTML = html;
}

function cbtHubSetTab(tab) {
  cbtHubState.activeTab = tab;
  cbtHubState.selectedSubject = null;
  var subs = cbtSubjectsForTab();
  if (subs.length) cbtHubState.selectedSubject = subs[0];
  renderCbtHub();
}

function cbtHubSetSubject(s) {
  cbtHubState.selectedSubject = s;
  renderCbtHub();
}

async function loadCbtHubPage() {
  var grid = document.getElementById("cbt-grid");
  if (!grid) return;
  if (typeof isCbtExamActive === "function" && isCbtExamActive()) return;
  if (typeof showCbtListView === "function") showCbtListView();
  grid.innerHTML = '<div class="loading">Loading CBT practice…</div>';
  cbtRefreshDownloadedSet();
  if (typeof syncStudentProfile === "function") await syncStudentProfile();
  try {
    var data = await api("/api/v1/cbt/exams/for-me?paper_kind=cbt_practice");
    if (!data) return;
    var practice = (data.practice_exams || []).filter(function (e) {
      return !e.is_school_exam && !e.is_portal && !e.is_aloc;
    });
    cbtHubState.allExams = practice;
    cbtHubState.jambExams = data.jamb_exams || [];
    cbtHubState.ssceExams = data.ssce_exams || [];
    cbtHubState.boards = (data.boards || []).map(String);
    cbtHubState.jambSubjects = (data.jamb_subjects || []).filter(Boolean);
    cbtHubState.ssceSubjects = (data.ssce_subjects || []).filter(Boolean);
    if (!cbtHubState.jambSubjects.length && typeof getUser === "function") {
      var u = getUser();
      cbtHubState.jambSubjects = u.jambSubjects || u.subjects || [];
      cbtHubState.ssceSubjects = u.ssceSubjects || u.subjects || [];
    }
    if (cbtHubState.boards.indexOf("WAEC_NECO") >= 0) cbtHubState.activeTab = "WAEC_NECO";
    else if (cbtHubState.boards.indexOf("JAMB") >= 0) cbtHubState.activeTab = "JAMB";
    else if (cbtHubState.boards.length) cbtHubState.activeTab = cbtHubState.boards[0];
    var subs = cbtSubjectsForTab();
    cbtHubState.selectedSubject = subs.length ? subs[0] : null;
    renderCbtHub();
  } catch (e) {
    grid.innerHTML = '<div class="empty-state-premium"><h3>Could not load CBT</h3><p>' + cbtEsc(e.message) + '</p><button type="button" class="btn-action" onclick="loadCbtHubPage()">Retry</button></div>';
  }
}

async function cbtHubDownload(examId) {
  if (cbtHubState.busyId) return;
  cbtHubState.busyId = examId;
  renderCbtHub();
  try {
    var pack = await api("/api/v1/cbt/exams/" + examId + "/download");
    if (typeof saveOfflineCbtPack === "function") saveOfflineCbtPack(examId, "", pack);
    cbtHubState.downloaded[examId] = true;
    alert("Downloaded! You can start this exam offline.");
  } catch (e) {
    var msg = e.message || "Download failed.";
    if (/402|cbt_package|package|paid|required/i.test(msg)) {
      if (typeof openCbtUnlockModal === "function") openCbtUnlockModal(function () { cbtHubDownload(examId); });
      else if (typeof showPage === "function") showPage("cbt-packages");
      else alert(msg);
    } else {
      alert(msg);
    }
  } finally {
    cbtHubState.busyId = null;
    cbtRefreshDownloadedSet();
    renderCbtHub();
  }
}

async function cbtHubDownloadJamb(year) {
  var members = cbtJambBundleForYear(year);
  if (members.length !== 4) {
    alert("All 4 JAMB subject packs must be uploaded by admin for year " + year + ".");
    return;
  }
  if (cbtHubState.busyId) return;
  cbtHubState.busyId = "jamb_" + year;
  renderCbtHub();
  try {
    for (var i = 0; i < members.length; i++) {
      var id = String(members[i].id);
      var pack = await api("/api/v1/cbt/exams/" + id + "/download");
      if (typeof saveOfflineCbtPack === "function") saveOfflineCbtPack(id, "", pack);
      cbtHubState.downloaded[id] = true;
    }
    alert("JAMB full exam downloaded — 4 subjects ready offline.");
  } catch (e) {
    var msg = e.message || "Download failed.";
    if (/402|cbt_package|package|paid|required/i.test(msg)) {
      if (typeof openCbtUnlockModal === "function") openCbtUnlockModal(function () { cbtHubDownloadJamb(year); });
      else if (typeof showPage === "function") showPage("cbt-packages");
      else alert(msg);
    } else {
      alert(msg);
    }
  } finally {
    cbtHubState.busyId = null;
    cbtRefreshDownloadedSet();
    renderCbtHub();
  }
}

async function cbtHubStart(examId) {
  async function ensureLocalPack() {
    var pack = cbtLoadLocalPack(examId);
    if (pack && pack.questions && pack.questions.length) return pack;
    // Match website: Start auto-downloads when no offline pack yet
    var downloaded = await api("/api/v1/cbt/exams/" + examId + "/download");
    if (typeof saveOfflineCbtPack === "function") saveOfflineCbtPack(examId, "", downloaded);
    cbtHubState.downloaded[examId] = true;
    cbtRefreshDownloadedSet();
    return downloaded;
  }

  async function proceed() {
    var pack;
    try {
      pack = await ensureLocalPack();
    } catch (e) {
      var msg = (e && e.message) || "";
      if (/402|cbt_package|package|paid|required/i.test(msg) || (e && e.status === 402)) {
        if (typeof openCbtUnlockModal === "function") openCbtUnlockModal(proceed);
        else if (typeof showPage === "function") showPage("cbt-packages");
        else alert(msg);
        return;
      }
      alert(msg || "Could not load this exam.");
      return;
    }
    if (!pack || !pack.questions || !pack.questions.length) {
      alert("Exam pack not found. Try again while online.");
      return;
    }
    var session = null;
    try {
      session = await api("/api/v1/cbt/sessions/" + examId + "/start", { method: "POST", body: {} });
    } catch (e) {
      var smsg = (e && e.message) || "";
      if (/402|cbt_package|package|paid|required/i.test(smsg) || (e && e.status === 402)) {
        if (typeof openCbtUnlockModal === "function") openCbtUnlockModal(proceed);
        else if (typeof showPage === "function") showPage("cbt-packages");
        return;
      }
    }
    currentExam = pack;
    currentSession = session
      ? { session_id: session.session_id || session.id, is_school_exam: false }
      : { session_id: null };
    answers = {};
    currentQ = 0;
    secondsLeft = (pack.duration_minutes || 60) * 60;
    if (typeof showCbtExamView === "function") showCbtExamView();
    document.getElementById("exam-title").textContent = pack.title || "CBT Practice";
    document.getElementById("exam-meta").textContent =
      (pack.subject || "Exam") + " · " + pack.questions.length + " questions · Practice";
    if (typeof buildQNav === "function") buildQNav();
    if (typeof renderQuestion === "function") renderQuestion();
    if (typeof startTimer === "function") startTimer();
  }

  var justUnlocked = 0;
  try { justUnlocked = Number(sessionStorage.getItem("sia_cbt_just_unlocked") || 0); } catch (e) {}
  if (justUnlocked && Date.now() - justUnlocked < 120000) {
    await proceed();
    return;
  }
  if (typeof ensureCbtAccessThen === "function") await ensureCbtAccessThen(proceed);
  else await proceed();
}

async function cbtHubStartJamb(year) {
  var members = cbtJambBundleForYear(year);
  if (members.length !== 4) {
    alert("Need all 4 JAMB subject exams from admin.");
    return;
  }

  async function proceedJamb() {
    if (cbtHubState.busyId) return;
    cbtHubState.busyId = "jamb_" + year;
    try {
      var allQuestions = [];
      var sections = [];
      var totalDuration = 0;
      for (var j = 0; j < members.length; j++) {
        var exam = members[j];
        var eid = String(exam.id);
        var pack = cbtLoadLocalPack(eid);
        if (!pack || !pack.questions || !pack.questions.length) {
          pack = await api("/api/v1/cbt/exams/" + eid + "/download");
          if (typeof saveOfflineCbtPack === "function") saveOfflineCbtPack(eid, "", pack);
          cbtHubState.downloaded[eid] = true;
        }
        var subjLabel = cbtExamSubject(exam) || exam.title || "Subject";
        sections.push({ subject: subjLabel, start: allQuestions.length, count: (pack.questions || []).length });
        totalDuration = Math.max(totalDuration, pack.duration_minutes || 0);
        (pack.questions || []).forEach(function (q) { allQuestions.push(q); });
      }
      cbtRefreshDownloadedSet();
      var merged = {
        title: "JAMB Full Exam (" + cbtHubState.jambSubjects.join(" · ") + ") · " + year,
        subject: "JAMB",
        duration_minutes: totalDuration || 120,
        questions: allQuestions,
        sections: sections,
      };
      var session = null;
      try {
        session = await api("/api/v1/cbt/sessions/" + String(members[0].id) + "/start", { method: "POST", body: {} });
      } catch (e) { /* offline ok */ }

      currentExam = merged;
      currentSession = session ? { session_id: session.session_id || session.id } : { session_id: null };
      answers = {};
      currentQ = 0;
      secondsLeft = (merged.duration_minutes || 120) * 60;

      if (typeof showCbtExamView === "function") showCbtExamView();
      document.getElementById("exam-title").textContent = merged.title;
      document.getElementById("exam-meta").textContent = allQuestions.length + " questions · Full UTME";
      if (typeof buildSubjectTabs === "function") buildSubjectTabs();
      if (typeof buildQNav === "function") buildQNav();
      if (typeof renderQuestion === "function") renderQuestion();
      if (typeof startTimer === "function") startTimer();
    } catch (e) {
      var msg = (e && e.message) || "";
      if (/402|cbt_package|package|paid|required/i.test(msg) || (e && e.status === 402)) {
        if (typeof openCbtUnlockModal === "function") openCbtUnlockModal(proceedJamb);
        else alert(msg);
      } else {
        alert(msg || "Could not start exam.");
      }
    } finally {
      cbtHubState.busyId = null;
      renderCbtHub();
    }
  }

  var justUnlocked = 0;
  try { justUnlocked = Number(sessionStorage.getItem("sia_cbt_just_unlocked") || 0); } catch (e2) {}
  if (justUnlocked && Date.now() - justUnlocked < 120000) {
    await proceedJamb();
    return;
  }
  if (typeof ensureCbtAccessThen === "function") {
    try {
      var access = await api("/api/v1/payments/paystack/cbt-access");
      if (!(access && access.has_access)) {
        openCbtUnlockModal(proceedJamb);
        return;
      }
    } catch (e) {
      openCbtUnlockModal(proceedJamb);
      return;
    }
  }
  await proceedJamb();
}

if (typeof window !== "undefined") {
  window.loadCbtHubPage = loadCbtHubPage;
  window.cbtHubSetTab = cbtHubSetTab;
  window.cbtHubSetSubject = cbtHubSetSubject;
  window.cbtHubDownload = cbtHubDownload;
  window.cbtHubDownloadJamb = cbtHubDownloadJamb;
  window.cbtHubStart = cbtHubStart;
  window.cbtHubStartJamb = cbtHubStartJamb;
}
