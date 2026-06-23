/**
 * Flutterwave checkout for Scholaxia One-on-One Live Class monthly plans.
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

function paymentReturnUrl(ctx) {
  var base = window.location.origin + "/payment-return.html";
  if (ctx.type === "material" && ctx.material_id) {
    return base + "?ctx=material&material_id=" + encodeURIComponent(ctx.material_id);
  }
  var q = "?ctx=live&plan_id=" + encodeURIComponent(ctx.plan_id || "");
  if (ctx.class_id) q += "&class_id=" + encodeURIComponent(ctx.class_id);
  return base + q;
}

function savePaymentReturnContext(ctx) {
  var raw = JSON.stringify(ctx);
  sessionStorage.setItem("sia_pay_return", raw);
  localStorage.setItem("sia_pay_return", raw);
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
      title: ctx.custom_title || "Scholaxia Live Class",
      description: ctx.custom_description || "Monthly live class plan",
      logo: window.location.origin + "/assets/logo.png",
    },
    meta: ctx.meta || {},
    redirect_url: paymentReturnUrl(ctx),
  });
  return { redirecting: true };
}

async function payForLivePlan(planId, classId, btn) {
  await loadFlutterwaveScript();

  var init = await api("/api/v1/payments/flutterwave/live-plan/init", {
    method: "POST",
    body: JSON.stringify({
      plan_id: planId,
      class_id: classId || null,
    }),
  });

  if (init.already_paid) {
    if (classId) await completeJoinClass(classId, null);
    return { paid: true };
  }

  if (!init.public_key || !init.tx_ref) {
    throw new Error("Payment could not be started. Try again later.");
  }

  var card = btn && btn.dataset ? btn.dataset : {};
  return startFlutterwaveRedirect(init, {
    type: "live",
    plan_id: planId,
    class_id: classId || init.class_id || "",
    tx_ref: init.tx_ref,
    title: card.title || init.plan_name || "",
    custom_title: "Scholaxia — " + (init.plan_name || "Live Plan"),
    custom_description: (init.plan_name || "Monthly plan") + " — " + formatNaira(init.amount) + "/month",
    meta: { plan_id: planId, class_id: classId || "" },
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
      if (typeof scrollToLivePlans === "function") scrollToLivePlans();
      if (typeof loadLivePlans === "function") loadLivePlans(classId);
      alert("Choose a monthly live class plan below, then pay once to join this class and others for 30 days.");
      return;
    }
    await completeJoinClass(classId, card);
  } catch (e) {
    if (String(e.message || "").indexOf("402") >= 0 || String(e.message).toLowerCase().indexOf("plan") >= 0) {
      if (typeof scrollToLivePlans === "function") scrollToLivePlans();
      if (typeof loadLivePlans === "function") loadLivePlans(classId);
    }
    alert(e.message || "Could not join class.");
  }
}

window.joinClassWithPayment = joinClassWithPayment;
window.completeJoinClass = completeJoinClass;
window.payForLivePlan = payForLivePlan;

async function payForMaterial(materialId) {
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
