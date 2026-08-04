/* Paystack checkout — redirects to Paystack (reliable on mobile + desktop) */
(function (global) {
  async function paystackPurchase(opts) {
    var api = global.ScholaxiaAPI;
    if (!api || typeof api.api !== "function") {
      throw new Error("API helper not loaded.");
    }
    var productType = opts && opts.productType;
    var productId = opts && opts.productId;
    if (!productType || !productId) throw new Error("Missing payment product.");
    if (typeof navigator !== "undefined" && !navigator.onLine) {
      throw new Error("Payment requires internet. Connect and try again.");
    }

    var body = {
      product_type: productType,
      product_id: String(productId),
    };
    [
      "payment_mode",
      "installment",
      "full_name",
      "phone",
      "email",
      "location",
      "preferred_start",
      "notes",
    ].forEach(function (k) {
      if (opts[k] != null && opts[k] !== "") body[k] = opts[k];
    });

    var initialized = await api.api("/api/v1/payments/paystack/initialize", {
      method: "POST",
      body: body,
    });
    if (initialized && (initialized.already_owned || initialized.already_paid)) {
      return true;
    }

    var url = (initialized && initialized.authorization_url) || "";
    var reference = (initialized && initialized.reference) || "";
    if (!url || !reference) throw new Error("Paystack checkout is unavailable.");

    // Save pending payment so we can verify when user returns
    sessionStorage.setItem(
      "sia_paystack_pending",
      JSON.stringify({
        reference: reference,
        productType: productType,
        productId: String(productId),
        returnPage: opts.returnPage || "subscription",
      })
    );

    // Always go to Paystack (popup is often blocked / confusing on mobile)
    window.location.href = url;
    return false;
  }

  async function resumePendingPaystack() {
    var raw = sessionStorage.getItem("sia_paystack_pending");
    if (!raw) return null;
    sessionStorage.removeItem("sia_paystack_pending");
    try {
      var pending = JSON.parse(raw);
      if (!pending || !pending.reference) return null;
      var api = global.ScholaxiaAPI;
      var result = await api.api("/api/v1/payments/paystack/verify", {
        method: "POST",
        body: { reference: pending.reference },
      });
      return {
        paid: !!(result && (result.paid === true || result.has_access === true)),
        pending: pending,
        result: result,
      };
    } catch (e) {
      return { paid: false, error: e, pending: null };
    }
  }

  global.paystackPurchase = paystackPurchase;
  global.resumePendingPaystack = resumePendingPaystack;
})(window);
