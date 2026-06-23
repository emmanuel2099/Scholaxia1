/**
 * Flutterwave checkout for Scholaxia One-on-One Live Class monthly plans.
 */
var _livePayBusy = false;

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
  if (ctx.type === "book" && ctx.book_id) {
    return base + "?ctx=book&book_id=" + encodeURIComponent(ctx.book_id);
  }
  var q = "?ctx=live&plan_id=" + encodeURIComponent(ctx.plan_id || "");
  if (ctx.class_id) q += "&class_id=" + encodeURIComponent(ctx.class_id);
  return base + q;
}

function savePaymentReturnContext(ctx) {
  var raw = JSON.stringify(ctx);
  sessionStorage.setItem("sia_pay_return", raw);
  localStorage.setItem("sia_pay_return", raw);
  if (ctx.tx_ref) {
    localStorage.setItem("sia_plan_pending_verify", JSON.stringify({
      tx_ref: ctx.tx_ref,
      plan_id: ctx.plan_id || "",
      class_id: ctx.class_id || "",
    }));
  }
}

function clearPlanPaymentPending() {
  localStorage.removeItem("sia_plan_pending_verify");
  try { sessionStorage.removeItem("sia_live_plans_cache"); } catch (e) { /* ignore */ }
  if (typeof window._livePlansCache !== "undefined") window._livePlansCache = null;
}

async function reconcilePendingPlanPayment() {
  var raw = localStorage.getItem("sia_plan_pending_verify");
  var txRef = null;
  if (raw) {
    try { txRef = JSON.parse(raw).tx_ref || null; } catch (e) { /* ignore */ }
  }
  try {
    var result = await api("/api/v1/payments/flutterwave/reconcile-plan", {
      method: "POST",
      body: JSON.stringify({ tx_ref: txRef }),
    });
    if (result && (result.paid || result.reconciled)) {
      clearPlanPaymentPending();
      return true;
    }
  } catch (e) { /* ignore */ }
  return false;
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

function setJoinButtonBusy(btn, busy, label) {
  if (!btn) return;
  btn.disabled = !!busy;
  if (busy) {
    if (!btn.dataset.prevLabel) btn.dataset.prevLabel = btn.textContent;
    btn.textContent = label || "Please wait…";
  } else if (btn.dataset.prevLabel) {
    btn.textContent = btn.dataset.prevLabel;
  }
}

async function payForLivePlan(planId, classId, btn) {
  if (_livePayBusy) return;
  if (!planId) {
    alert("Plan not found. Refresh the page and try again.");
    return;
  }
  _livePayBusy = true;
  setJoinButtonBusy(btn, true, "Opening payment…");
  try {
    await loadFlutterwaveScript();

    var init = await api("/api/v1/payments/flutterwave/live-plan/init", {
      method: "POST",
      body: JSON.stringify({
        plan_id: planId,
        class_id: classId || null,
      }),
    });

    if (!init) throw new Error("Could not start payment.");

    if (init.already_paid) {
      if (classId) await completeJoinClass(classId, null);
      return { paid: true };
    }

    if (!init.public_key || !init.tx_ref) {
      throw new Error("Payment could not be started. Try again later.");
    }

    return startFlutterwaveRedirect(init, {
      type: "live",
      plan_id: planId,
      class_id: classId || init.class_id || "",
      tx_ref: init.tx_ref,
      custom_title: "Scholaxia — " + (init.plan_name || "Live Plan"),
      custom_description: (init.plan_name || "Monthly plan") + " — " + formatNaira(init.amount) + "/month",
      meta: { plan_id: planId, class_id: classId || "" },
    });
  } catch (e) {
    alert(e.message || "Payment could not start.");
    throw e;
  } finally {
    _livePayBusy = false;
    setJoinButtonBusy(btn, false);
  }
}

async function completeJoinClass(classId, card) {
  if (!classId) throw new Error("Class not found.");
  var data = await api("/api/v1/live-classes/" + classId + "/join", { method: "POST" });
  if (!data) throw new Error("Could not join class.");
  localStorage.setItem("live_session", JSON.stringify({
    class_id: classId,
    classId: classId,
    room_id: data.room_id,
    channel_id: data.channel_id,
    agora_token: data.agora_token,
    uid: data.uid,
    app_id: data.app_id,
    title: data.title || (card && card.dataset && card.dataset.title) || "Live Class",
    subject: data.subject || (card && card.dataset && card.dataset.subject) || "",
    teacher_name: (card && card.dataset && card.dataset.teacher) || "",
    role: "student",
    end_time: data.end_time || (card && card.dataset && card.dataset.end) || null,
  }));
  window.location.href = "classroom.html";
}

async function joinClassWithPayment(btn) {
  if (_livePayBusy) return;
  var classId = typeof btn === "string" ? btn : (btn && (btn.getAttribute("data-id") || btn.dataset.id));
  var card = typeof btn === "string" ? null : btn;
  if (!classId) {
    alert("Class not found. Refresh and try again.");
    return;
  }

  _livePayBusy = true;
  setJoinButtonBusy(card, true, "Joining…");
  try {
    var reconciled = await reconcilePendingPlanPayment();
    if (reconciled) {
      if (typeof clearPlansCache === "function") clearPlansCache();
      else {
        try { sessionStorage.removeItem("sia_live_plans_cache"); } catch (e) { /* ignore */ }
      }
    }
    var access = await api("/api/v1/payments/live-class/" + encodeURIComponent(classId) + "/access");
    if (!access || !access.paid) {
      if (typeof scrollToLivePlans === "function") scrollToLivePlans();
      if (typeof loadLivePlans === "function") loadLivePlans(classId, false);
      alert("Choose a monthly plan below, then pay once to join this class.");
      return;
    }
    await completeJoinClass(classId, card);
  } catch (e) {
    var msg = e.message || "Could not join class.";
    if (msg.toLowerCase().indexOf("plan") >= 0 || msg.indexOf("402") >= 0) {
      if (typeof scrollToLivePlans === "function") scrollToLivePlans();
      if (typeof loadLivePlans === "function") loadLivePlans(classId, false);
    }
    alert(msg);
  } finally {
    _livePayBusy = false;
    setJoinButtonBusy(card, false);
  }
}

function bindLivePageClickHandlers() {
  if (window._livePageClicksBound) return;
  window._livePageClicksBound = true;

  document.addEventListener("click", function (e) {
    var planBtn = e.target.closest(".live-plan-pay");
    if (planBtn && planBtn.closest("#page-live")) {
      e.preventDefault();
      e.stopPropagation();
      var planId = planBtn.getAttribute("data-plan-id");
      var classId = planBtn.getAttribute("data-class-id") ||
        (typeof getPendingJoinClassId === "function" ? getPendingJoinClassId() : "") || "";
      payForLivePlan(planId, classId || null, planBtn);
      return;
    }

    var joinBtn = e.target.closest(".btn-join[data-id]");
    if (joinBtn && joinBtn.closest("#page-live, #page-skills")) {
      e.preventDefault();
      e.stopPropagation();
      joinClassWithPayment(joinBtn);
    }
  }, true);
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", bindLivePageClickHandlers);
} else {
  bindLivePageClickHandlers();
}

window.joinClassWithPayment = joinClassWithPayment;
window.completeJoinClass = completeJoinClass;
window.payForLivePlan = payForLivePlan;
window.reconcilePendingPlanPayment = reconcilePendingPlanPayment;
window.clearPlanPaymentPending = clearPlanPaymentPending;

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

async function payForBook(bookId) {
  await loadFlutterwaveScript();

  var init = await api("/api/v1/payments/flutterwave/book/" + encodeURIComponent(bookId) + "/init", {
    method: "POST",
  });

  if (init.already_paid || init.is_free) {
    return { paid: true, has_access: true };
  }

  if (!init.public_key || !init.tx_ref) {
    throw new Error("Payment could not be started. Try again later.");
  }

  return startFlutterwaveRedirect(init, {
    type: "book",
    book_id: bookId,
    tx_ref: init.tx_ref,
    custom_title: "Scholaxia Materials",
    custom_description: (init.book_title || "Study material") + " — " + (init.book_subject || ""),
    meta: { book_id: bookId },
  });
}

window.payForBook = payForBook;
