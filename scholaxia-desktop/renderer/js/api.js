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
  return localStorage.getItem("sia_token") || localStorage.getItem("sia_teacher_token") || localStorage.getItem("sia_admin_token") || "";
}

function isStudentLoggedIn() {
  return !!localStorage.getItem("sia_token");
}

var PUBLIC_APP_PAGES = ["dashboard", "school-portal", "marketplace"];

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

function handleApiUnauthorized() {
  var hadSession = !!localStorage.getItem("sia_token");
  clearSession();
  if (!hadSession) return;
  if (isClassroomPage()) {
    clearLiveSession();
    alert("Your session expired. Please sign in again.");
    window.location.href = "index.html";
    return;
  }
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
      signal: options.signal || fetchTimeout(45000),
    });
  } catch (ex) {
    if (ex.name === "AbortError" || ex.name === "TimeoutError") {
      throw new Error("Request timed out. The server may be waking up — try again.");
    }
    throw new Error(ex.message || "Network error. Check your connection.");
  }
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    handleApiUnauthorized();
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Request failed (" + res.status + ")");
  return data;
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
    handleApiUnauthorized();
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
