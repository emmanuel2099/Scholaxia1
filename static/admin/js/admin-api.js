var API_BASE = (function () {
  try {
    if (typeof location !== "undefined" && location.protocol && location.protocol.indexOf("http") === 0) {
      var host = String(location.hostname || "").toLowerCase();
      if (host === "scholaxia1.onrender.com" || host === "localhost" || host === "127.0.0.1") {
        return location.origin;
      }
    }
  } catch (e) { /* fall through */ }
  return "https://scholaxia1.onrender.com";
})();

function adminHomeUrl() {
  try {
    if (typeof location !== "undefined" && location.pathname.indexOf("/admin") === 0) {
      return "/admin/";
    }
  } catch (e) { /* fall through */ }
  if (typeof location !== "undefined" && /index\.html$/i.test(location.pathname)) {
    return "index.html";
  }
  return "admin.html";
}

function getAdminToken() {
  return localStorage.getItem("sia_admin_token") || "";
}

function getAdminUser() {
  return {
    name: localStorage.getItem("sia_admin_name") || "Admin",
    email: localStorage.getItem("sia_admin_email") || "",
  };
}

function saveAdminSession(data, email, name) {
  if (!data || !data.access_token) {
    throw new Error("Login response missing access token.");
  }
  localStorage.setItem("sia_admin_token", data.access_token);
  localStorage.setItem("sia_admin_role", data.role || "admin");
  if (email) localStorage.setItem("sia_admin_email", email);
  if (name) localStorage.setItem("sia_admin_name", name);
}

function clearAdminSession() {
  ["sia_admin_token", "sia_admin_role", "sia_admin_name", "sia_admin_email", "sia_school_id", "sia_school_name"].forEach(function (k) {
    localStorage.removeItem(k);
  });
}

function kickAdminToLogin(message) {
  clearAdminSession();
  try {
    if (typeof showAuth === "function") {
      showAuth();
      var err = document.getElementById("login-error");
      if (err && message) err.textContent = message;
      var emailEl = document.getElementById("login-email");
      var saved = localStorage.getItem("sia_admin_email_last") || "";
      if (emailEl && saved && !emailEl.value) emailEl.value = saved;
      return;
    }
  } catch (e) { /* fall through */ }
  try {
    window.location.replace(adminHomeUrl());
  } catch (e2) {
    window.location.href = adminHomeUrl();
  }
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

function fetchTimeout(ms) {
  var ctrl = new AbortController();
  var t = setTimeout(function () { ctrl.abort(); }, ms);
  var signal = ctrl.signal;
  signal.addEventListener("abort", function () { clearTimeout(t); });
  return signal;
}

async function wakeAdminServer() {
  try {
    await fetch(API_BASE + "/health", { signal: fetchTimeout(12000), mode: "cors", cache: "no-store" });
  } catch (e) { /* server may still be waking */ }
}

function adminXhrJson(path, options) {
  options = options || {};
  return new Promise(function (resolve, reject) {
    var xhr = new XMLHttpRequest();
    xhr.open(options.method || "POST", API_BASE + path, true);
    xhr.timeout = options.timeout || 25000;
    var headers = options.headers || {};
    Object.keys(headers).forEach(function (k) {
      try { xhr.setRequestHeader(k, headers[k]); } catch (e) {}
    });
    xhr.onload = function () {
      var data = null;
      try { data = xhr.responseText ? JSON.parse(xhr.responseText) : null; } catch (e) {
        data = { detail: xhr.responseText || "Invalid response" };
      }
      if (xhr.status >= 200 && xhr.status < 300) {
        resolve(data);
        return;
      }
      var msg = (data && (data.detail || data.message)) || ("Request failed (" + xhr.status + ")");
      if (typeof msg === "object") msg = JSON.stringify(msg);
      var err = new Error(msg);
      err.status = xhr.status;
      err.data = data;
      reject(err);
    };
    xhr.onerror = function () { reject(new Error("Could not reach the server. Check your internet and try again.")); };
    xhr.ontimeout = function () { reject(new Error("Request timed out. The server may be waking up — try again.")); };
    xhr.send(options.body || null);
  });
}

async function adminApi(path, options) {
  options = options || {};
  var res;
  try {
    res = await fetch(API_BASE + path, {
      method: options.method || "GET",
      headers: Object.assign(
        { "Content-Type": "application/json", Authorization: "Bearer " + getAdminToken() },
        options.headers || {}
      ),
      body: options.body,
      signal: options.signal || fetchTimeout(options.timeout || 90000),
    });
  } catch (ex) {
    if (ex.name === "AbortError") {
      throw new Error("Request timed out. The server may be waking up — try again.");
    }
    throw new Error("Could not reach the server. Check your internet and try again.");
  }
  if (res.status === 204) return null;
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    // Never hard-reload here — that wipes the login form and looks like "login failed".
    kickAdminToLogin(formatApiError(data.detail) || "Session expired. Please sign in again.");
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Request failed (" + res.status + ")");
  return data;
}

function escHtml(s) {
  return String(s || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function fmtDate(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString(undefined, {
    month: "short", day: "numeric", year: "numeric",
    hour: "2-digit", minute: "2-digit",
  });
}

async function uploadCbtImage(file) {
  var fd = new FormData();
  fd.append("file", file);
  var res = await fetch(API_BASE + "/api/v1/admin/cbt/upload-image", {
    method: "POST",
    headers: { Authorization: "Bearer " + getAdminToken() },
    body: fd,
    signal: fetchTimeout(60000),
  });
  var data = await res.json().catch(function () { return {}; });
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Image upload failed");
  return data.image_url;
}

async function uploadCbtExamFile(file, fields) {
  var fd = new FormData();
  fd.append("file", file);
  if (fields.title) fd.append("title", fields.title);
  if (fields.subject) fd.append("subject", fields.subject);
  if (fields.year) fd.append("year", String(fields.year));
  if (fields.exam_type) fd.append("exam_type", fields.exam_type);
  if (fields.duration_minutes != null) fd.append("duration_minutes", String(fields.duration_minutes));
  fd.append("is_published", fields.is_published ? "true" : "false");
  fd.append("skip_duplicates", fields.skip_duplicates ? "true" : "false");
  fd.append("paper_kind", fields.paper_kind || "cbt_practice");
  var res = await fetch(API_BASE + "/api/v1/admin/cbt/import", {
    method: "POST",
    headers: { Authorization: "Bearer " + getAdminToken() },
    body: fd,
    signal: fetchTimeout(120000),
  });
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    kickAdminToLogin(formatApiError(data.detail) || "Session expired. Please sign in again.");
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "CBT import failed (" + res.status + ")");
  return data;
}

async function previewCbtFile(file) {
  var fd = new FormData();
  fd.append("file", file);
  var res = await fetch(API_BASE + "/api/v1/admin/cbt/import/preview", {
    method: "POST",
    headers: { Authorization: "Bearer " + getAdminToken() },
    body: fd,
    signal: fetchTimeout(120000),
  });
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    kickAdminToLogin(formatApiError(data.detail) || "Session expired. Please sign in again.");
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Could not read the file (" + res.status + ")");
  return data;
}

async function confirmCbtImport(payload) {
  return adminApi("/api/v1/admin/cbt/import/confirm", {
    method: "POST",
    body: JSON.stringify(payload),
    timeout: 120000,
  });
}

async function uploadAdminFile(url, file) {
  var fd = new FormData();
  fd.append("file", file);
  var res = await fetch(API_BASE + url, {
    method: "POST",
    headers: { Authorization: "Bearer " + getAdminToken() },
    body: fd,
    signal: fetchTimeout(180000),
  });
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    kickAdminToLogin(formatApiError(data.detail) || "Session expired. Please sign in again.");
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "Upload failed (" + res.status + ")");
  return data;
}

async function uploadMarketplaceImage(file) {
  return uploadAdminFile("/api/v1/admin/marketplace/upload-image", file);
}

async function uploadMarketplaceFile(file) {
  return uploadAdminFile("/api/v1/admin/marketplace/upload-file", file);
}

async function uploadInternalNotes(file) {
  return uploadAdminFile("/api/v1/admin/internal-exams/upload-notes", file);
}

async function uploadLibraryPdf(file) {
  return uploadAdminFile("/api/v1/admin/library/upload-file", file);
}

async function downloadCbtImportTemplate() {
  var res = await fetch(API_BASE + "/api/v1/admin/cbt/import-template", {
    headers: { Authorization: "Bearer " + getAdminToken() },
    signal: fetchTimeout(60000),
  });
  if (!res.ok) {
    var data = await res.json().catch(function () { return {}; });
    throw new Error(formatApiError(data.detail) || "Could not download template");
  }
  var blob = await res.blob();
  var url = URL.createObjectURL(blob);
  var a = document.createElement("a");
  a.href = url;
  a.download = "cbt_exam_template.json";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
