/**
 * Flutterwave checkout before joining a live class.
 * Uses full-page redirect (not iframe modal) so WebView2 desktop can complete payment.
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

function paymentReturnUrl() {
  return window.location.origin + "/payment-return.html";
}

function savePaymentReturnContext(ctx) {
  sessionStorage.setItem("sia_pay_return", JSON.stringify(ctx));
}

function startFlutterwaveRedirect(init, ctx) {
  savePaymentReturnContext(ctx);
  var user = typeof getUser === "function" ? getUser() : { name: "Student", email: "" };
  var customer = init.customer || {};
  var email = customer.email || localStorage.getItem("sia_email") || "student@scholaxia.local";
  var name = customer.name || user.name || "Student";

  window.FlutterwaveCheckout({
    public_key: init.public_key,
    tx_ref: init.tx_ref,
    amount: init.amount,
    currency: init.currency || "NGN",
    payment_options: "card, banktransfer, ussd",
    customer: { email: email, name: name },
    customizations: {
      title: ctx.custom_title || "Scholaxia",
      description: ctx.custom_description || "Payment",
      logo: window.location.origin + "/assets/logo.png",
    },
    meta: ctx.meta || {},
    redirect_url: paymentReturnUrl(),
  });
  return { redirecting: true };
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

  var card = cardMeta && cardMeta.dataset ? cardMeta.dataset : {};
  return startFlutterwaveRedirect(init, {
    type: "live",
    class_id: classId,
    tx_ref: init.tx_ref,
    title: card.title || init.class_title || "",
    subject: card.subject || init.class_subject || "",
    teacher: card.teacher || "",
    end_time: card.end || "",
    custom_title: "Scholaxia Live Class",
    custom_description: (init.class_title || "Live class") + " — " + (init.class_subject || ""),
    meta: { class_id: classId },
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
      var payResult = await payForLiveClass(classId, card);
      if (payResult && payResult.redirecting) {
        return;
      }
    }
    await completeJoinClass(classId, card);
  } catch (e) {
    alert(e.message || "Could not join class.");
  }
}

window.joinClassWithPayment = joinClassWithPayment;
window.completeJoinClass = completeJoinClass;

async function payForMaterial(materialId, meta) {
  await loadFlutterwaveScript();

  var init = await api("/api/v1/payments/flutterwave/material/" + encodeURIComponent(materialId) + "/init", {
    method: "POST",
  });

  if (init.already_paid || init.is_free) {
    return { paid: true, has_access: true };
  }

  if (!init.public_key || !init.tx_ref) {
    throw new Error("Payment could not be started. Try again later.");
  }

  return startFlutterwaveRedirect(init, {
    type: "material",
    material_id: materialId,
    tx_ref: init.tx_ref,
    custom_title: "Scholaxia Library",
    custom_description: (init.material_title || "Study material") + " — " + (init.material_subject || ""),
    meta: { material_id: materialId },
  });
}

window.payForMaterial = payForMaterial;
