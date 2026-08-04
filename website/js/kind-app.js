/* Scholaxia Kids website — Home, Sia, Live, Saved, CBT, Profile (no games, no search) */
(function () {
  var api = window.ScholaxiaAPI;
  if (!api || typeof api.requireAuth !== "function") {
    console.error("ScholaxiaAPI failed to load");
    return;
  }
  if (!api.requireAuth(["kind"])) return;

  var TITLES = {
    home: "Home",
    sia: "Sia AI",
    live: "Live Class",
    saved: "Saved",
    cbt: "CBT",
    profile: "Profile",
  };

  var pageHistory = ["home"];
  var currentPage = "home";
  var siaHistory = [];
  var cbtState = { exam: null, session: null, answers: {}, index: 0 };
  var shell = document.getElementById("kindShell");

  function $(id) {
    return document.getElementById(id);
  }

  function esc(s) {
    return String(s == null ? "" : s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function setUserChip(name, ageGroup) {
    var first = (name || "Friend").split(" ")[0];
    var letter = first.charAt(0).toUpperCase() || "K";
    if ($("userName")) $("userName").textContent = first;
    if ($("userAv")) $("userAv").textContent = letter;
    if ($("hello")) $("hello").textContent = "Hi, " + first + "!";
    if ($("profileName")) $("profileName").textContent = name || first;
    if ($("profileAv")) $("profileAv").textContent = letter;
    if (ageGroup) {
      var label = "Ages " + ageGroup;
      if ($("userAge")) $("userAge").textContent = label;
      localStorage.setItem("sia_age_group", ageGroup);
    }
  }

  function closeMobileNav() {
    document.body.classList.remove("nav-open");
    var bd = $("sidebarBackdrop");
    if (bd) bd.hidden = true;
  }

  function openMobileNav() {
    document.body.classList.add("nav-open");
    var bd = $("sidebarBackdrop");
    if (bd) bd.hidden = false;
  }

  function updateBackBtn() {
    var btn = $("backBtn");
    if (!btn) return;
    var show = pageHistory.length > 1 || currentPage !== "home";
    btn.hidden = !show;
  }

  function showPage(id, opts) {
    id = String(id || "").trim();
    if (!TITLES[id]) return;
    opts = opts || {};
    if (!opts.replace && currentPage !== id) {
      pageHistory.push(id);
      if (pageHistory.length > 20) pageHistory.shift();
    }
    currentPage = id;

    document.querySelectorAll(".page").forEach(function (p) {
      var on = p.id === "page-" + id;
      p.classList.toggle("is-on", on);
    });
    document.querySelectorAll(".kind-nav-btn").forEach(function (b) {
      var page = b.getAttribute("data-page");
      b.classList.toggle("is-active", page === id);
    });
    if ($("pageTitle")) $("pageTitle").textContent = TITLES[id];
    updateBackBtn();
    closeMobileNav();

    // Keep sidebar usable after navigation
    if (shell) {
      shell.classList.remove("sidebar-collapsed");
      if ($("sidebarToggle")) {
        $("sidebarToggle").textContent = "‹";
        $("sidebarToggle").setAttribute("aria-label", "Hide menu");
      }
    }

    try {
      if (id === "home") loadHome();
      else if (id === "live") loadLive();
      else if (id === "saved") loadSaved();
      else if (id === "cbt") loadCbt();
      else if (id === "profile") loadProfile();
      else if (id === "sia") renderSia();
    } catch (err) {
      console.error("Kids page load failed:", err);
    }
  }

  // Expose for debugging / inline handlers
  window.kindShowPage = showPage;

  function goBack() {
    if (currentPage === "cbt" && $("cbtPlay") && !$("cbtPlay").hidden) {
      exitCbtPlayer();
      return;
    }
    if (pageHistory.length > 1) {
      pageHistory.pop();
      var prev = pageHistory[pageHistory.length - 1] || "home";
      showPage(prev, { replace: true });
      return;
    }
    if (currentPage !== "home") showPage("home", { replace: true });
  }

  /* —— Home —— */
  async function loadHome() {
    try {
      var me = await api.api("/api/v1/kind/me");
      if (me && me.full_name) {
        setUserChip(me.full_name, me.age_group);
        localStorage.setItem("sia_name", me.full_name);
      }
      var live = await api.api("/api/v1/live-classes?status=live").catch(function () {
        return [];
      });
      if (!Array.isArray(live)) live = live.classes || live.items || [];
      var count = live.filter(function (c) {
        return c.is_live;
      }).length;
      if ($("statLive")) $("statLive").textContent = String(count);
      var banner = $("homeBanner");
      if (banner) {
        banner.innerHTML = count
          ? '<div class="banner-card"><div><strong>' +
            count +
            " live class" +
            (count === 1 ? "" : "es") +
            "</strong> ready — join a lesson now!</div>" +
            '<button type="button" class="btn btn-primary" data-goto="live">View classes</button></div>'
          : '<div class="banner-card"><div>No live class right now. Talk to Sia or practise CBT while you wait.</div>' +
            '<button type="button" class="btn btn-primary" data-goto="sia">Talk to Sia</button></div>';
      }
    } catch (e) {
      /* keep chip from session */
    }
  }

  /* —— Sia —— */
  function renderSia() {
    var box = $("siaChat");
    if (!box) return;
    if (!siaHistory.length) {
      box.innerHTML =
        '<div class="sia-welcome"><div class="sia-orb sm">S</div><div><strong>Hi friend!</strong><p>What do you want to learn today?</p></div></div>';
      return;
    }
    box.innerHTML = siaHistory
      .map(function (m) {
        return '<div class="bubble ' + (m.isAi ? "bot" : "me") + '">' + esc(m.text) + "</div>";
      })
      .join("");
    box.scrollTop = box.scrollHeight;
  }

  async function sendSia(question) {
    var q = String(question || "").trim();
    if (!q) return;
    var err = $("siaError");
    if (err) {
      err.textContent = "";
      err.className = "form-status";
    }
    siaHistory.push({ isAi: false, text: q });
    renderSia();
    try {
      var history = siaHistory.slice(-10).map(function (m) {
        return { role: m.isAi ? "assistant" : "user", content: m.text };
      });
      var r = await api.api("/api/v1/kind/sia/chat", {
        method: "POST",
        body: { question: q, subject: "General", conversation_history: history },
      });
      var reply =
        (r && (r.sia_kind || r.text || r.response || r.answer || r.message || r.reply)) || "";
      if (!String(reply).trim()) {
        reply =
          "I'd love to help you learn! Tell me a subject (like English or Maths) and what you want to practise.";
      }
      siaHistory.push({ isAi: true, text: String(reply) });
      renderSia();
    } catch (e) {
      if (err) {
        err.textContent = e.message || "Sia is resting. Try again!";
        err.className = "form-status err";
      }
      siaHistory.push({
        isAi: true,
        text: "Hmm, I lost that answer. Try again — ask me something like “teach me nouns”.",
      });
      renderSia();
    }
  }

  /* —— Live —— */
  async function loadLive() {
    var el = $("liveList");
    if (!el) return;
    el.innerHTML = '<div class="loading">Loading live classes…</div>';
    try {
      var rows = await api.api("/api/v1/live-classes?status=live");
      if (!Array.isArray(rows)) rows = rows.classes || rows.items || [];
      if (!rows.length) {
        el.innerHTML =
          '<div class="empty"><strong>No live class right now</strong><br/>Check back soon, or book a one-on-one tutor.</div>';
        return;
      }
      el.innerHTML = rows
        .map(function (c) {
          var live = !!c.is_live;
          return (
            '<article class="live-card' +
            (live ? " is-live" : "") +
            '">' +
            (live ? '<span class="badge-live">Live now</span>' : "") +
            "<strong>" +
            esc(c.title || c.subject || "Live class") +
            "</strong>" +
            "<span style='color:var(--muted);font-weight:700;font-size:0.86rem'>" +
            esc(c.teacher_name || "Teacher") +
            (c.subject ? " · " + esc(c.subject) : "") +
            "</span>" +
            (live
              ? '<button type="button" class="btn btn-primary" data-join-live="' +
                esc(String(c.id)) +
                '">Join class</button>'
              : "") +
            "</article>"
          );
        })
        .join("");
    } catch (e) {
      el.innerHTML = '<div class="empty">' + esc(e.message || "Could not load classes") + "</div>";
    }
  }

  async function joinLive(id) {
    try {
      var res = await api.api("/api/v1/live-classes/" + encodeURIComponent(id) + "/join", {
        method: "POST",
      });
      var url =
        (res && (res.join_url || res.meeting_url || res.room_url || res.url)) || "";
      if (url) {
        window.open(url, "_blank", "noopener");
        return;
      }
      alert("You're in! Open the class from your teacher link when it appears.");
    } catch (e) {
      alert(e.message || "Could not join class.");
    }
  }

  async function bookClass() {
    var status = $("bookStatus");
    var subject = (($("bookSubject") && $("bookSubject").value) || "").trim();
    var topic = (($("bookTopic") && $("bookTopic").value) || "").trim();
    var packageId = (($("bookPackage") && $("bookPackage").value) || "nursery_standard").trim();
    if (!subject) {
      if (status) {
        status.textContent = "Enter a subject.";
        status.className = "form-status err";
      }
      return;
    }
    if (status) {
      status.textContent = "Opening Paystack…";
      status.className = "form-status";
    }
    try {
      var paid = await window.paystackPurchase({
        productType: "class_package",
        productId: packageId,
        returnPage: "live",
        notes: topic || subject,
      });
      if (!paid) return;
      await api.api("/api/v1/live-classes/requests", {
        method: "POST",
        body: {
          subject: subject,
          topic: topic || undefined,
          message: "Kids website booking",
        },
      });
      if (status) {
        status.textContent = "Booked! We'll assign a teacher.";
        status.className = "form-status ok";
      }
    } catch (e) {
      if (status) {
        status.textContent = e.message || "Booking failed.";
        status.className = "form-status err";
      }
    }
  }

  /* —— Saved —— */
  async function loadSaved() {
    var el = $("savedList");
    if (!el) return;
    el.innerHTML = '<div class="loading">Loading saved lessons…</div>';
    try {
      var rows = await api.api("/api/v1/saved-live-classes");
      if (!Array.isArray(rows)) rows = rows.items || [];
      if (!rows.length) {
        el.innerHTML =
          '<div class="empty">No saved lessons yet. Save a live class replay to watch here!</div>';
        return;
      }
      el.innerHTML = rows
        .map(function (s) {
          return (
            '<article class="saved-card"><strong>' +
            esc(s.title || s.class_title || "Saved lesson") +
            "</strong>" +
            (s.subject
              ? '<span style="color:var(--muted);font-weight:700">' + esc(s.subject) + "</span>"
              : "") +
            (s.recording_url
              ? '<a class="btn btn-primary" href="' +
                esc(s.recording_url) +
                '" target="_blank" rel="noopener">Watch replay</a>'
              : '<span style="color:var(--muted);font-weight:700">Replay coming soon</span>') +
            "</article>"
          );
        })
        .join("");
    } catch (e) {
      el.innerHTML = '<div class="empty">' + esc(e.message || "Could not load saved") + "</div>";
    }
  }

  /* —— CBT —— */
  function exitCbtPlayer() {
    cbtState = { exam: null, session: null, answers: {}, index: 0 };
    if ($("cbtPlay")) {
      $("cbtPlay").hidden = true;
      $("cbtPlay").innerHTML = "";
    }
    if ($("cbtBrowse")) $("cbtBrowse").hidden = false;
    if ($("cbtPayCard")) $("cbtPayCard").style.display = "";
  }

  async function loadCbt() {
    exitCbtPlayer();
    var list = $("cbtExamList");
    var banner = $("cbtAccessBanner");
    var payCard = $("cbtPayCard");
    if (list) list.innerHTML = '<div class="loading">Loading exams…</div>';

    var hasAccess = false;
    try {
      var access = await api.api("/api/v1/payments/paystack/cbt-access");
      var boards = ((access && access.boards) || []).map(function (b) {
        return String(b).toUpperCase();
      });
      hasAccess = boards.indexOf("COMMON_ENTRANCE") >= 0;
    } catch (e) {
      hasAccess = false;
    }

    if (banner) {
      if (hasAccess) {
        banner.style.display = "";
        banner.className = "info-banner";
        banner.textContent = "Access active — Common Entrance unlocked";
      } else {
        banner.style.display = "none";
      }
    }
    if (payCard) payCard.style.display = hasAccess ? "none" : "";

    try {
      var exams = await api.api("/api/v1/cbt/exams?exam_type=COMMON_ENTRANCE");
      if (!Array.isArray(exams)) exams = (exams && exams.exams) || [];
      if (!list) return;
      if (!exams.length) {
        list.innerHTML =
          '<div class="empty">No Common Entrance exams yet. You can still pay to unlock access for when they appear.</div>';
        return;
      }
      list.innerHTML = exams
        .map(function (ex) {
          return (
            '<article class="cbt-card"><strong>' +
            esc(ex.title || "Common Entrance") +
            "</strong><span style='color:var(--muted);font-weight:700'>" +
            esc(ex.subject || "") +
            '</span><button type="button" class="btn btn-primary" data-start-cbt="' +
            esc(String(ex.id || "")) +
            '">Start practice</button></article>'
          );
        })
        .join("");
    } catch (e) {
      if (list) list.innerHTML = '<div class="empty">' + esc(e.message || "Could not load exams") + "</div>";
    }
  }

  async function payCbt() {
    try {
      var paid = await window.paystackPurchase({
        productType: "cbt_package",
        productId: "common_entrance",
        returnPage: "cbt",
      });
      if (paid) {
        alert("Payment successful! Common Entrance CBT is unlocked.");
        loadCbt();
      }
    } catch (e) {
      alert(e.message || "Could not start payment.");
    }
  }

  async function startCbt(examId, btn) {
    if (!examId) return;
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Starting…";
    }
    try {
      var session = await api.api("/api/v1/cbt/sessions/" + encodeURIComponent(examId) + "/start", {
        method: "POST",
      });
      var pack = await api.api("/api/v1/cbt/exams/" + encodeURIComponent(examId) + "/download");
      if (!pack || !pack.questions || !pack.questions.length) {
        throw new Error("This exam has no questions yet.");
      }
      cbtState.exam = pack;
      cbtState.session = session;
      cbtState.answers = {};
      cbtState.index = 0;
      renderCbtPlayer();
    } catch (e) {
      var msg = e.message || "Could not start exam.";
      if (/402|cbt_package|package|paid|required/i.test(msg)) {
        await payCbt();
      } else {
        alert(msg);
      }
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = "Start practice";
      }
    }
  }

  function renderCbtPlayer() {
    var play = $("cbtPlay");
    if (!play || !cbtState.exam) return;
    if ($("cbtBrowse")) $("cbtBrowse").hidden = true;
    if ($("cbtPayCard")) $("cbtPayCard").style.display = "none";
    if ($("cbtAccessBanner")) $("cbtAccessBanner").style.display = "none";
    play.hidden = false;

    var qs = cbtState.exam.questions || [];
    var i = cbtState.index;
    var q = qs[i] || {};
    var opts = q.options || q.choices || [];
    if (!Array.isArray(opts) && typeof opts === "object") {
      opts = Object.keys(opts).map(function (k) {
        return opts[k];
      });
    }
    var qid = String(q.id != null ? q.id : i);
    var selected = cbtState.answers[qid];

    play.innerHTML =
      '<div class="cbt-play-head"><strong>' +
      esc(cbtState.exam.title || "Common Entrance") +
      "</strong><span>Question " +
      (i + 1) +
      " / " +
      qs.length +
      '</span></div><div class="cbt-q">' +
      esc(q.question || q.text || q.prompt || "Question") +
      '</div><div class="cbt-opts">' +
      opts
        .map(function (opt, oi) {
          var val = typeof opt === "object" ? opt.text || opt.label || opt.value || oi : opt;
          var key = typeof opt === "object" && opt.id != null ? String(opt.id) : String(oi);
          var on = String(selected) === key || String(selected) === String(val);
          return (
            '<button type="button" class="cbt-opt' +
            (on ? " is-on" : "") +
            '" data-cbt-opt="' +
            esc(key) +
            '">' +
            esc(String(val)) +
            "</button>"
          );
        })
        .join("") +
      '</div><div class="cbt-nav">' +
      '<button type="button" class="btn btn-mini" id="cbtPrev"' +
      (i === 0 ? " disabled" : "") +
      ">Previous</button>" +
      (i < qs.length - 1
        ? '<button type="button" class="btn btn-primary" id="cbtNext">Next</button>'
        : '<button type="button" class="btn btn-primary" id="cbtSubmit">Submit</button>') +
      "</div>";

    play.querySelectorAll("[data-cbt-opt]").forEach(function (btn) {
      btn.addEventListener("click", function () {
        cbtState.answers[qid] = btn.getAttribute("data-cbt-opt");
        renderCbtPlayer();
      });
    });
    if ($("cbtPrev")) {
      $("cbtPrev").onclick = function () {
        if (cbtState.index > 0) {
          cbtState.index -= 1;
          renderCbtPlayer();
        }
      };
    }
    if ($("cbtNext")) {
      $("cbtNext").onclick = function () {
        cbtState.index += 1;
        renderCbtPlayer();
      };
    }
    if ($("cbtSubmit")) {
      $("cbtSubmit").onclick = submitCbt;
    }
    updateBackBtn();
  }

  async function submitCbt() {
    try {
      var sessionId =
        (cbtState.session && (cbtState.session.id || cbtState.session.session_id)) || "";
      var body = {
        answers: cbtState.answers,
        session_id: sessionId,
      };
      var result = await api.api("/api/v1/cbt/sessions/submit", {
        method: "POST",
        body: body,
      });
      var score = result && (result.score != null ? result.score : result.percentage);
      alert(
        score != null
          ? "Great job! Score: " + score + (String(score).indexOf("%") >= 0 ? "" : "%")
          : "Answers submitted. Well done!"
      );
      exitCbtPlayer();
      loadCbt();
    } catch (e) {
      alert(e.message || "Could not submit. Try again.");
    }
  }

  /* —— Profile —— */
  async function loadProfile() {
    var user = api.getUser();
    setUserChip(user.name, user.ageGroup);
    if ($("profileText")) {
      $("profileText").textContent =
        (user.name || "Friend") +
        " · " +
        (user.email || "") +
        " · Kid" +
        (user.ageGroup ? " · Ages " + user.ageGroup : "");
    }
    try {
      var me = await api.api("/api/v1/kind/me");
      if (me) {
        setUserChip(me.full_name || user.name, me.age_group || user.ageGroup);
        if ($("profileText")) {
          $("profileText").textContent =
            (me.full_name || user.name) +
            " · " +
            (me.email || user.email) +
            " · Kid" +
            (me.age_group ? " · Ages " + me.age_group : "");
        }
      }
    } catch (e) {
      /* keep session data */
    }
  }

  /* —— Events (delegated so all tabs / tiles always work) —— */
  document.addEventListener("click", function (e) {
    var t = e.target;
    if (!t || !t.closest) return;

    var navBtn = t.closest(".kind-nav-btn, [data-page]");
    if (navBtn && navBtn.getAttribute("data-page")) {
      e.preventDefault();
      e.stopPropagation();
      showPage(navBtn.getAttribute("data-page"));
      return;
    }

    var goto = t.closest("[data-goto]");
    if (goto && goto.getAttribute("data-goto")) {
      e.preventDefault();
      e.stopPropagation();
      showPage(goto.getAttribute("data-goto"));
      return;
    }

    var join = t.closest("[data-join-live]");
    if (join) {
      e.preventDefault();
      joinLive(join.getAttribute("data-join-live"));
      return;
    }

    var start = t.closest("[data-start-cbt]");
    if (start) {
      e.preventDefault();
      startCbt(start.getAttribute("data-start-cbt"), start);
    }
  });

  if ($("logoutBtn")) {
    $("logoutBtn").addEventListener("click", function () {
      api.clearSession();
      window.location.href = "auth.html";
    });
  }

  if ($("siaForm")) {
    $("siaForm").addEventListener("submit", function (e) {
      e.preventDefault();
      var input = $("siaInput");
      var text = (input && input.value.trim()) || "";
      if (!text) return;
      if (input) input.value = "";
      sendSia(text);
    });
  }

  document.querySelectorAll("[data-sia-q]").forEach(function (chip) {
    chip.addEventListener("click", function () {
      sendSia(chip.getAttribute("data-sia-q"));
    });
  });

  if ($("refreshLiveBtn")) $("refreshLiveBtn").addEventListener("click", loadLive);
  if ($("bookPayBtn")) $("bookPayBtn").addEventListener("click", bookClass);
  if ($("cbtPayBtn")) $("cbtPayBtn").addEventListener("click", payCbt);

  if ($("mobileMenuBtn")) {
    $("mobileMenuBtn").addEventListener("click", function () {
      if (document.body.classList.contains("nav-open")) closeMobileNav();
      else openMobileNav();
    });
  }
  if ($("sidebarBackdrop")) {
    $("sidebarBackdrop").addEventListener("click", closeMobileNav);
  }
  if ($("sidebarCloseBtn")) {
    $("sidebarCloseBtn").addEventListener("click", function (e) {
      e.preventDefault();
      e.stopPropagation();
      if (window.matchMedia("(max-width: 900px)").matches) {
        closeMobileNav();
      } else if (shell) {
        shell.classList.add("sidebar-collapsed");
        if ($("sidebarToggle")) {
          $("sidebarToggle").textContent = "›";
          $("sidebarToggle").setAttribute("aria-label", "Show menu");
        }
      }
    });
  }
  if ($("sidebarToggle")) {
    $("sidebarToggle").addEventListener("click", function () {
      if (!shell) return;
      var collapsed = !shell.classList.contains("sidebar-collapsed");
      shell.classList.toggle("sidebar-collapsed", collapsed);
      $("sidebarToggle").textContent = collapsed ? "›" : "‹";
      $("sidebarToggle").setAttribute("aria-label", collapsed ? "Show menu" : "Hide menu");
    });
  }
  if ($("backBtn")) $("backBtn").addEventListener("click", goBack);

  /* boot */
  var user = api.getUser();
  setUserChip(user.name, user.ageGroup);

  if (typeof window.resumePendingPaystack === "function") {
    window.resumePendingPaystack().then(function (res) {
      if (!res) return;
      var page = (res.pending && res.pending.returnPage) || "home";
      if (res.paid) {
        alert("Payment confirmed!");
        showPage(TITLES[page] ? page : "home", { replace: true });
      } else if (res.error) {
        alert((res.error && res.error.message) || "Payment could not be verified.");
      }
    });
  }

  var hash = (location.hash || "").replace("#", "");
  showPage(TITLES[hash] ? hash : "home", { replace: true });
})();
