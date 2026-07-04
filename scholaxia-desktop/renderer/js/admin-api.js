const API_BASE = "https://scholaxia1.onrender.com";

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
  localStorage.setItem("sia_admin_token", data.access_token);
  localStorage.setItem("sia_admin_role", data.role || "admin");
  if (email) localStorage.setItem("sia_admin_email", email);
  if (name) localStorage.setItem("sia_admin_name", name);
}

function clearAdminSession() {
  ["sia_admin_token", "sia_admin_role", "sia_admin_name", "sia_admin_email"].forEach(function (k) {
    localStorage.removeItem(k);
  });
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
  setTimeout(function () { ctrl.abort(); }, ms);
  return ctrl.signal;
}

async function wakeAdminServer() {
  try {
    await fetch(API_BASE + "/health", { signal: fetchTimeout(120000) });
  } catch (e) { /* server may still be waking */ }
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
    clearAdminSession();
    window.location.href = "admin.html";
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
  if (fields.exam_type) fd.append("exam_type", fields.exam_type);
  if (fields.duration_minutes != null) fd.append("duration_minutes", String(fields.duration_minutes));
  fd.append("is_published", fields.is_published ? "true" : "false");
  fd.append("skip_duplicates", fields.skip_duplicates ? "true" : "false");
  var res = await fetch(API_BASE + "/api/v1/admin/cbt/import", {
    method: "POST",
    headers: { Authorization: "Bearer " + getAdminToken() },
    body: fd,
    signal: fetchTimeout(120000),
  });
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    clearAdminSession();
    window.location.href = "admin.html";
    return null;
  }
  if (!res.ok) throw new Error(formatApiError(data.detail) || "CBT import failed (" + res.status + ")");
  return data;
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
