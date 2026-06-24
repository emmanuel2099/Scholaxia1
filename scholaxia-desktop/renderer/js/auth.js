// API_BASE, fetchTimeout, getToken, saveSession — from api.js (loaded first)

document.addEventListener("DOMContentLoaded", function () {
  try {
    initAuthPage();
  } catch (err) {
    console.error("Auth init error:", err);
    alert("App failed to load: " + err.message);
  }
});

function initAuthPage() {
  if (typeof getToken !== "function") {
    throw new Error("api.js did not load — check js/api.js file");
  }

  if (getToken()) {
    window.location.href = "app.html";
    return;
  }

  var remembered = localStorage.getItem("sia_remember_email");
  if (remembered) {
    document.getElementById("login-email").value = remembered;
    document.getElementById("remember-me").checked = true;
  }

  document.getElementById("tab-login").addEventListener("click", function () { switchTab("login"); });
  document.getElementById("tab-signup").addEventListener("click", function () { switchTab("signup"); });
  document.getElementById("go-signup").addEventListener("click", function () { switchTab("signup"); });
  document.getElementById("go-login").addEventListener("click", function () { switchTab("login"); });
  document.getElementById("form-login").addEventListener("submit", login);
  document.getElementById("form-signup").addEventListener("submit", signup);

  document.querySelectorAll(".toggle-pw").forEach(function (btn) {
    btn.addEventListener("click", function () { togglePw(btn.dataset.target, btn); });
  });

  initIntroPage();

  var params = new URLSearchParams(window.location.search);
  var ret = params.get("return");
  if (ret) {
    sessionStorage.setItem("sia_login_return", ret);
    setTimeout(function () { scrollToAuth("login"); }, 400);
  }
}

function scrollToAuth(tab) {
  var panel = document.getElementById("auth");
  if (panel) panel.scrollIntoView({ behavior: "smooth", block: "center" });
  if (tab) switchTab(tab);
}

function initIntroPage() {
  var heroLogin = document.getElementById("hero-login");
  var heroRegister = document.getElementById("hero-register");
  var navLogin = document.getElementById("nav-login");
  var navRegister = document.getElementById("nav-register");
  var contactForm = document.getElementById("contact-form");

  if (heroLogin) heroLogin.addEventListener("click", function () { scrollToAuth("login"); });
  if (heroRegister) heroRegister.addEventListener("click", function () { scrollToAuth("signup"); });
  if (navLogin) navLogin.addEventListener("click", function (e) {
    e.preventDefault();
    scrollToAuth("login");
  });
  if (navRegister) navRegister.addEventListener("click", function () { scrollToAuth("signup"); });

  if (contactForm) {
    contactForm.addEventListener("submit", function (e) {
      e.preventDefault();
      var ok = document.getElementById("contact-success");
      if (ok) ok.classList.remove("hidden");
      contactForm.reset();
      setTimeout(function () {
        if (ok) ok.classList.add("hidden");
      }, 6000);
    });
  }

  if ("IntersectionObserver" in window) {
    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (entry.isIntersecting) {
          entry.target.classList.add("visible");
          observer.unobserve(entry.target);
        }
      });
    }, { threshold: 0.15, rootMargin: "0px 0px -40px 0px" });

    document.querySelectorAll(".reveal").forEach(function (el) {
      observer.observe(el);
    });
  } else {
    document.querySelectorAll(".reveal").forEach(function (el) {
      el.classList.add("visible");
    });
  }
}

function switchTab(tab) {
  var isLogin = tab === "login";
  document.getElementById("tab-login").classList.toggle("active", isLogin);
  document.getElementById("tab-signup").classList.toggle("active", !isLogin);
  document.getElementById("form-login").classList.toggle("hidden", !isLogin);
  document.getElementById("form-signup").classList.toggle("hidden", isLogin);
  document.getElementById("portal-title").textContent = isLogin ? "STUDENT PORTAL" : "CREATE ACCOUNT";
  document.getElementById("portal-sub").textContent = isLogin
    ? "Sign in to access live classes, exams & CBT"
    : "Join Scholaxia — free for all students";
  document.getElementById("login-error").textContent = "";
  document.getElementById("signup-error").textContent = "";
}

function togglePw(id, btn) {
  var input = document.getElementById(id);
  var show = input.type === "password";
  input.type = show ? "text" : "password";
  btn.style.opacity = show ? "1" : "0.45";
}

async function routeAfterAuth(accessToken, role, email, nameOverride) {
  try {
    var p = await fetch(API_BASE + "/api/v1/students/me", {
      headers: { Authorization: "Bearer " + accessToken },
      signal: fetchTimeout(30000),
    });
    if (p.ok) {
      var pd = await p.json();
      localStorage.setItem("sia_name", pd.full_name || nameOverride || email);
      localStorage.setItem("sia_exam_type", pd.exam_type || "");
      localStorage.setItem("sia_subjects", JSON.stringify(pd.selected_subjects || []));
    } else {
      localStorage.setItem("sia_name", nameOverride || email);
    }
  } catch (e) {
    localStorage.setItem("sia_name", nameOverride || email);
  }
  var ret = sessionStorage.getItem("sia_login_return");
  sessionStorage.removeItem("sia_login_return");
  try { sessionStorage.setItem("sia_skip_splash", "1"); } catch (e) { /* ignore */ }
  if (ret) {
    window.location.href = "app.html?open=" + encodeURIComponent(ret);
  } else {
    window.location.href = "app.html";
  }
}

async function login(e) {
  e.preventDefault();
  var email = document.getElementById("login-email").value.trim();
  var password = document.getElementById("login-password").value;
  var err = document.getElementById("login-error");
  var btn = document.getElementById("btn-login");
  err.textContent = "";
  btn.disabled = true;
  btn.textContent = "LOGGING IN...";

  if (document.getElementById("remember-me").checked) {
    localStorage.setItem("sia_remember_email", email);
  } else {
    localStorage.removeItem("sia_remember_email");
  }

  try {
    var res = await fetch(API_BASE + "/api/v1/auth/login", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password }),
      signal: fetchTimeout(45000),
    });
    var data = await res.json();
    if (!res.ok) {
      err.textContent = typeof data.detail === "string" ? data.detail : "Login failed.";
      return;
    }
    if (data.role !== "student") {
      err.textContent = "This app is for students only.";
      return;
    }
    saveSession(data, email);
    await routeAfterAuth(data.access_token, data.role, email);
  } catch (ex) {
    err.textContent = ex.name === "TimeoutError" || ex.name === "AbortError"
      ? "Server is waking up — try again in 30 seconds."
      : "Network error. Check your connection.";
  } finally {
    btn.disabled = false;
    btn.textContent = "LOG IN";
  }
}

async function signup(e) {
  e.preventDefault();
  var name = document.getElementById("signup-name").value.trim();
  var email = document.getElementById("signup-email").value.trim();
  var password = document.getElementById("signup-password").value;
  var err = document.getElementById("signup-error");
  var btn = document.getElementById("btn-signup");
  err.textContent = "";

  if (!name || !email || !password) {
    err.textContent = "Please fill in all fields.";
    return;
  }
  if (password.length < 8) {
    err.textContent = "Password must be at least 8 characters.";
    return;
  }

  btn.disabled = true;
  btn.textContent = "CREATING...";

  try {
    var res = await fetch(API_BASE + "/api/v1/auth/student/signup", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email: email, password: password, full_name: name }),
      signal: fetchTimeout(45000),
    });
    var data = await res.json();
    if (!res.ok) {
      err.textContent = typeof data.detail === "string" ? data.detail : "Signup failed.";
      return;
    }
    saveSession(data, email, name);
    await routeAfterAuth(data.access_token, "student", email, name);
  } catch (ex) {
    err.textContent = ex.name === "TimeoutError" || ex.name === "AbortError"
      ? "Server is waking up — try again in 30 seconds."
      : "Network error. Check your connection.";
  } finally {
    btn.disabled = false;
    btn.textContent = "CREATE ACCOUNT";
  }
}
