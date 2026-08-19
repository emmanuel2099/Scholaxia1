/** CBT annual packages — Paystack (matches mobile CbtPackagesScreen). */

async function loadCbtPackagesPage() {
  var el = document.getElementById("cbt-packages-root");
  if (!el) return;
  if (!isStudentLoggedIn()) {
    el.innerHTML = '<div class="empty-state-premium"><h3>Sign in required</h3><p>Log in to buy CBT packages.</p></div>';
    return;
  }
  el.innerHTML = '<div class="loading">Loading CBT packages…</div>';
  try {
    var access = await api("/api/v1/payments/paystack/cbt-access");
    var catalog = await api("/api/v1/payments/paystack/cbt-packages");
    var packages = (catalog && catalog.packages) || [];
    var html = "";
    if (access && access.has_access) {
      html +=
        '<div class="info-banner success">You have active CBT access' +
        (access.expires_at ? " until " + escHtml(String(access.expires_at).slice(0, 10)) : "") +
        ".</div>";
    }
    html += '<div class="sx-page-hero"><h2>CBT Packages</h2><p>Annual access — pay with Paystack, or redeem an admin coupon to skip payment.</p></div>';
    html += '<div class="sx-card" style="margin-bottom:16px"><h3>Coupon code</h3><p>Paste the code admin sent you.</p><input id="cbt-coupon-input" placeholder="SX-XXXX" style="width:100%;margin:8px 0;padding:10px;border-radius:8px" /><button type="button" class="btn-action" onclick="redeemCbtCoupon()">Redeem coupon</button><p id="cbt-coupon-msg" class="cbt-hint"></p></div>';
    if (!packages.length) {
      html += '<div class="empty-state">No packages available.</div>';
    } else {
      html += '<div class="card-grid">';
      packages.forEach(function (p) {
        var id = p.id || p.package_id || "";
        var name = p.name || p.title || id;
        var price = Number(p.price || p.amount || 0);
        html +=
          '<div class="sx-card cp-card">' +
          "<h3>" + escHtml(name) + "</h3>" +
          '<p class="cp-desc">' + escHtml(p.description || "1 year CBT + Sia support") + "</p>" +
          '<div class="cp-card-foot">' +
          '<strong class="cp-price">₦' + price.toLocaleString("en-NG") + "</strong>" +
          '<button type="button" class="btn-action" onclick="buyCbtPackage(\'' + escHtml(id) + '\')">Pay with Paystack</button>' +
          "</div></div>";
      });
      html += "</div>";
    }
    el.innerHTML = html;
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escHtml(e.message || "Could not load packages.") + "</div>";
  }
}

async function buyCbtPackage(packageId) {
  if (!packageId) return;
  if (typeof paystackPurchase !== "function") {
    alert("Payment module not loaded.");
    return;
  }
  try {
    var ok = await paystackPurchase({
      productType: "cbt_package",
      productId: packageId,
    });
    if (ok) {
      alert("Payment successful! CBT access unlocked.");
      loadCbtPackagesPage();
      if (typeof loadCbtHubPage === "function") loadCbtHubPage();
    } else {
      alert("Payment was not completed.");
    }
  } catch (e) {
    alert(e.message || "Payment failed.");
  }
}

function escHtml(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

window.loadCbtPackagesPage = loadCbtPackagesPage;
window.buyCbtPackage = buyCbtPackage;

async function redeemCbtCoupon() {
  var input = document.getElementById("cbt-coupon-input");
  var msg = document.getElementById("cbt-coupon-msg");
  var code = (input && input.value || "").trim();
  if (!code) return;
  try {
    var data = await api("/api/v1/cbt/coupons/redeem", { method: "POST", body: { code: code } });
    if (msg) msg.textContent = (data && data.message) || "Unlocked.";
    loadCbtPackagesPage();
  } catch (e) {
    if (msg) msg.textContent = e.message || "Invalid coupon";
  }
}
window.redeemCbtCoupon = redeemCbtCoupon;
