const API_BASE = "https://scholaxia1.onrender.com";

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

async function teacherApi(path, options) {
  options = options || {};
  var res = await fetch(API_BASE + path, {
    method: options.method || "GET",
    headers: Object.assign(
      { "Content-Type": "application/json", Authorization: "Bearer " + getTeacherToken() },
      options.headers || {}
    ),
    body: options.body,
  });
  var data = await res.json().catch(function () { return {}; });
  if (res.status === 401) {
    clearTeacherSession();
    window.location.reload();
    return null;
  }
  if (!res.ok) throw new Error((data.detail && (typeof data.detail === "string" ? data.detail : data.detail.msg)) || "Request failed");
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
