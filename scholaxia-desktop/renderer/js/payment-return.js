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
      err.innerHTML = '<a href="app.html">Back to Scholaxia</a>';
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
    var payType = params.get("ctx") || (pending && pending.type);

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
      if ((payType === "live" || (pending && pending.type === "live")) && planId) {
        await api("/api/v1/payments/flutterwave/verify", {
          method: "POST",
          body: JSON.stringify({
            transaction_id: String(transactionId),
            plan_id: planId,
            class_id: classId || null,
            tx_ref: txRef || (pending && pending.tx_ref) || null,
          }),
        });
        clearPending();
        if (classId) {
          document.getElementById("status-title").textContent = "Plan activated!";
          document.getElementById("status-msg").textContent = "Joining your live class now…";
          await completeJoinClass(classId, fakeCard(pending));
          return;
        }
        document.getElementById("status-title").textContent = "Plan activated!";
        document.getElementById("status-msg").textContent = "Redirecting to Live Class…";
        window.location.href = "app.html";
        return;
      }

      if (payType === "material" || (pending && pending.type === "material")) {
        var materialId = params.get("material_id") || (pending && pending.material_id);
        await api("/api/v1/payments/flutterwave/verify", {
          method: "POST",
          body: JSON.stringify({
            transaction_id: String(transactionId),
            material_id: materialId,
            tx_ref: txRef || (pending && pending.tx_ref) || null,
          }),
        });
        clearPending();
        window.location.href = "app.html";
        return;
      }

      clearPending();
      showError("Payment received. Open Live Class and tap Join — your plan should be active.");
    } catch (e) {
      if (classId && planId) {
        try {
          var access = await api("/api/v1/payments/live-class/" + encodeURIComponent(classId) + "/access");
          if (access && access.paid) {
            clearPending();
            document.getElementById("status-title").textContent = "Plan active";
            document.getElementById("status-msg").textContent = "Joining your live class now…";
            await completeJoinClass(classId, fakeCard(pending));
            return;
          }
        } catch (ignored) { /* fall through */ }
      }
      clearPending();
      showError(e.message || "Verification failed. Open Live Class and try Join again.");
    }
  }

  document.addEventListener("DOMContentLoaded", handleReturn);
})();
