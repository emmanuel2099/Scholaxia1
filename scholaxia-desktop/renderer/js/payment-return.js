(function () {
  function showError(msg) {
    var spinner = document.getElementById("spinner");
    var title = document.getElementById("status-title");
    var statusMsg = document.getElementById("status-msg");
    var err = document.getElementById("status-err");
    if (spinner) spinner.style.display = "none";
    if (title) title.textContent = "Payment not completed";
    if (statusMsg) statusMsg.textContent = msg;
    if (err) {
      err.classList.remove("hidden");
      err.innerHTML = '<a href="app.html">Back to Scholaxia</a>';
    }
  }

  function readPending() {
    try {
      return JSON.parse(sessionStorage.getItem("sia_pay_return") || "null");
    } catch (e) {
      return null;
    }
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
    var transactionId = params.get("transaction_id");
    var txRef = params.get("tx_ref");
    var pending = readPending();

    if (status === "cancelled" || status === "failed") {
      sessionStorage.removeItem("sia_pay_return");
      showError("You cancelled or the payment did not go through. Try again from Live Class.");
      return;
    }

    if (status !== "successful" || !transactionId) {
      sessionStorage.removeItem("sia_pay_return");
      showError("We could not confirm this payment. If you were charged, contact support with reference: " + (txRef || "unknown"));
      return;
    }

    var payType = pending && pending.type;
    try {
      if (payType === "live" && pending.class_id) {
        await api("/api/v1/payments/flutterwave/verify", {
          method: "POST",
          body: JSON.stringify({
            transaction_id: String(transactionId),
            class_id: pending.class_id,
            tx_ref: txRef || pending.tx_ref || null,
          }),
        });
        sessionStorage.removeItem("sia_pay_return");
        document.getElementById("status-title").textContent = "Payment successful!";
        document.getElementById("status-msg").textContent = "Joining your class now…";
        await completeJoinClass(pending.class_id, fakeCard(pending));
        return;
      }

      if (payType === "material" && pending.material_id) {
        await api("/api/v1/payments/flutterwave/verify", {
          method: "POST",
          body: JSON.stringify({
            transaction_id: String(transactionId),
            material_id: pending.material_id,
            tx_ref: txRef || pending.tx_ref || null,
          }),
        });
        sessionStorage.removeItem("sia_pay_return");
        document.getElementById("status-title").textContent = "Payment successful!";
        document.getElementById("status-msg").textContent = "Opening your material…";
        window.location.href = "app.html#library";
        return;
      }

      sessionStorage.removeItem("sia_pay_return");
      showError("Payment received but session details were lost. Open Live Class and tap Join again — you should not be charged twice.");
    } catch (e) {
      sessionStorage.removeItem("sia_pay_return");
      showError(e.message || "Verification failed. Try joining again from Live Class.");
    }
  }

  document.addEventListener("DOMContentLoaded", handleReturn);
})();
