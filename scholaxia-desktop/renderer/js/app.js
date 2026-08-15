const PAGE_TITLES = {
  dashboard: "Home",
  live: "Live Class",
  "access-code": "Access Code",
  school: "Scholaxia Exam",
  "school-portal": "External School Exam",
  marketplace: "Scholaxia Marketplace",
  assignments: "Assignments",
  "cbt-packages": "CBT Packages",
  "class-packages": "Class packages",
  "holiday-packages": "Holiday Promo",
  skills: "Skills Training",
  subscription: "Subscription",
  cbt: "CBT Practice",
  "study-materials": "Study Materials",
  "past-questions": "Past Questions",
  about: "About Scholaxia",
  contact: "Contact",
  library: "Library",
  "saved-lives": "Saved Lives",
  sia: "Tutor AI",
  games: "Games",
  community: "Community",
  "community-create": "New Post",
  "group-chat": "Group Chat",
  groups: "Groups",
  notifications: "Notifications",
  profile: "Profile",
};

let currentPage = "dashboard";
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
let examLockBypass = false;
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

const cbtPrefetchInflight = new Map();
let cbtLoadingTimer = null;

function cbtPrefetchKey(examId, year) {
  return `${examId}::${year || "any"}`;
}

function hasOfflineCbtPack(examId, year) {
  const pack = loadOfflineCbtPack(examId, year);
  if (!pack) return false;
  if (pack.questions && pack.questions.length) return true;
  return !!(pack.exam && pack.exam.questions && pack.exam.questions.length);
}

function updateCbtCardReadyState(card) {
  if (!card) return;
  card.querySelector(".cbt-ready-badge")?.remove();
}

function requestCbtPortalPack(examId, year) {
  const key = cbtPrefetchKey(examId, year);
  if (cbtPrefetchInflight.has(key)) return cbtPrefetchInflight.get(key);
  const promise = beginPortalExam(examId, { year: year || "" })
    .then((portal) => {
      saveOfflineCbtPack(examId, year || "", portal);
      return portal;
    })
    .finally(() => {
      cbtPrefetchInflight.delete(key);
      document.querySelectorAll("#cbt-grid .card-combined").forEach(updateCbtCardReadyState);
    });
  cbtPrefetchInflight.set(key, promise);
  return promise;
}

function refreshCbtPackInBackground(examId, year) {
  if (!navigator.onLine) return Promise.resolve();
  return requestCbtPortalPack(examId, year).catch(() => null);
}

function isCbtPackFresh(pack, maxAgeMs) {
  if (!pack || !pack.exam || !pack.exam.questions || !pack.exam.questions.length) return false;
  const age = Date.now() - (pack.cached_at || 0);
  return age >= 0 && age < (maxAgeMs || 7 * 24 * 60 * 60 * 1000);
}

async function startPortalExamCached(examId, opts) {
  const year = (opts && opts.year) || "";
  const key = cbtPrefetchKey(examId, year);
  const cached = loadOfflineCbtPack(examId, year);

  if (isCbtPackFresh(cached)) {
    return cached;
  }

  if (cached && cached.exam?.questions?.length) {
    if (navigator.onLine) refreshCbtPackInBackground(examId, year);
    return cached;
  }

  if (cbtPrefetchInflight.has(key)) {
    try {
      return await cbtPrefetchInflight.get(key);
    } catch (e) {
      if (cached && cached.exam?.questions?.length) return cached;
      throw e;
    }
  }

  if (navigator.onLine) {
    try {
      const portal = await requestCbtPortalPack(examId, year);
      return portal;
    } catch (e) {
      if (cached && cached.exam?.questions?.length) return cached;
      throw e;
    }
  }
  if (cached) return cached;
  throw new Error("You are offline. Download this exam year once while online, then practice without data.");
}

function prefetchCbtExam(card, year) {
  if (!card || !navigator.onLine) return;
  const btn = card.querySelector("[data-exam-id]");
  const examId = btn?.dataset?.examId;
  if (!examId || typeof isPortalExamId !== "function" || !isPortalExamId(examId)) return;
  const y = year || "";
  const prefetchTag = y || "any";
  if (hasOfflineCbtPack(examId, y)) {
    updateCbtCardReadyState(card);
    return;
  }
  if (card.dataset.prefetching === prefetchTag) return;
  card.dataset.prefetching = prefetchTag;
  updateCbtCardReadyState(card);
  requestCbtPortalPack(examId, y)
    .then(() => { delete card.dataset.prefetching; updateCbtCardReadyState(card); })
    .catch(() => { delete card.dataset.prefetching; updateCbtCardReadyState(card); });
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
  if (localStorage.getItem("sia_role") === "kind" && isStudentLoggedIn()) {
    window.location.href = "kind.html";
    return;
  }

  const splashMinMs = 1400;
  const splashStarted = Date.now();

  function shouldShowSplash() {
    try {
      if (sessionStorage.getItem("sia_skip_splash") === "1") {
        sessionStorage.removeItem("sia_skip_splash");
        return false;
      }
      if (isStudentLoggedIn()) return false;
    } catch (e) { /* ignore */ }
    return true;
  }

  const hideSplash = function (immediate) {
    const splash = document.getElementById("app-splash");
    if (!splash || splash.classList.contains("app-splash-hide")) return;
    if (!shouldShowSplash() || immediate) {
      splash.classList.add("app-splash-hide");
      splash.setAttribute("aria-hidden", "true");
      setTimeout(function () {
        if (splash.parentNode) splash.parentNode.removeChild(splash);
      }, immediate ? 0 : 500);
      return;
    }
    const wait = Math.max(0, splashMinMs - (Date.now() - splashStarted));
    setTimeout(function () {
      splash.classList.add("app-splash-hide");
      splash.setAttribute("aria-hidden", "true");
      setTimeout(function () {
        if (splash.parentNode) splash.parentNode.removeChild(splash);
      }, 500);
    }, wait);
  };

  if (!shouldShowSplash()) {
    hideSplash(true);
  }

  window.addEventListener("beforeunload", (e) => {
    if (isCbtExamActive()) {
      e.preventDefault();
      e.returnValue = "";
    }
  });
  initUserUI();
  initSidebarToggle();
  bindExamLockListeners();
  bindCbtGridClicks();

  const loggedIn = isStudentLoggedIn();
  if (loggedIn) {
    await syncStudentProfile();
    loadSubjects();
    if (typeof reconcilePendingPlanPayment === "function") {
      await reconcilePendingPlanPayment();
    }
    if (typeof flushPendingInternalSubmits === "function") {
      flushPendingInternalSubmits();
    }
    window.addEventListener("online", function () {
      if (typeof flushPendingInternalSubmits === "function") {
        flushPendingInternalSubmits();
      }
    });
  }

  var urlParams = new URLSearchParams(window.location.search);
  var pendingJoinId = urlParams.get("join") || urlParams.get("class");
  if (loggedIn && pendingJoinId && typeof joinClassWithPayment === "function") {
    if (window.history && window.history.replaceState) {
      window.history.replaceState({}, "", "app.html");
    }
    setTimeout(function () { joinClassWithPayment(String(pendingJoinId)); }, 600);
  }

  var openPage = urlParams.get("open");
  if (!openPage && localStorage.getItem("sia_app_resume_mode") === "league") {
    openPage = "games";
    try { localStorage.removeItem("sia_app_resume_mode"); } catch (e) { /* ignore */ }
  }
  var openLive = urlParams.get("live") === "1";
  if (openLive || urlParams.get("paid") === "1") {
    try { sessionStorage.removeItem("sia_live_plans_cache"); } catch (e) { /* ignore */ }
  }
  var openLibrary = urlParams.get("library") === "1";
  var openSkills = urlParams.get("skills") === "1";
  if (openPage) {
    showPage(openPage);
    if (window.history && window.history.replaceState) {
      window.history.replaceState({}, "", "app.html");
    }
  } else if (openLive) {
    showPage("live");
    if (urlParams.get("paid") === "1" && typeof loadLivePlans === "function") {
      loadLivePlans(null, false);
    }
    if (window.history && window.history.replaceState) {
      window.history.replaceState({}, "", "app.html");
    }
  } else if (openLibrary) {
    showPage("library");
    if (window.history && window.history.replaceState) {
      window.history.replaceState({}, "", "app.html");
    }
  } else if (openSkills) {
    showPage("skills");
    if (urlParams.get("enrolled") === "1") {
      setTimeout(function () {
        alert("Enrollment payment received! Scholaxia will contact you with your class schedule.");
      }, 400);
    }
    if (window.history && window.history.replaceState) {
      window.history.replaceState({}, "", "app.html");
    }
  } else {
    refreshPage();
  }
  if (loggedIn) {
    startLivePolling();
    if (typeof startAccessCodePoll === "function") startAccessCodePoll();
    if (typeof startCommunityNotifyPoll === "function") startCommunityNotifyPoll();
    if (typeof prefetchCommunityFeed === "function") prefetchCommunityFeed();
  }
  hideSplash();
};

function showCbtLoadingOverlay(message) {
  let el = document.getElementById("cbt-loading-overlay");
  if (!el) {
    el = document.createElement("div");
    el.id = "cbt-loading-overlay";
    el.className = "cbt-loading-overlay hidden";
    document.getElementById("page-cbt").appendChild(el);
  }
  const started = Date.now();
  const baseMessage = message || "Loading exam…";
  const render = () => {
    const secs = Math.floor((Date.now() - started) / 1000);
    let hint = "";
    if (secs >= 25) hint = "<span class=\"cbt-loading-hint\">Server is waking up — almost there…</span>";
    else if (secs >= 12) hint = "<span class=\"cbt-loading-hint\">Fetching questions from ALOC…</span>";
    else if (secs >= 4) hint = "<span class=\"cbt-loading-hint\">Connecting to Scholaxia…</span>";
    el.innerHTML = `<div class="cbt-loading-box"><div class="cbt-spinner"></div><p>${escHtml(baseMessage)}</p>${hint}</div>`;
  };
  render();
  el.classList.remove("hidden");
  if (cbtLoadingTimer) clearInterval(cbtLoadingTimer);
  cbtLoadingTimer = setInterval(render, 1000);
}

function hideCbtLoadingOverlay() {
  if (cbtLoadingTimer) {
    clearInterval(cbtLoadingTimer);
    cbtLoadingTimer = null;
  }
  const el = document.getElementById("cbt-loading-overlay");
  if (el) el.classList.add("hidden");
}

function closeAllYearDropdowns() {
  document.querySelectorAll("#cbt-grid .year-dropdown").forEach((root) => {
    root.dataset.open = "false";
    const trigger = root.querySelector(".year-dropdown-trigger");
    const menu = root.querySelector(".year-dropdown-menu");
    if (trigger) trigger.setAttribute("aria-expanded", "false");
    if (menu) menu.classList.remove("open");
  });
}

function bindYearDropdowns() {
  document.querySelectorAll("#cbt-grid .year-dropdown").forEach((root) => {
    if (root.dataset.bound) return;
    root.dataset.bound = "1";
    const trigger = root.querySelector(".year-dropdown-trigger");
    const menu = root.querySelector(".year-dropdown-menu");
    const hidden = root.querySelector(".cbt-year-value");
    const label = root.querySelector(".year-dropdown-label");
    if (!trigger || !menu || !hidden || !label) return;

    trigger.addEventListener("click", (e) => {
      e.stopPropagation();
      const open = root.dataset.open === "true";
      closeAllYearDropdowns();
      if (!open) {
        root.dataset.open = "true";
        trigger.setAttribute("aria-expanded", "true");
        menu.classList.add("open");
      }
    });

    menu.querySelectorAll(".year-dropdown-option").forEach((opt) => {
      opt.addEventListener("click", (e) => {
        e.stopPropagation();
        menu.querySelectorAll(".year-dropdown-option").forEach((o) => o.classList.remove("active"));
        opt.classList.add("active");
        hidden.value = opt.dataset.value || "";
        label.textContent = opt.textContent.trim();
        closeAllYearDropdowns();
        const card = root.closest(".card");
        if (card) {
          prefetchCbtExam(card, hidden.value);
          updateCbtCardReadyState(card);
        }
      });
    });
  });

  if (!window._yearDropdownDocBound) {
    window._yearDropdownDocBound = true;
    document.addEventListener("click", closeAllYearDropdowns);
  }
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
    const year = card?.querySelector(".cbt-year-value")?.value || "";
    beginExam(btn.dataset.examId, false, year);
  });
}

function showCbtExamView() {
  examLockBypass = true;
  const targetPage = currentSession && currentSession.is_school_exam ? "school" : "cbt";
  if (currentPage !== targetPage) {
    currentPage = targetPage;
    document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
    document.querySelectorAll(".topnav-btn").forEach((n) => n.classList.remove("active"));
    const pg = document.getElementById("page-" + targetPage);
    if (pg) pg.classList.add("active");
    const navEl = document.querySelector('.topnav-btn[data-page="' + targetPage + '"]');
    if (navEl) navEl.classList.add("active");
    document.getElementById("page-title").textContent = PAGE_TITLES[targetPage] || targetPage;
  }
  examLockBypass = false;

  document.getElementById("result-screen").classList.add("hidden");
  const screen = document.getElementById("exam-screen");
  screen.classList.remove("hidden");
  setExamLockMode(true);
  const main = document.querySelector(".main-content-sidebar") || document.querySelector(".main-content");
  if (main) main.scrollTop = 0;
  screen.scrollIntoView({ behavior: "smooth", block: "start" });
}

function showCbtListView() {
  setExamLockMode(false);
  const embed = document.getElementById("cbt-embed-wrap");
  if (embed) embed.classList.add("hidden");
  document.getElementById("exam-screen").classList.add("hidden");
  document.getElementById("result-screen").classList.add("hidden");
  document.getElementById("cbt-grid").classList.remove("hidden");
  const schoolGrid = document.getElementById("school-grid");
  if (schoolGrid) schoolGrid.classList.remove("hidden");
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

function initSidebarToggle() {
  var shell = document.querySelector(".app-shell-sidebar");
  var btn = document.getElementById("sidebar-toggle");
  if (!shell || !btn) return;

  if (localStorage.getItem("sia_sidebar_collapsed") === "1") {
    shell.classList.add("sidebar-collapsed");
  }
  updateSidebarToggleBtn(btn, shell.classList.contains("sidebar-collapsed"));

  btn.addEventListener("click", function () {
    shell.classList.toggle("sidebar-collapsed");
    var collapsed = shell.classList.contains("sidebar-collapsed");
    localStorage.setItem("sia_sidebar_collapsed", collapsed ? "1" : "0");
    updateSidebarToggleBtn(btn, collapsed);
  });
}

function updateSidebarToggleBtn(btn, collapsed) {
  btn.textContent = collapsed ? "\u203A" : "\u2039";
  btn.setAttribute("aria-label", collapsed ? "Show menu" : "Hide menu");
  btn.title = collapsed ? "Show menu" : "Hide menu";
}

function syncDashActionCards(page) {
  var quickPages = ["live", "school", "subscription", "skills", "sia"];
  document.querySelectorAll(".dash-action-card[data-dash-page]").forEach(function (btn) {
    var pg = btn.getAttribute("data-dash-page");
    btn.classList.toggle("active", page === pg && quickPages.indexOf(page) >= 0);
  });
}

function quickDashAction(page) {
  syncDashActionCards(page);
  showPage(page);
}

function applyGuestNavLocks() {
  var guest = !isStudentLoggedIn();
  document.querySelectorAll(".topnav-btn[data-page]").forEach(function (btn) {
    var pg = btn.getAttribute("data-page");
    var locked = guest && !isPagePublic(pg);
    btn.classList.toggle("nav-locked", locked);
  });
  var fab = document.getElementById("community-fab");
  if (fab && guest) fab.style.display = "none";
  var bell = document.getElementById("topbar-bell");
  if (bell) bell.style.display = guest ? "none" : "";
  var ringBar = document.getElementById("notif-ring-bar");
  if (ringBar && guest) ringBar.classList.add("hidden");
}

function handleAuthButton() {
  if (isStudentLoggedIn()) logout();
  else goToLogin(currentPage || "dashboard");
}

function handleTopbarUserClick() {
  if (isStudentLoggedIn()) showPage("profile");
  else goToLogin(currentPage || "dashboard");
}

function setTopbarAuthButton(loggedIn) {
  var btn = document.getElementById("topbar-auth-btn") || document.querySelector(".btn-logout.topbar-logout");
  if (!btn) return;
  if (loggedIn) {
    btn.textContent = "Sign out";
    btn.setAttribute("aria-label", "Sign out");
    btn.title = "Sign out";
    btn.classList.remove("topbar-logout-primary");
  } else {
    btn.textContent = "Sign in";
    btn.setAttribute("aria-label", "Sign in to Scholaxia");
    btn.title = "Sign in to Scholaxia";
    btn.classList.add("topbar-logout-primary");
  }
}

function setAvatarPhoto(el, photoUrl, fallbackLetter) {
  if (!el) return;
  var letter = (fallbackLetter || "?").toString().charAt(0).toUpperCase();
  if (photoUrl) {
    el.classList.add("has-photo");
    el.style.backgroundImage = 'url("' + String(photoUrl).replace(/"/g, "") + '")';
    el.textContent = "";
  } else {
    el.classList.remove("has-photo");
    el.style.backgroundImage = "";
    el.textContent = letter;
  }
}

function resolveProfileMediaUrl(url) {
  if (!url) return "";
  if (/^https?:\/\//i.test(url)) return url;
  return (typeof API_BASE !== "undefined" ? API_BASE : "") + (url.startsWith("/") ? url : "/" + url);
}

function applyStoredAvatar(initial) {
  var photo = localStorage.getItem("sia_profile_picture") || "";
  setAvatarPhoto(document.getElementById("user-avatar"), photo, initial);
  setAvatarPhoto(document.getElementById("profile-avatar"), photo, initial);
}

async function uploadStudentProfilePhoto(input) {
  var file = input && input.files && input.files[0];
  var msg = document.getElementById("profile-photo-msg");
  if (!file) return;
  if (msg) msg.textContent = "Uploading photo…";
  try {
    var form = new FormData();
    form.append("file", file);
    var token = getToken();
    var up = await fetch(API_BASE + "/api/v1/community/upload", {
      method: "POST",
      headers: token ? { Authorization: "Bearer " + token } : {},
      body: form,
    });
    var uploaded = await up.json().catch(function () { return {}; });
    if (!up.ok) throw new Error(uploaded.detail || uploaded.message || "Upload failed");
    var url = uploaded.file_url || uploaded.secure_url || uploaded.url;
    if (!url) throw new Error("No image URL returned.");
    var saved = await api("/api/v1/profiles/me/picture", {
      method: "PATCH",
      body: JSON.stringify({ profile_picture: url }),
    });
    var finalUrl = resolveProfileMediaUrl(
      (saved && saved.profile_picture) || url
    );
    localStorage.setItem("sia_profile_picture", finalUrl);
    var initial = (document.getElementById("profile-name") || {}).textContent || "S";
    applyStoredAvatar(initial.trim().charAt(0) || "S");
    if (msg) msg.textContent = "Photo updated.";
  } catch (e) {
    if (msg) msg.textContent = e.message || "Could not update photo.";
  } finally {
    if (input) input.value = "";
  }
}

window.uploadStudentProfilePhoto = uploadStudentProfilePhoto;
window.applyStoredAvatar = applyStoredAvatar;

function initUserUI() {
  const loggedIn = isStudentLoggedIn();
  if (!loggedIn) {
    const nameEl = document.getElementById("header-user-name");
    const handleEl = document.getElementById("header-user-handle");
    if (nameEl) nameEl.textContent = "Guest";
    if (handleEl) handleEl.textContent = "Tap to sign in";
    const examEl = document.getElementById("sidebar-exam");
    if (examEl) examEl.textContent = "Browse";
    setAvatarPhoto(document.getElementById("user-avatar"), "", "G");
    setAvatarPhoto(document.getElementById("profile-avatar"), "", "G");
    const pn = document.getElementById("profile-name");
    if (pn) pn.textContent = "Guest";
    const pe = document.getElementById("profile-email");
    if (pe) pe.textContent = "Sign in to access your account";
    setTopbarAuthButton(false);
    applyGuestNavLocks();
    return;
  }
  const user = getUser();
  const initial = firstName(user.name)[0].toUpperCase();
  const first = firstName(user.name);
  const handle = "@" + (user.email ? user.email.split("@")[0] : "student");
  const nameEl = document.getElementById("header-user-name");
  const handleEl = document.getElementById("header-user-handle");
  if (nameEl) nameEl.textContent = first;
  if (handleEl) handleEl.textContent = handle;
  document.getElementById("sidebar-exam").textContent = formatExamType(user.examType) || "Student";
  applyStoredAvatar(initial);
  document.getElementById("profile-name").textContent = user.name;
  document.getElementById("profile-email").textContent = user.email;
  setTopbarAuthButton(true);
  applyGuestNavLocks();
}

function logout() {
  if (isCbtExamActive()) {
    alert("Submit your exam first — you cannot sign out or open other tabs until you finish.");
    return;
  }
  clearSession();
  window.location.href = "app.html";
}

function setExamLockMode(on) {
  document.body.classList.toggle("exam-lock-active", !!on);
  const topnav = document.getElementById("student-topnav");
  if (topnav) {
    topnav.querySelectorAll(".topnav-btn").forEach((btn) => {
      btn.disabled = !!on;
      btn.setAttribute("aria-disabled", on ? "true" : "false");
      if (on) btn.setAttribute("tabindex", "-1");
      else btn.removeAttribute("tabindex");
    });
  }
  const refreshBtn = document.querySelector(".btn-refresh");
  if (refreshBtn) {
    refreshBtn.style.display = on ? "none" : "";
    refreshBtn.disabled = !!on;
  }
  const logoutBtn = document.querySelector(".btn-logout");
  if (logoutBtn) logoutBtn.disabled = !!on;
  const lockBanner = document.getElementById("exam-lock-banner");
  if (lockBanner) lockBanner.classList.toggle("hidden", !on);
  const fab = document.getElementById("community-fab");
  if (fab) fab.style.display = on ? "none" : (currentPage === "community" ? "flex" : "none");
  const headBar = document.querySelector(".app-topbar");
  if (headBar) headBar.style.display = on ? "none" : "";
}

function getGreeting() {
  const h = new Date().getHours();
  if (h < 12) return "Good morning";
  if (h < 17) return "Good afternoon";
  return "Good evening";
}

async function loadDashboard(force) {
  const titleEl = document.getElementById("dash-greeting-title");
  const subEl = document.getElementById("dash-greeting-sub");
  if (!isStudentLoggedIn()) {
    if (titleEl) titleEl.textContent = getGreeting() + ", welcome";
    if (subEl) subEl.textContent = "Browse External School Exam and Marketplace — sign in for CBT, Live Class, Community, and more.";
    const statSubs = document.getElementById("dash-stat-subjects");
    const liveEl = document.getElementById("dash-stat-live");
    const examsEl = document.getElementById("dash-stat-exams");
    if (statSubs) statSubs.textContent = "—";
    if (liveEl) liveEl.textContent = "—";
    if (examsEl) examsEl.textContent = "—";
    const heroTitle = document.getElementById("dash-hero-title");
    if (heroTitle) heroTitle.textContent = "Scholaxia CBT Practice";
    const heroExam = document.getElementById("dash-hero-exam");
    if (heroExam) heroExam.textContent = "Sign in to start";
    const focusSubject = document.getElementById("dash-focus-subject");
    if (focusSubject) focusSubject.textContent = "Sign in to set subjects";
    const progressFill = document.getElementById("dash-progress-fill");
    if (progressFill) progressFill.style.width = "0%";
    const progressText = document.getElementById("dash-progress-text");
    if (progressText) progressText.textContent = "Sign in to track progress";
    if (typeof renderHomeSkillsPreview === "function") renderHomeSkillsPreview();
    return;
  }
  const user = getUser();
  const subjects = user.subjects || [];
  if (titleEl) titleEl.textContent = getGreeting() + " " + firstName(user.name);
  if (subEl) subEl.textContent = "Let's beat your weak topics today.";

  const heroTitle = document.getElementById("dash-hero-title");
  const heroExam = document.getElementById("dash-hero-exam");
  const focusSubject = document.getElementById("dash-focus-subject");
  const progressText = document.getElementById("dash-progress-text");
  const progressFill = document.getElementById("dash-progress-fill");
  const examLabel = formatExamType(user.examType) || "Your exam";

  if (heroTitle) {
    heroTitle.textContent = subjects[0]
      ? subjects[0] + " — CBT Practice"
      : "Scholaxia CBT Practice";
  }
  if (heroExam) heroExam.textContent = examLabel;
  if (focusSubject) {
    focusSubject.textContent = subjects[0] || "Set up subjects in Profile";
  }
  const subCount = subjects.length;
  const maxSubs = examLabel.indexOf("WAEC") >= 0 || examLabel.indexOf("NECO") >= 0 ? 9 : 4;
  const pct = maxSubs ? Math.min(100, Math.round((subCount / maxSubs) * 100)) : 0;
  if (progressFill) progressFill.style.width = pct + "%";
  if (progressText) {
    progressText.textContent = subCount
      ? subCount + " subject" + (subCount === 1 ? "" : "s") + " selected"
      : "0 subjects selected";
  }

  const statSubs = document.getElementById("dash-stat-subjects");
  if (statSubs) statSubs.textContent = String(subCount);

  try {
    if (force && isStudentLoggedIn()) {
      await syncStudentProfile();
    }
    const [liveRaw, examData] = await Promise.all([
      api("/api/v1/live-classes/?status=live&_=" + Date.now()).catch(function () { return []; }),
      api("/api/v1/cbt/exams/for-me").catch(function () { return null; }),
    ]);
    const liveEl = document.getElementById("dash-stat-live");
    const examsEl = document.getElementById("dash-stat-exams");
    if (liveEl) liveEl.textContent = String((liveRaw || []).length);
    if (examsEl) {
      const count = examData && examData.school_exams ? examData.school_exams.length : 0;
      examsEl.textContent = String(count);
    }
    renderDashboardLive(liveRaw || []);
  } catch (e) { /* stats optional */ }

  if (typeof renderHomeSkillsPreview === "function") renderHomeSkillsPreview();
}

async function loadStudyMaterials() {
  var el = document.getElementById("study-materials-list");
  if (!el) return;
  if (!isStudentLoggedIn()) {
    el.innerHTML = '<div class="empty">Sign in to see study materials posted by admin.</div>';
    return;
  }
  el.innerHTML = '<div class="loading">Loading materials…</div>';
  try {
    var rows = await api("/api/v1/recommendations/feed");
    if (!rows || !rows.length) {
      el.innerHTML = '<div class="empty">No study materials yet. Admin will post materials here soon.</div>';
      return;
    }
    el.innerHTML = rows.map(function (r) {
      var cover = r.cover_image_url
        ? '<img class="study-mat-cover" src="' + escHtml(r.cover_image_url) + '" alt="" />'
        : '<div class="study-mat-cover study-mat-cover-ph">&#128218;</div>';
      var action = "";
      if (r.book_id) {
        action = '<button type="button" class="btn-action btn-sm" onclick="showPage(\'library\')">Read in Library</button>';
      }
      return (
        '<article class="study-mat-card">' + cover +
        '<div class="study-mat-body"><h4>' + escHtml(r.title || "Material") + '</h4>' +
        (r.author ? '<p class="study-mat-meta">' + escHtml(r.author) + "</p>" : "") +
        (r.description ? '<p class="study-mat-desc">' + escHtml(r.description) + "</p>" : "") +
        (action ? '<div class="study-mat-actions">' + action + "</div>" : "") +
        "</div></article>"
      );
    }).join("");
  } catch (e) {
    var msg = typeof networkErrorMessage === "function" ? networkErrorMessage(e) : e.message;
    el.innerHTML = '<div class="empty">' + escHtml(msg) + "</div>";
  }
}

function dedupeLiveSessions(sessions) {
  var seen = {};
  return (sessions || []).filter(function (s) {
    if (!s || !s.id || seen[s.id]) return false;
    seen[s.id] = true;
    return true;
  });
}

function dashLiveBadge(session) {
  if (session.visibility === "private") {
    return '<span class="dash-invite-pill">&#128276; Private invitation</span>';
  }
  if (session.is_live) {
    return '<span class="live-pill">LIVE NOW</span>';
  }
  return '<span class="live-pill starting">STARTING</span>';
}

function renderDashboardLive(sessions) {
  var wrap = document.getElementById("dash-platform-live");
  var grid = document.getElementById("dash-live-grid");
  if (!wrap || !grid) return;
  var live = dedupeLiveSessions(sessions || []);
  if (!live.length) {
    wrap.classList.add("hidden");
    return;
  }
  wrap.classList.remove("hidden");
  grid.innerHTML = live.map(function (s) {
    return '<article class="dash-live-card">' +
      dashLiveBadge(s) +
      (s.visibility && s.visibility !== "private" ? '<span class="live-vis-pill">' + escHtml(liveVisibilityLabel(s.visibility)) + "</span>" : "") +
      "<h4>" + escHtml(s.title) + "</h4>" +
      '<p class="meta">Teacher: ' + escHtml(s.teacher_name || "Teacher") + " · " + escHtml(s.subject) + "</p>" +
      '<button type="button" class="btn-action" onclick="openJoinLiveModal()">Join live</button>' +
      "</article>";
  }).join("");
}

function bindExamLockListeners() {
  if (window._examLockBound) return;
  window._examLockBound = true;
  document.addEventListener("click", (e) => {
    if (!isCbtExamActive() || examLockBypass) return;
    const blocked = e.target.closest(
      ".topnav-btn, .nav-item, .btn-logout, .btn-refresh, .community-fab, .sidebar-brand"
    );
    if (blocked) {
      e.preventDefault();
      e.stopImmediatePropagation();
      alert("You are in an exam. Submit the exam first — other tabs (Sia, Community, Marketplace, etc.) stay locked until then.");
    }
  }, true);
  document.addEventListener("keydown", (e) => {
    if (!isCbtExamActive() || examLockBypass) return;
    if ((e.altKey && e.key === "Tab") || (e.ctrlKey && e.key === "Tab")) {
      e.preventDefault();
    }
  }, true);
}

var appPageHistory = [];

function showPage(page, opts) {
  opts = opts || {};
  if (isCbtExamActive() && !examLockBypass) {
    alert("You are in an exam. Submit the exam to leave — other tabs (Sia, Community, etc.) are locked until then.");
    return;
  }
  if (page === "access-code") page = "live";
  if (!opts.replace && currentPage && currentPage !== page) {
    appPageHistory.push(currentPage);
    if (appPageHistory.length > 40) appPageHistory.shift();
  }
  sessionStorage.setItem("sia_current_page", page);
  if (!isPagePublic(page) && !isStudentLoggedIn()) {
    goToLogin(page);
    return;
  }
  currentPage = page;
  document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
  document.querySelectorAll(".topnav-btn").forEach((n) => n.classList.remove("active"));
  document.getElementById(`page-${page}`).classList.add("active");
  const navPage = page === "community-create" || page === "group-chat" ? "community" : page;
  const navEl = document.querySelector(`.topnav-btn[data-page="${navPage}"]`);
  if (navEl) navEl.classList.add("active");
  document.getElementById("page-title").textContent = PAGE_TITLES[page] || page;
  const fab = document.getElementById("community-fab");
  if (fab) fab.style.display = page === "community" && isStudentLoggedIn() ? "flex" : "none";
  var backBtn = document.getElementById("page-back-btn");
  if (backBtn) {
    backBtn.classList.toggle("is-hidden", page === "dashboard" && !appPageHistory.length);
  }
  applyGuestNavLocks();
  syncDashActionCards(page === "dashboard" ? "" : page);
  refreshPage();
}

function goAppBack() {
  var prev = appPageHistory.pop();
  if (!prev) prev = "dashboard";
  showPage(prev, { replace: true });
}
window.goAppBack = goAppBack;

function openGroupsHub() {
  showPage("community");
  if (typeof window.discordSelectScholaxia === "function") {
    window.discordSelectScholaxia();
  }
  if (typeof window.discordSelectChannel === "function") {
    window.discordSelectChannel("groups");
  }
}

if (typeof window !== "undefined") {
  window.showPage = showPage;
  window.handleAuthButton = handleAuthButton;
  window.handleTopbarUserClick = handleTopbarUserClick;
  window.quickDashAction = quickDashAction;
  window.openGroupsHub = openGroupsHub;
}

function refreshPage() {
  var refreshBtn = document.querySelector(".btn-refresh");
  if (refreshBtn) refreshBtn.classList.add("is-refreshing");

  _liveSessionsCache = { live: [], upcoming: [], at: 0 };
  knownLiveClassIds = new Set();
  try { sessionStorage.removeItem("sia_live_plans_cache"); } catch (e) { /* ignore */ }

  var done = function () {
    if (refreshBtn) refreshBtn.classList.remove("is-refreshing");
  };

  if (currentPage === "dashboard") {
    loadDashboard(true).then(done).catch(done);
  }   else if (currentPage === "live") {
    loadLive(false).then(done).catch(done);
  } else if (currentPage === "access-code") {
    if (typeof loadAccessCodesPage === "function") loadAccessCodesPage();
    done();
  } else if (currentPage === "school") { loadSchoolExams(); done(); }
  else if (currentPage === "school-portal") {
    if (typeof loadInternalExamsPage === "function") loadInternalExamsPage();
    done();
  }
  else if (currentPage === "study-materials") { loadStudyMaterials(); done(); }
  else if (currentPage === "past-questions") {
    if (typeof loadPastQuestionsPage === "function") loadPastQuestionsPage();
    done();
  }
  else if (currentPage === "about") { done(); }
  else if (currentPage === "contact") { initAppContactForm(); done(); }
  else if (currentPage === "marketplace") {
    if (typeof loadMarketplacePage === "function") loadMarketplacePage();
    done();
  }
  else if (currentPage === "assignments") {
    if (typeof loadAssignmentsPage === "function") loadAssignmentsPage();
    done();
  }
  else if (currentPage === "cbt-packages") {
    if (typeof loadCbtPackagesPage === "function") loadCbtPackagesPage();
    done();
  }
  else if (currentPage === "class-packages") {
    if (typeof loadClassPackagesPage === "function") loadClassPackagesPage();
    done();
  }
  else if (currentPage === "holiday-packages") {
    if (typeof loadHolidayPackagesPage === "function") loadHolidayPackagesPage();
    done();
  }
  else if (currentPage === "subscription") {
    if (typeof loadLivePlans === "function") {
      var justPaid = false;
      try {
        var paidAt = Number(sessionStorage.getItem("sia_live_plan_just_paid") || 0);
        justPaid = paidAt > 0 && (Date.now() - paidAt) < 30 * 60 * 1000;
        if (justPaid) sessionStorage.removeItem("sia_live_plan_just_paid");
      } catch (e) { /* ignore */ }
      // After Paystack on this screen, always refresh so active_plan is visible.
      loadLivePlans(null, !justPaid);
    }
    done();
  }
  else if (currentPage === "skills") {
    loadSkillsTraining();
    done();
  }
  else if (currentPage === "cbt") { loadCbtExams(); done(); }
  else if (currentPage === "library") { loadLibrary(); done(); }
  else if (currentPage === "saved-lives") { loadSavedLivesPage(); done(); }
  else if (currentPage === "sia") { loadSia(); done(); }
  else if (currentPage === "games") {
    if (typeof loadGamesPage === "function") loadGamesPage();
    done();
  }
  else if (currentPage === "community") {
    if (typeof markCommunityRead === "function") markCommunityRead();
    var pending = communityPendingPost;
    communityPendingPost = null;
    loadCommunity(pending);
    done();
  }
  else if (currentPage === "group-chat") {
    if (typeof loadGroupChatPage === "function") loadGroupChatPage();
    done();
  }
  else if (currentPage === "community-create") { initCommunityCreate(); done(); }
  else if (currentPage === "notifications") { loadNotifications(); done(); }
  else if (currentPage === "profile") { loadProfile(); done(); }
  else { done(); }
}

/* ── Live Class ── */

var livePollTimer = null;
var knownLiveClassIds = new Set();
var _liveSessionsCache = { live: [], upcoming: [], at: 0 };
var LIVE_CACHE_MS = 20000;

function cacheLiveSessions(live, upcoming) {
  _liveSessionsCache = { live: live || [], upcoming: upcoming || [], at: Date.now() };
}

function paintLiveFromCache() {
  if (!(_liveSessionsCache.at && Date.now() - _liveSessionsCache.at < LIVE_CACHE_MS)) return false;
  renderLive(_liveSessionsCache.live);
  renderUpcoming(_liveSessionsCache.upcoming);
  return true;
}

function getStudentSubjects() {
  try {
    return JSON.parse(localStorage.getItem("sia_subjects") || "[]");
  } catch (e) {
    return [];
  }
}

function filterSessionsBySubjects(sessions) {
  return sessions || [];
}

function sessionMatchesSubjects(session, subjects) {
  if (!subjects || !subjects.length) return true;
  var aliases = {
    math: "mathematics",
    maths: "mathematics",
    english: "english language",
    agric: "agricultural science",
    agriculture: "agricultural science",
    econs: "economics",
    govt: "government",
    geo: "geography",
  };
  function norm(s) {
    var k = (s || "").toLowerCase().trim();
    return aliases[k] || k;
  }
  var exam = norm(session.subject || "");
  return subjects.some(function (sub) {
    var sel = norm(sub);
    var raw = (sub || "").toLowerCase().trim();
    var rawExam = (session.subject || "").toLowerCase().trim();
    return exam === sel || rawExam === raw || rawExam.indexOf(raw) >= 0 || raw.indexOf(rawExam) >= 0;
  });
}

function startLivePolling() {
  if (livePollTimer) return;
  livePollTimer = setInterval(function () {
    if (currentPage === "live") loadLive(true);
    if (currentPage === "dashboard") loadDashboard(true);
  }, 20000);
}

function showLiveClassToast(session) {
  if (typeof Notification !== "undefined" && Notification.permission === "granted") {
    try {
      var n = new Notification("Class is live!", {
        body: (session.title || "Live class") + " — " + (session.subject || ""),
        icon: "assets/logo.png",
      });
      n.onclick = function () { window.focus(); showPage("live"); };
    } catch (e) { /* ignore */ }
  }
}

async function loadLive(quiet) {
  var hadLiveCache = paintLiveFromCache();

  if (!quiet && !hadLiveCache) {
    document.getElementById("live-grid").innerHTML = `<div class="loading">Loading…</div>`;
    document.getElementById("upcoming-grid").innerHTML = `<div class="loading">Loading…</div>`;
  }

  try {
    if (!quiet) syncStudentProfile().catch(function () { /* background */ });

    const [liveRaw, upcomingRaw] = await Promise.all([
      api("/api/v1/live-classes/?status=live&limit=50"),
      api("/api/v1/live-classes/?status=upcoming&limit=50"),
    ]);

    let live = filterSessionsBySubjects(liveRaw || []);
    const upcoming = filterSessionsBySubjects(upcomingRaw || []);

    if (quiet) {
      live.forEach(function (s) {
        if (!knownLiveClassIds.has(s.id)) showLiveClassToast(s);
      });
    }
    knownLiveClassIds = new Set(live.map(function (s) { return s.id; }));

    cacheLiveSessions(live, upcoming);
    renderLive(live);
    renderUpcoming(upcoming);
    renderDashboardLive(live);

    if (!live.length) {
      if (typeof window.stopNotificationRing === "function") window.stopNotificationRing();
      if (typeof window.scholaxiaSyncLiveRing === "function") window.scholaxiaSyncLiveRing();
    }

    if (!quiet) {
      api("/api/v1/home/feed").then(function (feed) {
        if (feed && feed.my_session_requests) renderRequests(feed.my_session_requests);
        else loadMyRequests();
      }).catch(function () { loadMyRequests(); });
    }
  } catch (e) {
    if (!quiet && !_liveSessionsCache.live.length) {
      var liveMsg = typeof networkErrorMessage === "function" ? networkErrorMessage(e) : e.message;
      document.getElementById("live-grid").innerHTML = `<div class="empty">${escHtml(liveMsg)}</div>`;
    }
  }
}

function liveVisibilityLabel(v) {
  if (v === "public") return "Platform";
  if (v === "private") return "Private";
  if (v === "school_group") return "School";
  return "Subject";
}

function renderLiveEmpty(el) {
  el.innerHTML = `
    <div class="live-empty-state">
      <div class="live-empty-icon" aria-hidden="true">&#127909;</div>
      <h3>No live classes right now</h3>
      <p>When your teacher hosts a class, copy your code from <strong>Access Code</strong>, then tap <strong>Join live</strong> and paste once.</p>
      <button type="button" class="btn-action live-empty-refresh" onclick="refreshPage()">Check again</button>
    </div>`;
}

function renderUpcomingEmpty(el) {
  el.innerHTML = `
    <div class="live-empty-state live-empty-compact">
      <p>No classes scheduled. Ask your teacher to schedule one, or send a request below.</p>
    </div>`;
}

function renderLive(sessions) {
  sessions = dedupeLiveSessions(sessions);
  document.getElementById("live-count").textContent = sessions.length;
  const el = document.getElementById("live-grid");
  if (!sessions.length) {
    renderLiveEmpty(el);
    return;
  }
  el.innerHTML = sessions.map((s) => {
    const badge = s.visibility === "private"
      ? "PRIVATE INVITE"
      : (s.is_live ? "LIVE NOW" : "STARTING");
    const badgeClass = s.visibility === "private" ? "dash-invite-pill" : "live-pill";
    const vis = s.visibility && s.visibility !== "private"
      ? '<span class="live-vis-pill">' + escHtml(liveVisibilityLabel(s.visibility)) + "</span>"
      : "";
    return `
    <div class="card">
      <div class="${badgeClass}">${badge}</div>
      ${vis}
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">Teacher: ${escHtml(s.teacher_name)} · ${escHtml(s.subject)}</p>
      <button type="button" class="btn-action" onclick="openJoinLiveModal()">Join live</button>
    </div>
  `;
  }).join("");
}

function renderUpcoming(sessions) {
  const el = document.getElementById("upcoming-grid");
  const now = Date.now();
  if (!sessions.length) {
    renderUpcomingEmpty(el);
    return;
  }
  el.innerHTML = sessions.map((s) => {
    const startMs = s.start_time ? new Date(s.start_time).getTime() : 0;
    const started = startMs && startMs <= now;
    const badge = s.is_live ? "LIVE NOW" : (started ? "Starting…" : "Upcoming");
    const badgeClass = s.is_live || started ? "live-pill" : "time-badge";
    return `
    <div class="card upcoming-card">
      <div class="${badgeClass}">${badge}</div>
      <h3>${escHtml(s.title)}</h3>
      <p class="meta">${escHtml(s.subject)} · ${escHtml(s.teacher_name)}</p>
      <p class="schedule-meta">&#128197; ${formatDate(s.start_time)}${s.end_time ? " → " + formatDate(s.end_time) : ""}</p>
      ${s.is_live ? `<button type="button" class="btn-action" onclick="openJoinLiveModal()">Join live</button>` : (started ? `<p class="notify-hint">Code will appear in Access Code tab when class starts.</p>` : `<p class="notify-hint">You'll get a code in Access Code tab when class starts.</p>`)}
    </div>`;
  }).join("");
}

async function joinClass(btn) {
  return joinClassWithPayment(btn);
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

/* ── External School Exam ── */

async function loadSchoolExams() {
  document.getElementById("school-grid").innerHTML = `<div class="loading">Loading…</div>`;
  try {
    const data = await api("/api/v1/cbt/exams/for-me");
    if (!data) return;
    schoolExams = data.school_exams || [];
    renderSchoolGrid();
  } catch (e) {
    var msg = e.message && e.message.includes("setup")
      ? e.message + " Go to Profile to complete setup."
      : (typeof networkErrorMessage === "function" ? networkErrorMessage(e) : e.message);
    document.getElementById("school-grid").innerHTML = `<div class="empty">${escHtml(msg)}</div>`;
  }
}

function renderSchoolGrid() {
  const el = document.getElementById("school-grid");
  if (!schoolExams.length) {
    el.innerHTML = `<div class="empty">No teacher exams for your subjects yet. When your teacher uploads one, it appears here.</div>`;
    return;
  }
  el.innerHTML = schoolExams.map((e) => `
    <div class="card">
      <div class="time-badge">&#128221; Teacher exam</div>
      <h3>${escHtml(e.title)}</h3>
      <p class="meta">${escHtml(e.subject)} · ${e.total_questions} questions · ${e.duration_minutes} min</p>
      ${e.scheduled_start ? `<p class="meta">${formatDate(e.scheduled_start)} – ${formatDate(e.scheduled_end)}</p>` : ""}
      <button class="btn-join" onclick="openSchoolExam('${e.id}', ${e.camera_required ? "true" : "false"})">Start exam</button>
    </div>
  `).join("");
}

function openSchoolExam(examId, needsCamera) {
  pendingSchoolExamId = examId;
  if (!needsCamera) {
    beginExam(examId, true);
    return;
  }
  document.getElementById("camera-modal").classList.remove("hidden");
  navigator.mediaDevices.getUserMedia({ video: true })
    .then((stream) => {
      cameraStream = stream;
      document.getElementById("camera-preview").srcObject = stream;
    })
    .catch(() => alert("Camera access is required for external school exams."));
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
  if (typeof loadCbtHubPage === "function") {
    await loadCbtHubPage();
    return;
  }
  showCbtListView();
  document.getElementById("cbt-grid").innerHTML = `<div class="loading">Loading…</div>`;
  if (typeof warmScholaxiaApi === "function") warmScholaxiaApi();
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
      var msg = e.message && e.message.includes("setup")
        ? e.message + " Go to Profile to complete setup."
        : (typeof networkErrorMessage === "function" ? networkErrorMessage(e) : e.message);
      document.getElementById("cbt-grid").innerHTML = `<div class="empty">${escHtml(msg)}</div>`;
      return;
    }
    renderCbtGrid({ profileComplete: true });
  }
}

function renderCbtYearPicker(exam) {
  if (!exam.is_aloc) return "";
  const yearTag = exam.exam_type === "JAMB" ? "UTME"
    : (exam.exam_type === "POST_UTME" ? "POST-UTME" : (exam.exam_type || "Exam"));
  const bySubject = exam.years_by_subject || {};
  const pickerYears = exam.common_years || exam.available_years || [];
  const subjectRows = Object.keys(bySubject).map((s) => {
    const years = bySubject[s] || [];
    const recent = years.filter((y) => Number(y) >= 2015).slice(0, 6).map((y) => `<span class="year-mini">${escHtml(y)}</span>`).join("");
    const older = years.filter((y) => Number(y) < 2015).length
      ? `<span class="year-mini muted">+${years.filter((y) => Number(y) < 2015).length} older</span>`
      : "";
    return `<div class="year-subject-row"><span class="year-subject-name">${escHtml(s)}</span><div class="year-mini-row">${recent}${older}</div></div>`;
  }).join("");
  const menuItems = [
    { value: "", label: `Any year — mixed ${yearTag} papers` },
    ...pickerYears.map((y) => ({ value: y, label: `${yearTag} ${y} ✓ all subjects` })),
  ];
  const defaultItem = pickerYears.length
    ? menuItems.find((item) => item.value === pickerYears[0]) || menuItems[0]
    : menuItems[0];
  const menuHtml = menuItems.map((item) => `
    <button type="button" class="year-dropdown-option ${item.value === defaultItem.value ? "active" : ""}"
      data-value="${escHtml(item.value)}" role="option">${escHtml(item.label)}</button>
  `).join("");
  const noSharedYears = !pickerYears.length
    ? `<p class="year-common-note meta-warn">No single ${escHtml(yearTag)} year has papers for <strong>all</strong> your subjects in ALOC. Use <strong>Any year</strong>, or change subjects in Profile.</p>`
    : `<p class="year-common-note"><strong>Full exam years</strong> (all your subjects): ${pickerYears.slice(0, 12).map((y) => escHtml(y)).join(", ")}</p>`;
  return `
    <div class="cbt-year-picker">
      <div class="year-picker-row">
        <label class="year-picker-label">Exam year</label>
        <div class="year-dropdown" data-open="false">
          <input type="hidden" class="cbt-year-value" value="${escHtml(defaultItem.value)}" />
          <button type="button" class="year-dropdown-trigger" aria-expanded="false" aria-haspopup="listbox">
            <span class="year-dropdown-label">${escHtml(defaultItem.label)}</span>
            <span class="year-dropdown-chevron" aria-hidden="true">▾</span>
          </button>
          <div class="year-dropdown-menu" role="listbox">${menuHtml}</div>
        </div>
      </div>
      <p class="year-picker-hint">Only years where <strong>every</strong> subject has ${escHtml(yearTag)} papers are listed.</p>
      <details class="year-details">
        <summary>View years per subject</summary>
        <div class="year-subject-grid">${subjectRows}</div>
      </details>
      ${noSharedYears}
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
      <button type="button" class="btn-join" data-exam-id="${escHtml(e.id)}">${startLabel}</button>
    </div>`;
  }).join("");
  bindYearDropdowns();
  const grid = document.getElementById("cbt-grid");
  const combinedCard = grid?.querySelector(".card-combined");
  if (combinedCard && navigator.onLine) {
    const defaultYear = combinedCard.querySelector(".cbt-year-value")?.value || "";
    prefetchCbtExam(combinedCard, defaultYear);
    updateCbtCardReadyState(combinedCard);
  }
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
  const fastOpen = hasOfflineCbtPack(examId, utmeYear || "");
  showCbtLoadingOverlay(
    fastOpen
      ? "Opening your saved exam…"
      : `Loading ${examLabel} CBT (${yearLabel})… First download may take 20–40 seconds.`
  );
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
      `${exam.subject} · ${exam.questions.length} questions · ${isSchool ? "Scholaxia exam (locked mode)" : "Practice"}`;
    if (isSchool && session.block_minimize) bindSchoolExamGuards();

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

function bindSchoolExamGuards() {
  if (window._schoolExamGuardBound) return;
  window._schoolExamGuardBound = true;
  document.addEventListener("visibilitychange", onExamVisibilityChange);
}

async function onExamVisibilityChange() {
  if (!isCbtExamActive() || !currentSession || !currentSession.is_school_exam) {
    if (!document.hidden && timerEndsAt) tickCbtTimer();
    return;
  }
  if (!document.hidden) {
    if (timerEndsAt) tickCbtTimer();
    return;
  }
  try {
    await api("/api/v1/cbt/proctor/event", {
      method: "POST",
      body: JSON.stringify({
        session_id: currentSession.session_id,
        event_type: "tab_switch",
      }),
    });
  } catch (e) { /* ignore */ }
  alert("Stay on the exam screen until you submit. Sia and other tabs are locked during the test.");
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

  if (currentSession && currentSession.is_internal) {
    try {
      const result = await api("/api/v1/cbt/external-exams/" + currentSession.exam_id + "/submit", {
        method: "POST",
        body: JSON.stringify({
          answers: answerMap,
          is_auto_submit: secondsLeft <= 0,
        }),
      });
      showResult(result);
    } catch (e) {
      const offline = typeof navigator !== "undefined" && !navigator.onLine;
      if (offline && typeof queueInternalSubmit === "function") {
        queueInternalSubmit(currentSession.exam_id, answerMap);
        // Local preview score so students see how they did; admin still gets the real score on sync.
        let localCorrect = 0;
        let localWrong = 0;
        currentExam.questions.forEach((q, i) => {
          const chosen = answers[i];
          if (chosen && String(chosen).toUpperCase() === String(q.correct_option || "").toUpperCase()) localCorrect++;
          else localWrong++;
        });
        const localTotal = localCorrect + localWrong;
        const localPct = localTotal ? Math.round((localCorrect / localTotal) * 100) : 0;
        showResult({
          percentage: localPct,
          correct: localCorrect,
          wrong: localWrong,
          total: localTotal,
          pending_sync: true,
        });
        document.getElementById("result-detail").innerHTML =
          localCorrect + " correct · " + localWrong + " wrong · " + localTotal + " total<br>" +
          "<strong>Offline:</strong> Your answers are saved. When you reconnect they sync to admin — your official score will appear on External School Exam.";
      } else {
        alert(e.message || "Submit failed.");
        closeExam();
      }
    }
    return;
  }

  if (!currentSession || !currentSession.session_id) {
    let correct = 0;
    let wrong = 0;
    currentExam.questions.forEach((q, i) => {
      const chosen = answers[i];
      if (chosen && String(chosen).toUpperCase() === String(q.correct_option || "").toUpperCase()) correct++;
      else wrong++;
    });
    const total = correct + wrong;
    showResult({
      percentage: total ? Math.round((correct / total) * 100) : 0,
      correct,
      wrong,
      total,
    });
    return;
  }

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
  setExamLockMode(false);
  hideSubjectStartPicker();
  hideCbtLoadingOverlay();
  document.getElementById("exam-screen").classList.add("hidden");
  const resultEl = document.getElementById("result-screen");
  resultEl.classList.remove("hidden");
  const closeBtn = document.getElementById("exam-result-close-btn");
  if (closeBtn) {
    closeBtn.textContent = currentSession && currentSession.is_internal
      ? "Back to External School Exam"
      : currentSession && currentSession.is_school_exam
      ? "Back to Scholaxia Exam"
      : "Back to Exams";
  }
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
  setExamLockMode(false);
  window._schoolExamGuardBound = false;
  const wasInternal = currentSession && currentSession.is_internal;
  const wasSchool = currentSession && currentSession.is_school_exam && !wasInternal;
  currentExam = null;
  currentSession = null;
  document.getElementById("exam-screen").classList.add("hidden");
  document.getElementById("result-screen").classList.add("hidden");
  if (wasInternal) {
    currentPage = "school-portal";
    document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
    document.querySelectorAll(".topnav-btn").forEach((n) => n.classList.remove("active"));
    const pg = document.getElementById("page-school-portal");
    if (pg) pg.classList.add("active");
    const navEl = document.querySelector('.topnav-btn[data-page="school-portal"]');
    if (navEl) navEl.classList.add("active");
    document.getElementById("page-title").textContent = PAGE_TITLES["school-portal"];
    if (typeof loadInternalExamsPage === "function") loadInternalExamsPage();
    return;
  }
  if (wasSchool) {
    currentPage = "school";
    document.querySelectorAll(".page").forEach((p) => p.classList.remove("active"));
    document.querySelectorAll(".topnav-btn").forEach((n) => n.classList.remove("active"));
    const pg = document.getElementById("page-school");
    if (pg) pg.classList.add("active");
    const navEl = document.querySelector('.topnav-btn[data-page="school"]');
    if (navEl) navEl.classList.add("active");
    document.getElementById("page-title").textContent = PAGE_TITLES.school;
    loadSchoolExams();
    return;
  }
  showCbtListView();
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

    var photo = resolveProfileMediaUrl(p.profile_picture || p.avatar_url || "");
    if (photo) localStorage.setItem("sia_profile_picture", photo);
    else localStorage.removeItem("sia_profile_picture");
    applyStoredAvatar((p.full_name || "S").charAt(0).toUpperCase());

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
    if (typeof updateThemeToggleUi === "function") updateThemeToggleUi(typeof getAppTheme === "function" ? getAppTheme() : "light");
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
  if (typeof initAppTheme === "function") initAppTheme();
  if (typeof warmScholaxiaApi === "function") warmScholaxiaApi();
  const sel = document.getElementById("setup-exam-type");
  if (sel) sel.addEventListener("change", () => { selectedSubjects = []; renderSubjectPicker(); });
});

document.addEventListener("visibilitychange", () => {
  if (window._schoolExamGuardBound && isCbtExamActive() && currentSession && currentSession.is_school_exam) {
    onExamVisibilityChange();
    return;
  }
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
window.saveOfflineCbtPack = saveOfflineCbtPack;
window.hasOfflineCbtPack = hasOfflineCbtPack;
window.buildQNav = buildQNav;
window.renderQuestion = renderQuestion;
window.startTimer = startTimer;
window.setExamLockMode = setExamLockMode;
window.closeExam = closeExam;
window.submitExam = submitExam;

function initAppContactForm() {
  var form = document.getElementById("app-contact-form");
  if (!form || form.dataset.bound === "1") return;
  form.dataset.bound = "1";

  var nameEl = document.getElementById("app-contact-name");
  var emailEl = document.getElementById("app-contact-email");
  var topicEl = document.getElementById("app-contact-topic");
  var topicsWrap = document.getElementById("contact-topics");

  if (typeof getUser === "function") {
    var user = getUser();
    if (nameEl && !nameEl.value && user.name && user.name !== "Student") nameEl.value = user.name;
    if (emailEl && !emailEl.value && user.email) emailEl.value = user.email;
  }

  if (topicsWrap) {
    topicsWrap.addEventListener("click", function (e) {
      var btn = e.target.closest(".contact-topic");
      if (!btn) return;
      topicsWrap.querySelectorAll(".contact-topic").forEach(function (b) { b.classList.remove("active"); });
      btn.classList.add("active");
      if (topicEl) topicEl.value = btn.getAttribute("data-topic") || "Other";
    });
  }

  form.addEventListener("submit", function (e) {
    e.preventDefault();
    var ok = document.getElementById("app-contact-success");
    var topic = topicEl ? topicEl.value : "General";
    var msg = document.getElementById("app-contact-message");
    if (msg && msg.value.indexOf("[" + topic + "]") !== 0) {
      msg.value = "[" + topic + "] " + msg.value.trim();
    }
    if (ok) ok.classList.remove("hidden");
    form.reset();
    if (nameEl && typeof getUser === "function") {
      var u = getUser();
      if (u.name && u.name !== "Student") nameEl.value = u.name;
      if (u.email) emailEl.value = u.email;
    }
    if (topicsWrap) {
      topicsWrap.querySelectorAll(".contact-topic").forEach(function (b) { b.classList.remove("active"); });
      var first = topicsWrap.querySelector(".contact-topic");
      if (first) {
        first.classList.add("active");
        if (topicEl) topicEl.value = first.getAttribute("data-topic") || "Live class";
      }
    }
    setTimeout(function () { if (ok) ok.classList.add("hidden"); }, 6000);
  });
}
window.initAppContactForm = initAppContactForm;
window.goToQuestion = goToQuestion;
window.goToSubject = goToSubject;
window.startWithSubject = startWithSubject;
window.prevQuestion = prevQuestion;
window.nextQuestion = nextQuestion;
window.selectAnswer = selectAnswer;
window.showCbtExamView = showCbtExamView;
window.showCbtListView = showCbtListView;
window.refreshPage = refreshPage;
