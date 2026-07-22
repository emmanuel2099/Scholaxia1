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
    html += '<div class="sx-page-hero"><h2>CBT Packages</h2><p>Annual access — same packages as the mobile app. Pay with Paystack.</p></div>';
    if (!packages.length) {
      html += '<div class="empty-state">No packages available.</div>';
    } else {
      html += '<div class="card-grid">';
      packages.forEach(function (p) {
        var id = p.id || p.package_id || "";
        var name = p.name || p.title || id;
        var price = Number(p.price || p.amount || 0);
        html +=
          '<div class="sx-card" style="padding:18px">' +
          "<h3>" + escHtml(name) + "</h3>" +
          '<p style="color:var(--sx-grey)">' + escHtml(p.description || "1 year CBT + Sia support") + "</p>" +
          '<div style="display:flex;justify-content:space-between;align-items:center;margin-top:12px">' +
          "<strong>₦" + price.toLocaleString("en-NG") + "</strong>" +
          '<button type="button" class="btn-action btn-sm" onclick="buyCbtPackage(\'' + escHtml(id) + '\')">Pay with Paystack</button>' +
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
