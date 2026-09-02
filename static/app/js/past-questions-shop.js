(function () {
  var API = (window.SCHOLAXIA_API_BASE || "").replace(/\/$/, "");
  var state = {
    products: [],
    exam: "ALL",
    subject: "",
    year: "",
    search: "",
    sort: "latest",
    selected: null,
    loadError: null,
  };

  function money(n) {
    return "₦" + Number(n || 0).toLocaleString("en-NG");
  }

  function qs(id) {
    return document.getElementById(id);
  }

  function escapeHtml(s) {
    return String(s || "")
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  function examLabel(ex) {
    if (ex === "COMMON_ENTRANCE") return "Common Entrance";
    if (ex === "ALL") return "All";
    return ex || "Exam";
  }

  async function api(path, opts) {
    var res = await fetch(
      API + path,
      Object.assign(
        {
          headers: { "Content-Type": "application/json", Accept: "application/json" },
        },
        opts || {}
      )
    );
    var data = null;
    try {
      data = await res.json();
    } catch (e) {
      data = null;
    }
    if (!res.ok) {
      var msg = (data && (data.detail || data.message)) || ("Request failed (" + res.status + ")");
      if (typeof msg !== "string") msg = JSON.stringify(msg);
      var err = new Error(msg);
      err.status = res.status;
      throw err;
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

  function uniqueYears(list) {
    var set = {};
    list.forEach(function (p) {
      if (p.year) set[String(p.year)] = true;
    });
    return Object.keys(set).sort(function (a, b) {
      return Number(b) - Number(a);
    });
  }

  function poolForFilters() {
    return state.products.filter(function (p) {
      if (state.exam !== "ALL" && String(p.exam_type || "").toUpperCase() !== state.exam) return false;
      return true;
    });
  }

  function filtered() {
    var rows = state.products.filter(function (p) {
      if (state.exam !== "ALL" && String(p.exam_type || "").toUpperCase() !== state.exam) return false;
      if (state.subject && p.subject !== state.subject) return false;
      if (state.year && String(p.year || "") !== String(state.year)) return false;
      if (state.search) {
        var hay = [p.title, p.subject, p.exam_type, p.year, p.description].join(" ").toLowerCase();
        if (hay.indexOf(state.search.toLowerCase()) < 0) return false;
      }
      return true;
    });
    var sort = state.sort || "latest";
    rows = rows.slice();
    if (sort === "price-asc") {
      rows.sort(function (a, b) { return Number(a.price || 0) - Number(b.price || 0); });
    } else if (sort === "price-desc") {
      rows.sort(function (a, b) { return Number(b.price || 0) - Number(a.price || 0); });
    } else if (sort === "title") {
      rows.sort(function (a, b) {
        return String(a.title || "").localeCompare(String(b.title || ""));
      });
    } else {
      rows.sort(function (a, b) {
        return Number(b.year || 0) - Number(a.year || 0);
      });
    }
    return rows;
  }

  function shortDesc(p) {
    var d = (p.description || "").trim();
    if (d) return d;
    var exam = examLabel(String(p.exam_type || "").toUpperCase());
    var year = p.year ? " " + p.year : "";
    return exam + year + " past questions PDF for " + (p.subject || "this subject") + ".";
  }

  function coverHtml(p) {
    var exam = String(p.exam_type || "EXAM").toUpperCase();
    var subject = (p.subject || "Subject").toUpperCase();
    var year = p.year ? String(p.year) : "PDF";
    if (p.cover_image_url) {
      return (
        '<div class="pq-cover">' +
        '<img class="pq-cover-img" src="' +
        escapeHtml(p.cover_image_url) +
        '" alt="" loading="lazy" />' +
        '<span class="pq-cover-badge">' +
        escapeHtml(examLabel(exam)) +
        "</span>" +
        "</div>"
      );
    }
    return (
      '<div class="pq-cover">' +
      '<span class="pq-cover-badge">' +
      escapeHtml(examLabel(exam)) +
      "</span>" +
      '<div class="pq-cover-main">' +
      "<strong>" +
      escapeHtml(subject) +
      "</strong>" +
      "<span>" +
      escapeHtml(year) +
      " Past Questions</span>" +
      "</div>" +
      '<div class="pq-cover-foot"><span>SCHOLAXIA</span><span class="pq-cover-icon">PDF</span></div>' +
      "</div>"
    );
  }

  function renderCats() {
    var tabs = qs("pqExamTabs");
    if (!tabs) return;
    var exams = ["ALL", "JAMB", "WAEC", "NECO", "COMMON_ENTRANCE"];
    tabs.innerHTML = exams
      .map(function (ex) {
        return (
          '<button type="button" class="pq-cat' +
          (state.exam === ex ? " is-active" : "") +
          '" data-exam="' +
          ex +
          '" role="tab" aria-selected="' +
          (state.exam === ex ? "true" : "false") +
          '">' +
          examLabel(ex) +
          "</button>"
        );
      })
      .join("");
    tabs.querySelectorAll("button").forEach(function (btn) {
      btn.addEventListener("click", function () {
        state.exam = btn.getAttribute("data-exam") || "ALL";
        state.subject = "";
        state.year = "";
        syncFilterControls();
        render();
      });
    });
  }

  function syncFilterControls() {
    var examSel = qs("pqFilterExam");
    var subSel = qs("pqFilterSubject");
    var yearSel = qs("pqFilterYear");
    if (examSel) examSel.value = state.exam || "ALL";

    var pool = poolForFilters();
    var subjects = uniqueSubjects(pool);
    var years = uniqueYears(pool);

    if (subSel) {
      subSel.innerHTML =
        '<option value="">All subjects</option>' +
        subjects
          .map(function (s) {
            return (
              '<option value="' +
              escapeHtml(s) +
              '"' +
              (state.subject === s ? " selected" : "") +
              ">" +
              escapeHtml(s) +
              "</option>"
            );
          })
          .join("");
    }
    if (yearSel) {
      yearSel.innerHTML =
        '<option value="">All years</option>' +
        years
          .map(function (y) {
            return (
              '<option value="' +
              escapeHtml(y) +
              '"' +
              (String(state.year) === String(y) ? " selected" : "") +
              ">" +
              escapeHtml(y) +
              "</option>"
            );
          })
          .join("");
    }
  }

  function renderCount(rows) {
    var el = qs("pqResultCount");
    if (!el) return;
    if (state.loadError) {
      el.textContent = "Could not load the catalog.";
      return;
    }
    var n = rows.length;
    el.textContent = n === 1 ? "1 paper available" : n + " papers available";
  }

  function renderGrid() {
    var grid = qs("pqGrid");
    if (!grid) return;

    if (state.loadError) {
      grid.innerHTML =
        '<div class="pq-error">' +
        '<div class="pq-error-icon" aria-hidden="true">!</div>' +
        "<h3>Unable to load past questions</h3>" +
        "<p>Please try again in a moment.</p>" +
        '<button type="button" class="pq-retry" id="pqRetryBtn">Try Again</button>' +
        "</div>";
      var retry = qs("pqRetryBtn");
      if (retry) retry.addEventListener("click", loadCatalog);
      return;
    }

    var rows = filtered();
    renderCount(rows);

    if (!rows.length) {
      grid.innerHTML =
        '<div class="pq-empty">' +
        '<div class="pq-empty-icon" aria-hidden="true">📚</div>' +
        "<h3>No past questions available yet</h3>" +
        "<p>New JAMB, WAEC, NECO and Common Entrance papers will appear here.</p>" +
        "</div>";
      return;
    }

    grid.innerHTML = rows
      .map(function (p) {
        return (
          '<article class="pq-card">' +
          coverHtml(p) +
          '<div class="pq-card-body">' +
          "<h3>" +
          escapeHtml(p.title || p.subject || "Past Questions") +
          "</h3>" +
          '<div class="pq-card-meta">' +
          escapeHtml(examLabel(String(p.exam_type || "").toUpperCase())) +
          (p.year ? " · " + escapeHtml(String(p.year)) : "") +
          (p.subject ? " · " + escapeHtml(p.subject) : "") +
          "</div>" +
          '<p class="pq-card-desc">' +
          escapeHtml(shortDesc(p)) +
          "</p>" +
          '<div class="pq-card-foot">' +
          '<div class="pq-price">' +
          money(p.price) +
          "</div>" +
          '<button type="button" class="pq-buy" data-id="' +
          escapeHtml(p.id) +
          '">Buy Now →</button>' +
          "</div></div></article>"
        );
      })
      .join("");

    grid.querySelectorAll(".pq-buy").forEach(function (btn) {
      btn.addEventListener("click", function () {
        openBuy(btn.getAttribute("data-id"));
      });
    });
  }

  function render() {
    renderCats();
    syncFilterControls();
    renderGrid();
  }

  function openBuy(id) {
    var product = state.products.find(function (p) {
      return p.id === id;
    });
    if (!product) return;
    state.selected = product;
    var bg = qs("pqDrawerBg");
    var drawer = qs("pqDrawer");
    var body = qs("pqDrawerBody");
    body.innerHTML =
      coverHtml(product) +
      "<h2>" +
      escapeHtml(product.title) +
      "</h2>" +
      '<p class="pq-meta">' +
      escapeHtml(examLabel(String(product.exam_type || "").toUpperCase())) +
      " · " +
      escapeHtml(product.subject || "") +
      (product.year ? " · " + escapeHtml(String(product.year)) : "") +
      "</p>" +
      "<p>" +
      escapeHtml(shortDesc(product)) +
      "</p>" +
      '<p class="pq-price" style="margin:0.85rem 0">' +
      money(product.price) +
      "</p>" +
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
    document.body.style.overflow = "hidden";
    qs("pqBuyForm").addEventListener("submit", onPay);
  }

  function closeDrawer() {
    qs("pqDrawerBg").hidden = true;
    qs("pqDrawer").hidden = true;
    document.body.style.overflow = "";
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
          sessionStorage.setItem(
            "sia_pq_pending",
            JSON.stringify({
              reference: data.reference,
              book_id: state.selected.id,
              email: email,
            })
          );
        } catch (e) {
          /* ignore */
        }
      }
      if (!data.authorization_url) throw new Error("No Paystack checkout URL returned");
      location.href = data.authorization_url;
    } catch (e) {
      console.error("[past-questions] payment init failed", e);
      err.textContent = "Payment could not start. Please try again.";
      btn.disabled = false;
      btn.textContent = "Pay with Paystack";
    }
  }

  async function resumePending() {
    var params = new URLSearchParams(location.search);
    var reference = params.get("reference") || params.get("trxref");
    var pending = null;
    try {
      pending = JSON.parse(sessionStorage.getItem("sia_pq_pending") || "null");
    } catch (e) {}
    if (!reference && pending) reference = pending.reference;
    if (!reference) return;

    var mount = qs("pqVerifyMount");
    if (!mount) return;
    mount.innerHTML = '<div class="pq-success" id="pqVerifyBox">Verifying payment…</div>';
    try {
      var result = await api("/api/v1/payments/paystack/guest/past-question/verify", {
        method: "POST",
        body: JSON.stringify({ reference: reference }),
      });
      try {
        sessionStorage.removeItem("sia_pq_pending");
      } catch (e) {}
      var box = qs("pqVerifyBox");
      if (!box) return;
      if (result.paid && result.access_token) {
        var url =
          API + (result.download_path || "/api/v1/past-questions/download/" + result.access_token);
        box.innerHTML =
          "<strong>Payment successful.</strong> Your PDF is unlocked." +
          '<div style="margin-top:0.75rem"><a class="pq-buy" style="display:inline-block;text-decoration:none;padding:0.65rem 1rem" href="' +
          url +
          '">Download PDF</a></div>' +
          '<p style="margin-top:0.75rem;font-size:0.9rem">Save this link — it works with the email you paid with.</p>';
      } else {
        box.innerHTML = "Payment recorded, but download token was not ready. Refresh in a moment.";
      }
      history.replaceState({}, "", location.pathname);
    } catch (e) {
      console.error("[past-questions] verify failed", e);
      var box2 = qs("pqVerifyBox");
      if (box2) {
        box2.innerHTML =
          "<strong>Unable to verify payment.</strong> If you were charged, use the same email to recover access or contact support.";
      }
    }
  }

  async function loadCatalog() {
    var grid = qs("pqGrid");
    if (grid) grid.innerHTML = '<div class="pq-loading">Loading past questions…</div>';
    state.loadError = null;
    try {
      var data = await api("/api/v1/past-questions/catalog");
      state.products = (data && data.products) || [];
      render();
    } catch (e) {
      console.error("[past-questions] catalog failed", e);
      state.loadError = e;
      state.products = [];
      render();
    }
  }

  function bindFilters() {
    var examSel = qs("pqFilterExam");
    var subSel = qs("pqFilterSubject");
    var yearSel = qs("pqFilterYear");
    var sortSel = qs("pqFilterSort");
    var search = qs("pqSearch");
    var form = qs("pqHeroSearchForm");

    if (examSel) {
      examSel.addEventListener("change", function () {
        state.exam = examSel.value || "ALL";
        state.subject = "";
        state.year = "";
        render();
      });
    }
    if (subSel) {
      subSel.addEventListener("change", function () {
        state.subject = subSel.value || "";
        renderGrid();
        syncFilterControls();
      });
    }
    if (yearSel) {
      yearSel.addEventListener("change", function () {
        state.year = yearSel.value || "";
        renderGrid();
      });
    }
    if (sortSel) {
      sortSel.addEventListener("change", function () {
        state.sort = sortSel.value || "latest";
        renderGrid();
      });
    }
    if (search) {
      search.addEventListener("input", function () {
        state.search = search.value || "";
        renderGrid();
      });
    }
    if (form) {
      form.addEventListener("submit", function (ev) {
        ev.preventDefault();
        state.search = (search && search.value) || "";
        var shelf = qs("shelf");
        if (shelf) shelf.scrollIntoView({ behavior: "smooth", block: "start" });
        renderGrid();
      });
    }
  }

  function bindNav() {
    var toggle = qs("pqNavToggle");
    var links = qs("pqNavLinks");
    if (!toggle || !links) return;
    toggle.addEventListener("click", function () {
      var open = links.classList.toggle("is-open");
      toggle.setAttribute("aria-expanded", open ? "true" : "false");
    });
  }

  async function boot() {
    qs("pqDrawerClose").addEventListener("click", closeDrawer);
    qs("pqDrawerBg").addEventListener("click", closeDrawer);
    bindFilters();
    bindNav();
    await loadCatalog();
    resumePending();
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", boot);
  else boot();
})();
