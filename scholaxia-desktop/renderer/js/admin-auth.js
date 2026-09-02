/* Standalone admin auth — must stay syntax-clean so login works even if admin.js breaks. */
(function () {
  function $(id) {
    return document.getElementById(id);
  }

  function switchAuthTab(tab) {
    var isLogin = tab === "login";
    var tabLogin = $("tab-login");
    var tabReg = $("tab-register");
    var formLogin = $("form-login");
    var formReg = $("form-register");
    if (tabLogin) tabLogin.classList.toggle("active", isLogin);
    if (tabReg) tabReg.classList.toggle("active", !isLogin);
    if (formLogin) formLogin.classList.toggle("hidden", !isLogin);
    if (formReg) formReg.classList.toggle("hidden", isLogin);
    if ($("login-error")) $("login-error").textContent = "";
    if ($("register-error")) $("register-error").textContent = "";
  }

  function xhrLogin(email, password) {
    return new Promise(function (resolve, reject) {
      var xhr = new XMLHttpRequest();
      xhr.open("POST", (typeof API_BASE !== "undefined" ? API_BASE : "https://scholaxia1.onrender.com") + "/api/v1/auth/login", true);
      xhr.timeout = 25000;
      xhr.setRequestHeader("Content-Type", "application/json");
      xhr.setRequestHeader("Accept", "application/json");
      xhr.onload = function () {
        var data = null;
        try {
          data = xhr.responseText ? JSON.parse(xhr.responseText) : null;
        } catch (e) {
          data = { detail: xhr.responseText || "Invalid response" };
        }
        if (xhr.status >= 200 && xhr.status < 300) {
          resolve(data);
          return;
        }
        var msg =
          (data && (data.detail || data.message)) ||
          ("Login failed (" + xhr.status + ")");
        if (typeof msg === "object") {
          try {
            msg = msg.message || JSON.stringify(msg);
          } catch (e2) {
            msg = "Login failed";
          }
        }
        var err = new Error(String(msg));
        err.status = xhr.status;
        err.data = data;
        reject(err);
      };
      xhr.onerror = function () {
        reject(new Error("Could not reach the server. Check your internet and try again."));
      };
      xhr.ontimeout = function () {
        reject(new Error("Server took too long. Wait 20 seconds and try again."));
      };
      xhr.send(JSON.stringify({ email: email, password: password }));
    });
  }

  async function onAdminLogin(e) {
    if (e && e.preventDefault) e.preventDefault();
    if (e && e.stopPropagation) e.stopPropagation();
    var email = ($("login-email") && $("login-email").value.trim()) || "";
    var password = ($("login-password") && $("login-password").value) || "";
    var err = $("login-error");
    var btn = $("btn-login");
    if (err) err.textContent = "";
    if (email) {
      try {
        localStorage.setItem("sia_admin_email_last", email);
      } catch (e0) {}
    }
    if (!email || !password) {
      if (err) err.textContent = "Enter email and password.";
      return false;
    }
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Signing in…";
    }
    try {
      if (typeof wakeAdminServer === "function") {
        try {
          wakeAdminServer();
        } catch (w) {}
      }
      var data = await xhrLogin(email, password);
      var role = String(data.role || (data.user && data.user.role) || "")
        .toLowerCase()
        .replace(/^userrole\./, "");
      if (role !== "admin" && role !== "school_admin") {
        if (err) {
          err.textContent =
            "This email is a " +
            (role || "unknown") +
            " account, not an admin. Use the student/teacher sign-in on the website.";
        }
        return false;
      }
      if (!data.access_token) {
        if (err) err.textContent = "Login succeeded but no token was returned. Try again.";
        return false;
      }
      if (typeof saveAdminSession === "function") {
        saveAdminSession(data, email, (data.user && data.user.full_name) || email);
      } else {
        localStorage.setItem("sia_admin_token", data.access_token);
        localStorage.setItem("sia_admin_role", role);
        localStorage.setItem("sia_admin_email", email);
        localStorage.setItem(
          "sia_admin_name",
          (data.user && data.user.full_name) || email
        );
      }
      if (data.user && data.user.school_id) {
        localStorage.setItem("sia_school_id", data.user.school_id);
      }
      if (data.user && data.user.school_name) {
        localStorage.setItem("sia_school_name", data.user.school_name);
      }
      if (role === "school_admin" && !(data.user && data.user.school_id)) {
        if (err) {
          err.textContent =
            "This school admin is not linked to a school yet. Ask the main Scholaxia admin to assign the school.";
        }
        if (typeof clearAdminSession === "function") clearAdminSession();
        return false;
      }
      if (typeof showApp === "function") {
        showApp();
        if (role === "school_admin" && typeof showAdminPage === "function") {
          try {
            showAdminPage("school-office");
          } catch (pageErr) {
            if (err) err.textContent = pageErr.message || "Signed in, but School office failed to open.";
            if (typeof showAuth === "function") showAuth();
          }
        } else if (typeof loadDashboard === "function") {
          try {
            loadDashboard();
          } catch (dashErr) {
            console.error("[admin] loadDashboard failed", dashErr);
          }
        }
        // Ensure dashboard is visible even if a later helper throws.
        try {
          var auth = $("auth-screen");
          var app = $("app-screen");
          if (auth) auth.classList.add("hidden");
          if (app) app.classList.remove("hidden");
        } catch (uiErr) {}
      } else {
        window.location.href = (typeof adminHomeUrl === "function" ? adminHomeUrl() : "/admin/") +
          (location.search.indexOf("fresh=") >= 0 ? "" : "?fresh=" + Date.now());
      }
    } catch (ex) {
      if (err) err.textContent = (ex && ex.message) || "Network error. Try again.";
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = "LOG IN";
      }
    }
    return false;
  }

  async function onAdminRegister(e) {
    if (e && e.preventDefault) e.preventDefault();
    var name = ($("reg-name") && $("reg-name").value.trim()) || "";
    var email = ($("reg-email") && $("reg-email").value.trim()) || "";
    var password = ($("reg-password") && $("reg-password").value) || "";
    var err = $("register-error");
    var btn = $("btn-register");
    if (err) err.textContent = "";
    if (!name || !email || !password) {
      if (err) err.textContent = "Fill in all fields.";
      return false;
    }
    if (btn) btn.disabled = true;
    try {
      var base = typeof API_BASE !== "undefined" ? API_BASE : "https://scholaxia1.onrender.com";
      var res = await fetch(base + "/api/v1/admin/register", {
        method: "POST",
        headers: { "Content-Type": "application/json", Accept: "application/json" },
        body: JSON.stringify({ email: email, password: password, full_name: name }),
      });
      var data = await res.json().catch(function () {
        return {};
      });
      if (!res.ok) {
        var msg = data.detail || data.message || "Registration failed.";
        if (typeof msg === "object") msg = msg.message || JSON.stringify(msg);
        if (err) err.textContent = String(msg);
        return false;
      }
      if (err) err.textContent = "Admin created. Switch to Log in.";
      switchAuthTab("login");
      if ($("login-email")) $("login-email").value = email;
    } catch (ex) {
      if (err) err.textContent = (ex && ex.message) || "Could not reach server.";
    } finally {
      if (btn) btn.disabled = false;
    }
    return false;
  }

  document.addEventListener("DOMContentLoaded", function () {
    var tabLogin = $("tab-login");
    var tabReg = $("tab-register");
    var formLogin = $("form-login");
    var btnLogin = $("btn-login");
    var formReg = $("form-register");
    if (tabLogin) tabLogin.addEventListener("click", function () { switchAuthTab("login"); });
    if (tabReg) tabReg.addEventListener("click", function () { switchAuthTab("register"); });
    if (formLogin) formLogin.addEventListener("submit", onAdminLogin);
    if (btnLogin) btnLogin.addEventListener("click", onAdminLogin);
    if (formReg) formReg.addEventListener("submit", onAdminRegister);
    try {
      var lastEmail = localStorage.getItem("sia_admin_email_last");
      if (lastEmail && $("login-email") && !$("login-email").value) {
        $("login-email").value = lastEmail;
      }
    } catch (e) {}
  });

  window.switchAuthTab = switchAuthTab;
  window.adminLoginFromAuth = onAdminLogin;
})();
