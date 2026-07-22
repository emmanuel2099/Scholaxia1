function scholaxiaApiBase() {
  var host = window.location.hostname;
  if (host === "127.0.0.1" || host === "localhost") {
    return window.location.origin + "/api-proxy";
  }
  return "https://scholaxia1.onrender.com";
}

var API_BASE = scholaxiaApiBase();
if (typeof window !== "undefined") window.API_BASE = API_BASE;

function getToken() {
  if (typeof isClassroomPage === "function" && isClassroomPage()) {
    var teacherTok = localStorage.getItem("sia_teacher_token") || "";
    var adminTok = localStorage.getItem("sia_admin_token") || "";
    var studentTok = localStorage.getItem("sia_token") || "";
    try {
      var sess = typeof loadLiveSessionData === "function" ? loadLiveSessionData() : null;
      if (sess && (sess.role === "teacher" || sess.role === "admin")) {
        return teacherTok || adminTok || studentTok;
      }
    } catch (e) { /* ignore */ }
    return studentTok || teacherTok || adminTok;
  }
  return localStorage.getItem("sia_token") || localStorage.getItem("sia_teacher_token") || localStorage.getItem("sia_admin_token") || "";
}

function isStudentLoggedIn() {
  return !!localStorage.getItem("sia_token");
}

var PUBLIC_APP_PAGES = ["dashboard", "school-portal", "marketplace", "study-materials", "past-questions", "about", "contact"];

function isPagePublic(page) {
  return PUBLIC_APP_PAGES.indexOf(page) >= 0;
}

function goToLogin(returnPage) {
  var page = returnPage || sessionStorage.getItem("sia_current_page") || "dashboard";
  if (page && !isPagePublic(page)) {
    sessionStorage.setItem("sia_login_return", page);
  }
  window.location.href = "index.html" + (page && !isPagePublic(page) ? "?return=" + encodeURIComponent(page) : "");
}

if (typeof window !== "undefined") {
  window.SCHOLAXIA_MODE = "student";
  window.isStudentLoggedIn = isStudentLoggedIn;
  window.isPagePublic = isPagePublic;
  window.goToLogin = goToLogin;
  window.PUBLIC_APP_PAGES = PUBLIC_APP_PAGES;
}

function getUser() {
  return {
    name: localStorage.getItem("sia_name") || "Student",
    email: localStorage.getItem("sia_email") || "",
    role: localStorage.getItem("sia_role") || "student",
    examType: localStorage.getItem("sia_exam_type") || "",
    subjects: JSON.parse(localStorage.getItem("sia_subjects") || "[]"),
  };
}

function saveSession(data, email, nameOverride) {
  localStorage.setItem("sia_token", data.access_token);
  localStorage.setItem("sia_role", data.role || "student");
  if (email) localStorage.setItem("sia_email", email);
  if (nameOverride) localStorage.setItem("sia_name", nameOverride);
  if (data.user && data.user.full_name) localStorage.setItem("sia_name", data.user.full_name);
}

function clearSession() {
  ["sia_token", "sia_role", "sia_name", "sia_email", "sia_exam_type", "sia_subjects", "sia_fcm_token", "sia_last_notif_id"].forEach(function (k) {
    localStorage.removeItem(k);
  });
}

function parseUtcIso(iso) {
  if (!iso) return null;
  var s = String(iso).trim();
  if (!s) return null;
  if (!/[zZ]|[+-]\d{2}:?\d{2}$/.test(s)) s += "Z";
  var d = new Date(s);
  return isNaN(d.getTime()) ? null : d;
}

function normalizeLiveEndTime(endTime, isLive) {
  if (!endTime) return null;
  var endAt = parseUtcIso(endTime);
  if (!endAt) return null;
  if (endAt.getTime() <= Date.now() && isLive !== false) return null;
  return endTime;
}

function persistLiveSession(sess) {
  if (!sess) return;
  var json = JSON.stringify(sess);
  localStorage.setItem("live_session", json);
  sessionStorage.setItem("live_session", json);
}

function loadLiveSessionData() {
  try {
    var raw = localStorage.getItem("live_session") || sessionStorage.getItem("live_session");
    return JSON.parse(raw || "null");
  } catch (e) {
    return null;
  }
}

function clearLiveSession() {
  localStorage.removeItem("live_session");
  sessionStorage.removeItem("live_session");
}

function isClassroomPage() {
  try {
    var path = window.location.pathname || "";
    var href = window.location.href || "";
    return /classroom\.html/i.test(path) || /classroom\.html/i.test(href);
  } catch (e) {
    return false;
  }
}

function handleApiUnauthorized(detail) {
  var hadSession = !!localStorage.getItem("sia_token");
  clearSession();
  if (!hadSession) return;
  var msg = (detail && String(detail)) || "Your session expired. Please sign in again.";
  if (/another device|logged in elsewhere|session/i.test(msg)) {
    msg = "You signed in on another device. This session was signed out.";
  }
  if (isClassroomPage()) {
    clearLiveSession();
    alert(msg);
    window.location.href = "index.html";
    return;
  }
  alert(msg);
  if (typeof goToLogin === "function") {
    goToLogin(sessionStorage.getItem("sia_current_page"));
  } else {
    window.location.href = "index.html";
  }
}

if (typeof window !== "undefined") {
  window.parseUtcIso = parseUtcIso;
  window.normalizeLiveEndTime = normalizeLiveEndTime;
  window.persistLiveSession = persistLiveSession;
  window.loadLiveSessionData = loadLiveSessionData;
  window.clearLiveSession = clearLiveSession;
}

function fetchTimeout(ms) {
  if (typeof AbortSignal !== "undefined" && AbortSignal.timeout) {
    return AbortSignal.timeout(ms);
  }
  var ctrl = new AbortController();
  setTimeout(function () { ctrl.abort(); }, ms);
  return ctrl.signal;
}

var _apiWarmPromise = null;
function warmScholaxiaApi() {
  if (_apiWarmPromise) return _apiWarmPromise;
  _apiWarmPromise = fetch(API_BASE + "/health", { signal: fetchTimeout(90000) })
    .catch(function () { _apiWarmPromise = null; });
  return _apiWarmPromise;
}

async function api(path, options) {
  options = options || {};
  var res;
  try {
    res = await fetch(API_BASE + path, {
      method: options.method || "GET",
      headers: Object.assign(
        { "Content-Type": "application/json", Authorization: "Bearer " + getToken() },
        options.headers || {}
      ),
      body: options.body,
      signal: options.signal || fetchTimeout(options.timeoutMs || 45000),
    });
  } catch (ex) {
    setOfflineBanner(true);
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      throw new Error("There is no internet on your data.");
    }
    if (ex.name === "AbortError" || ex.name === "TimeoutError") {
      throw new Error("There is no internet on your data.");
    }
    var netMsg = ex.message || "Network error";
    if (/failed to fetch/i.test(netMsg)) {
      throw new Error("There is no internet on your data.");
    }
    throw new Error(netMsg + ". Check your connection.");
  }
  setOfflineBanner(false);
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    handleApiUnauthorized(formatApiError(data.detail) || data.detail);
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Request failed (" + res.status + ")");
  return data;
}

function setOfflineBanner(offline) {
  var el = document.getElementById("sx-offline-banner");
  if (!el) {
    el = document.createElement("div");
    el.id = "sx-offline-banner";
    el.style.cssText =
      "display:none;position:fixed;top:0;left:0;right:0;z-index:9999;background:#F59E0B;color:#000;text-align:center;padding:6px 12px;font-size:12px;font-weight:700";
    el.textContent = "Offline — showing saved information";
    document.body.appendChild(el);
  }
  // Only show inside student/kid shells when logged in
  var role = localStorage.getItem("sia_role") || "";
  var show = !!offline && !!getToken() && (role === "student" || role === "kind");
  el.style.display = show ? "block" : "none";
}

window.setOfflineBanner = setOfflineBanner;

function networkErrorMessage(err) {
  if (typeof navigator !== "undefined" && !navigator.onLine) {
    return "There is no internet on your data.";
  }
  var msg = (err && err.message) || "";
  if (/failed to fetch|timed out|network error|no internet/i.test(msg)) {
    return "There is no internet on your data.";
  }
  return msg || "Something went wrong.";
}

/** Retry API calls — helps when Render wakes from sleep. */
async function apiRetry(path, options) {
  options = options || {};
  var attempts = options.attempts || 3;
  var baseDelay = options.retryDelay || 1000;
  if (!options.skipWarm) await warmScholaxiaApi().catch(function () {});
  var lastErr;
  for (var i = 0; i < attempts; i++) {
    try {
      return await api(path, options);
    } catch (e) {
      lastErr = e;
      var retryable = /failed to fetch|timed out|network|waking up/i.test(e.message || "");
      if (!retryable || i >= attempts - 1) throw e;
      await new Promise(function (r) { setTimeout(r, baseDelay * (i + 1)); });
      _apiWarmPromise = null;
      await warmScholaxiaApi().catch(function () {});
    }
  }
  throw lastErr;
}

if (typeof window !== "undefined") {
  window.apiRetry = apiRetry;
  window.warmScholaxiaApi = warmScholaxiaApi;
  window.networkErrorMessage = networkErrorMessage;
}

async function apiUpload(path, file) {
  var form = new FormData();
  form.append("file", file);
  var res;
  try {
    res = await fetch(API_BASE + path, {
      method: "POST",
      headers: { Authorization: "Bearer " + getToken() },
      body: form,
      signal: fetchTimeout(60000),
    });
  } catch (ex) {
    if (ex.name === "AbortError" || ex.name === "TimeoutError") {
      throw new Error("Upload timed out. Try again.");
    }
    throw new Error(ex.message || "Network error. Check your connection.");
  }
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    handleApiUnauthorized(formatApiError(data.detail) || data.detail);
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Upload failed (" + res.status + ")");
  return data;
}

function formatApiError(detail) {
  if (!detail) return "";
  if (typeof detail === "string") return detail;
  if (Array.isArray(detail)) {
    return detail.map(function (d) {
      if (typeof d === "string") return d;
      if (d && d.msg) return d.msg;
      return JSON.stringify(d);
    }).join("; ");
  }
  if (detail.msg) return detail.msg;
  try { return JSON.stringify(detail); } catch (e) { return String(detail); }
}

function escHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function firstName(name) {
  return (name || "Student").split(" ")[0];
}

function formatDate(iso) {
  if (!iso) return "—";
  var d = new Date(iso);
  return d.toLocaleString(undefined, {
    weekday: "short", month: "short", day: "numeric",
    hour: "2-digit", minute: "2-digit",
  });
}
