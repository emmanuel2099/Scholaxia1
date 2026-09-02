(function () {
  var API = (window.SCHOLAXIA_API_BASE || "").replace(/\/$/, "");
  var state = {
    products: [],
    exam: "ALL",
    subject: "",
    search: "",
    selected: null,
  };

  function money(n) {
    return "₦" + Number(n || 0).toLocaleString("en-NG");
  }

  function qs(id) {
    return document.getElementById(id);
  }

  async function api(path, opts) {
    var res = await fetch(API + path, Object.assign({
      headers: { "Content-Type": "application/json", Accept: "application/json" },
    }, opts || {}));
    var data = null;
    try { data = await res.json(); } catch (e) { data = null; }
    if (!res.ok) {
      var msg = (data && (data.detail || data.message)) || ("Request failed (" + res.status + ")");
      if (typeof msg !== "string") msg = JSON.stringify(msg);
      throw new Error(msg);
    }
    return data;
  }

  function uniqueSubjects(list) {
    var set = {};
    list.forEach(function (p) {
      if (p.subject) set[p.subject] = true;
    });
    return Object.keys(set).sort();
  }

  function filtered() {
    return state.products.filter(function (p) {
      if (state.exam !== "ALL" && String(p.exam_type || "").toUpperCase() !== state.exam) return false;
      if (state.subject && p.subject !== state.subject) return false;
      if (state.search) {
        var hay = [p.title, p.subject, p.exam_type, p.year, p.description].join(" ").toLowerCase();
        if (hay.indexOf(state.search.toLowerCase()) < 0) return false;
      }
      return true;
    });
  }

  function renderTabs() {
    var tabs = qs("pqExamTabs");
    if (!tabs) return;
    var exams = ["ALL", "JAMB", "WAEC", "NECO", "COMMON_ENTRANCE"];
    tabs.innerHTML = exams.map(function (ex) {
      var label = ex === "COMMON_ENTRANCE" ? "Common Entrance" : ex === "ALL" ? "All" : ex;
      return '<button type="button" class="mkt-tab' + (state.exam === ex ? " is-active" : "") +
        '" data-exam="' + ex + '">' + label + "</button>";
    }).join("");
    tabs.querySelectorAll("button").forEach(function (btn) {
      btn.addEventListener("click", function () {
        state.exam = btn.getAttribute("data-exam");
        state.subject = "";
        render();
      });
    });
  }

  function renderSubjects() {
    var wrap = qs("pqSubjectTabs");
    if (!wrap) return;
    var pool = state.products.filter(function (p) {
      return state.exam === "ALL" || String(p.exam_type || "").toUpperCase() === state.exam;
    });
    var subjects = uniqueSubjects(pool);
    wrap.innerHTML = '<button type="button" class="' + (!state.subject ? "is-active" : "") +
      '" data-subject="">All subjects</button>' +
      subjects.map(function (s) {
        return '<button type="button" class="' + (state.subject === s ? "is-active" : "") +
          '" data-subject="' + s.replace(/"/g, "&quot;") + '">' + s + "</button>";
      }).join("");
    wrap.querySelectorAll("button").forEach(function (btn) {
      btn.addEventListener("click", function () {
        state.subject = btn.getAttribute("data-subject") || "";
        render();
      });
    });
  }

  function renderGrid() {
    var grid = qs("pqGrid");
    if (!grid) return;
    var rows = filtered();
    if (!rows.length) {
      grid.innerHTML = '<div class="mkt-empty">No Past Questions match this filter yet.</div>';
      return;
    }
    grid.innerHTML = rows.map(function (p) {
      var year = p.year ? " · " + p.year : "";
      return '<article class="pq-card">' +
        '<div class="pq-meta">' + (p.exam_type || "") + year + "</div>" +
        "<h3>" + escapeHtml(p.title) + "</h3>" +
        "<div>" + escapeHtml(p.subject || "") + "</div>" +
        '<div class="pq-price">' + money(p.price) + "</div>" +
        '<button type="button" class="pq-buy" data-id="' + p.id + '">Buy</button>' +
        "</article>";
    }).join("");
    grid.querySelectorAll(".pq-buy").forEach(function (btn) {
      btn.addEventListener("click", function () {
        openBuy(btn.getAttribute("data-id"));
      });
    });
  }

  function escapeHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function render() {
    renderTabs();
    renderSubjects();
    renderGrid();
  }

  function openBuy(id) {
    var product = state.products.find(function (p) { return p.id === id; });
    if (!product) return;
    state.selected = product;
    var bg = qs("pqDrawerBg");
    var drawer = qs("pqDrawer");
    var body = qs("pqDrawerBody");
    body.innerHTML =
      "<h2>" + escapeHtml(product.title) + "</h2>" +
      '<p class="pq-meta">' + escapeHtml(product.exam_type || "") + " · " +
      escapeHtml(product.subject || "") +
      (product.year ? " · " + product.year : "") + "</p>" +
      "<p>" + escapeHtml(product.description || "Past Questions PDF.") + "</p>" +
      '<p class="pq-price">' + money(product.price) + "</p>" +
      '<form class="pq-form" id="pqBuyForm">' +
      "<label>Email for receipt &amp; download link</label>" +
      '<input type="email" id="pqEmail" required placeholder="you@email.com" />' +
      "<label>Full name (optional)</label>" +
      '<input type="text" id="pqName" placeholder="Your name" />' +
      '<p class="pq-err" id="pqBuyErr"></p>' +
      '<button type="submit" class="pq-buy" id="pqPayBtn" style="width:100%;margin-top:1rem">Pay with Paystack</button>' +
      "</form>" +
      '<div id="pqBuyResult"></div>';
    bg.hidden = false;
    drawer.hidden = false;
    qs("pqBuyForm").addEventListener("submit", onPay);
  }

  function closeDrawer() {
    qs("pqDrawerBg").hidden = true;
    qs("pqDrawer").hidden = true;
  }

  async function onPay(ev) {
    ev.preventDefault();
    var err = qs("pqBuyErr");
    var btn = qs("pqPayBtn");
    err.textContent = "";
    var email = (qs("pqEmail").value || "").trim();
    var name = (qs("pqName").value || "").trim();
    if (!email) {
      err.textContent = "Enter your email.";
      return;
    }
    btn.disabled = true;
    btn.textContent = "Redirecting to Paystack…";
    try {
      var data = await api("/api/v1/payments/paystack/guest/past-question/initialize", {
        method: "POST",
        body: JSON.stringify({
          book_id: state.selected.id,
          email: email,
          full_name: name || null,
        }),
      });
      if (data.reference) {
        try {
          sessionStorage.setItem("sia_pq_pending", JSON.stringify({
            reference: data.reference,
            book_id: state.selected.id,
            email: email,
          }));
        } catch (e) { /* ignore */ }
      }
      if (!data.authorization_url) throw new Error("No Paystack checkout URL returned");
      location.href = data.authorization_url;
    } catch (e) {
      err.textContent = e.message || "Payment could not start";
      btn.disabled = false;
      btn.textContent = "Pay with Paystack";
    }
  }

  async function resumePending() {
    var params = new URLSearchParams(location.search);
    var reference = params.get("reference") || params.get("trxref");
    var pending = null;
    try { pending = JSON.parse(sessionStorage.getItem("sia_pq_pending") || "null"); } catch (e) {}
    if (!reference && pending) reference = pending.reference;
    if (!reference) return;

    var grid = qs("pqGrid");
    if (grid) grid.insertAdjacentHTML("beforebegin",
      '<div class="pq-success" id="pqVerifyBox">Verifying payment…</div>');
    try {
      var result = await api("/api/v1/payments/paystack/guest/past-question/verify", {
        method: "POST",
        body: JSON.stringify({ reference: reference }),
      });
      try { sessionStorage.removeItem("sia_pq_pending"); } catch (e) {}
      var box = qs("pqVerifyBox");
      if (!box) return;
      if (result.paid && result.access_token) {
        var url = API + (result.download_path || ("/api/v1/past-questions/download/" + result.access_token));
        box.innerHTML = "<strong>Payment successful.</strong> Your PDF is unlocked." +
          '<div style="margin-top:0.75rem"><a class="pq-buy" style="display:inline-block;text-decoration:none;padding:0.65rem 1rem" href="' +
          url + '">Download PDF</a></div>' +
          "<p style=\"margin-top:0.75rem;font-size:0.9rem\">Save this link — it works with the email you paid with.</p>";
      } else {
        box.innerHTML = "Payment recorded, but download token was not ready. Refresh in a moment.";
      }
      history.replaceState({}, "", location.pathname);
    } catch (e) {
      var box2 = qs("pqVerifyBox");
      if (box2) box2.innerHTML = "Could not verify payment: " + escapeHtml(e.message);
    }
  }

  async function boot() {
    qs("pqDrawerClose").addEventListener("click", closeDrawer);
    qs("pqDrawerBg").addEventListener("click", closeDrawer);
    qs("pqSearch").addEventListener("input", function () {
      state.search = qs("pqSearch").value || "";
      renderGrid();
    });
    try {
      var data = await api("/api/v1/past-questions/catalog");
      state.products = (data && data.products) || [];
      render();
    } catch (e) {
      qs("pqGrid").innerHTML = '<div class="mkt-empty">' + escapeHtml(e.message) + "</div>";
    }
    resumePending();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
