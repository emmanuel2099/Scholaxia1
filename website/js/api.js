/* Scholaxia website API — calls production backend */
(function (global) {
  var API_BASE = "https://scholaxia1.onrender.com";
  global.API_BASE = API_BASE;

  function fetchTimeout(ms) {
    var ctrl = new AbortController();
    setTimeout(function () { ctrl.abort(); }, ms || 45000);
    return ctrl.signal;
  }

  function getToken() {
    var teacherTok = localStorage.getItem("sia_teacher_token") || localStorage.getItem("sia_admin_token") || "";
    var studentTok = localStorage.getItem("sia_token") || "";
    var role = "";
    try {
      role = localStorage.getItem("sia_role") || "";
    } catch (e) {}
    try {
      var path = String(window.location.pathname || "");
      var onClassroom = /classroom(\.html)?$/i.test(path) || /\/classroom/i.test(path);
      var sess = null;
      try {
        sess = JSON.parse(localStorage.getItem("live_session") || "null");
      } catch (e2) {
        sess = null;
      }
      var sessRole = (sess && sess.role) || "";
      // Host classroom must never send a leftover student JWT — presence/students will 403.
      if (onClassroom && (sessRole === "teacher" || sessRole === "admin")) {
        return teacherTok || studentTok;
      }
      if (onClassroom && sessRole === "student") {
        return studentTok || teacherTok;
      }
      if (role === "teacher" || role === "admin") {
        return teacherTok || studentTok;
      }
      if (role === "student" || role === "kind") {
        return studentTok || teacherTok;
      }
    } catch (e) {}
    return teacherTok || studentTok;
  }

  function getUser() {
    return {
      name: localStorage.getItem("sia_name") || "User",
      email: localStorage.getItem("sia_email") || "",
      role: localStorage.getItem("sia_role") || "student",
      ageGroup: localStorage.getItem("sia_age_group") || "",
    };
  }

  function saveSession(data, email, nameOverride) {
    var role = (data && data.role) || "student";
    var token = data && data.access_token;
    if (!token) return;

    if (role === "teacher" || role === "admin") {
      localStorage.setItem("sia_teacher_token", token);
    } else {
      localStorage.setItem("sia_token", token);
    }
    localStorage.setItem("sia_role", role);
    if (email) localStorage.setItem("sia_email", email);
    var name =
      nameOverride ||
      (data.user && data.user.full_name) ||
      localStorage.getItem("sia_name") ||
      email ||
      "User";
    localStorage.setItem("sia_name", name);
  }

  function clearSession() {
    [
      "sia_token",
      "sia_teacher_token",
      "sia_role",
      "sia_name",
      "sia_email",
      "sia_exam_type",
      "sia_subjects",
      "sia_age_group",
    ].forEach(function (k) {
      localStorage.removeItem(k);
    });
  }

  async function parseResponse(res) {
    var text = await res.text();
    var data = null;
    try {
      data = text ? JSON.parse(text) : null;
    } catch (e) {
      data = { detail: text || "Invalid response" };
    }
    if (!res.ok) {
      var msg =
        (data && (data.detail || data.message)) ||
        "Request failed (" + res.status + ")";
      if (typeof msg === "object") msg = JSON.stringify(msg);
      var err = new Error(msg);
      err.status = res.status;
      err.data = data;
      throw err;
    }
    return data;
  }

  async function api(path, options) {
    options = options || {};
    var headers = Object.assign(
      { "Content-Type": "application/json", Accept: "application/json" },
      options.headers || {}
    );
    var token = getToken();
    if (token && !options.noAuth && !headers.Authorization) {
      headers.Authorization = "Bearer " + token;
    }
    var res = await fetch(API_BASE + path, {
      method: options.method || "GET",
      headers: headers,
      body: options.body ? JSON.stringify(options.body) : undefined,
      signal: options.signal || fetchTimeout(45000),
    });
    return parseResponse(res);
  }

  async function apiUpload(path, formData, options) {
    options = options || {};
    var headers = { Accept: "application/json" };
    var token = getToken();
    if (token && !options.noAuth && !headers.Authorization) {
      headers.Authorization = "Bearer " + token;
    }
    var res = await fetch(API_BASE + path, {
      method: options.method || "POST",
      headers: headers,
      body: formData,
      signal: options.signal || fetchTimeout(90000),
    });
    return parseResponse(res);
  }

  function dashboardForRole(role) {
    if (role === "teacher" || role === "admin") return "teacher.html";
    if (role === "kind") return "kind.html";
    return "student.html";
  }

  function requireAuth(expectedRoles) {
    var role = localStorage.getItem("sia_role") || "";
    var token = getToken();
    if (!token) {
      window.location.href = "auth.html";
      return false;
    }
    if (expectedRoles && expectedRoles.indexOf(role) < 0) {
      window.location.href = dashboardForRole(role);
      return false;
    }
    return true;
  }

  global.ScholaxiaAPI = {
    API_BASE: API_BASE,
    api: api,
    apiUpload: apiUpload,
    getToken: getToken,
    getUser: getUser,
    saveSession: saveSession,
    clearSession: clearSession,
    dashboardForRole: dashboardForRole,
    requireAuth: requireAuth,
    fetchTimeout: fetchTimeout,
  };
})(window);
