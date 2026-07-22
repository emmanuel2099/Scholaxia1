/** Kids Common Entrance CBT — matches Flutter KindCbtScreen + Paystack ₦2000. */

var kindCbtState = {
  exam: null,
  session: null,
  answers: {},
  index: 0,
};

async function loadKindCbtPage() {
  var root = document.getElementById("kind-cbt-root");
  var play = document.getElementById("kind-cbt-play");
  if (play) {
    play.classList.add("hidden");
    play.innerHTML = "";
  }
  if (!root) return;
  root.classList.remove("hidden");
  root.innerHTML = '<div class="loading">Loading Common Entrance CBT…</div>';

  try {
    var exams = [];
    var hasAccess = false;
    try {
      exams = await api("/api/v1/cbt/exams?exam_type=COMMON_ENTRANCE") || [];
      if (!Array.isArray(exams)) exams = exams.exams || [];
    } catch (e) {
      exams = [];
    }
    try {
      var access = await api("/api/v1/payments/paystack/cbt-access") || {};
      var boards = (access.boards || []).map(function (b) {
        return String(b).toUpperCase();
      });
      hasAccess = boards.indexOf("COMMON_ENTRANCE") >= 0;
    } catch (e) {
      hasAccess = false;
    }

    var paywall =
      '<div class="kind-cbt-paywall">' +
      "<h3>Common Entrance CBT — ₦2,000 / year</h3>" +
      "<p>Unlock Primary 6 Common Entrance practice with Paystack. Same setting as the mobile Kids app.</p>" +
      '<button type="button" class="btn-action" onclick="payKindCbtPackage()">Pay ₦2,000 with Paystack</button>' +
      "</div>";

    if (!hasAccess) {
      root.innerHTML =
        paywall +
        (exams.length
          ? '<p class="cbt-hint" style="margin-top:16px">Exams are ready — pay to start practising.</p>'
          : '<p class="cbt-hint" style="margin-top:16px">Admin will publish Common Entrance exams here.</p>');
      return;
    }

    if (!exams.length) {
      root.innerHTML =
        '<div class="as-empty"><h3>No exams yet</h3><p>You have CBT access. When admin uploads Common Entrance exams, they appear here.</p></div>';
      return;
    }

    root.innerHTML =
      '<div class="kind-cbt-status is-active">Access active — Common Entrance unlocked</div>' +
      '<div class="kind-cbt-grid">' +
      exams
        .map(function (ex) {
          var id = ex.id || "";
          var title = ex.title || "Common Entrance";
          var subject = ex.subject || "";
          return (
            '<article class="kind-cbt-card">' +
            "<h4>" + kindEsc(title) + "</h4>" +
            "<p>" + kindEsc(subject) + "</p>" +
            '<button type="button" class="btn-action btn-sm" onclick="startKindCbtExam(\'' +
            kindEsc(id) +
            "', this)\">Start practice</button>" +
            "</article>"
          );
        })
        .join("") +
      "</div>";
  } catch (e) {
    root.innerHTML = '<div class="empty-state">' + kindEsc(e.message) + "</div>";
  }
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
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Starting…";
  }
  try {
    var session = await api("/api/v1/cbt/sessions/" + encodeURIComponent(examId) + "/start", {
      method: "POST",
    });
    var pack = await api("/api/v1/cbt/exams/" + encodeURIComponent(examId) + "/download");
    if (!pack || !pack.questions || !pack.questions.length) {
      throw new Error("This exam has no questions yet.");
    }
    kindCbtState.exam = pack;
    kindCbtState.session = session;
    kindCbtState.answers = {};
    kindCbtState.index = 0;
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

function renderKindCbtPlayer() {
  var root = document.getElementById("kind-cbt-root");
  var play = document.getElementById("kind-cbt-play");
  if (!play || !kindCbtState.exam) return;
  if (root) root.classList.add("hidden");
  play.classList.remove("hidden");

  var qs = kindCbtState.exam.questions || [];
  var i = kindCbtState.index;
  var q = qs[i] || {};
  var opts = q.options || q.choices || [];
  if (!Array.isArray(opts) && typeof opts === "object") {
    opts = Object.keys(opts).map(function (k) {
      return { key: k, text: opts[k] };
    });
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
    kindEsc(kindCbtState.exam.title || "Common Entrance") +
    "</h3>" +
    "<p>Question " +
    (i + 1) +
    " of " +
    qs.length +
    "</p>" +
    '<button type="button" class="btn-secondary btn-sm" onclick="exitKindCbtPlayer()">Exit</button>' +
    "</div>" +
    '<div class="kind-cbt-q">' +
    "<p>" +
    kindEsc(q.question || q.text || q.prompt || "") +
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
}

function kindCbtNext() {
  var qs = (kindCbtState.exam && kindCbtState.exam.questions) || [];
  if (kindCbtState.index < qs.length - 1) {
    kindCbtState.index += 1;
    renderKindCbtPlayer();
  }
}

function kindCbtPrev() {
  if (kindCbtState.index > 0) {
    kindCbtState.index -= 1;
    renderKindCbtPlayer();
  }
}

function exitKindCbtPlayer() {
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
  try {
    if (sessionId) {
      await api("/api/v1/cbt/sessions/submit", {
        method: "POST",
        body: JSON.stringify({
          session_id: sessionId,
          answers: kindCbtState.answers,
          is_auto_submit: false,
        }),
      });
    }
    alert("Submitted! Great job practising.");
  } catch (e) {
    alert(e.message || "Could not submit. Your answers were saved on this device.");
  }
  exitKindCbtPlayer();
}

window.loadKindCbtPage = loadKindCbtPage;
window.payKindCbtPackage = payKindCbtPackage;
window.startKindCbtExam = startKindCbtExam;
window.kindCbtPickAnswer = kindCbtPickAnswer;
window.kindCbtNext = kindCbtNext;
window.kindCbtPrev = kindCbtPrev;
window.exitKindCbtPlayer = exitKindCbtPlayer;
window.submitKindCbtExam = submitKindCbtExam;
