/** Kids Common Entrance CBT — matches Flutter KindCbtScreen + Paystack ₦2000.
 *  Offline-first (professional): the exam list, downloaded packs, in-progress
 *  attempts and sealed submissions all survive reloads and internet loss.
 *
 *  localStorage keys:
 *   sia_kind_cbt_home                — cached exam list + access flag
 *   sia_kind_cbt_pack_<examId>       — downloaded question pack (offline practice)
 *   sia_kind_cbt_prog_<examId>       — in-progress attempt { index, answers, savedAt }
 *   sia_kind_cbt_pending_<examId>    — sealed submission waiting to sync
 */

var kindCbtState = {
  exam: null,
  session: null,
  answers: {},
  index: 0,
};

var KIND_STORE = {
  home: "sia_kind_cbt_home",
  pack: function (id) { return "sia_kind_cbt_pack_" + id; },
  prog: function (id) { return "sia_kind_cbt_prog_" + id; },
  pend: function (id) { return "sia_kind_cbt_pending_" + id; },
};

function kindLsGet(key) {
  try { var v = localStorage.getItem(key); return v ? JSON.parse(v) : null; } catch (e) { return null; }
}
function kindLsSet(key, val) {
  try { localStorage.setItem(key, JSON.stringify(val)); return true; } catch (e) { return false; }
}
function kindLsDel(key) {
  try { localStorage.removeItem(key); } catch (e) { /* ignore */ }
}
function kindLsKeys(prefix) {
  var out = [];
  try {
    for (var i = 0; i < localStorage.length; i++) {
      var k = localStorage.key(i);
      if (k && k.indexOf(prefix) === 0) out.push(k);
    }
  } catch (e) { /* ignore */ }
  return out;
}

function cleanTitle(raw) {
  var t = String(raw || "").trim();
  var low = t.toLowerCase();
  if (low.indexOf("common_entrance") === 0) {
    t = t.substring("common_entrance".length);
  } else if (low.indexOf("common entrance") === 0) {
    t = t.substring("common entrance".length);
  }
  t = t.replace(/_question_bank/gi, " ").replace(/question bank/gi, " ");
  t = t.replace(/_/g, " ").replace(/\s+/g, " ").trim();
  return t || "Practice";
}

var KIND_CBT_STYLES = [
  { icon: "&#128218;", from: "#7c3aed", to: "#4f46e5" }, /* violet book */
  { icon: "&#127757;", from: "#0ea5e9", to: "#0369a1" }, /* globe */
  { icon: "&#128300;", from: "#10b981", to: "#047857" }, /* science */
  { icon: "&#128288;", from: "#f59e0b", to: "#d97706" }, /* language arts */
  { icon: "&#129490;", from: "#ec4899", to: "#be185d" }, /* french */
  { icon: "&#127979;", from: "#6366f1", to: "#4338ca" }, /* general */
  { icon: "&#129513;", from: "#14b8a6", to: "#0f766e" }, /* reasoning */
  { icon: "&#127918;", from: "#f43f5e", to: "#be123c" }, /* fun */
];

function kindCbtStyleFor(title) {
  var t = String(title || "").toLowerCase();
  if (t.indexOf("english") >= 0 || t.indexOf("verbal") >= 0) return KIND_CBT_STYLES[3];
  if (t.indexOf("french") >= 0) return KIND_CBT_STYLES[4];
  if (t.indexOf("science") >= 0) return KIND_CBT_STYLES[2];
  if (t.indexOf("social") >= 0 || t.indexOf("study") >= 0) return KIND_CBT_STYLES[1];
  if (t.indexOf("reasoning") >= 0 || t.indexOf("quantitative") >= 0) return KIND_CBT_STYLES[6];
  if (t.indexOf("math") >= 0) return KIND_CBT_STYLES[0];
  var hash = 0;
  for (var i = 0; i < t.length; i++) hash = (hash * 31 + t.charCodeAt(i)) >>> 0;
  return KIND_CBT_STYLES[hash % KIND_CBT_STYLES.length];
}

/* ── Sealed-submission sync: flushes automatically when internet returns ── */
function kindCbtFlushPending() {
  if (typeof navigator !== "undefined" && !navigator.onLine) return;
  kindLsKeys(KIND_STORE.pend("")).forEach(function (key) {
    var examId = key.replace(KIND_STORE.pend(""), "");
    var pend = kindLsGet(key);
    if (!pend) return;
    var ensureSession = pend.session_id
      ? Promise.resolve({ session_id: pend.session_id })
      : api("/api/v1/cbt/sessions/" + encodeURIComponent(examId) + "/start", { method: "POST" });
    ensureSession.then(function (sess) {
      var sessionId = sess && (sess.session_id || sess.id);
      if (!sessionId) throw new Error("no session");
      pend.session_id = sessionId;
      kindLsSet(key, pend);
      return api("/api/v1/cbt/sessions/submit", {
        method: "POST",
        body: JSON.stringify({ session_id: sessionId, answers: pend.answers, is_auto_submit: !!pend.is_auto_submit }),
      });
    }).then(function () {
      kindLsDel(key);
      if (typeof window.kindCbtOnSynced === "function") window.kindCbtOnSynced(examId);
    }).catch(function () { /* stays sealed; retried on next online/boot */ });
  });
}
window.kindCbtOnSynced = function () { /* default: silent */ };
window.addEventListener("online", function () {
  kindCbtFlushPending();
});
if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", kindCbtFlushPending);
} else {
  kindCbtFlushPending();
}

async function loadKindCbtPage() {
  var root = document.getElementById("kind-cbt-root");
  var play = document.getElementById("kind-cbt-play");
  if (play) {
    play.classList.add("hidden");
    play.innerHTML = "";
  }
  if (!root) return;
  root.classList.remove("hidden");
  root.innerHTML = '<div class="loading">Loading practice exams…</div>';

  var exams = [];
  var hasAccess = false;
  var offline = typeof navigator !== "undefined" && !navigator.onLine;
  var cachedHome = kindLsGet(KIND_STORE.home);

  if (!offline) {
    try {
      exams = await api("/api/v1/cbt/exams?exam_type=COMMON_ENTRANCE") || [];
      if (!Array.isArray(exams)) exams = exams.exams || [];
      kindLsSet(KIND_STORE.home, { exams: exams, fetchedAt: Date.now() });
    } catch (e) {
      exams = [];
      offline = true; // server unreachable — treat like offline and use the cache
    }
    try {
      var access = await api("/api/v1/payments/paystack/cbt-access") || {};
      var boards = (access.boards || []).map(function (b) { return String(b).toUpperCase(); });
      hasAccess = boards.indexOf("COMMON_ENTRANCE") >= 0;
      if (cachedHome) cachedHome.hasAccess = hasAccess;
    } catch (e2) {
      hasAccess = false;
    }
    if (cachedHome) cachedHome.hasAccess = hasAccess;
  }

  if (!exams.length && cachedHome) {
    exams = cachedHome.exams || [];
    hasAccess = !!cachedHome.hasAccess;
  }

  var payBanner =
    '<div class="kind-cbt-paywall kind-cbt-paywall-hero">' +
    '<div class="kind-cbt-paywall-art" aria-hidden="true">&#127891;</div>' +
    "<h3>Unlock Common Entrance practice</h3>" +
    "<p>Year-round access to every Common Entrance exam for <strong>&#8358;2,000 / year</strong>, paid securely with Paystack.</p>" +
    '<button type="button" class="kind-cbt-pay-btn" onclick="payKindCbtPackage()">&#128179; Pay &#8358;2,000 with Paystack</button>' +
    "</div>";

  if (!exams.length) {
    root.innerHTML =
      (hasAccess ? "" : payBanner) +
      '<div class="as-empty"><h3>No exams yet</h3><p>' +
      (hasAccess
        ? "You have CBT access. When admin uploads Common Entrance exams, they appear here."
        : "Admin will publish Common Entrance exams here. You can pay anytime to unlock practice.") +
      "</p></div>";
    return;
  }

  var offlineNote = offline
    ? '<div class="kind-cbt-status" style="background:rgba(245,158,11,.15);color:#b45309">&#128244; Offline — downloaded exams below still work, and submissions sync when internet returns</div>'
    : "";

  root.innerHTML =
    (hasAccess
      ? '<div class="kind-cbt-status is-active">&#127881; Access active — every Common Entrance exam is unlocked</div>'
      : payBanner) +
    offlineNote +
    '<div class="kind-cbt-section-title">Pick a practice exam</div>' +
    '<div class="kind-cbt-grid">' +
    exams
      .map(function (ex, idx) {
        var id = ex.id || "";
        var title = cleanTitle(ex.title || ex.subject || "Practice");
        var subject = ex.subject || "";
        var st = kindCbtStyleFor(title);
        var qCount = ex.question_count || ex.total_questions || null;
        var downloaded = !!kindLsGet(KIND_STORE.pack(id));
        var inProgress = !!kindLsGet(KIND_STORE.prog(id));
        var pending = !!kindLsGet(KIND_STORE.pend(id));
        var badge = "";
        if (pending) badge = '<span class="kind-cbt-card-meta" style="color:#b45309">&#8987; submitted — waiting to sync</span>';
        else if (inProgress) badge = '<span class="kind-cbt-card-meta" style="color:#047857">&#9203; continue — saved on this device</span>';
        else if (downloaded) badge = '<span class="kind-cbt-card-meta" style="color:#0369a1">&#11015; ready offline</span>';
        return (
          '<article class="kind-cbt-card" style="background:linear-gradient(150deg,' + st.from + "," + st.to + ')"' +
          ' onclick="startKindCbtExam(\'' + kindEsc(id) + '\', this)">' +
          '<div class="kind-cbt-card-icon">' + st.icon + "</div>" +
          '<div class="kind-cbt-card-body">' +
          "<h4>" + kindEsc(title) + "</h4>" +
          (subject && subject.toLowerCase() !== title.toLowerCase()
            ? "<p>" + kindEsc(subject) + "</p>"
            : "") +
          '<span class="kind-cbt-card-meta">' + (qCount ? qCount + " questions" : "") + "</span>" +
          badge +
          '</div>' +
          '<span class="kind-cbt-card-cta">' + (inProgress ? "Continue &#9654;" : "Start &#9654;") + "</span>" +
          "</article>"
        );
      })
      .join("") +
    "</div>";
}

async function payKindCbtPackage() {
  try {
    if (typeof paystackPurchase !== "function") {
      throw new Error("Paystack is not available. Refresh and try again.");
    }
    var paid = await paystackPurchase({
      productType: "cbt_package",
      productId: "common_entrance",
    });
    if (!paid) {
      alert("Payment was not completed.");
      return;
    }
    alert("Payment successful! Common Entrance CBT is unlocked.");
    loadKindCbtPage();
  } catch (e) {
    alert(e.message || "Could not start payment.");
  }
}

async function startKindCbtExam(examId, btn) {
  if (!examId) return;
  var offline = typeof navigator !== "undefined" && !navigator.onLine;
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Starting…";
  }
  try {
    var pack = null;
    var session = null;
    var prog = kindLsGet(KIND_STORE.prog(examId));
    var pending = kindLsGet(KIND_STORE.pend(examId));
    if (pending) {
      alert("Great job! This one is already submitted and is waiting to sync — it will upload automatically when internet returns.");
      return;
    }
    if (prog && prog.answers && Object.keys(prog.answers).length) {
      // Resume the saved attempt — no network needed.
      var cachedPack = kindLsGet(KIND_STORE.pack(examId));
      if (!cachedPack) { prog = null; }
      else {
        kindCbtState.exam = cachedPack;
        kindCbtState.session = prog.session || null;
        kindCbtState.answers = prog.answers || {};
        kindCbtState.index = prog.index || 0;
        renderKindCbtPlayer(true);
        return;
      }
    }
    if (!offline) {
      try {
        session = await api("/api/v1/cbt/sessions/" + encodeURIComponent(examId) + "/start", { method: "POST" });
        var raw = await api("/api/v1/cbt/exams/" + encodeURIComponent(examId) + "/download");
        if (!raw || !raw.questions || !raw.questions.length) {
          throw new Error("This exam has no questions yet.");
        }
        // Normalize + cache for offline practice (same shape as the offline path).
        pack = {
          examId: examId,
          title: raw.title || (raw.exam && raw.exam.title) || "",
          subject: raw.subject || (raw.exam && raw.exam.subject) || "",
          cachedAt: Date.now(),
          questions: raw.questions,
        };
        kindLsSet(KIND_STORE.pack(examId), pack);
      } catch (startErr) {
        var cached = kindLsGet(KIND_STORE.pack(examId));
        if (cached) {
          pack = cached; // fall back to the downloaded pack — offline-capable
          session = null;
        } else {
          throw startErr;
        }
      }
    } else {
      pack = kindLsGet(KIND_STORE.pack(examId));
      if (!pack) {
        alert("Connect to the internet once to download this exam — after that it works offline anytime.");
        return;
      }
    }
    kindCbtState.exam = pack;
    kindCbtState.session = session;
    kindCbtState.answers = {};
    kindCbtState.index = 0;
    kindCbtPersistProgress();
    renderKindCbtPlayer();
  } catch (e) {
    var msg = e.message || "Could not start exam.";
    if (/402|cbt_package|package|paid|required/i.test(msg)) {
      await payKindCbtPackage();
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

function kindCbtPersistProgress() {
  if (!kindCbtState.exam || !kindCbtState.exam.examId) return;
  kindLsSet(KIND_STORE.prog(kindCbtState.exam.examId), {
    index: kindCbtState.index,
    answers: kindCbtState.answers,
    session: kindCbtState.session,
    savedAt: Date.now(),
  });
}

function renderKindCbtPlayer(resuming) {
  var root = document.getElementById("kind-cbt-root");
  var play = document.getElementById("kind-cbt-play");
  if (!play || !kindCbtState.exam) return;
  if (root) root.classList.add("hidden");
  play.classList.remove("hidden");

  var qs = kindCbtState.exam.questions || [];
  var i = Math.min(kindCbtState.index, Math.max(0, qs.length - 1));
  kindCbtState.index = i;
  var q = qs[i] || {};
  var opts = q.options || q.choices || [];
  if (!Array.isArray(opts) && typeof opts === "object") {
    opts = Object.keys(opts).map(function (k) {
      return { key: k, text: opts[k] };
    });
  }
  // API shape (cbt_questions): question_text + option_a..d — normalize it.
  if ((!opts || !opts.length) && (q.option_a || q.option_b || q.option_c || q.option_d)) {
    opts = ["a", "b", "c", "d"]
      .filter(function (k) { return q["option_" + k]; })
      .map(function (k) { return { key: k.toUpperCase(), text: q["option_" + k] }; });
  }
  var qid = String(q.id || i);
  var selected = kindCbtState.answers[qid];

  var optionsHtml = (opts || [])
    .map(function (opt, idx) {
      var key = opt.key != null ? String(opt.key) : String.fromCharCode(65 + idx);
      var text = typeof opt === "string" ? opt : opt.text || opt.label || opt.value || key;
      var checked = selected === key ? " checked" : "";
      return (
        '<label class="kind-cbt-option">' +
        '<input type="radio" name="kind-cbt-opt" value="' +
        kindEsc(key) +
        '"' +
        checked +
        ' onchange="kindCbtPickAnswer(\'' +
        kindEsc(qid) +
        "', this.value)\" />" +
        "<span><strong>" +
        kindEsc(key) +
        ".</strong> " +
        kindEsc(text) +
        "</span></label>"
      );
    })
    .join("");

  play.innerHTML =
    '<div class="kind-cbt-player">' +
    '<div class="kind-cbt-player-head">' +
    "<h3>" +
    kindEsc(cleanTitle(kindCbtState.exam.title || "Practice")) +
    "</h3>" +
    "<p>Question " +
    (i + 1) +
    " of " +
    qs.length +
    (resuming ? " · resumed from your saved work" : "") +
    "</p>" +
    '<button type="button" class="btn-secondary btn-sm" onclick="exitKindCbtPlayer()">Exit</button>' +
    "</div>" +
    '<div class="kind-cbt-q">' +
    "<p>" +
    kindEsc(q.question_text || q.question || q.text || q.prompt || "") +
    "</p>" +
    optionsHtml +
    "</div>" +
    '<div class="kind-cbt-nav">' +
    '<button type="button" class="btn-secondary" ' +
    (i <= 0 ? "disabled" : "") +
    ' onclick="kindCbtPrev()">Previous</button>' +
    (i >= qs.length - 1
      ? '<button type="button" class="btn-action" onclick="submitKindCbtExam()">Submit</button>'
      : '<button type="button" class="btn-action" onclick="kindCbtNext()">Next</button>') +
    "</div></div>";
}

function kindCbtPickAnswer(qid, value) {
  kindCbtState.answers[qid] = value;
  kindCbtPersistProgress();
}

function kindCbtNext() {
  var qs = (kindCbtState.exam && kindCbtState.exam.questions) || [];
  if (kindCbtState.index < qs.length - 1) {
    kindCbtState.index += 1;
    kindCbtPersistProgress();
    renderKindCbtPlayer();
  }
}

function kindCbtPrev() {
  if (kindCbtState.index > 0) {
    kindCbtState.index -= 1;
    kindCbtPersistProgress();
    renderKindCbtPlayer();
  }
}

function exitKindCbtPlayer() {
  if (kindCbtState.exam) kindCbtPersistProgress();
  kindCbtState = { exam: null, session: null, answers: {}, index: 0 };
  var play = document.getElementById("kind-cbt-play");
  var root = document.getElementById("kind-cbt-root");
  if (play) {
    play.classList.add("hidden");
    play.innerHTML = "";
  }
  if (root) root.classList.remove("hidden");
  loadKindCbtPage();
}

async function submitKindCbtExam() {
  var sessionId =
    (kindCbtState.session && (kindCbtState.session.session_id || kindCbtState.session.id)) || "";
  var examId = kindCbtState.exam && kindCbtState.exam.examId;
  var offline = typeof navigator !== "undefined" && !navigator.onLine;
  var submitted = false;
  try {
    if (sessionId && !offline) {
      await api("/api/v1/cbt/sessions/submit", {
        method: "POST",
        body: JSON.stringify({
          session_id: sessionId,
          answers: kindCbtState.answers,
          is_auto_submit: false,
        }),
      });
      submitted = true;
    }
  } catch (e) {
    // Network hiccup mid-submit — fall through to the sealed-offline path.
  }
  if (!submitted) {
    // Seal locally (works with no session too — a fresh session is created on sync server-side).
    if (examId) {
      kindLsSet(KIND_STORE.pend(examId), {
        session_id: sessionId,
        answers: kindCbtState.answers,
        submitted_at: new Date().toISOString(),
      });
    }
    alert("Saved on this device! " + (offline ? "It will upload automatically when internet comes back." : "It will upload automatically in a moment."));
    kindCbtFlushPending();
  }
  if (examId) kindLsDel(KIND_STORE.prog(examId));
  kindCbtState = { exam: null, session: null, answers: {}, index: 0 };
  var play = document.getElementById("kind-cbt-play");
  var root = document.getElementById("kind-cbt-root");
  if (play) {
    play.classList.add("hidden");
    play.innerHTML = "";
  }
  if (root) root.classList.remove("hidden");
  loadKindCbtPage();
}

window.loadKindCbtPage = loadKindCbtPage;
window.payKindCbtPackage = payKindCbtPackage;
window.startKindCbtExam = startKindCbtExam;
window.kindCbtPickAnswer = kindCbtPickAnswer;
window.kindCbtNext = kindCbtNext;
window.kindCbtPrev = kindCbtPrev;
window.exitKindCbtPlayer = exitKindCbtPlayer;
window.submitKindCbtExam = submitKindCbtExam;
