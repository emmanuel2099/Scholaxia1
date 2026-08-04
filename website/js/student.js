/* Scholaxia — Student Portal
   Functional dashboard wired to the production backend via window.ScholaxiaAPI.
*/
(function () {
  "use strict";

  var api = window.ScholaxiaAPI;
  if (!api || !api.requireAuth(["student"])) return;

  /* =====================================================================
     Small utilities
     ===================================================================== */

  function $(id) {
    return document.getElementById(id);
  }

  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function fmtDate(v) {
    if (!v) return "";
    var d = new Date(v);
    if (isNaN(d.getTime())) return String(v);
    return d.toLocaleString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  }

  function errMsg(err) {
    var msg = (err && err.message) || "Something went wrong. Please try again.";
    // Unwrap JSON-looking detail blobs from FastAPI
    try {
      if (msg.charAt(0) === "{") {
        var parsed = JSON.parse(msg);
        if (parsed && (parsed.message || parsed.detail || parsed.code)) {
          return parsed.message || parsed.detail || msg;
        }
      }
    } catch (e) { /* ignore */ }
    if (err && err.data) {
      var d = err.data.detail || err.data.message || err.data;
      if (typeof d === "object" && d) return d.message || d.detail || JSON.stringify(d);
      if (typeof d === "string") return d;
    }
    return msg;
  }

  function isCbtPackageError(err) {
    var raw = ((err && err.message) || "") + JSON.stringify((err && err.data) || {});
    return /cbt_package|package_required|402/i.test(raw);
  }

  function loadingHtml(msg) {
    return '<div class="loading-state">' + esc(msg || "Loading…") + "</div>";
  }

  function emptyHtml(icon, msg) {
    return (
      '<div class="empty-state"><span class="empty-icon">' +
      (icon || "✨") +
      "</span><strong style=\"display:block;margin-bottom:0.35rem;color:#0f172a\">Nothing here yet</strong>" +
      esc(msg || "Check back soon.") +
      "</div>"
    );
  }

  function errorHtml(msg, retryAttr) {
    return (
      '<div class="error-state">⚠ ' +
      esc(msg || "Could not load this.") +
      (retryAttr
        ? '<br /><button type="button" data-retry="' + retryAttr + '">Try again</button>'
        : "") +
      "</div>"
    );
  }

  function setStatus(el, msg, ok) {
    if (!el) return;
    el.textContent = msg || "";
    el.className = "form-status" + (msg ? (ok ? " ok" : " err") : "");
  }

  function firstArray(data, keys) {
    if (Array.isArray(data)) return data;
    if (!data || typeof data !== "object") return [];
    for (var i = 0; i < keys.length; i++) {
      if (Array.isArray(data[keys[i]])) return data[keys[i]];
    }
    return [];
  }

  function debounce(fn, ms) {
    var t;
    return function () {
      var args = arguments;
      clearTimeout(t);
      t = setTimeout(function () {
        fn.apply(null, args);
      }, ms || 250);
    };
  }

  function readLocalJson(key, fallback) {
    try {
      var raw = localStorage.getItem(key);
      return raw ? JSON.parse(raw) : fallback;
    } catch (e) {
      return fallback;
    }
  }

  function writeLocalJson(key, val) {
    try {
      localStorage.setItem(key, JSON.stringify(val));
    } catch (e) {}
  }

  /* =====================================================================
     Header / identity
     ===================================================================== */

  var user = api.getUser();
  var nameEl = $("userName");
  var av = $("userAv");
  if (nameEl) nameEl.textContent = user.name;
  if (av) av.textContent = (user.name || "S").charAt(0).toUpperCase();

  var hour = new Date().getHours();
  var greet =
    hour < 12 ? "Good morning" : hour < 17 ? "Good afternoon" : "Good evening";
  var dashGreetingEl = $("dashGreeting");
  if (dashGreetingEl) {
    dashGreetingEl.textContent =
      greet + ", " + (user.name || "Student").split(" ")[0];
  }

  function refreshLocalExamBadges() {
    var examType = localStorage.getItem("sia_exam_type") || "";
    var subjects = readLocalJson("sia_subjects", []);
    if (!Array.isArray(subjects)) subjects = [];

    if ($("examPill")) $("examPill").textContent = examType ? examType.toUpperCase() : "Student";
    if ($("dashExamType")) $("dashExamType").textContent = examType ? examType.toUpperCase() : "Your exam";
    if ($("dashSubjCount"))
      $("dashSubjCount").textContent = subjects.length ? subjects.length + " subjects" : "Your subjects";
    if ($("dashFocus")) $("dashFocus").textContent = subjects.length ? subjects.slice(0, 2).join(", ") : "Set up subjects";
    if ($("dashSubjectsText"))
      $("dashSubjectsText").textContent =
        subjects.length + " subject" + (subjects.length === 1 ? "" : "s") + " selected";
    if ($("statSubjects")) $("statSubjects").textContent = String(subjects.length);
    if ($("profileExam")) $("profileExam").textContent = examType ? examType.toUpperCase() : "Not set";
    if ($("profileSubjects")) $("profileSubjects").textContent = subjects.length ? subjects.join(", ") : "None selected";
    return { examType: examType, subjects: subjects };
  }
  refreshLocalExamBadges();

  if ($("profileText")) {
    $("profileText").textContent = user.name + " · " + user.email + " · Student";
  }

  var logoutBtn = $("logoutBtn");
  if (logoutBtn) {
    logoutBtn.addEventListener("click", function () {
      api.clearSession();
      window.location.href = "auth.html";
    });
  }

  /* =====================================================================
     Navigation / lazy page loading
     ===================================================================== */

  var PAGE_TITLES = {
    home: "Home",
    "study-materials": "Study Materials",
    "past-questions": "Past Questions",
    cbt: "CBT Practice",
    school: "Scholaxia Exam",
    "access-code": "Live Class",
    live: "Live Class",
    "school-portal": "External School Exam",
    subscription: "Subscription",
    skills: "Skills",
    library: "Library",
    assignments: "Assignments",
    marketplace: "Marketplace",
    sia: "Tutor AI",
    community: "Community",
    groups: "Groups",
    saved: "Saved",
    about: "About",
    contact: "Contact",
    profile: "Profile",
  };

  var loadedPages = {};

  var PAGE_LOADERS = {
    home: loadHome,
    "study-materials": loadStudyMaterials,
    "past-questions": loadPastQuestions,
    cbt: loadCbt,
    school: loadSchoolExams,
    "access-code": function () { showPage("live"); },
    live: loadLive,
    "school-portal": loadSchoolPortal,
    subscription: loadSubscription,
    skills: loadSkills,
    library: loadLibrary,
    assignments: loadAssignments,
    marketplace: loadMarketplace,
    community: loadCommunity,
    groups: loadGroups,
    saved: loadSaved,
    profile: loadProfile,
  };

  var pageHistory = [];
  var currentPageId = "home";

  function showPage(id, opts) {
    opts = opts || {};
    if (id === "access-code") id = "live";
    if (!PAGE_TITLES.hasOwnProperty(id)) id = "home";

    if (!opts.replace && currentPageId && currentPageId !== id) {
      pageHistory.push(currentPageId);
      if (pageHistory.length > 20) pageHistory = pageHistory.slice(-20);
    }
    currentPageId = id;

    document.querySelectorAll(".page").forEach(function (p) {
      p.classList.toggle("is-on", p.id === "page-" + id);
    });
    document.querySelectorAll(".side-link").forEach(function (b) {
      b.classList.toggle("is-active", b.dataset.page === id || (id === "live" && b.dataset.page === "live"));
    });
    if ($("pageTitle")) $("pageTitle").textContent = PAGE_TITLES[id] || "";
    var main = document.querySelector(".app-content");
    if (main) main.scrollTop = 0;

    updateBackBtn();

    if (!loadedPages[id] && PAGE_LOADERS[id]) {
      loadedPages[id] = true;
      try {
        PAGE_LOADERS[id]();
      } catch (e) {
        console.error("Page load failed for", id, e);
      }
    }
  }

  function updateBackBtn() {
    var btn = $("backBtn");
    if (!btn) return;
    var show = currentPageId !== "home";
    btn.hidden = !show;
    btn.setAttribute("aria-hidden", show ? "false" : "true");
  }

  function goBack() {
    var prev = null;
    while (pageHistory.length) {
      prev = pageHistory.pop();
      if (prev && prev !== currentPageId) break;
      prev = null;
    }
    showPage(prev || "home", { replace: true });
  }

  document.querySelectorAll(".side-link, [data-goto]").forEach(function (el) {
    el.addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();
      var page = el.dataset.page || el.dataset.goto;
      if (page) {
        showPage(page);
        if (window.matchMedia("(max-width: 900px)").matches) closeMobileNav();
      }
    });
  });

  // Capture-phase fallback so mobile taps on icons/text still switch pages
  var sideNav = document.querySelector(".student-side");
  if (sideNav) {
    sideNav.addEventListener(
      "click",
      function (e) {
        var btn = e.target.closest(".side-link, [data-goto]");
        if (!btn) return;
        var page = btn.getAttribute("data-page") || btn.getAttribute("data-goto");
        if (!page) return;
        e.preventDefault();
        e.stopPropagation();
        showPage(page);
        if (window.matchMedia("(max-width: 900px)").matches) closeMobileNav();
      },
      true
    );
  }

  document.addEventListener("click", function (e) {
    var retryBtn = e.target.closest("[data-retry]");
    if (retryBtn) {
      var page = retryBtn.dataset.retry;
      if (PAGE_LOADERS[page]) PAGE_LOADERS[page]();
      return;
    }
    var refreshBtn = e.target.closest("[data-refresh]");
    if (refreshBtn) {
      var p2 = refreshBtn.dataset.refresh;
      if (PAGE_LOADERS[p2]) PAGE_LOADERS[p2]();
    }
  });

  /* =====================================================================
     HOME
     ===================================================================== */

  function renderLiveCardMini(c) {
    var title = c.title || c.topic || c.subject || "Live class";
    var teacher = c.teacher_name || c.host_name || c.teacher || "";
    return (
      '<div class="card">' +
      '<span class="card-tag">🔴 LIVE</span>' +
      "<h4>" +
      esc(title) +
      "</h4>" +
      (teacher ? '<p class="muted">' + esc(teacher) + "</p>" : "") +
      '<div class="card-foot"><button type="button" class="btn btn-primary btn-mini" data-goto="live">Join now</button></div>' +
      "</div>"
    );
  }

  function loadHome() {
    api
      .api("/api/v1/students/me")
      .then(function (me) {
        if (!me) return;
        var name = me.full_name || me.name || user.name;
        if (nameEl && name) nameEl.textContent = name;
        if (av && name) av.textContent = String(name).charAt(0).toUpperCase();
        if (dashGreetingEl && name) {
          dashGreetingEl.textContent = greet + ", " + String(name).split(" ")[0];
        }
        if (me.exam_type) localStorage.setItem("sia_exam_type", me.exam_type);
        if (Array.isArray(me.subjects)) writeLocalJson("sia_subjects", me.subjects);
        refreshLocalExamBadges();
      })
      .catch(function () {});

    api
      .api("/api/v1/live-classes/?status=live")
      .then(function (data) {
        var items = firstArray(data, ["classes", "items", "results", "live_classes"]);
        if ($("statLive")) $("statLive").textContent = String(items.length || 0);
        var wrap = $("homeLiveNow");
        var titleWrap = $("homeLiveNowTitle");
        if (!wrap) return;
        if (!items.length) {
          wrap.innerHTML = "";
          if (titleWrap) titleWrap.style.display = "none";
          return;
        }
        if (titleWrap) titleWrap.style.display = "flex";
        wrap.innerHTML = items.slice(0, 3).map(renderLiveCardMini).join("");
      })
      .catch(function () {
        if ($("statLive")) $("statLive").textContent = "0";
      });

    api
      .api("/api/v1/cbt/exams/for-me")
      .then(function (data) {
        data = data || {};
        var count =
          (data.practice_exams || []).length +
          (data.jamb_exams || []).length +
          (data.ssce_exams || []).length +
          (data.school_exams || []).length;
        if ($("statExams")) $("statExams").textContent = String(count);
        cacheExamsForMe(data);
      })
      .catch(function () {
        if ($("statExams")) $("statExams").textContent = "—";
      });
  }

  /* =====================================================================
     STUDY MATERIALS  — recommendations feed
     ===================================================================== */

  function loadStudyMaterials() {
    var wrap = $("studyMaterialsList");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading recommendations…");
    api
      .api("/api/v1/recommendations/feed")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "feed", "recommendations"]);
        if (!items.length) {
          wrap.innerHTML = emptyHtml("📘", "No recommendations yet. Set up your subjects in Profile to get personalised study picks.");
          return;
        }
        wrap.innerHTML = items
          .map(function (it) {
            var title = it.title || it.name || it.subject || "Study material";
            var desc = it.description || it.summary || it.reason || "";
            var tag = it.subject || it.category || "Recommended";
            var bookId = it.book_id || it.library_id || it.id;
            var canOpen = !!it.book_id || !!it.library_id;
            return (
              '<div class="card">' +
              '<span class="card-tag">' +
              esc(tag) +
              "</span><h4>" +
              esc(title) +
              "</h4>" +
              (desc ? "<p>" + esc(desc) + "</p>" : "") +
              '<div class="card-foot">' +
              (canOpen
                ? '<button type="button" class="btn btn-primary btn-mini" data-open-book="' +
                  esc(bookId) +
                  '">Open</button>'
                : '<span class="muted">Recommended for you</span>') +
              "</div></div>"
            );
          })
          .join("");
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "study-materials");
      });
  }

  document.addEventListener("click", function (e) {
    var openBtn = e.target.closest("[data-open-book]");
    if (openBtn) openLibraryRead(openBtn.dataset.openBook, openBtn);
  });

  function openLibraryRead(id, btn) {
    if (!id) return;
    if (btn) {
      btn.disabled = true;
      var prevText = btn.textContent;
      btn.textContent = "Opening…";
      var reset = function () {
        btn.disabled = false;
        btn.textContent = prevText;
      };
    }
    api
      .api("/api/v1/library/" + id + "/read")
      .then(function (res) {
        var url =
          (res && (res.read_url || res.file_url || res.url)) ||
          (typeof res === "string" ? res : "");
        if (url) {
          window.open(url, "_blank");
        } else {
          alert("This resource has no readable file yet.");
        }
        if (btn) reset();
      })
      .catch(function (err) {
        alert("Could not open resource: " + errMsg(err));
        if (btn) reset();
      });
  }

  /* =====================================================================
     PAST QUESTIONS — library filtered to "past" category
     ===================================================================== */

  var pastQuestionsCache = null;
  var pqActiveCat = "all";

  function loadPastQuestions() {
    var wrap = $("pastQuestionsList");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading past questions…");
    api
      .api("/api/v1/library/student")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "library"]);
        pastQuestionsCache = items.filter(function (it) {
          var cat = (it.category || it.type || "").toString().toLowerCase();
          var title = (it.title || "").toString().toLowerCase();
          return cat.indexOf("past") > -1 || title.indexOf("past question") > -1;
        });
        renderPastQuestions();
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "past-questions");
      });
  }

  function renderPastQuestions() {
    var wrap = $("pastQuestionsList");
    if (!wrap || !pastQuestionsCache) return;
    var items = pastQuestionsCache;
    if (pqActiveCat !== "all") {
      items = items.filter(function (it) {
        var hay = ((it.category || "") + " " + (it.title || "")).toLowerCase();
        return hay.indexOf(pqActiveCat) > -1 || (pqActiveCat === "post" && hay.indexOf("utme") > -1);
      });
    }
    if (!items.length) {
      wrap.innerHTML = emptyHtml("📄", "No past questions found for this filter yet.");
      return;
    }
    wrap.innerHTML = items.map(renderLibraryCard).join("");
  }

  var pqTabs = $("pqFilterTabs");
  if (pqTabs) {
    pqTabs.addEventListener("click", function (e) {
      var btn = e.target.closest(".tab");
      if (!btn) return;
      pqTabs.querySelectorAll(".tab").forEach(function (t) {
        t.classList.toggle("is-active", t === btn);
      });
      pqActiveCat = btn.dataset.cat;
      renderPastQuestions();
    });
  }

  function renderLibraryCard(it) {
    var title = it.title || it.name || "Resource";
    var cat = it.category || it.type || "Library";
    var desc = it.description || it.subject || "";
    var price = Number(it.price || 0);
    var hasAccess = !!(it.has_access || it.is_free || price <= 0);
    var foot;
    if (hasAccess) {
      foot =
        '<button type="button" class="btn btn-primary btn-mini" data-open-book="' +
        esc(it.id) +
        '">Read</button>';
    } else {
      foot =
        "<strong>₦" +
        price.toLocaleString("en-NG") +
        '</strong><button type="button" class="btn btn-primary btn-mini" data-pay-type="library_book" data-pay-id="' +
        esc(it.id) +
        '">Pay with Paystack</button>';
    }
    return (
      '<div class="card">' +
      '<span class="card-tag">' +
      esc(cat) +
      "</span><h4>" +
      esc(title) +
      "</h4>" +
      (desc ? "<p>" + esc(desc) + "</p>" : "") +
      '<div class="card-foot">' +
      foot +
      "</div></div>"
    );
  }

  /* =====================================================================
     LIBRARY — full list with search / category filter
     ===================================================================== */

  var libraryCache = [];

  function loadLibrary() {
    var wrap = $("libraryGrid");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading library…");
    api
      .api("/api/v1/library/student")
      .then(function (data) {
        libraryCache = firstArray(data, ["items", "results", "library"]);
        var cats = Array.from(
          new Set(libraryCache.map(function (it) { return it.category || it.type; }).filter(Boolean))
        );
        var sel = $("libFilter");
        if (sel) {
          sel.innerHTML =
            '<option value="">All categories</option>' +
            cats.map(function (c) { return '<option value="' + esc(c) + '">' + esc(c) + "</option>"; }).join("");
        }
        renderLibrary();
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "library");
      });
  }

  function renderLibrary() {
    var wrap = $("libraryGrid");
    if (!wrap) return;
    var q = ($("libSearch") && $("libSearch").value || "").toLowerCase().trim();
    var cat = ($("libFilter") && $("libFilter").value) || "";
    var items = libraryCache.filter(function (it) {
      if (cat && (it.category || it.type) !== cat) return false;
      if (q) {
        var hay = ((it.title || "") + " " + (it.description || "") + " " + (it.subject || "")).toLowerCase();
        if (hay.indexOf(q) < 0) return false;
      }
      return true;
    });
    if (!items.length) {
      wrap.innerHTML = emptyHtml("📚", "No library resources match your search.");
      return;
    }
    wrap.innerHTML = items.map(renderLibraryCard).join("");
  }

  if ($("libSearch")) $("libSearch").addEventListener("input", debounce(renderLibrary, 200));
  if ($("libFilter")) $("libFilter").addEventListener("change", renderLibrary);

  /* =====================================================================
     Exam data cache + shared exam engine (CBT / School / External)
     ===================================================================== */

  var examsForMeCache = null;

  function cacheExamsForMe(data) {
    examsForMeCache = data || {};
  }

  function fetchExamsForMe() {
    if (examsForMeCache) return Promise.resolve(examsForMeCache);
    return api.api("/api/v1/cbt/exams/for-me").then(function (data) {
      cacheExamsForMe(data);
      return examsForMeCache;
    });
  }

  function packKey(id, isExternal) {
    return isExternal ? "sia_cbt_pack_ext_" + id : "sia_cbt_pack_" + id;
  }

  function getPack(id, isExternal) {
    return readLocalJson(packKey(id, isExternal), null);
  }

  function setPack(id, isExternal, data) {
    writeLocalJson(packKey(id, isExternal), data);
  }

  function examMinutes(exam) {
    return exam.duration_minutes || exam.duration || exam.time_limit || 20;
  }

  function renderExamCard(exam, opts) {
    opts = opts || {};
    var id = exam.id || exam.exam_id;
    var title = exam.title || exam.name || exam.subject || "Exam";
    var subject = exam.subject || "";
    var year = exam.year || "";
    var qCount = exam.total_questions || exam.question_count || (exam.questions && exam.questions.length) || "";
    var hasPack = !!getPack(id, opts.isExternal);
    var badge = opts.badge || (exam.board ? exam.board.toUpperCase() : "EXAM");
    return (
      '<div class="card" data-exam-card="' +
      esc(id) +
      '">' +
      '<span class="card-tag">' +
      esc(badge) +
      "</span><h4>" +
      esc(title) +
      "</h4>" +
      '<p style="margin:0;color:#64748b;font-size:0.84rem;line-height:1.4">Timed CBT session ready when you are.</p>' +
      '<div class="card-meta-row">' +
      (subject ? "<span>" + esc(subject) + "</span>" : "") +
      (year ? "<span>" + esc(year) + "</span>" : "") +
      (qCount ? "<span>" + esc(qCount) + " Qs</span>" : "") +
      "<span>" + esc(examMinutes(exam)) + " mins</span>" +
      "</div>" +
      '<div class="card-foot">' +
      '<button type="button" class="btn btn-secondary btn-mini' +
      (hasPack ? " is-done" : "") +
      '" data-action="download" data-exam-id="' +
      esc(id) +
      '" data-external="' +
      (opts.isExternal ? "1" : "0") +
      '">' +
      (hasPack ? "Downloaded ✓" : "Download") +
      "</button>" +
      '<button type="button" class="btn btn-primary btn-mini" data-action="start" data-exam-id="' +
      esc(id) +
      '" data-external="' +
      (opts.isExternal ? "1" : "0") +
      '" data-school="' +
      (opts.isSchool ? "1" : "0") +
      '">Start exam</button>' +
      "</div></div>"
    );
  }

  function findExamById(list, id) {
    return (list || []).filter(function (e) { return String(e.id || e.exam_id) === String(id); })[0];
  }

  // Delegated handlers for exam cards (download / start) across cbt / school / school-portal
  document.addEventListener("click", function (e) {
    var btn = e.target.closest("[data-action]");
    if (!btn) return;
    var action = btn.dataset.action;
    var examId = btn.dataset.examId;
    var isExternal = btn.dataset.external === "1";
    var isSchool = btn.dataset.school === "1";
    if (action === "download") downloadExam(examId, isExternal, btn);
    if (action === "start") startExamFlow(examId, isExternal, isSchool, btn);
  });

  function currentExamSourceList() {
    var list = []
      .concat(examsForMeCache ? examsForMeCache.practice_exams || [] : [])
      .concat(examsForMeCache ? examsForMeCache.jamb_exams || [] : [])
      .concat(examsForMeCache ? examsForMeCache.ssce_exams || [] : [])
      .concat(examsForMeCache ? examsForMeCache.school_exams || [] : [])
      .concat(externalExamsCache || []);
    return list;
  }

  function downloadExam(examId, isExternal, btn) {
    var base = isExternal ? "/api/v1/cbt/external-exams/" : "/api/v1/cbt/exams/";
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Downloading…";
    }
    api
      .api(base + examId + "/download")
      .then(function (data) {
        setPack(examId, isExternal, data);
        if (btn) {
          btn.disabled = false;
          btn.textContent = "Downloaded ✓";
          btn.classList.add("is-done");
        }
      })
      .catch(function (err) {
        if (btn) {
          btn.disabled = false;
          btn.textContent = "Download";
        }
        if (isCbtPackageError(err)) {
          if (confirm("Your CBT package is inactive or expired. Open CBT packages to pay with Paystack?")) {
            showPage("cbt");
          }
          return;
        }
        alert("Download failed: " + errMsg(err));
      });
  }

  function startExamFlow(examId, isExternal, isSchool, btn) {
    var pack = getPack(examId, isExternal);
    if (!pack) {
      alert("Please download this exam first.");
      return;
    }
    var exam = findExamById(currentExamSourceList(), examId) || {};
    var title = exam.title || exam.name || pack.title || pack.name || "Exam";

    if (isExternal) {
      openExam({
        examId: examId,
        title: title,
        pack: pack,
        isExternal: true,
      });
      return;
    }

    if (btn) {
      btn.disabled = true;
      btn.textContent = "Starting…";
    }
    api
      .api("/api/v1/cbt/sessions/" + examId + "/start", {
        method: "POST",
        body: { is_school: !!isSchool },
      })
      .then(function (res) {
        var sessionId =
          (res && (res.session_id || res.id || (res.session && res.session.id))) || null;
        var questions = (res && (res.questions || (res.session && res.session.questions))) || null;
        if (btn) {
          btn.disabled = false;
          btn.textContent = "Start exam";
        }
        openExam({
          examId: examId,
          title: title,
          pack: questions ? { questions: questions, duration_minutes: examMinutes(exam) } : pack,
          sessionId: sessionId,
          isSchool: isSchool,
        });
      })
      .catch(function (err) {
        if (btn) {
          btn.disabled = false;
          btn.textContent = "Start exam";
        }
        if (typeof isCbtPackageError === "function" && isCbtPackageError(err)) {
          if (confirm("CBT package required. Open CBT packages to pay with Paystack?")) {
            showPage("cbt");
          }
          return;
        }
        // Offline fallback — still let the student practice with the local pack.
        openExam({ examId: examId, title: title, pack: pack, isSchool: isSchool });
      });
  }

  /* ---------- Exam runner ---------- */

  var Exam = { current: null };

  function normalizeQuestions(raw) {
    return (raw || []).map(function (q, i) {
      var options = [];
      if (q.options && typeof q.options === "object" && !Array.isArray(q.options)) {
        ["A", "B", "C", "D", "E"].forEach(function (k) {
          if (q.options[k] != null && q.options[k] !== "") options.push({ key: k, text: q.options[k] });
        });
      } else if (Array.isArray(q.options)) {
        var letters = ["A", "B", "C", "D", "E"];
        q.options.forEach(function (opt, idx) {
          var text = typeof opt === "string" ? opt : opt.text || opt.label || opt.value || "";
          if (text) options.push({ key: letters[idx] || String(idx), text: text });
        });
      } else {
        ["a", "b", "c", "d", "e"].forEach(function (l) {
          var field = "option_" + l;
          if (q[field] != null && q[field] !== "") options.push({ key: l.toUpperCase(), text: q[field] });
        });
      }
      var correct = q.correct_answer || q.correct_option || q.answer || q.correct || null;
      if (correct != null) correct = String(correct).trim().charAt(0).toUpperCase();
      return {
        id: String(q.id || q.question_id || q._id || i),
        text: q.question || q.text || q.title || q.question_text || "Question " + (i + 1),
        options: options,
        correct: correct,
      };
    });
  }

  function openExam(opts) {
    var pack = opts.pack || {};
    var rawQuestions = Array.isArray(pack) ? pack : pack.questions || pack.data || pack.items || [];
    var questions = normalizeQuestions(rawQuestions);
    if (!questions.length) {
      alert("No questions were found in this exam pack.");
      return;
    }
    Exam.current = {
      examId: opts.examId,
      title: opts.title || "Exam",
      questions: questions,
      answers: {},
      sessionId: opts.sessionId || null,
      isExternal: !!opts.isExternal,
      isSchool: !!opts.isSchool,
      index: 0,
      remainingSec: examMinutes(pack) * 60,
      timerId: null,
    };
    renderExamNav();
    renderExamQuestion();
    $("examTitle").textContent = Exam.current.title;
    $("examSub").textContent =
      (Exam.current.isExternal ? "External exam" : Exam.current.isSchool ? "Scholaxia exam" : "CBT practice") +
      " · " +
      questions.length +
      " questions";
    $("exam-screen").classList.add("is-on");
    startExamTimer();
  }

  function startExamTimer() {
    stopExamTimer();
    updateTimerDisplay();
    Exam.current.timerId = setInterval(function () {
      if (!Exam.current) return;
      Exam.current.remainingSec -= 1;
      updateTimerDisplay();
      if (Exam.current.remainingSec <= 0) {
        stopExamTimer();
        submitExam(true);
      }
    }, 1000);
  }

  function stopExamTimer() {
    if (Exam.current && Exam.current.timerId) {
      clearInterval(Exam.current.timerId);
      Exam.current.timerId = null;
    }
  }

  function updateTimerDisplay() {
    var el = $("examTimer");
    if (!el || !Exam.current) return;
    var s = Math.max(0, Exam.current.remainingSec);
    var m = Math.floor(s / 60);
    var sec = s % 60;
    el.textContent = (m < 10 ? "0" : "") + m + ":" + (sec < 10 ? "0" : "") + sec;
    el.classList.toggle("is-low", s <= 60);
  }

  function renderExamNav() {
    var nav = $("examQuestionNav");
    if (!nav || !Exam.current) return;
    nav.innerHTML = Exam.current.questions
      .map(function (q, i) {
        var cls = "";
        if (i === Exam.current.index) cls = "is-current";
        else if (Exam.current.answers[q.id]) cls = "is-answered";
        return (
          '<button type="button" data-goto-q="' + i + '" class="' + cls + '">' + (i + 1) + "</button>"
        );
      })
      .join("");
  }

  function renderExamQuestion() {
    var st = Exam.current;
    if (!st) return;
    var q = st.questions[st.index];
    $("examQCount").textContent = "Question " + (st.index + 1) + " of " + st.questions.length;
    $("examQuestionText").textContent = q.text;
    var selected = st.answers[q.id];
    $("examOptions").innerHTML = q.options
      .map(function (opt) {
        return (
          '<button type="button" class="exam-option' +
          (selected === opt.key ? " is-selected" : "") +
          '" data-opt-key="' +
          esc(opt.key) +
          '"><span class="opt-key">' +
          esc(opt.key) +
          "</span><span>" +
          esc(opt.text) +
          "</span></button>"
        );
      })
      .join("");
    $("examPrevBtn").disabled = st.index === 0;
    $("examNextBtn").textContent = st.index === st.questions.length - 1 ? "Finish" : "Next →";
    renderExamNav();
  }

  var examOptionsEl = $("examOptions");
  if (examOptionsEl) {
    examOptionsEl.addEventListener("click", function (e) {
      var btn = e.target.closest(".exam-option");
      if (!btn || !Exam.current) return;
      var q = Exam.current.questions[Exam.current.index];
      Exam.current.answers[q.id] = btn.dataset.optKey;
      renderExamQuestion();
    });
  }

  var examNavEl = $("examQuestionNav");
  if (examNavEl) {
    examNavEl.addEventListener("click", function (e) {
      var btn = e.target.closest("[data-goto-q]");
      if (!btn || !Exam.current) return;
      Exam.current.index = parseInt(btn.dataset.gotoQ, 10) || 0;
      renderExamQuestion();
    });
  }

  if ($("examPrevBtn")) {
    $("examPrevBtn").addEventListener("click", function () {
      if (!Exam.current) return;
      Exam.current.index = Math.max(0, Exam.current.index - 1);
      renderExamQuestion();
    });
  }

  if ($("examNextBtn")) {
    $("examNextBtn").addEventListener("click", function () {
      if (!Exam.current) return;
      if (Exam.current.index >= Exam.current.questions.length - 1) {
        confirmSubmitExam();
      } else {
        Exam.current.index += 1;
        renderExamQuestion();
      }
    });
  }

  if ($("examSubmitBtn")) {
    $("examSubmitBtn").addEventListener("click", confirmSubmitExam);
  }

  if ($("examQuitBtn")) {
    $("examQuitBtn").addEventListener("click", function () {
      if (confirm("Quit this exam? Your progress will be lost.")) {
        stopExamTimer();
        Exam.current = null;
        $("exam-screen").classList.remove("is-on");
      }
    });
  }

  function confirmSubmitExam() {
    if (!Exam.current) return;
    var answered = Object.keys(Exam.current.answers).length;
    var total = Exam.current.questions.length;
    if (answered < total) {
      if (!confirm("You have answered " + answered + " of " + total + " questions. Submit anyway?")) return;
    }
    submitExam(false);
  }

  function localScore(st) {
    var correctCount = 0;
    var scored = 0;
    st.questions.forEach(function (q) {
      if (!q.correct) return;
      scored += 1;
      if (st.answers[q.id] && st.answers[q.id] === q.correct) correctCount += 1;
    });
    var total = st.questions.length;
    var pct = scored ? Math.round((correctCount / scored) * 100) : null;
    return {
      score: correctCount,
      total: scored || total,
      percentage: pct,
      offline: true,
      unscored: !scored,
    };
  }

  function submitExam(isAuto) {
    var st = Exam.current;
    if (!st) return;
    stopExamTimer();
    $("exam-screen").classList.remove("is-on");

    var answersOut = {};
    Object.keys(st.answers).forEach(function (k) {
      answersOut[k] = st.answers[k];
    });

    if (st.isExternal) {
      api
        .api("/api/v1/cbt/external-exams/" + st.examId + "/submit", {
          method: "POST",
          body: { answers: answersOut, is_auto_submit: !!isAuto },
        })
        .then(function (res) {
          showResult(res, st);
        })
        .catch(function () {
          showResult(localScore(st), st);
        });
      return;
    }

    if (st.sessionId) {
      api
        .api("/api/v1/cbt/sessions/submit", {
          method: "POST",
          body: { session_id: st.sessionId, answers: answersOut, is_auto_submit: !!isAuto },
        })
        .then(function (res) {
          showResult(res, st);
        })
        .catch(function () {
          showResult(localScore(st), st);
        });
      return;
    }

    showResult(localScore(st), st);
  }

  function showResult(res, st) {
    res = res || {};
    var score = res.score != null ? res.score : res.correct_count;
    var total = res.total != null ? res.total : res.total_questions || (st && st.questions.length);
    var pct =
      res.percentage != null
        ? res.percentage
        : score != null && total
        ? Math.round((score / total) * 100)
        : null;

    $("resultRing").textContent = pct != null ? pct + "%" : "—";
    $("resultTitle").textContent = res.unscored ? "Exam submitted" : "Exam completed";
    $("resultSub").textContent = st ? st.title : "";
    $("resultStats").innerHTML =
      '<div><strong>' +
      (score != null ? score : "—") +
      "</strong><span>Correct</span></div>" +
      '<div><strong>' +
      (total != null ? total : "—") +
      "</strong><span>Total</span></div>" +
      '<div><strong>' +
      (res.offline ? "Offline" : "Synced") +
      "</strong><span>Status</span></div>";
    $("result-screen").classList.add("is-on");
    Exam.current = null;
  }

  if ($("resultCloseBtn")) {
    $("resultCloseBtn").addEventListener("click", function () {
      $("result-screen").classList.remove("is-on");
      // Refresh whichever exam list is currently visible so downloaded/attempted state updates.
      ["cbt", "school", "school-portal"].forEach(function (p) {
        if (document.getElementById("page-" + p) && document.getElementById("page-" + p).classList.contains("is-on")) {
          loadedPages[p] = false;
          PAGE_LOADERS[p] && PAGE_LOADERS[p]();
        }
      });
    });
  }

  /* =====================================================================
     CBT
     ===================================================================== */

  var cbtActiveBoard = "practice_exams";

  function loadCbt() {
    loadCbtPackages({
      gridId: "cbtPagePackagesGrid",
      bannerId: "cbtPageAccessBanner",
    });
    var wrap = $("cbtExamList");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading exams…");
    fetchExamsForMe()
      .then(function () {
        renderCbtBoard();
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "cbt");
      });
  }

  function renderCbtBoard() {
    var wrap = $("cbtExamList");
    if (!wrap) return;
    var list = (examsForMeCache && examsForMeCache[cbtActiveBoard]) || [];
    if (!list.length) {
      wrap.innerHTML = emptyHtml("📝", "No exams available in this category yet.");
      return;
    }
    wrap.innerHTML = list
      .map(function (exam) {
        return renderExamCard(exam, { badge: exam.board || cbtActiveBoard.replace("_exams", "").toUpperCase() });
      })
      .join("");
  }

  var cbtTabs = $("cbtBoardTabs");
  if (cbtTabs) {
    cbtTabs.addEventListener("click", function (e) {
      var btn = e.target.closest(".tab");
      if (!btn) return;
      cbtTabs.querySelectorAll(".tab").forEach(function (t) {
        t.classList.toggle("is-active", t === btn);
      });
      cbtActiveBoard = btn.dataset.board;
      renderCbtBoard();
    });
  }

  /* =====================================================================
     SCHOOL (Scholaxia Exam)
     ===================================================================== */

  function loadSchoolExams() {
    var wrap = $("schoolExamsList");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading exams…");
    fetchExamsForMe()
      .then(function (data) {
        var list = (data && data.school_exams) || [];
        if (!list.length) {
          wrap.innerHTML = emptyHtml("⏱", "No school exams loaded yet. Check back after your teacher publishes one.");
          return;
        }
        wrap.innerHTML = list.map(function (exam) { return renderExamCard(exam, { isSchool: true, badge: "SCHOOL" }); }).join("");
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "school");
      });
  }

  /* =====================================================================
     EXTERNAL SCHOOL EXAM (school-portal)
     ===================================================================== */

  var externalExamsCache = [];

  function loadSchoolPortal() {
    var wrap = $("schoolPortalList");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading external exams…");
    api
      .api("/api/v1/cbt/external-exams/for-me")
      .then(function (data) {
        externalExamsCache = firstArray(data, ["exams", "items", "results", "external_exams"]);
        if (!externalExamsCache.length) {
          wrap.innerHTML = emptyHtml("🏫", "No external school exams available right now.");
          return;
        }
        wrap.innerHTML = externalExamsCache
          .map(function (exam) { return renderExamCard(exam, { isExternal: true, badge: "EXTERNAL" }); })
          .join("");
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "school-portal");
      });
  }

  /* =====================================================================
     ACCESS CODE
     ===================================================================== */

  function renderAccessCodeCard(c) {
    var code = c.code || c.access_code || "";
    var subject = c.subject || c.topic || c.class_title || "Live class access";
    var unread = c.is_read === false || c.read === false;
    return (
      '<div class="card-list-row" data-code-id="' +
      esc(c.id) +
      '">' +
      "<div><strong>" +
      esc(subject) +
      "</strong><div class=\"card-meta-row\"><span>" +
      esc(code) +
      "</span>" +
      (unread ? '<span class="badge badge-purple">New</span>' : "") +
      (c.created_at ? "<span>" + esc(fmtDate(c.created_at)) + "</span>" : "") +
      "</div></div>" +
      '<div class="btn-row">' +
      '<button type="button" class="btn btn-primary btn-mini" data-join-code="' +
      esc(code) +
      '">Join class</button>' +
      '<button type="button" class="btn btn-secondary btn-mini" data-copy-code="' +
      esc(code) +
      '">Copy</button>' +
      (unread
        ? '<button type="button" class="btn btn-mini" data-mark-read="' + esc(c.id) + '">Mark read</button>'
        : "") +
      "</div></div>"
    );
  }

  /* Live class invitation ringtone (same sound as the mobile app) */
  var liveRingAudio = null;
  var liveRingTimer = null;
  var liveRingLimitTimer = null;
  var knownUnreadCodes = {};
  var LIVE_RING_MAX_MS = 45000;
  var LIVE_RING_BURST_MS = 4000;

  function stopLiveClassRing() {
    if (liveRingTimer) {
      clearInterval(liveRingTimer);
      liveRingTimer = null;
    }
    if (liveRingLimitTimer) {
      clearTimeout(liveRingLimitTimer);
      liveRingLimitTimer = null;
    }
    try {
      if (liveRingAudio) {
        liveRingAudio.pause();
        liveRingAudio.currentTime = 0;
      }
    } catch (e) {}
    var bar = $("liveInviteRingBar");
    if (bar) bar.hidden = true;
  }

  function playLiveClassRingBurst() {
    try {
      if (!liveRingAudio) {
        liveRingAudio = new Audio("media/sounds/live_class_ringtone.mp3");
        liveRingAudio.preload = "auto";
      }
      liveRingAudio.currentTime = 0;
      var p = liveRingAudio.play();
      if (p && typeof p.catch === "function") p.catch(function () {});
    } catch (e) {}
  }

  function startLiveClassRing() {
    if (liveRingTimer) return;
    var bar = $("liveInviteRingBar");
    if (bar) bar.hidden = false;
    playLiveClassRingBurst();
    liveRingTimer = setInterval(playLiveClassRingBurst, LIVE_RING_BURST_MS);
    // Hard stop so ringtone is never endless while a class stays live.
    liveRingLimitTimer = setTimeout(function () {
      stopLiveClassRing();
      try {
        localStorage.setItem("sia_stop_live_ring", String(Date.now()));
      } catch (e) {}
    }, LIVE_RING_MAX_MS);
  }

  function pollLiveInvitesForRing() {
    var stopped = Number(localStorage.getItem("sia_stop_live_ring") || "0");
    if (stopped && Date.now() - stopped < 60000) {
      stopLiveClassRing();
      return;
    }
    api
      .api("/api/v1/live-classes/access-codes/mine")
      .then(function (data) {
        var items = firstArray(data, ["codes", "items", "results"]);
        var unread = items.filter(function (c) {
          if (c.is_class_live === false) return false;
          return c.is_read === false || c.read === false;
        });
        var hasNew = false;
        unread.forEach(function (c) {
          var id = String(c.id || c.code || c.access_code || "");
          if (id && !knownUnreadCodes[id]) {
            knownUnreadCodes[id] = true;
            hasNew = true;
          }
        });
        if (unread.length && hasNew) startLiveClassRing();
        else if (!unread.length) stopLiveClassRing();
      })
      .catch(function () {});
  }

  function loadAccessCodes() {
    var wrap = $("accessCodesList");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading access codes…");
    api
      .api("/api/v1/live-classes/access-codes/mine")
      .then(function (data) {
        var items = firstArray(data, ["codes", "items", "results"]);
        if (!items.length) {
          wrap.innerHTML = emptyHtml("🔑", "No access codes yet.");
          return;
        }
        wrap.innerHTML = items.map(renderAccessCodeCard).join("");
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "access-code");
      });
  }

  document.addEventListener("click", function (e) {
    var joinCodeBtn = e.target.closest("[data-join-code]");
    if (joinCodeBtn) {
      var joinCode = (joinCodeBtn.dataset.joinCode || "").trim();
      if (!joinCode) return;
      joinCodeBtn.disabled = true;
      joinCodeBtn.textContent = "Joining…";
      stopLiveClassRing();
      api
        .api("/api/v1/live-classes/join-by-code", { method: "POST", body: { code: joinCode } })
        .then(function (res) {
          showLiveJoinResult(res || {});
        })
        .catch(function (err) {
          alert("Could not join with that code: " + errMsg(err));
        })
        .then(function () {
          joinCodeBtn.disabled = false;
          joinCodeBtn.textContent = "Join class";
        });
      return;
    }
    var copyBtn = e.target.closest("[data-copy-code]");
    if (copyBtn) {
      var code = copyBtn.dataset.copyCode;
      if (navigator.clipboard && code) {
        navigator.clipboard.writeText(code).then(function () {
          var prev = copyBtn.textContent;
          copyBtn.textContent = "Copied!";
          setTimeout(function () { copyBtn.textContent = prev; }, 1500);
        });
      }
      return;
    }
    var markBtn = e.target.closest("[data-mark-read]");
    if (markBtn) {
      var id = markBtn.dataset.markRead;
      api
        .api("/api/v1/live-classes/access-codes/mark-read", { method: "POST", body: { id: id, code_id: id } })
        .then(function () { loadAccessCodes(); })
        .catch(function () {});
    }
  });

  if ($("clearOldCodesBtn")) {
    $("clearOldCodesBtn").addEventListener("click", function () {
      if (!confirm("Clear old access codes?")) return;
      api
        .api("/api/v1/live-classes/access-codes/clear", { method: "POST", body: { mode: "old" } })
        .then(function () { loadAccessCodes(); })
        .catch(function (err) { alert(errMsg(err)); });
    });
  }
  if ($("clearAllCodesBtn")) {
    $("clearAllCodesBtn").addEventListener("click", function () {
      if (!confirm("Clear ALL access codes? This cannot be undone.")) return;
      api
        .api("/api/v1/live-classes/access-codes/clear", { method: "POST", body: { mode: "all" } })
        .then(function () { loadAccessCodes(); })
        .catch(function (err) { alert(errMsg(err)); });
    });
  }

  /* =====================================================================
     LIVE CLASS
     ===================================================================== */

  function renderLiveCard(c, isLive) {
    var title = c.title || c.topic || c.subject || "Live class";
    var teacher = c.teacher_name || c.host_name || c.teacher || "Scholaxia teacher";
    var subject = c.subject || c.topic || "";
    var time = c.starts_at || c.scheduled_at || c.start_time;
    var vis = (c.visibility || c.type || "").toLowerCase();
    var isFree =
      c.is_free === true ||
      c.requires_payment === false ||
      vis === "private" ||
      vis === "public" ||
      vis === "school_group";
    return (
      '<article class="live-card' + (isLive ? " is-live" : "") + '">' +
      '<div class="live-card-banner">' +
      '<span class="badge" style="background:rgba(255,255,255,.2);color:#fff">' +
      (isLive ? "● LIVE" : "UPCOMING") +
      "</span>" +
      (vis ? '<span style="opacity:.9;font-size:.75rem;font-weight:700">' + esc(vis) + (isFree ? " · Free" : "") + "</span>" : "") +
      "</div>" +
      '<div class="live-card-body">' +
      "<h4>" + esc(title) + "</h4>" +
      "<p>" + esc(teacher) + (subject ? " · " + esc(subject) : "") + "</p>" +
      (time ? '<div class="card-meta-row"><span>' + esc(fmtDate(time)) + "</span></div>" : "") +
      '<div class="card-foot">' +
      (isLive || isFree
        ? '<button type="button" class="btn btn-primary btn-mini" data-join-live="' + esc(c.id) + '">' +
          (isLive ? "Join now" : "Join free") +
          "</button>"
        : '<button type="button" class="btn btn-secondary btn-mini" data-goto="subscription">Get plan</button>') +
      "</div></div></article>"
    );
  }

  function loadLive() {
    loadAccessCodes();
    var liveWrap = $("liveNowGrid");
    var upWrap = $("liveUpcomingGrid");
    if (liveWrap) liveWrap.innerHTML = loadingHtml("Loading live classes…");
    if (upWrap) upWrap.innerHTML = loadingHtml("Loading upcoming classes…");

    api
      .api("/api/v1/live-classes/?status=live")
      .then(function (data) {
        var items = firstArray(data, ["classes", "items", "results", "live_classes"]);
        if (!liveWrap) return;
        liveWrap.innerHTML = items.length
          ? items.map(function (c) { return renderLiveCard(c, true); }).join("")
          : emptyHtml("📺", "No live classes right now. Your invite codes appear above when a teacher starts a class.");
      })
      .catch(function (err) {
        if (liveWrap) liveWrap.innerHTML = errorHtml(errMsg(err), "live");
      });

    api
      .api("/api/v1/live-classes/?status=upcoming")
      .then(function (data) {
        var items = firstArray(data, ["classes", "items", "results", "live_classes"]);
        if (!upWrap) return;
        upWrap.innerHTML = items.length
          ? items.map(function (c) { return renderLiveCard(c, false); }).join("")
          : emptyHtml("🗓", "No upcoming classes scheduled yet.");
      })
      .catch(function () {
        if (upWrap) upWrap.innerHTML = emptyHtml("🗓", "No upcoming classes scheduled yet.");
      });
  }

  document.addEventListener("click", function (e) {
    var joinBtn = e.target.closest("[data-join-live]");
    if (!joinBtn) return;
    var id = joinBtn.dataset.joinLive;
    joinBtn.disabled = true;
    joinBtn.textContent = "Joining…";
    api
      .api("/api/v1/live-classes/" + id + "/join", { method: "POST" })
      .then(function (res) {
        showLiveJoinResult(res || {});
      })
      .catch(function (err) {
        alert("Could not join: " + errMsg(err));
      })
      .then(function () {
        joinBtn.disabled = false;
        joinBtn.textContent = "Join";
      });
  });

  function enterLiveClassroom(res) {
    var classId = res.class_id || res.classId || res.id || "";
    var roomId = res.room_id || res.channel_id || "";
    var token = res.livekit_token || res.token || "";
    var url = res.livekit_url || "";
    function go(sessRes) {
      var r = sessRes || res || {};
      var rid = r.room_id || r.channel_id || roomId;
      var tok = r.livekit_token || r.token || token;
      var lurl = r.livekit_url || url;
      if (!rid || !tok) {
        alert("Joined, but classroom media was not ready. Ask the teacher to restart the class, then try again.");
        return;
      }
      var user = api.getUser();
      var sess = {
        class_id: classId || r.class_id || "",
        classId: classId || r.class_id || "",
        room_id: rid,
        channel_id: rid,
        livekit_token: tok,
        livekit_url: lurl,
        identity: r.identity || "",
        teacher_id: r.teacher_id || "",
        title: r.title || r.topic || r.subject || "Live Class",
        subject: r.subject || "",
        teacher_name: r.teacher_name || r.host_name || "",
        mic_allowed: r.mic_allowed !== false,
        camera_allowed: r.camera_allowed !== false,
        can_publish: r.can_publish !== false,
        role: "student",
        end_time: r.end_time || null,
      };
      writeLocalJson("live_session", sess);
      try {
        localStorage.setItem("sia_stop_live_ring", String(Date.now()));
      } catch (e) {}
      window.location.href = "classroom.html";
    }
    if (roomId && token && url) {
      go(res);
      return;
    }
    // Missing LiveKit URL/token — fetch a fresh one before opening the room.
    if (!classId) {
      go(res);
      return;
    }
    api
      .api("/api/v1/live-classes/" + encodeURIComponent(classId) + "/token")
      .then(function (tokRes) {
        go(Object.assign({}, res || {}, tokRes || {}));
      })
      .catch(function () {
        go(res);
      });
  }

  function showLiveJoinResult(res) {
    writeLocalJson("live_session", res);
    var panel = $("liveJoinResult");
    var title = res.title || res.topic || res.subject || "Live class";
    var code = res.code || res.access_code || "";
    if (panel) {
      panel.style.display = "block";
      panel.innerHTML =
        "<h3>✅ You're in: " +
        esc(title) +
        "</h3>" +
        '<div class="card-meta-row">' +
        (code ? "<span>Code: " + esc(code) + "</span>" : "") +
        (res.host_name || res.teacher_name
          ? "<span>Host: " + esc(res.host_name || res.teacher_name) + "</span>"
          : "") +
        "</div>" +
        '<div class="btn-row">' +
        '<button type="button" class="btn btn-primary" id="openClassroomBtn">Open classroom</button>' +
        '<button type="button" class="btn btn-secondary" id="saveLiveBtn">Save for later</button>' +
        "</div>";
      var openBtn = document.getElementById("openClassroomBtn");
      if (openBtn) {
        openBtn.addEventListener("click", function () {
          enterLiveClassroom(res || {});
        });
      }
      var saveBtn = document.getElementById("saveLiveBtn");
      if (saveBtn) {
        saveBtn.addEventListener("click", function () {
          var saved = readLocalJson("sia_saved_lives_web", []);
          if (!Array.isArray(saved)) saved = [];
          saved.unshift({
            id: res.id || res.class_id || res.session_id || Date.now(),
            title: title,
            savedAt: new Date().toISOString(),
          });
          writeLocalJson("sia_saved_lives_web", saved);
          saveBtn.textContent = "Saved ✓";
          saveBtn.disabled = true;
        });
      }
    }
    // Auto-enter the real LiveKit classroom (two-way A/V)
    enterLiveClassroom(res || {});
  }

  var joinCodeForm = $("joinCodeForm");
  if (joinCodeForm) {
    joinCodeForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var code = $("joinCodeInput").value.trim();
      if (!code) return;
      var btn = joinCodeForm.querySelector("button[type=submit]");
      btn.disabled = true;
      api
        .api("/api/v1/live-classes/join-by-code", { method: "POST", body: { code: code } })
        .then(function (res) {
          showLiveJoinResult(res || {});
          $("joinCodeInput").value = "";
        })
        .catch(function (err) {
          alert("Could not join with that code: " + errMsg(err));
        })
        .then(function () {
          btn.disabled = false;
        });
    });
  }

  var liveRequestForm = $("liveRequestForm");
  if (liveRequestForm) {
    liveRequestForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var subject = $("liveReqSubject").value.trim();
      var topic = $("liveReqTopic").value.trim();
      var description = $("liveReqDesc").value.trim();
      if (!subject || !topic) return;
      var btn = liveRequestForm.querySelector("button[type=submit]");
      btn.disabled = true;
      btn.textContent = "Sending…";
      api
        .api("/api/v1/live-classes/requests", {
          method: "POST",
          body: { subject: subject, topic: topic, description: description },
        })
        .then(function () {
          alert("Request sent! We'll notify you when a class is scheduled.");
          liveRequestForm.reset();
        })
        .catch(function (err) {
          alert("Could not send request: " + errMsg(err));
        })
        .then(function () {
          btn.disabled = false;
          btn.textContent = "Send request";
        });
    });
  }

  /* =====================================================================
     SUBSCRIPTION
     ===================================================================== */

  function planSessionsLabel(p) {
    var sessions = Number(p.sessions || 0);
    var billing = String(p.billing || "");
    var cat = String(p.category || "");
    var isWeekly =
      billing === "holiday" ||
      billing === "monthly" ||
      /holiday|nursery|primary|secondary|exam/i.test(cat);
    if (sessions === 1) return "1 session";
    if (isWeekly && sessions > 1) return sessions + " sessions weekly";
    return sessions + " sessions";
  }

  var PLAN_SUBJECTS_FALLBACK = {
    holiday_primary: ["Mathematics", "English Language", "Phonics", "Moral values"],
    holiday_jss: ["Mathematics", "English Language", "Phonics", "French", "Computer"],
    holiday_ss_science: ["Mathematics", "English", "Physics", "Chemistry", "Biology"],
    holiday_ss_art: ["Mathematics", "English", "Literature-in-English", "CRS/IRS", "Government"],
    holiday_ss_commercial: ["Mathematics", "English", "Financial Accounting", "Commerce", "Economics"],
  };

  function planSubjectsHtml(p) {
    var features = Array.isArray(p.features) ? p.features : [];
    var subjects = features.filter(function (f) {
      return f && !/session|tutor|notes|save|questions|and answers/i.test(String(f));
    });
    var planId = String(p.id || p.plan_id || "");
    if (!subjects.length && PLAN_SUBJECTS_FALLBACK[planId]) {
      subjects = PLAN_SUBJECTS_FALLBACK[planId].slice();
    }
    if (!subjects.length && p.max_subjects) {
      subjects = [
        p.max_subjects === "All core subjects" || p.max_subjects >= 99
          ? "All core subjects"
          : "Up to " + p.max_subjects + " subjects",
      ];
    }
    if (!subjects.length) return "";
    return (
      '<ul class="plan-subjects">' +
      subjects
        .map(function (s) {
          return "<li>" + esc(s) + "</li>";
        })
        .join("") +
      "</ul>"
    );
  }

  function loadSubscription() {
    var wrap = $("subscriptionPlans");
    var banner = $("activePlanBanner");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading plans…");
    api
      .api("/api/v1/payments/live-class/plans")
      .then(function (data) {
        data = data || {};
        var plans = firstArray(data, ["plans", "items", "results"]);
        var active = data.active_plan || data.current_plan || null;
        if (banner) {
          if (active) {
            banner.style.display = "flex";
            banner.innerHTML =
              "<div><strong>Active plan: " +
              esc(active.plan_name || active.name || active.title || "Plan") +
              "</strong><div style=\"opacity:.9;font-size:.86rem\">" +
              (active.sessions_left != null ? esc(active.sessions_left) + " sessions left · " : "") +
              (active.expires_at ? "Expires " + esc(fmtDate(active.expires_at)) : "Active subscription") +
              "</div></div>";
          } else {
            banner.style.display = "none";
          }
        }
        if (!plans.length) {
          wrap.innerHTML = emptyHtml("💳", "No subscription plans available right now.");
        } else {
          wrap.innerHTML = plans
            .map(function (p) {
              var id = p.id || p.plan_id;
              var isActive = active && (active.id === id || active.plan_id === id);
              var price = p.price != null ? Number(p.price) : null;
              var mins = p.session_minutes
                ? p.session_minutes >= 60
                  ? p.session_minutes / 60 + " hr each"
                  : p.session_minutes + " min each"
                : "";
              return (
                '<div class="card plan-card' +
                (isActive ? " is-active" : "") +
                '">' +
                '<span class="card-tag">' +
                esc(p.category || p.interval || p.billing || "Live plan") +
                "</span><h4>" +
                esc(p.name || p.title || "Plan") +
                "</h4>" +
                '<p class="plan-sessions"><strong>' +
                esc(planSessionsLabel(p)) +
                "</strong>" +
                (mins ? " · " + esc(mins) : "") +
                "</p>" +
                planSubjectsHtml(p) +
                '<div class="card-foot"><strong>' +
                (price != null ? "₦" + price.toLocaleString("en-NG") : "—") +
                "</strong>" +
                (isActive
                  ? '<span class="badge badge-green">Active</span>'
                  : '<button type="button" class="btn btn-primary btn-mini" data-pay-type="class_package" data-pay-id="' +
                    esc(id) +
                    '">Pay with Paystack</button>') +
                "</div></div>"
              );
            })
            .join("");
        }
        loadCbtPackages();
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "subscription");
        loadCbtPackages();
      });
  }

  function loadCbtPackages(opts) {
    opts = opts || {};
    var wrap = $(opts.gridId || "cbtPackagesGrid");
    var banner = $(opts.bannerId || "cbtAccessBanner");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading CBT packages…");
    Promise.all([
      api.api("/api/v1/payments/paystack/cbt-packages").catch(function () { return { packages: [] }; }),
      api.api("/api/v1/payments/paystack/cbt-access").catch(function () { return null; }),
    ]).then(function (pair) {
      var catalog = pair[0] || {};
      var access = pair[1];
      var packages = firstArray(catalog, ["packages", "items"]);
      if (banner) {
        if (access && access.has_access) {
          banner.style.display = "block";
          banner.textContent =
            "You have active CBT access" +
            (access.expires_at ? " until " + String(access.expires_at).slice(0, 10) : "") +
            ". You can download and start practice exams below.";
        } else {
          banner.style.display = "block";
          banner.className = "info-banner warn-banner";
          banner.textContent =
            "No active CBT package yet. Pick a plan below and pay with Paystack to unlock downloads.";
        }
      }
      if (!packages.length) {
        wrap.innerHTML = emptyHtml("📝", "No CBT packages listed yet.");
        return;
      }
      wrap.innerHTML = packages
        .map(function (p) {
          var id = p.id || p.package_id;
          var price = Number(p.price || p.amount || 0);
          var hasAccess = !!(access && access.has_access);
          return (
            '<div class="card plan-card' +
            (hasAccess ? " is-active" : "") +
            '">' +
            '<span class="card-tag">CBT Package</span><h4>' +
            esc(p.name || p.title || id) +
            "</h4><p>" +
            esc(p.description || "Annual CBT practice access + Tutor AI support") +
            '</p><div class="card-meta-row">' +
            (p.duration_days ? "<span>" + esc(p.duration_days) + " days</span>" : "<span>1 year</span>") +
            '</div><div class="card-foot"><strong>₦' +
            price.toLocaleString("en-NG") +
            "</strong>" +
            (hasAccess
              ? '<span class="badge badge-green">Unlocked</span>'
              : '<button type="button" class="btn btn-primary btn-mini" data-pay-type="cbt_package" data-pay-id="' +
                esc(id) +
                '">Pay with Paystack</button>') +
            "</div></div>"
          );
        })
        .join("");
    });
  }

  if ($("refreshCbtPackagesBtn")) {
    $("refreshCbtPackagesBtn").addEventListener("click", function () {
      loadCbtPackages({
        gridId: "cbtPagePackagesGrid",
        bannerId: "cbtPageAccessBanner",
      });
    });
  }

  async function handlePayClick(btn) {
    var type = btn.dataset.payType;
    var id = btn.dataset.payId;
    if (!type || !id) return;
    if (type === "skill_enrollment") {
      openSkillEnroll(id);
      return;
    }
    if (typeof window.paystackPurchase !== "function") {
      alert("Payment module not loaded. Refresh the page.");
      return;
    }
    var label = btn.textContent;
    btn.disabled = true;
    btn.textContent = "Opening Paystack…";
    try {
      var returnPage =
        type === "cbt_package"
          ? "cbt"
          : type === "class_package"
          ? "subscription"
          : type === "library_book"
          ? "library"
          : type === "marketplace_booking"
          ? "marketplace"
          : "subscription";
      // Redirects away — code after this usually won't run
      await window.paystackPurchase({
        productType: type,
        productId: id,
        returnPage: returnPage,
      });
    } catch (err) {
      alert(errMsg(err));
      btn.disabled = false;
      btn.textContent = label;
    }
  }

  document.addEventListener("click", function (e) {
    var payBtn = e.target.closest("[data-pay-type]");
    if (payBtn) handlePayClick(payBtn);
  });

  /* =====================================================================
     SKILLS
     ===================================================================== */

  var SKILLS_PROGRAMS = [
    { id: "web-design", title: "Web Design", fee: 400000, duration: "6 months", description: "HTML, CSS, JavaScript and modern responsive design fundamentals." },
    { id: "mobile-app", title: "Mobile App Development", fee: 300000, duration: "9 months", description: "Build Android & iOS apps with a beginner-friendly cross-platform stack." },
    { id: "graphics", title: "Graphics Design", fee: 70000, duration: "3 months", description: "Logo, flyer, and social media design using industry tools." },
    { id: "cyber-security", title: "Cyber Security", fee: 250000, duration: "6 months", description: "Security fundamentals, ethical hacking basics, and safe practices." },
    { id: "data-analysis", title: "Data Analysis", fee: 100000, duration: "6 months", description: "Excel, SQL, and visualisation for real-world decision making." },
    { id: "gsm-repairs", title: "Computer / GSM Repairs", fee: 150000, duration: "6 months", description: "Hands-on phone & computer hardware diagnosis and repair training." },
  ];

  function formatNaira(n) {
    return "₦" + Number(n || 0).toLocaleString("en-NG");
  }

  function loadSkills() {
    var wrap = $("skillsGrid");
    if (!wrap) return;
    var enrolledIds = [];
    wrap.innerHTML = SKILLS_PROGRAMS.map(function (p) { return renderSkillCard(p, false); }).join("");

    api
      .api("/api/v1/payments/flutterwave/skills/enrollments")
      .then(function (data) {
        var items = firstArray(data, ["enrollments", "items", "results"]);
        enrolledIds = items.map(function (it) { return it.program_id || it.skill_id || it.slug || it.id; });
        wrap.innerHTML = SKILLS_PROGRAMS
          .map(function (p) { return renderSkillCard(p, enrolledIds.indexOf(p.id) > -1); })
          .join("");
      })
      .catch(function () {
        // Enrollment endpoint optional — keep the static program cards as-is.
      });
  }

  function renderSkillCard(p, enrolled) {
    return (
      '<div class="card">' +
      '<span class="card-tag">' +
      (enrolled ? "✅ Enrolled" : "Skill Program") +
      "</span><h4>" +
      esc(p.title) +
      "</h4>" +
      "<p>" +
      esc(p.description) +
      "</p>" +
      '<div class="card-meta-row"><span>' +
      esc(p.duration) +
      "</span></div>" +
      '<div class="card-foot"><strong>' +
      esc(formatNaira(p.fee)) +
      "</strong>" +
      (enrolled
        ? '<span class="badge badge-green">Active</span>'
        : '<button type="button" class="btn btn-primary btn-mini" data-enroll-skill="' +
          esc(p.id) +
          '">Enroll</button>') +
      "</div></div>"
    );
  }

  function openSkillEnroll(skillId) {
    var skill = SKILLS_PROGRAMS.filter(function (s) { return s.id === skillId; })[0];
    if (!skill || !$("skillEnrollModal")) return;
    $("skillEnrollId").value = skill.id;
    $("skillEnrollTitle").textContent = "Enroll — " + skill.title;
    $("skillEnrollSub").textContent = "Fill your details, then continue to Paystack.";
    $("skillEnrollName").value = user.name || "";
    $("skillEnrollEmail").value = user.email || "";
    $("skillEnrollPhone").value = "";
    $("skillEnrollStart").value = "";
    $("skillEnrollNotes").value = "";
    if ($("skillPayMode")) $("skillPayMode").value = "half";
    updateSkillFeeCopy();
    setStatus($("skillEnrollStatus"), "", true);
    $("skillEnrollModal").classList.add("is-on");
  }

  function updateSkillFeeCopy() {
    var id = $("skillEnrollId") && $("skillEnrollId").value;
    var skill = SKILLS_PROGRAMS.filter(function (s) { return s.id === id; })[0];
    var feeEl = $("skillEnrollFee");
    if (!skill || !feeEl) return;
    var mode = ($("skillPayMode") && $("skillPayMode").value) || "half";
    var half = Math.round(skill.fee / 2);
    feeEl.textContent =
      mode === "once"
        ? "Paying once: " + formatNaira(skill.fee) + " — unlocks enrollment + live classes."
        : "Pay half now (" + formatNaira(half) + "), then balance (" + formatNaira(skill.fee - half) + ") later.";
  }

  document.addEventListener("click", function (e) {
    var enrollBtn = e.target.closest("[data-enroll-skill]");
    if (enrollBtn) openSkillEnroll(enrollBtn.dataset.enrollSkill);
    if (e.target.id === "skillEnrollClose" || e.target === $("skillEnrollModal")) {
      if ($("skillEnrollModal")) $("skillEnrollModal").classList.remove("is-on");
    }
  });
  if ($("skillPayMode")) $("skillPayMode").addEventListener("change", updateSkillFeeCopy);
  if ($("skillEnrollForm")) {
    $("skillEnrollForm").addEventListener("submit", function (e) {
      e.preventDefault();
      var statusEl = $("skillEnrollStatus");
      var btn = $("skillEnrollSubmit");
      var opts = {
        productType: "skill_enrollment",
        productId: $("skillEnrollId").value,
        full_name: $("skillEnrollName").value.trim(),
        phone: $("skillEnrollPhone").value.trim(),
        email: $("skillEnrollEmail").value.trim(),
        preferred_start: $("skillEnrollStart").value.trim(),
        notes: $("skillEnrollNotes").value.trim(),
        payment_mode: ($("skillPayMode") && $("skillPayMode").value) || "half",
        installment: 1,
        returnPage: "skills",
      };
      if (!opts.full_name || !opts.phone || !opts.email) {
        setStatus(statusEl, "Name, phone, and email are required.", false);
        return;
      }
      btn.disabled = true;
      btn.textContent = "Opening Paystack…";
      setStatus(statusEl, "Redirecting to Paystack…", true);
      window.paystackPurchase(opts).catch(function (err) {
        setStatus(statusEl, errMsg(err), false);
        btn.disabled = false;
        btn.textContent = "Continue to Paystack";
      });
    });
  }

  /* =====================================================================
     ASSIGNMENTS
     ===================================================================== */

  function loadAssignments() {
    var annWrap = $("announcementsList");
    var mineWrap = $("assignmentsMineList");
    var teacherSel = $("assignTeacherSelect");
    if (annWrap) annWrap.innerHTML = loadingHtml("Loading announcements…");
    if (mineWrap) mineWrap.innerHTML = loadingHtml("Loading your assignments…");

    api
      .api("/api/v1/community/announcements")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "announcements"]);
        if (!annWrap) return;
        annWrap.innerHTML = items.length
          ? items
              .map(function (a) {
                return (
                  '<div class="feed-post"><div class="feed-post-head"><div class="feed-avatar">📢</div><div><strong>' +
                  esc(a.title || "Announcement") +
                  "</strong><span> " +
                  esc(fmtDate(a.created_at)) +
                  "</span></div></div><div class=\"feed-post-body\">" +
                  esc(a.content || a.message || "") +
                  "</div></div>"
                );
              })
              .join("")
          : emptyHtml("📢", "No announcements yet.");
      })
      .catch(function (err) {
        if (annWrap) annWrap.innerHTML = errorHtml(errMsg(err), "assignments");
      });

    api
      .api("/api/v1/community/assignments/mine")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "assignments"]);
        if (!mineWrap) return;
        mineWrap.innerHTML = items.length
          ? items
              .map(function (a) {
                var status = a.status || (a.grade != null ? "graded" : "pending");
                return (
                  '<div class="card-list-row"><div><strong>' +
                  esc(a.caption || a.title || "Submission") +
                  "</strong><div class=\"card-meta-row\"><span>" +
                  esc(fmtDate(a.created_at)) +
                  "</span>" +
                  (a.grade != null ? "<span>Grade: " + esc(a.grade) + "</span>" : "") +
                  "</div></div><span class=\"badge " +
                  (status === "graded" ? "badge-green" : "badge-grey") +
                  "\">" +
                  esc(status) +
                  "</span></div>"
                );
              })
              .join("")
          : emptyHtml("📋", "You haven't submitted any assignments yet.");
      })
      .catch(function (err) {
        if (mineWrap) mineWrap.innerHTML = errorHtml(errMsg(err), "assignments");
      });

    api
      .api("/api/v1/profiles/teachers")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "teachers"]);
        if (!teacherSel) return;
        teacherSel.innerHTML =
          '<option value="">Select teacher</option>' +
          items
            .map(function (t) {
              return '<option value="' + esc(t.id) + '">' + esc(t.full_name || t.name || "Teacher") + "</option>";
            })
            .join("");
      })
      .catch(function () {});
  }

  var assignmentForm = $("assignmentForm");
  if (assignmentForm) {
    assignmentForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var statusEl = $("assignmentStatus");
      var teacherId = $("assignTeacherSelect").value;
      var file = $("assignFileInput").files[0];
      var caption = $("assignCaption").value.trim();
      if (!teacherId || !file) {
        setStatus(statusEl, "Please choose a teacher and a file.", false);
        return;
      }
      var fd = new FormData();
      fd.append("file", file);
      fd.append("tagged_teacher_id", teacherId);
      fd.append("caption", caption);
      var btn = assignmentForm.querySelector("button[type=submit]");
      btn.disabled = true;
      setStatus(statusEl, "Uploading…", true);
      api
        .apiUpload("/api/v1/community/assignments", fd)
        .then(function () {
          setStatus(statusEl, "Submitted!", true);
          assignmentForm.reset();
          loadedPages.assignments = false;
          loadAssignments();
        })
        .catch(function (err) {
          setStatus(statusEl, errMsg(err), false);
        })
        .then(function () {
          btn.disabled = false;
        });
    });
  }

  /* =====================================================================
     MARKETPLACE
     ===================================================================== */

  var marketplaceCache = [];
  var marketActiveCat = "all";

  function loadMarketplace() {
    var wrap = $("marketplaceGrid");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading products…");
    api
      .api("/api/v1/marketplace/products")
      .then(function (data) {
        marketplaceCache = firstArray(data, ["products", "items", "results"]);
        var cats = Array.from(
          new Set(marketplaceCache.map(function (p) { return p.category; }).filter(Boolean))
        );
        var tabsWrap = $("marketCategoryTabs");
        if (tabsWrap) {
          tabsWrap.innerHTML =
            '<button type="button" class="tab is-active" data-mcat="all">All</button>' +
            cats
              .map(function (c) { return '<button type="button" class="tab" data-mcat="' + esc(c) + '">' + esc(c) + "</button>"; })
              .join("");
        }
        renderMarketplace();
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "marketplace");
      });
  }

  function renderMarketplace() {
    var wrap = $("marketplaceGrid");
    if (!wrap) return;
    var items =
      marketActiveCat === "all"
        ? marketplaceCache
        : marketplaceCache.filter(function (p) { return p.category === marketActiveCat; });
    if (!items.length) {
      wrap.innerHTML = emptyHtml("🛍", "No products in this category yet.");
      return;
    }
    wrap.innerHTML = items
      .map(function (p) {
        var title = p.title || p.name || "Item";
        var price = p.price != null ? "₦" + p.price : "";
        return (
          '<div class="card">' +
          (p.image_url || p.secure_url
            ? '<img src="' + esc(p.image_url || p.secure_url) + '" alt="" />'
            : '<div class="card-media-fallback">🛍</div>') +
          '<span class="card-tag">' +
          esc(p.category || "Marketplace") +
          "</span><h4>" +
          esc(title) +
          "</h4>" +
          (p.description ? "<p>" + esc(String(p.description).slice(0, 110)) + (String(p.description).length > 110 ? "…" : "") + "</p>" : "") +
          '<div class="card-foot"><strong>' +
          esc(price) +
          '</strong><button type="button" class="btn btn-primary btn-mini" data-book-product="' +
          esc(p.id) +
          '" data-product-title="' +
          esc(title) +
          '">Book now</button></div></div>'
        );
      })
      .join("");
  }

  var marketTabsWrap = $("marketCategoryTabs");
  if (marketTabsWrap) {
    marketTabsWrap.addEventListener("click", function (e) {
      var btn = e.target.closest(".tab");
      if (!btn) return;
      marketTabsWrap.querySelectorAll(".tab").forEach(function (t) { t.classList.toggle("is-active", t === btn); });
      marketActiveCat = btn.dataset.mcat;
      renderMarketplace();
    });
  }

  var bookingModal = $("bookingModal");
  document.addEventListener("click", function (e) {
    var bookBtn = e.target.closest("[data-book-product]");
    if (bookBtn) {
      $("bookingProductId").value = bookBtn.dataset.bookProduct;
      $("bookingProductName").textContent = bookBtn.dataset.productTitle || "Product";
      $("bookingFullName").value = user.name || "";
      $("bookingEmail").value = user.email || "";
      setStatus($("bookingStatus"), "", false);
      bookingModal.classList.add("is-on");
      return;
    }
    if (e.target === bookingModal || e.target.closest("#bookingModalClose")) {
      bookingModal.classList.remove("is-on");
    }
  });

  var bookingForm = $("bookingForm");
  if (bookingForm) {
    bookingForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var productId = $("bookingProductId").value;
      var statusEl = $("bookingStatus");
      var body = {
        full_name: $("bookingFullName").value.trim(),
        email: $("bookingEmail").value.trim(),
        phone: $("bookingPhone").value.trim(),
        whatsapp: $("bookingWhatsapp").value.trim(),
        note: $("bookingNote").value.trim(),
      };
      var btn = bookingForm.querySelector("button[type=submit]");
      btn.disabled = true;
      setStatus(statusEl, "Booking…", true);
      api
        .api("/api/v1/marketplace/products/" + productId + "/book", { method: "POST", body: body })
        .then(async function (res) {
          var bookingId = res && (res.booking_id || res.id || (res.booking && res.booking.id));
          var product = marketplaceCache.filter(function (p) { return String(p.id) === String(productId); })[0];
          var price = product ? Number(product.price || 0) : 0;
          if (price > 0 && bookingId && typeof window.paystackPurchase === "function") {
            setStatus(statusEl, "Booking created — opening Paystack…", true);
            try {
              var ok = await window.paystackPurchase({
                productType: "marketplace_booking",
                productId: String(bookingId),
              });
              setStatus(statusEl, ok ? "Paid successfully!" : "Booked. Complete payment later if needed.", ok);
            } catch (err) {
              setStatus(statusEl, "Booked, but payment failed: " + errMsg(err), false);
            }
          } else {
            setStatus(statusEl, "Booked! We'll reach out shortly.", true);
          }
          setTimeout(function () {
            bookingModal.classList.remove("is-on");
            bookingForm.reset();
          }, 1400);
        })
        .catch(function (err) {
          setStatus(statusEl, errMsg(err), false);
        })
        .then(function () {
          btn.disabled = false;
        });
    });
  }

  /* =====================================================================
     TUTOR AI — SIA
     ===================================================================== */

  var siaHistory = [];
  var siaLevelSelect = $("siaLevelSelect");
  if (siaLevelSelect) {
    var savedLevel = localStorage.getItem("sia_education_level");
    if (savedLevel) {
      var optMatch = Array.prototype.some.call(siaLevelSelect.options, function (o) {
        return o.value.toUpperCase() === String(savedLevel).toUpperCase();
      });
      if (optMatch) siaLevelSelect.value = String(savedLevel).toUpperCase();
    }
    siaLevelSelect.addEventListener("change", function () {
      localStorage.setItem("sia_education_level", siaLevelSelect.value);
    });
    if (!localStorage.getItem("sia_education_level")) {
      localStorage.setItem("sia_education_level", siaLevelSelect.value);
    }
  }

  if ($("communityAv")) {
    $("communityAv").textContent = (user.name || "S").charAt(0).toUpperCase();
  }

  function addBubble(text, isMe) {
    var box = $("siaChat");
    if (!box) return;
    var welcome = box.querySelector(".sia-welcome");
    if (welcome) welcome.remove();
    var el = document.createElement("div");
    el.className = "bubble " + (isMe ? "me" : "bot");
    el.textContent = text;
    box.appendChild(el);
    box.scrollTop = box.scrollHeight;
  }

  function askSia(text) {
    if (!text) return;
    var input = $("siaInput");
    if (input) input.value = "";
    addBubble(text, true);
    siaHistory.push({ role: "user", content: text });
    if (siaHistory.length > 12) siaHistory = siaHistory.slice(-12);

    var thinking = document.createElement("div");
    thinking.className = "bubble bot";
    thinking.textContent = "Sia is thinking…";
    $("siaChat").appendChild(thinking);
    $("siaChat").scrollTop = $("siaChat").scrollHeight;

    api
      .api("/api/v1/sia/ask", {
        method: "POST",
        body: {
          question: text,
          language: "english",
          education_level: (siaLevelSelect && siaLevelSelect.value) || "SS3",
          conversation_history: siaHistory,
          tutor_mode: "smart",
        },
      })
      .then(function (res) {
        var answer =
          (res && (res.sia || res.answer || res.response || res.reply || res.message || res.result)) ||
          "I couldn't find an answer for that just now.";
        thinking.remove();
        addBubble(answer, false);
        siaHistory.push({ role: "assistant", content: answer });
      })
      .catch(function (err) {
        thinking.remove();
        addBubble("Sorry, I ran into a problem: " + errMsg(err), false);
      });
  }

  var siaForm = $("siaForm");
  if (siaForm) {
    siaForm.addEventListener("submit", function (e) {
      e.preventDefault();
      askSia(($("siaInput") && $("siaInput").value.trim()) || "");
    });
  }

  document.addEventListener("click", function (e) {
    var chip = e.target.closest("[data-sia-q]");
    if (chip) askSia(chip.dataset.siaQ);
  });

  if ($("siaClearChat")) {
    $("siaClearChat").addEventListener("click", function () {
      siaHistory = [];
      var box = $("siaChat");
      if (!box) return;
      box.innerHTML =
        '<div class="sia-welcome"><div class="sia-orb sm">S</div><div><strong>Hi, I’m Sia</strong><p>Ask me anything about your subjects. I’ll explain at your level with clear steps.</p></div></div>';
    });
  }

  /* =====================================================================
     COMMUNITY — General / Groups / Announcements
     ===================================================================== */

  var communityTab = "general";
  var communityGeneralChannelId = null;

  function setCommunityTab(tab) {
    communityTab = tab || "general";
    document.querySelectorAll(".comm-tab").forEach(function (b) {
      var on = b.getAttribute("data-comm-tab") === communityTab;
      b.classList.toggle("is-active", on);
      b.setAttribute("aria-selected", on ? "true" : "false");
    });
    var g = $("commPanelGeneral");
    var gr = $("commPanelGroups");
    var a = $("commPanelAnnouncements");
    if (g) {
      g.hidden = communityTab !== "general";
      g.classList.toggle("is-on", communityTab === "general");
    }
    if (gr) {
      gr.hidden = communityTab !== "groups";
      gr.classList.toggle("is-on", communityTab === "groups");
    }
    if (a) {
      a.hidden = communityTab !== "announcements";
      a.classList.toggle("is-on", communityTab === "announcements");
    }
    if (communityTab === "general") loadCommunityGeneral();
    else if (communityTab === "groups") loadCommunityGroupsTab();
    else if (communityTab === "announcements") loadCommunityAnnouncementsTab();
  }

  function loadCommunity() {
    setCommunityTab(communityTab || "general");
  }

  function loadCommunityGeneral() {
    var wrap = $("communityFeed");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading #general…");
    Promise.all([
      api.api("/api/v1/community/channels").catch(function () { return []; }),
      api.api("/api/v1/community/feed?limit=50").catch(function (err) { throw err; }),
    ])
      .then(function (pair) {
        var channels = Array.isArray(pair[0]) ? pair[0] : [];
        var general = channels.find(function (c) {
          return c.type === "general";
        });
        if (general) communityGeneralChannelId = general.id;
        var data = pair[1];
        var items = Array.isArray(data) ? data : firstArray(data, ["items", "results", "posts", "feed"]);
        if (!items.length) {
          wrap.innerHTML = emptyHtml("💬", "No posts in #general yet. Be the first to share something!");
          return;
        }
        wrap.innerHTML = items.map(renderCommunityPost).join("");
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "community");
      });
  }

  function loadCommunityAnnouncementsTab() {
    var wrap = $("communityAnnouncements");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading announcements…");
    api
      .api("/api/v1/community/announcements?limit=40")
      .then(function (data) {
        var items = Array.isArray(data) ? data : firstArray(data, ["items", "results", "posts", "announcements"]);
        if (!items.length) {
          wrap.innerHTML = emptyHtml("📢", "No announcements yet. Teachers post updates here.");
          return;
        }
        wrap.innerHTML = items.map(renderCommunityPost).join("");
      })
      .catch(function (err) {
        wrap.innerHTML = errorHtml(errMsg(err), "community");
      });
  }

  function loadCommunityGroupsTab() {
    var wrap = $("communityTabGroups");
    if (!wrap) return;
    wrap.innerHTML = loadingHtml("Loading groups…");
    Promise.all([
      api.api("/api/v1/student-groups/mine").catch(function () { return []; }),
      api.api("/api/v1/student-groups/?is_community_listed=true").catch(function () { return []; }),
    ]).then(function (pair) {
      var mine = firstArray(pair[0], ["items", "groups", "results"]);
      if (Array.isArray(pair[0])) mine = pair[0];
      var discover = firstArray(pair[1], ["items", "groups", "results"]);
      if (Array.isArray(pair[1])) discover = pair[1];
      var cards = []
        .concat(
          mine.map(function (g) {
            return renderGroupCard(g, true);
          })
        )
        .concat(
          discover.map(function (g) {
            return renderGroupCard(g, false);
          })
        );
      wrap.innerHTML = cards.length
        ? cards.join("")
        : emptyHtml("👥", "No groups yet. Open Groups to create or join one.");
    }).catch(function (err) {
      wrap.innerHTML = errorHtml(errMsg(err), "community");
    });
  }

  function renderCommunityPost(p) {
    var name = p.author_name || p.full_name || (p.author && p.author.full_name) || "Student";
    var media = "";
    if (p.media_url && p.media_type === "audio") {
      media = '<audio controls src="' + esc(p.media_url) + '" style="width:100%;margin-top:0.5rem"></audio>';
    } else if (p.media_url && /image/i.test(String(p.media_type || ""))) {
      media = '<img src="' + esc(p.media_url) + '" alt="" style="max-width:100%;border-radius:12px;margin-top:0.5rem" />';
    }
    return (
      '<div class="feed-post"><div class="feed-post-head"><div class="feed-avatar">' +
      esc(name.charAt(0).toUpperCase()) +
      "</div><div><strong>" +
      esc(name) +
      "</strong><span> " +
      esc(fmtDate(p.created_at)) +
      "</span></div></div><div class=\"feed-post-body\">" +
      esc(p.content || p.text || "") +
      media +
      "</div></div>"
    );
  }

  var communityTabs = $("communityTabs");
  if (communityTabs) {
    communityTabs.addEventListener("click", function (e) {
      var btn = e.target.closest("[data-comm-tab]");
      if (!btn) return;
      setCommunityTab(btn.getAttribute("data-comm-tab"));
    });
  }

  var communityPostForm = $("communityPostForm");
  if (communityPostForm) {
    communityPostForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var input = $("communityPostInput");
      var content = input.value.trim();
      if (!content) return;
      var btn = communityPostForm.querySelector("button[type=submit]");
      btn.disabled = true;

      function doPost(channelId) {
        var body = { content: content, visibility: "everyone" };
        if (channelId) body.channel_id = channelId;
        return api.api("/api/v1/community/posts", { method: "POST", body: body });
      }

      var ready = communityGeneralChannelId
        ? Promise.resolve(communityGeneralChannelId)
        : api.api("/api/v1/community/channels").then(function (channels) {
            var general = (channels || []).find(function (c) {
              return c.type === "general";
            });
            if (general) communityGeneralChannelId = general.id;
            return communityGeneralChannelId;
          });

      ready
        .then(function (channelId) {
          return doPost(channelId);
        })
        .then(function () {
          input.value = "";
          loadCommunityGeneral();
        })
        .catch(function (err) {
          alert("Could not post: " + errMsg(err));
        })
        .then(function () {
          btn.disabled = false;
        });
    });
  }

  /* =====================================================================
     GROUPS
     ===================================================================== */

  function renderGroupCard(g, mine) {
    var name = g.name || g.title || "Study group";
    var initial = name.charAt(0).toUpperCase();
    return (
      '<article class="group-card">' +
      '<div class="group-avatar">' + esc(initial) + "</div>" +
      "<h4>" + esc(name) + "</h4>" +
      (g.description ? "<p>" + esc(g.description) + "</p>" : "<p>Study group</p>") +
      '<div class="card-meta-row"><span>' +
      esc(g.member_count || (g.members && g.members.length) || 0) +
      " members</span>" +
      (mine ? '<span class="badge badge-purple">Yours</span>' : "") +
      "</div>" +
      '<div class="card-foot">' +
      (mine
        ? '<span class="badge badge-green">Joined</span>'
        : '<button type="button" class="btn btn-primary btn-mini" data-join-group="' + esc(g.id) + '">Request to join</button>') +
      "</div></article>"
    );
  }

  function loadGroups() {
    var mineWrap = $("myGroupsList");
    var commWrap = $("communityGroupsList");
    if (mineWrap) mineWrap.innerHTML = loadingHtml("Loading your groups…");
    if (commWrap) commWrap.innerHTML = loadingHtml("Loading community groups…");

    api
      .api("/api/v1/student-groups/mine")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "groups"]);
        if (!mineWrap) return;
        mineWrap.innerHTML = items.length
          ? items.map(function (g) { return renderGroupCard(g, true); }).join("")
          : emptyHtml("👥", "No groups yet. Create one to start studying together.");
      })
      .catch(function (err) {
        if (mineWrap) mineWrap.innerHTML = errorHtml(errMsg(err), "groups");
      });

    api
      .api("/api/v1/student-groups/?is_community_listed=true")
      .then(function (data) {
        var items = firstArray(data, ["items", "results", "groups"]);
        if (!commWrap) return;
        commWrap.innerHTML = items.length
          ? items.map(function (g) { return renderGroupCard(g, false); }).join("")
          : emptyHtml("🌐", "No community groups listed yet.");
      })
      .catch(function (err) {
        if (commWrap) commWrap.innerHTML = errorHtml(errMsg(err), "groups");
      });
  }

  document.addEventListener("click", function (e) {
    var joinBtn = e.target.closest("[data-join-group]");
    if (!joinBtn) return;
    var id = joinBtn.dataset.joinGroup;
    joinBtn.disabled = true;
    joinBtn.textContent = "Joining…";
    api
      .api("/api/v1/student-groups/" + id + "/join-request", { method: "POST" })
      .catch(function () {
        return api.api("/api/v1/student-groups/" + id + "/join", { method: "POST" });
      })
      .then(function () {
        joinBtn.textContent = "Requested ✓";
      })
      .catch(function (err) {
        joinBtn.disabled = false;
        joinBtn.textContent = "Join";
        alert("Could not join group: " + errMsg(err));
      });
  });

  if ($("showCreateGroupBtn")) {
    $("showCreateGroupBtn").addEventListener("click", function () {
      var form = $("createGroupForm");
      form.style.display = form.style.display === "none" ? "grid" : "none";
    });
  }
  if ($("cancelCreateGroupBtn")) {
    $("cancelCreateGroupBtn").addEventListener("click", function () {
      $("createGroupForm").style.display = "none";
    });
  }

  var createGroupForm = $("createGroupForm");
  if (createGroupForm) {
    createGroupForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var name = $("groupNameInput").value.trim();
      var description = $("groupDescInput").value.trim();
      if (!name) return;
      var statusEl = $("groupCreateStatus");
      var btn = createGroupForm.querySelector("button[type=submit]");
      btn.disabled = true;
      setStatus(statusEl, "Creating…", true);
      api
        .api("/api/v1/student-groups/", {
          method: "POST",
          body: { name: name, description: description, is_public: true, is_community_listed: true },
        })
        .then(function () {
          setStatus(statusEl, "Group created!", true);
          createGroupForm.reset();
          loadedPages.groups = false;
          loadGroups();
        })
        .catch(function (err) {
          setStatus(statusEl, errMsg(err), false);
        })
        .then(function () {
          btn.disabled = false;
        });
    });
  }

  /* =====================================================================
     SAVED
     ===================================================================== */

  function loadSaved() {
    renderSaved();
  }

  function renderSaved() {
    var wrap = $("savedList");
    if (!wrap) return;
    var items = readLocalJson("sia_saved_lives_web", []);
    if (!Array.isArray(items) || !items.length) {
      wrap.innerHTML = emptyHtml("▶", "No saved items yet. Save a live class from the Live Class page.");
      return;
    }
    wrap.innerHTML = items
      .map(function (it, i) {
        return (
          '<div class="card-list-row"><div><strong>' +
          esc(it.title || "Saved item") +
          "</strong><div class=\"card-meta-row\"><span>" +
          esc(fmtDate(it.savedAt)) +
          "</span></div></div><div class=\"btn-row\">" +
          (it.url
            ? '<button type="button" class="btn btn-primary btn-mini" data-play-saved="' + i + '">Play</button>'
            : '<span class="muted">No recording link</span>') +
          '<button type="button" class="btn btn-danger btn-mini" data-delete-saved="' +
          i +
          '">Delete</button></div></div>'
        );
      })
      .join("");
  }

  document.addEventListener("click", function (e) {
    var playBtn = e.target.closest("[data-play-saved]");
    if (playBtn) {
      var items = readLocalJson("sia_saved_lives_web", []);
      var it = items[parseInt(playBtn.dataset.playSaved, 10)];
      if (it && it.url) window.open(it.url, "_blank");
      return;
    }
    var delBtn = e.target.closest("[data-delete-saved]");
    if (delBtn) {
      var idx = parseInt(delBtn.dataset.deleteSaved, 10);
      var arr = readLocalJson("sia_saved_lives_web", []);
      arr.splice(idx, 1);
      writeLocalJson("sia_saved_lives_web", arr);
      renderSaved();
    }
  });

  /* =====================================================================
     CONTACT (static + client-side success)
     ===================================================================== */

  var contactForm = $("contactForm");
  if (contactForm) {
    contactForm.addEventListener("submit", function (e) {
      e.preventDefault();
      setStatus($("contactStatus"), "Message sent! We'll get back to you shortly.", true);
      contactForm.reset();
    });
  }

  /* =====================================================================
     PROFILE
     ===================================================================== */

  var subjectsCatalog = [];
  var selectedSubjects = [];

  function loadProfile() {
    api
      .api("/api/v1/students/me")
      .then(function (me) {
        if (!me) return;
        var name = me.full_name || me.name || user.name;
        $("profileText").textContent = name + " · " + (me.email || user.email) + " · Student";
        if (me.exam_type) {
          localStorage.setItem("sia_exam_type", me.exam_type);
          if ($("examTypeSelect")) $("examTypeSelect").value = me.exam_type;
        }
        if (me.education_level && $("eduLevelSelect")) $("eduLevelSelect").value = me.education_level;
        if (Array.isArray(me.subjects)) {
          selectedSubjects = me.subjects.slice();
          writeLocalJson("sia_subjects", selectedSubjects);
        }
        refreshLocalExamBadges();
        renderSubjectChips();
      })
      .catch(function () {
        refreshLocalExamBadges();
      });

    var examType = localStorage.getItem("sia_exam_type");
    if (examType && $("examTypeSelect")) $("examTypeSelect").value = examType;
    selectedSubjects = readLocalJson("sia_subjects", []);
    if (!Array.isArray(selectedSubjects)) selectedSubjects = [];

    api
      .api("/api/v1/students/subjects")
      .then(function (data) {
        subjectsCatalog = firstArray(data, ["subjects", "items", "results"]);
        if (!subjectsCatalog.length && data && typeof data === "object") {
          // Flatten grouped shapes e.g. { jamb: [...], waec: [...] }
          Object.keys(data).forEach(function (k) {
            if (Array.isArray(data[k])) subjectsCatalog = subjectsCatalog.concat(data[k]);
          });
        }
        renderSubjectChips();
      })
      .catch(function (err) {
        var wrap = $("profileSubjectChips");
        if (wrap) wrap.innerHTML = errorHtml(errMsg(err), "profile");
      });
  }

  function renderSubjectChips() {
    var wrap = $("profileSubjectChips");
    if (!wrap) return;
    if (!subjectsCatalog.length) {
      wrap.innerHTML = emptyHtml("📚", "Subject list unavailable right now.");
      return;
    }
    wrap.innerHTML = subjectsCatalog
      .map(function (s) {
        var name = typeof s === "string" ? s : s.name || s.title || s.subject || "";
        var isSel = selectedSubjects.indexOf(name) > -1;
        return (
          '<button type="button" class="chip' +
          (isSel ? " is-selected" : "") +
          '" data-subject-chip="' +
          esc(name) +
          '">' +
          esc(name) +
          "</button>"
        );
      })
      .join("");
  }

  var subjectChipsWrap = $("profileSubjectChips");
  if (subjectChipsWrap) {
    subjectChipsWrap.addEventListener("click", function (e) {
      var chip = e.target.closest("[data-subject-chip]");
      if (!chip) return;
      var name = chip.dataset.subjectChip;
      var idx = selectedSubjects.indexOf(name);
      if (idx > -1) selectedSubjects.splice(idx, 1);
      else selectedSubjects.push(name);
      renderSubjectChips();
    });
  }

  if ($("profileSaveBtn")) {
    $("profileSaveBtn").addEventListener("click", function () {
      var statusEl = $("profileSaveStatus");
      var examType = (($("examTypeSelect") && $("examTypeSelect").value) || "").toUpperCase().replace(/-/g, "_");
      var eduLevel = (($("eduLevelSelect") && $("eduLevelSelect").value) || "").toUpperCase();
      if (!selectedSubjects.length) {
        setStatus(statusEl, "Select at least one subject.", false);
        return;
      }
      var btn = $("profileSaveBtn");
      btn.disabled = true;
      setStatus(statusEl, "Saving…", true);
      api
        .api("/api/v1/students/setup-exam", {
          method: "POST",
          body: { exam_type: examType, subjects: selectedSubjects, education_level: eduLevel },
        })
        .then(function () {
          localStorage.setItem("sia_exam_type", examType);
          writeLocalJson("sia_subjects", selectedSubjects);
          refreshLocalExamBadges();
          setStatus(statusEl, "Saved!", true);
        })
        .catch(function (err) {
          setStatus(statusEl, errMsg(err), false);
        })
        .then(function () {
          btn.disabled = false;
        });
    });
  }

  /* =====================================================================
     Init
     ===================================================================== */

  if (typeof window.resumePendingPaystack === "function") {
    window.resumePendingPaystack().then(function (res) {
      if (!res) return;
      if (res.paid) {
        alert("Payment confirmed. Your access is updated.");
        var page = (res.pending && res.pending.returnPage) || "subscription";
        loadedPages[page] = false;
        showPage(page);
      }
    });
  }

  // Sidebar collapse (desktop) + mobile drawer
  function setSidebarCollapsed(collapsed) {
    var shell = $("appShell");
    var btn = $("sidebarToggle");
    if (!shell) return;
    shell.classList.toggle("sidebar-collapsed", !!collapsed);
    localStorage.setItem("sia_sidebar_collapsed", collapsed ? "1" : "0");
    if (btn) {
      btn.textContent = collapsed ? "›" : "‹";
      btn.setAttribute("aria-label", collapsed ? "Show menu" : "Hide menu");
      btn.title = collapsed ? "Show menu" : "Hide menu";
    }
  }

  function closeMobileNav() {
    document.body.classList.remove("nav-open");
    var bd = $("sidebarBackdrop");
    if (bd) bd.hidden = true;
  }
  function openMobileNav() {
    document.body.classList.add("nav-open");
    // On mobile, opening menu should not stay in collapsed desktop mode
    setSidebarCollapsed(false);
    var bd = $("sidebarBackdrop");
    if (bd) bd.hidden = false;
  }

  if (localStorage.getItem("sia_sidebar_collapsed") === "1") {
    setSidebarCollapsed(true);
  }

  if ($("sidebarToggle")) {
    $("sidebarToggle").addEventListener("click", function () {
      var shell = $("appShell");
      var collapsed = !(shell && shell.classList.contains("sidebar-collapsed"));
      setSidebarCollapsed(collapsed);
      if (!collapsed && window.matchMedia("(max-width: 900px)").matches) openMobileNav();
      if (collapsed) closeMobileNav();
    });
  }
  if ($("sidebarCloseBtn")) {
    $("sidebarCloseBtn").addEventListener("click", function () {
      if (window.matchMedia("(max-width: 900px)").matches) closeMobileNav();
      else setSidebarCollapsed(true);
    });
  }
  if ($("mobileMenuBtn")) {
    $("mobileMenuBtn").addEventListener("click", function () {
      if (document.body.classList.contains("nav-open")) closeMobileNav();
      else openMobileNav();
    });
  }
  if ($("backBtn")) {
    $("backBtn").addEventListener("click", function () {
      goBack();
    });
  }
  if ($("sidebarBackdrop")) {
    $("sidebarBackdrop").addEventListener("click", closeMobileNav);
  }
  // close handler already on side-link above

  if ($("stopLiveRingBtn")) {
    $("stopLiveRingBtn").addEventListener("click", function () {
      localStorage.setItem("sia_stop_live_ring", String(Date.now()));
      stopLiveClassRing();
    });
  }
  pollLiveInvitesForRing();
  setInterval(pollLiveInvitesForRing, 12000);

  loadHome();
})();
