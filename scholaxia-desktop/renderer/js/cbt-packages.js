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
    html += '<div class="sx-page-hero"><h2>CBT Packages</h2><p>Annual access — pay with Paystack. If you have a coupon, tap Start exam and choose coupon there.</p></div>';
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

var cbtUnlockAfter = null;

function closeCbtUnlockModal() {
  var modal = document.getElementById("cbt-unlock-modal");
  if (modal) modal.classList.add("hidden");
  cbtUnlockAfter = null;
  var choice = document.getElementById("cbt-unlock-choice");
  var coupon = document.getElementById("cbt-unlock-coupon");
  var pay = document.getElementById("cbt-unlock-pay");
  if (choice) choice.classList.remove("hidden");
  if (coupon) coupon.classList.add("hidden");
  if (pay) pay.classList.add("hidden");
  var msg = document.getElementById("cbt-unlock-msg");
  if (msg) msg.textContent = "";
}

function openCbtUnlockModal(afterUnlock) {
  cbtUnlockAfter = afterUnlock;
  var modal = document.getElementById("cbt-unlock-modal");
  if (!modal) {
    if (typeof showPage === "function") showPage("cbt-packages");
    return;
  }
  closeCbtUnlockModal();
  cbtUnlockAfter = afterUnlock;
  modal.classList.remove("hidden");
}

function cbtUnlockPick(which) {
  var choice = document.getElementById("cbt-unlock-choice");
  var coupon = document.getElementById("cbt-unlock-coupon");
  var pay = document.getElementById("cbt-unlock-pay");
  if (choice) choice.classList.add("hidden");
  if (which === "coupon") {
    if (coupon) coupon.classList.remove("hidden");
    if (pay) pay.classList.add("hidden");
  } else {
    if (coupon) coupon.classList.add("hidden");
    if (pay) pay.classList.remove("hidden");
    loadCbtUnlockPackages();
  }
}

async function loadCbtUnlockPackages() {
  var list = document.getElementById("cbt-unlock-pay-list");
  if (!list) return;
  list.innerHTML = "Loading…";
  try {
    var catalog = await api("/api/v1/payments/paystack/cbt-packages");
    var packages = (catalog && catalog.packages) || [];
    if (!packages.length) {
      list.innerHTML = "No packages listed yet.";
      return;
    }
    list.innerHTML = packages.map(function (p) {
      var id = p.id || p.package_id || "";
      var price = Number(p.price || p.amount || 0);
      return (
        '<div class="cp-card-foot" style="margin:8px 0">' +
        "<strong>" + escHtml(p.name || p.title || id) + " · ₦" + price.toLocaleString("en-NG") + "</strong> " +
        '<button type="button" class="btn-action" onclick="buyCbtPackage(\'' + escHtml(id) + '\')">Pay</button></div>'
      );
    }).join("");
  } catch (e) {
    list.innerHTML = e.message || "Could not load packages.";
  }
}

async function cbtUnlockRedeem() {
  var input = document.getElementById("cbt-unlock-code");
  var msg = document.getElementById("cbt-unlock-msg");
  var code = (input && input.value || "").trim();
  if (!code) {
    if (msg) msg.textContent = "Enter your coupon code.";
    return;
  }
  try {
    await api("/api/v1/cbt/coupons/redeem", { method: "POST", body: { code: code } });
    var next = cbtUnlockAfter;
    closeCbtUnlockModal();
    if (typeof loadCbtPackagesPage === "function") loadCbtPackagesPage();
    if (typeof next === "function") next();
  } catch (e) {
    if (msg) msg.textContent = e.message || "Invalid coupon";
  }
}

async function ensureCbtAccessThen(thenFn) {
  try {
    var access = await api("/api/v1/payments/paystack/cbt-access");
    if (access && access.has_access) {
      thenFn();
      return;
    }
  } catch (e) { /* show unlock */ }
  openCbtUnlockModal(thenFn);
}

window.closeCbtUnlockModal = closeCbtUnlockModal;
window.openCbtUnlockModal = openCbtUnlockModal;
window.cbtUnlockPick = cbtUnlockPick;
window.cbtUnlockRedeem = cbtUnlockRedeem;
window.ensureCbtAccessThen = ensureCbtAccessThen;
