/**
 * Flutterwave checkout before joining a live class.
 */
function loadFlutterwaveScript() {
  return new Promise(function (resolve, reject) {
    if (window.FlutterwaveCheckout) {
      resolve();
      return;
    }
    var s = document.createElement("script");
    s.src = "https://checkout.flutterwave.com/v3.js";
    s.onload = function () { resolve(); };
    s.onerror = function () { reject(new Error("Could not load Flutterwave checkout")); };
    document.head.appendChild(s);
  });
}

function formatNaira(amount) {
  return "₦" + Number(amount).toLocaleString("en-NG");
}

async function payForLiveClass(classId, cardMeta) {
  await loadFlutterwaveScript();

  var init = await api("/api/v1/payments/flutterwave/live-class/" + encodeURIComponent(classId) + "/init", {
    method: "POST",
  });

  if (init.already_paid) {
    return { paid: true };
  }

  if (!init.public_key || !init.tx_ref) {
    throw new Error("Payment could not be started. Try again later.");
  }

  var user = typeof getUser === "function" ? getUser() : { name: "Student", email: "" };
  var customer = init.customer || {};
  var email = customer.email || localStorage.getItem("sia_email") || "student@scholaxia.local";
  var name = customer.name || user.name || "Student";

  return new Promise(function (resolve, reject) {
    window.FlutterwaveCheckout({
      public_key: init.public_key,
      tx_ref: init.tx_ref,
      amount: init.amount,
      currency: init.currency || "NGN",
      payment_options: "card, banktransfer, ussd",
      customer: { email: email, name: name },
      customizations: {
        title: "Scholaxia Live Class",
        description: (init.class_title || "Live class") + " — " + (init.class_subject || ""),
        logo: "assets/logo.png",
      },
      meta: { class_id: classId, student_id: localStorage.getItem("sia_token") ? "student" : "" },
      callback: function (response) {
        if (response.status !== "successful") {
          reject(new Error("Payment was not completed."));
          return;
        }
        api("/api/v1/payments/flutterwave/verify", {
          method: "POST",
          body: JSON.stringify({
            transaction_id: String(response.transaction_id),
            class_id: classId,
            tx_ref: init.tx_ref,
          }),
        }).then(function (verified) {
          resolve(verified);
        }).catch(reject);
      },
      onclose: function () {
        reject(new Error("Payment window closed."));
      },
    });
  });
}

async function completeJoinClass(classId, card) {
  var data = await api("/api/v1/live-classes/" + classId + "/join", { method: "POST" });
  localStorage.setItem("live_session", JSON.stringify({
    class_id: classId,
    classId: classId,
    room_id: data.room_id,
    channel_id: data.channel_id,
    agora_token: data.agora_token,
    uid: data.uid,
    app_id: data.app_id,
    title: data.title || (card && card.dataset.title) || "Live Class",
    subject: data.subject || (card && card.dataset.subject) || "",
    teacher_name: (card && card.dataset.teacher) || "",
    role: "student",
    end_time: data.end_time || (card && card.dataset.end) || null,
  }));
  window.location.href = "classroom.html";
}

async function joinClassWithPayment(btn) {
  var classId = typeof btn === "string" ? btn : btn.dataset.id;
  var card = typeof btn === "string" ? null : btn;

  try {
    var access = await api("/api/v1/payments/live-class/" + encodeURIComponent(classId) + "/access");
    if (!access.paid) {
      var price = formatNaira(access.amount || 2000);
      var title = (card && card.dataset.title) || "this live class";
      if (!confirm("Join \"" + title + "\"?\n\nPay " + price + " with Flutterwave (card, bank, or USSD) before entering.")) {
        return;
      }
      await payForLiveClass(classId, card);
    }
    await completeJoinClass(classId, card);
  } catch (e) {
    alert(e.message || "Could not join class.");
  }
}

window.joinClassWithPayment = joinClassWithPayment;
window.completeJoinClass = completeJoinClass;
