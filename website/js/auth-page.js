(function () {
  var api = window.ScholaxiaAPI;
  var role = "student";
  var mode = "login";
  var pendingEmail = "";

  var ROLE_META = {
    student: {
      subLogin: "Student portal — live classes, CBT & study tools",
      subSignup: "Create a free student account",
      allowSignup: true,
    },
    teacher: {
      subLogin: "Teacher portal — host classes & manage students",
      subSignup: "Create teacher account (admin approval required)",
      allowSignup: true,
    },
    kind: {
      subLogin: "Kids portal — safe learning for ages 3–12",
      subSignup: "Create a Scholaxia Kids account",
      allowSignup: true,
    },
  };

  function $(id) {
    return document.getElementById(id);
  }

  function showErr(el, msg) {
    if (!el) return;
    if (!msg) {
      el.hidden = true;
      el.textContent = "";
      return;
    }
    el.hidden = false;
    el.textContent = msg;
  }

  function setVisible(el, on) {
    if (!el) return;
    el.hidden = !on;
    el.classList.toggle("is-off", !on);
  }

  function updateCopy() {
    var meta = ROLE_META[role];
    $("portalSub").textContent = mode === "login" ? meta.subLogin : meta.subSignup;
    setVisible($("kindFields"), role === "kind" && mode === "signup");
    setVisible($("teacherFields"), role === "teacher" && mode === "signup");
    setVisible($("teacherHint"), role === "teacher");
    $("btnSignup").disabled = false;
    $("tabSignup").disabled = false;
    $("gotoSignup").disabled = false;
  }

  function setRole(next) {
    role = next;
    document.querySelectorAll(".role-btn").forEach(function (btn) {
      var on = btn.dataset.role === role;
      btn.classList.toggle("is-active", on);
      btn.setAttribute("aria-selected", on ? "true" : "false");
    });
    updateCopy();
  }

  function switchMode(next) {
    mode = next;
    var login = mode === "login";

    $("tabLogin").classList.toggle("is-active", login);
    $("tabSignup").classList.toggle("is-active", !login);
    $("tabLogin").setAttribute("aria-selected", login ? "true" : "false");
    $("tabSignup").setAttribute("aria-selected", login ? "false" : "true");
    var tabs = document.querySelector(".mode-tabs");
    if (tabs) tabs.classList.toggle("is-signup", !login);
    var title = $("authTitle");
    if (title) title.textContent = login ? "Welcome back" : "Create account";

    setVisible($("formLogin"), login);
    setVisible($("formSignup"), !login);

    showErr($("loginError"));
    showErr($("signupError"));
    showErr($("otpError"));

    setVisible($("signupStepDetails"), true);
    setVisible($("signupStepOtp"), false);
    updateCopy();
  }

  function roleMismatch(selected, actual) {
    if (selected === "teacher") return "This account is not a teacher. Pick the correct role.";
    if (selected === "kind") return "This is not a Kid account. Choose Student or create a Kid account.";
    if (actual === "teacher") return "This is a teacher account. Select Teacher above.";
    if (actual === "kind") return "This is a Kid account. Select Kid above.";
    return "Account type does not match the role you selected.";
  }

  async function afterAuth(data, email, name) {
    var actual = (data && data.role) || "student";
    if (role === "teacher" && actual !== "teacher" && actual !== "admin") {
      throw new Error(roleMismatch(role, actual));
    }
    if (role === "kind" && actual !== "kind") {
      throw new Error(roleMismatch(role, actual));
    }
    if (role === "student" && (actual === "teacher" || actual === "kind" || actual === "admin")) {
      throw new Error(roleMismatch(role, actual));
    }

    api.saveSession(data, email, name);

    if (actual === "kind") {
      try {
        var kd = await api.api("/api/v1/kind/me");
        if (kd && kd.full_name) localStorage.setItem("sia_name", kd.full_name);
        if (kd && kd.age_group) localStorage.setItem("sia_age_group", kd.age_group);
      } catch (e) { /* ignore */ }
    } else if (actual === "student") {
      try {
        var st = await api.api("/api/v1/students/me");
        if (st && st.full_name) localStorage.setItem("sia_name", st.full_name);
        if (st && st.exam_type) localStorage.setItem("sia_exam_type", st.exam_type);
        if (st && st.selected_subjects) {
          localStorage.setItem("sia_subjects", JSON.stringify(st.selected_subjects));
        }
      } catch (e) { /* ignore */ }
    }
    if (actual === "teacher" && data && data.user && data.user.is_approved === false) {
      localStorage.setItem("sia_teacher_pending_approval", "1");
      alert("Your teacher account is pending admin approval. You can update profile while waiting.");
      window.location.href = "teacher.html#profile";
      return;
    }

    window.location.href = api.dashboardForRole(actual);
  }

  async function onLogin(e) {
    e.preventDefault();
    var email = $("loginEmail").value.trim();
    var password = $("loginPassword").value;
    var btn = $("btnLogin");
    showErr($("loginError"));
    btn.disabled = true;
    btn.textContent = "Logging in…";
    try {
      var data = await api.api("/api/v1/auth/login", {
        method: "POST",
        noAuth: true,
        body: { email: email, password: password },
      });
      await afterAuth(data, email, data.user && data.user.full_name);
    } catch (err) {
      showErr($("loginError"), err.message || "Login failed");
      btn.disabled = false;
      btn.textContent = "Log in";
    }
  }

  async function onSignup(e) {
    e.preventDefault();
    var email = $("signupEmail").value.trim();
    var password = $("signupPassword").value;
    var fullName = $("signupName").value.trim();
    var btn = $("btnSignup");
    showErr($("signupError"));
    btn.disabled = true;
    btn.textContent = "Sending OTP…";
    try {
      var body = {
        email: email,
        password: password,
        full_name: fullName,
        role: role,
      };
      if (role === "kind") {
        body.age_group = $("signupAge").value;
        var parent = $("signupParent").value.trim();
        if (parent) body.parent_email = parent;
      } else if (role === "teacher") {
        body.phone = $("signupPhone").value.trim();
        body.location = $("signupLocation").value.trim();
        var subjects = $("signupSubjects").value
          .split(",")
          .map(function (s) { return s.trim(); })
          .filter(Boolean);
        body.subjects = subjects;
      }
      await api.api("/api/v1/auth/signup/start", {
        method: "POST",
        noAuth: true,
        body: body,
      });
      pendingEmail = email;
      setVisible($("signupStepDetails"), false);
      setVisible($("signupStepOtp"), true);
      $("signupOtp").focus();
    } catch (err) {
      showErr($("signupError"), err.message || "Signup failed");
    } finally {
      btn.disabled = false;
      btn.textContent = "Create account";
    }
  }

  async function onVerify() {
    var otp = $("signupOtp").value.trim();
    var btn = $("btnVerify");
    showErr($("otpError"));
    if (!otp) {
      showErr($("otpError"), "Enter the OTP from your email");
      return;
    }
    btn.disabled = true;
    btn.textContent = "Verifying…";
    try {
      var data = await api.api("/api/v1/auth/signup/verify", {
        method: "POST",
        noAuth: true,
        body: { email: pendingEmail || $("signupEmail").value.trim(), otp: otp },
      });
      await afterAuth(
        data,
        pendingEmail || $("signupEmail").value.trim(),
        $("signupName").value.trim()
      );
    } catch (err) {
      showErr($("otpError"), err.message || "Verification failed");
      btn.disabled = false;
      btn.textContent = "Verify & continue";
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    if (api.getToken()) {
      window.location.href = api.dashboardForRole(localStorage.getItem("sia_role") || "student");
      return;
    }

    document.querySelectorAll(".role-btn").forEach(function (btn) {
      btn.addEventListener("click", function () {
        setRole(btn.dataset.role);
      });
    });

    $("tabLogin").addEventListener("click", function () {
      switchMode("login");
    });
    $("tabSignup").addEventListener("click", function () {
      switchMode("signup");
    });
    $("gotoSignup").addEventListener("click", function () {
      switchMode("signup");
    });
    $("gotoLogin").addEventListener("click", function () {
      switchMode("login");
    });

    $("formLogin").addEventListener("submit", onLogin);
    $("formSignup").addEventListener("submit", onSignup);
    $("btnVerify").addEventListener("click", onVerify);
    $("btnBackDetails").addEventListener("click", function () {
      setVisible($("signupStepDetails"), true);
      setVisible($("signupStepOtp"), false);
    });

    var params = new URLSearchParams(window.location.search);
    var roleParam = params.get("role");
    if (roleParam && ROLE_META[roleParam]) setRole(roleParam);
    if (params.get("mode") === "signup") {
      switchMode("signup");
    } else {
      switchMode("login");
    }
  });
})();
