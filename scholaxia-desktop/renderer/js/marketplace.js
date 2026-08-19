/** Scholaxia Marketplace — native shop (matches mobile app) */

var mpProducts = [];
var mpCategory = "all";
var mpSearchQ = "";

var MP_TABS = [
  { id: "all", label: "All" },
  { id: "books", label: "Books" },
  { id: "soft_copy", label: "Soft copy / PDF" },
  { id: "software", label: "Software" },
  { id: "educational_materials", label: "Educational materials" },
  { id: "phones", label: "Phones" },
  { id: "gadgets", label: "Gadgets" },
  { id: "flash_drive", label: "Flash drive" },
  { id: "charger", label: "Charger" },
  { id: "projector", label: "Projector" },
  { id: "desktop_computer", label: "Desktop computer" },
  { id: "bags", label: "Bags" },
  { id: "laptops", label: "Laptops" },
  { id: "other", label: "Other" },
];

function mpEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function mpAttr(s) {
  return String(s == null ? "" : s)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function mpPrice(p) {
  if (p.is_free || Number(p.price || 0) <= 0) return "Free";
  return "₦" + Number(p.price || 0).toLocaleString("en-NG");
}

function mpPublicDesc(p) {
  var d = String(p.description || "");
  var cut = d.indexOf("SIA_META:");
  if (cut >= 0) d = d.slice(0, cut);
  cut = d.indexOf("---");
  if (cut >= 0 && d.indexOf("{") > cut) d = d.slice(0, cut);
  return d.replace(/\{"condition".*$/, "").trim();
}

function mpImageUrl(url) {
  if (!url) return "";
  var u = String(url).trim();
  if (!u) return "";
  if (u.indexOf("//") === 0) u = "https:" + u;
  if (/^http:\/\//i.test(u)) u = "https://" + u.slice(7);
  if (/^https?:\/\//i.test(u)) return u;
  var base = typeof API_BASE !== "undefined" ? API_BASE : "";
  return base + (u.startsWith("/") ? u : "/" + u);
}

async function loadMarketplacePage() {
  var grid = document.getElementById("marketplace-grid");
  if (!grid) return;
  grid.innerHTML = '<div class="loading">Loading marketplace…</div>';
  renderMarketplaceTabs();
  var searchEl = document.getElementById("marketplace-search");
  if (searchEl && !searchEl._bound) {
    searchEl._bound = true;
    searchEl.addEventListener("input", function () {
      mpSearchQ = (searchEl.value || "").trim().toLowerCase();
      renderMarketplaceGrid();
    });
  }
  try {
    var url = "/api/v1/marketplace/products";
    if (mpCategory && mpCategory !== "all") url += "?category=" + encodeURIComponent(mpCategory);
    var rows = await api(url);
    mpProducts = Array.isArray(rows) ? rows : (rows && rows.products) || [];
    renderMarketplaceGrid();
  } catch (e) {
    grid.innerHTML = '<div class="empty-state-premium"><h3>Could not load shop</h3><p>' + mpEsc(e.message) + "</p></div>";
  }
}

function renderMarketplaceTabs() {
  var el = document.getElementById("marketplace-tabs");
  if (!el) return;
  el.innerHTML = MP_TABS.map(function (t) {
    return '<button type="button" class="mp-tab' + (mpCategory === t.id ? " active" : "") + '" onclick="setMarketplaceCategory(\'' + t.id + '\')">' + mpEsc(t.label) + "</button>";
  }).join("");
}

function setMarketplaceCategory(cat) {
  mpCategory = cat;
  loadMarketplacePage();
}

function renderMarketplaceGrid() {
  var grid = document.getElementById("marketplace-grid");
  if (!grid) return;
  var rows = mpProducts.filter(function (p) {
    if (!mpSearchQ) return true;
    var hay = ((p.title || "") + " " + mpPublicDesc(p) + " " + (p.category || "")).toLowerCase();
    return hay.indexOf(mpSearchQ) >= 0;
  });
  if (!rows.length) {
    grid.innerHTML = '<div class="empty-state-premium"><div class="empty-icon">&#128722;</div><h3>No products yet</h3><p>Admin will add gadgets, laptops, phones and books here. Free items show as Free.</p></div>';
    return;
  }
  grid.innerHTML = rows.map(function (p) {
    var img = mpImageUrl(p.image_url || p.secure_url || p.image || "");
    var bookLabel = p.is_free || Number(p.price || 0) <= 0 ? "Get free" : "Book item";
    return (
      '<div class="mp-product-card sx-card">' +
      (img
        ? '<div class="mp-product-img"><img src="' +
          mpAttr(img) +
          '" alt="' +
          mpAttr(p.title || "Product") +
          '" loading="lazy" referrerpolicy="no-referrer" onerror="this.parentNode.classList.add(\'mp-product-img-placeholder\');this.remove();" /></div>'
        : '<div class="mp-product-img mp-product-img-placeholder">&#128722;</div>') +
      '<div class="mp-product-body">' +
      '<span class="mp-product-cat">' + mpEsc(p.category || "item") + "</span>" +
      "<h3>" + mpEsc(p.title) + "</h3>" +
      '<p class="mp-product-desc">' + mpEsc(mpPublicDesc(p).slice(0, 100)) + "</p>" +
      '<div class="mp-product-footer">' +
      '<strong class="mp-price">' + mpPrice(p) + "</strong>" +
      '<button type="button" class="btn-action btn-sm" onclick="openMarketplaceBook(\'' + mpEsc(String(p.id)) + '\')">' + bookLabel + "</button>" +
      "</div></div></div>"
    );
  }).join("");
}

function openMarketplaceBook(productId) {
  var p = mpProducts.find(function (x) { return String(x.id) === String(productId); });
  if (!p) return;
  if (!isStudentLoggedIn()) {
    goToLogin("marketplace");
    return;
  }
  var modal = document.getElementById("marketplace-book-modal");
  if (!modal) return;
  document.getElementById("mp-book-product-id").value = productId;
  document.getElementById("mp-book-title").textContent = "Book: " + (p.title || "Item");
  document.getElementById("mp-book-price").textContent = mpPrice(p);
  var user = getUser();
  document.getElementById("mp-book-name").value = user.name || "";
  document.getElementById("mp-book-email").value = user.email || "";
  document.getElementById("mp-book-error").textContent = "";
  modal.classList.remove("hidden");
}

function closeMarketplaceBook() {
  var modal = document.getElementById("marketplace-book-modal");
  if (modal) modal.classList.add("hidden");
}

async function submitMarketplaceBook(e) {
  e.preventDefault();
  var err = document.getElementById("mp-book-error");
  var btn = document.getElementById("mp-book-submit");
  var productId = document.getElementById("mp-book-product-id").value;
  var product = mpProducts.find(function (x) { return String(x.id) === String(productId); });
  var price = Number(product && product.price ? product.price : 0);
  var body = {
    full_name: document.getElementById("mp-book-name").value.trim(),
    email: document.getElementById("mp-book-email").value.trim(),
    phone: document.getElementById("mp-book-phone").value.trim(),
    whatsapp: document.getElementById("mp-book-whatsapp").value.trim(),
    note: document.getElementById("mp-book-note").value.trim(),
  };
  if (!body.full_name || !body.email || !body.phone || !body.whatsapp) {
    if (err) err.textContent = "Name, email, phone and WhatsApp are required.";
    return;
  }
  btn.disabled = true;
  if (err) err.textContent = "";
  try {
    var booking = await api("/api/v1/marketplace/products/" + productId + "/book", {
      method: "POST",
      body: JSON.stringify(body),
    });
    var bookingId = booking && (booking.id || booking.booking_id);
    if (price > 0 && bookingId && typeof paystackPurchase === "function") {
      btn.textContent = "Opening Paystack…";
      var paid = await paystackPurchase({
        productType: "marketplace_booking",
        productId: String(bookingId),
      });
      closeMarketplaceBook();
      if (paid) {
        alert("Payment successful! Booking confirmed — Scholaxia will contact you.");
      } else {
        alert("Booking saved. Complete Paystack payment to confirm, or try again from support.");
      }
    } else {
      closeMarketplaceBook();
      alert("Booking sent! Scholaxia will contact you on WhatsApp or email.");
    }
  } catch (ex) {
    if (err) err.textContent = ex.message || "Booking failed.";
  } finally {
    btn.disabled = false;
    btn.textContent = "Submit booking";
  }
}

if (typeof window !== "undefined") {
  window.loadMarketplacePage = loadMarketplacePage;
  window.setMarketplaceCategory = setMarketplaceCategory;
  window.openMarketplaceBook = openMarketplaceBook;
  window.closeMarketplaceBook = closeMarketplaceBook;
  window.submitMarketplaceBook = submitMarketplaceBook;
}
