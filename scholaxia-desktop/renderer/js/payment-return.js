(function () {
  function showError(msg) {
    var spinner = document.getElementById("spinner");
    var title = document.getElementById("status-title");
    var statusMsg = document.getElementById("status-msg");
    var err = document.getElementById("status-err");
    if (spinner) spinner.style.display = "none";
    if (title) title.textContent = "Could not complete payment";
    if (statusMsg) statusMsg.textContent = msg;
    if (err) {
      err.classList.remove("hidden");
      err.innerHTML = '<a href="app.html?live=1">Open Live Class</a>';
    }
  }

  function readPending() {
    var raw = sessionStorage.getItem("sia_pay_return") || localStorage.getItem("sia_pay_return");
    try {
      return raw ? JSON.parse(raw) : null;
    } catch (e) {
      return null;
    }
  }

  function clearPending() {
    sessionStorage.removeItem("sia_pay_return");
    localStorage.removeItem("sia_pay_return");
    if (typeof clearPlanPaymentPending === "function") clearPlanPaymentPending();
  }

  function fakeCard(pending) {
    if (!pending) return null;
    return {
      dataset: {
        title: pending.title || "",
        subject: pending.subject || "",
        teacher: pending.teacher || "",
        end: pending.end_time || "",
      },
    };
  }

  function goToLiveClass(classId) {
    if (classId) {
      window.location.href = "classroom.html";
      return;
    }
    window.location.href = "app.html?live=1&paid=1";
  }

  async function handleReturn() {
    if (!getToken()) {
      window.location.href = "index.html";
      return;
    }

    var params = new URLSearchParams(window.location.search);
    var status = (params.get("status") || "").toLowerCase();
    var transactionId = params.get("transaction_id") || params.get("flw_ref");
    var txRef = params.get("tx_ref");
    var pending = readPending();
    var classId = params.get("class_id") || (pending && pending.class_id);
    var planId = params.get("plan_id") || (pending && pending.plan_id);
    var payType = params.get("ctx") || (pending && pending.type) || "live";

    if (status === "cancelled" || status === "failed") {
      clearPending();
      showError("Payment was cancelled. Your plan was not activated.");
      return;
    }

    if (status !== "successful" || !transactionId) {
      clearPending();
      showError("We could not confirm this payment. Reference: " + (txRef || "unknown"));
      return;
    }

    try {
      var verifyBody = {
        transaction_id: String(transactionId),
        tx_ref: txRef || (pending && pending.tx_ref) || null,
      };
      if (payType === "material") {
        var materialId = params.get("material_id") || (pending && pending.material_id);
        verifyBody.material_id = materialId || null;
      } else {
        verifyBody.plan_id = planId || null;
        verifyBody.class_id = classId || null;
      }

      var verified = await api("/api/v1/payments/flutterwave/verify", {
        method: "POST",
        body: JSON.stringify(verifyBody),
      });

      clearPending();
      try { sessionStorage.removeItem("sia_live_plans_cache"); } catch (e) { /* ignore */ }

      if (payType === "material") {
        document.getElementById("status-title").textContent = "Payment successful";
        document.getElementById("status-msg").textContent = "Your material is unlocked.";
        setTimeout(function () {
          window.location.href = "app.html?library=1";
        }, 800);
        return;
      }

      if (classId && verified && verified.paid) {
        document.getElementById("status-title").textContent = "Plan activated!";
        document.getElementById("status-msg").textContent = "Joining your live class now…";
        await completeJoinClass(classId, fakeCard(pending));
        return;
      }

      document.getElementById("status-title").textContent = "Plan activated!";
      document.getElementById("status-msg").textContent = "You can join live classes now.";
      setTimeout(function () {
        window.location.href = "app.html?live=1&paid=1";
      }, 800);
    } catch (e) {
      try {
        var access = await api("/api/v1/payments/live-class/plans");
        if (access && access.active_plan && access.active_plan.sessions_left > 0) {
          clearPending();
          if (classId) {
            document.getElementById("status-title").textContent = "Plan active";
            document.getElementById("status-msg").textContent = "Joining your live class now…";
            await completeJoinClass(classId, fakeCard(pending));
            return;
          }
          window.location.href = "app.html?live=1&paid=1";
          return;
        }
      } catch (ignored) { /* fall through */ }

      if (classId) {
        try {
          var classAccess = await api("/api/v1/payments/live-class/" + encodeURIComponent(classId) + "/access");
          if (classAccess && classAccess.paid) {
            clearPending();
            await completeJoinClass(classId, fakeCard(pending));
            return;
          }
        } catch (ignored2) { /* fall through */ }
      }

      clearPending();
      showError(e.message || "Verification failed. Open Live Class and tap Join again.");
    }
  }

  document.addEventListener("DOMContentLoaded", handleReturn);
})();
