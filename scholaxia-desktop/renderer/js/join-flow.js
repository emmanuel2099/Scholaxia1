/**
 * Google Meet-style join flow: shareable links, join codes, auto-join after login.
 */
(function () {
  var PENDING_KEY = "sia_pending_join";

  function appBasePath() {
    var path = window.location.pathname || "";
    if (path.indexOf("/") >= 0) {
      return path.replace(/[^/]+$/, "");
    }
    return "";
  }

  function buildJoinUrl(opts) {
    var base = window.location.origin + appBasePath();
    if (opts && opts.code) {
      return base + "join.html?code=" + encodeURIComponent(String(opts.code).trim().toUpperCase());
    }
    if (opts && opts.class_id) {
      return base + "join.html?class=" + encodeURIComponent(opts.class_id);
    }
    return base + "join.html";
  }

  function savePendingJoin(opts) {
    try {
      sessionStorage.setItem(PENDING_KEY, JSON.stringify({
        class_id: (opts && opts.class_id) || null,
        code: (opts && opts.code) ? String(opts.code).trim().toUpperCase() : null,
      }));
    } catch (e) { /* ignore */ }
  }

  function consumePendingJoin() {
    try {
      var raw = sessionStorage.getItem(PENDING_KEY);
      sessionStorage.removeItem(PENDING_KEY);
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }

  function parseJoinParams(search) {
    var params = new URLSearchParams(search || window.location.search);
    return {
      class_id: params.get("class") || params.get("join") || "",
      code: params.get("code") || "",
    };
  }

  function loginUrlForJoin(opts) {
    var q = [];
    if (opts.code) q.push("code=" + encodeURIComponent(opts.code));
    else if (opts.class_id) q.push("class=" + encodeURIComponent(opts.class_id));
    return "index.html" + (q.length ? "?" + q.join("&") : "");
  }

  async function fetchJoinPreview(opts) {
    var q = "";
    if (opts.code) q = "?code=" + encodeURIComponent(String(opts.code).trim().toUpperCase());
    else if (opts.class_id) q = "?class_id=" + encodeURIComponent(opts.class_id);
    else throw new Error("Missing join code or class link.");

    var data = await api("/api/v1/live-classes/join-preview" + q);
    if (!data || !data.id) throw new Error("Class not found. Check the link from your teacher.");
    return data;
  }

  async function joinClassFromPreview(preview, card) {
    if (!preview || !preview.id) throw new Error("Class not found.");
    if (!preview.is_joinable) {
      throw new Error("This class is not live yet. Wait for your teacher to start, then try again.");
    }
    if (typeof joinClassWithPayment !== "function") {
      throw new Error("Join is not available on this page.");
    }
    var fakeBtn = card || { dataset: {
      id: preview.id,
      title: preview.title || "",
      subject: preview.subject || "",
      teacher: preview.teacher_name || "",
      end: preview.end_time || "",
    }};
    await joinClassWithPayment(fakeBtn);
  }

  function redirectToJoinLanding(opts) {
    if (opts.code) {
      window.location.href = "join.html?code=" + encodeURIComponent(String(opts.code).trim().toUpperCase());
      return;
    }
    if (opts.class_id) {
      window.location.href = "join.html?class=" + encodeURIComponent(opts.class_id);
      return;
    }
    window.location.href = "join.html";
  }

  function handleJoinCodeInput(inputEl, errEl) {
    var raw = (inputEl && inputEl.value || "").trim();
    if (!raw) {
      if (errEl) errEl.textContent = "Enter the class code from your teacher.";
      return;
    }
    if (errEl) errEl.textContent = "";
    var opts = parseJoinInput(raw);
    if (!opts) {
      if (errEl) errEl.textContent = "Enter a valid class code or link.";
      return;
    }
    redirectToJoinLanding(opts);
  }

  function parseJoinInput(raw) {
    raw = (raw || "").trim();
    if (!raw) return null;
    try {
      if (/^https?:\/\//i.test(raw) || raw.indexOf("join.html") >= 0) {
        var u = new URL(raw, window.location.origin);
        var code = u.searchParams.get("code");
        var cls = u.searchParams.get("class") || u.searchParams.get("join");
        if (code) return { code: code.toUpperCase() };
        if (cls) return { class_id: cls };
      }
    } catch (e) { /* fall through */ }
    if (/^sx-/i.test(raw)) return { code: raw.toUpperCase() };
    if (/^[0-9a-f-]{36}$/i.test(raw)) return { class_id: raw };
    return { code: raw.toUpperCase() };
  }

  window.buildJoinUrl = buildJoinUrl;
  window.savePendingJoin = savePendingJoin;
  window.consumePendingJoin = consumePendingJoin;
  window.parseJoinParams = parseJoinParams;
  window.loginUrlForJoin = loginUrlForJoin;
  window.fetchJoinPreview = fetchJoinPreview;
  window.joinClassFromPreview = joinClassFromPreview;
  window.redirectToJoinLanding = redirectToJoinLanding;
  window.handleJoinCodeInput = handleJoinCodeInput;
  window.parseJoinInput = parseJoinInput;
})();
