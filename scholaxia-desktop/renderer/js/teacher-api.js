function scholaxiaApiBase() {
  var host = window.location.hostname;
  if (host === "127.0.0.1" || host === "localhost") {
    return window.location.origin + "/api-proxy";
  }
  return "https://scholaxia1.onrender.com";
}

var API_BASE = (typeof window !== "undefined" && window.API_BASE)
  ? window.API_BASE
  : scholaxiaApiBase();

function getTeacherToken() {
  return localStorage.getItem("sia_teacher_token") || "";
}

function getTeacherUser() {
  return {
    name: localStorage.getItem("sia_teacher_name") || "Teacher",
    email: localStorage.getItem("sia_teacher_email") || "",
    subjects: JSON.parse(localStorage.getItem("sia_teacher_subjects") || "[]"),
  };
}

function saveTeacherSession(data, email, nameOverride) {
  localStorage.setItem("sia_teacher_token", data.access_token);
  if (email) localStorage.setItem("sia_teacher_email", email);
  if (nameOverride) localStorage.setItem("sia_teacher_name", nameOverride);
  if (data.user && data.user.full_name) localStorage.setItem("sia_teacher_name", data.user.full_name);
}

function clearTeacherSession() {
  ["sia_teacher_token", "sia_teacher_name", "sia_teacher_email", "sia_teacher_subjects"].forEach(function (k) {
    localStorage.removeItem(k);
  });
}

function teacherFetchTimeout(ms) {
  var controller = new AbortController();
  setTimeout(function () { controller.abort(); }, ms || 90000);
  return controller.signal;
}

async function teacherApi(path, options) {
  options = options || {};
  var res;
  try {
    res = await fetch(API_BASE + path, {
      method: options.method || "GET",
      headers: Object.assign(
        { "Content-Type": "application/json", Authorization: "Bearer " + getTeacherToken() },
        options.headers || {}
      ),
      body: options.body,
      signal: options.signal || teacherFetchTimeout(options.timeout || 90000),
    });
  } catch (e) {
    if (e && e.name === "AbortError") throw new Error("Request timed out. Check your connection and try again.");
    throw e;
  }
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    clearTeacherSession();
    window.location.reload();
    return null;
  }
  if (!res.ok) {
    var detail = data.detail;
    if (Array.isArray(detail)) detail = detail.map(function (d) { return d.msg || d; }).join(", ");
    throw new Error(detail || data.message || "Request failed");
  }
  return data;
}

async function teacherApiUpload(path, file) {
  var form = new FormData();
  form.append("file", file);
  var res;
  try {
    res = await fetch(API_BASE + path, {
      method: "POST",
      headers: { Authorization: "Bearer " + getTeacherToken() },
      body: form,
      signal: teacherFetchTimeout(120000),
    });
  } catch (e) {
    if (e && e.name === "AbortError") throw new Error("Upload timed out. Try a smaller file.");
    throw e;
  }
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    clearTeacherSession();
    window.location.reload();
    return null;
  }
  if (!res.ok) throw new Error(data.detail || "Upload failed");
  return data;
}

function escHtml(s) {
  return String(s || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

function formatDateTime(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString(undefined, {
    weekday: "short", month: "short", day: "numeric", hour: "2-digit", minute: "2-digit",
  });
}
