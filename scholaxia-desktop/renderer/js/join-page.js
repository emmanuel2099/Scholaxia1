(function () {
  var preview = null;
  var joining = false;

  function show(id) {
    ["join-loading", "join-ready", "join-not-found"].forEach(function (elId) {
      var el = document.getElementById(elId);
      if (el) el.classList.toggle("hidden", elId !== id);
    });
  }

  function setError(msg) {
    var el = document.getElementById("join-error");
    if (el) el.textContent = msg || "";
  }

  function renderPreview(data) {
    preview = data;
    document.getElementById("join-title").textContent = data.title || "Live class";
    document.getElementById("join-meta").textContent =
      (data.subject || "Subject") + " · " + (data.teacher_name || "Teacher");
    document.getElementById("join-code-display").textContent = data.join_code || "—";

    var pill = document.getElementById("join-live-pill");
    var hint = document.getElementById("join-hint");
    if (data.is_live) {
      pill.classList.remove("hidden");
      hint.textContent = "Class is live — tap Join now to enter the classroom.";
    } else if (data.is_joinable) {
      pill.classList.add("hidden");
      hint.textContent = "Class is starting — you can join now.";
    } else {
      pill.classList.add("hidden");
      hint.textContent = "This class has not started yet. Check back when your teacher goes live.";
    }

    var loggedIn = typeof getToken === "function" && !!getToken();
    var joinBtn = document.getElementById("join-now-btn");
    var loginBtn = document.getElementById("join-login-btn");

    if (loggedIn) {
      joinBtn.classList.remove("hidden");
      loginBtn.classList.add("hidden");
      joinBtn.disabled = !data.is_joinable;
      joinBtn.textContent = data.is_joinable ? "Join now" : "Waiting for teacher…";
    } else {
      joinBtn.classList.add("hidden");
      loginBtn.classList.remove("hidden");
      loginBtn.textContent = "Sign in to join";
    }

    show("join-ready");
  }

  async function loadPreview() {
    var params = parseJoinParams();
    if (!params.code && !params.class_id) {
      show("join-not-found");
      document.getElementById("join-not-found-msg").textContent =
        "No class link was provided. Ask your teacher for the join link or code.";
      return;
    }

    try {
      var data = await fetchJoinPreview(params);
      renderPreview(data);
    } catch (e) {
      show("join-not-found");
      document.getElementById("join-not-found-msg").textContent =
        (e && e.message) ? e.message : "Class not found.";
    }
  }

  async function onJoinNow() {
    if (joining || !preview) return;
    if (!preview.is_joinable) {
      setError("Class is not live yet. Wait for your teacher to start.");
      return;
    }
    joining = true;
    var btn = document.getElementById("join-now-btn");
    btn.disabled = true;
    btn.textContent = "Joining…";
    setError("");
    try {
      await joinClassFromPreview(preview);
    } catch (e) {
      setError((e && e.message) ? e.message : "Could not join class.");
      btn.disabled = false;
      btn.textContent = "Join now";
      joining = false;
    }
  }

  function onLogin() {
    var params = parseJoinParams();
    savePendingJoin(params);
    window.location.href = loginUrlForJoin(params);
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.getElementById("join-now-btn").addEventListener("click", onJoinNow);
    document.getElementById("join-login-btn").addEventListener("click", onLogin);
    loadPreview();
  });
})();
