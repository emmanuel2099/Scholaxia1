const API_BASE = "https://scholaxia1.onrender.com";

function getToken() {
  return localStorage.getItem("sia_token") || "";
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
  ["sia_token", "sia_role", "sia_name", "sia_email", "sia_exam_type", "sia_subjects"].forEach(function (k) {
    localStorage.removeItem(k);
  });
}

function fetchTimeout(ms) {
  if (typeof AbortSignal !== "undefined" && AbortSignal.timeout) {
    return AbortSignal.timeout(ms);
  }
  var ctrl = new AbortController();
  setTimeout(function () { ctrl.abort(); }, ms);
  return ctrl.signal;
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
    clearSession();
    window.location.href = "index.html";
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Request failed (" + res.status + ")");
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
