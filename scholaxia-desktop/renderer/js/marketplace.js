/** Scholaxia Marketplace — native shop (matches mobile app) */

var mpProducts = [];
var mpCategory = "all";

var MP_TABS = [
  { id: "all", label: "All" },
  { id: "gadgets", label: "Gadgets" },
  { id: "laptops", label: "Laptops" },
  { id: "phones", label: "Phones" },
  { id: "books", label: "Books" },
  { id: "other", label: "Other" },
];

function mpEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function mpPrice(p) {
  var n = Number(p.price || 0);
  if (n <= 0) return "Ask price";
  return "₦" + n.toLocaleString("en-NG");
}

function mpImageUrl(url) {
  if (!url) return "";
  if (/^https?:\/\//i.test(url)) return url;
  var base = typeof API_BASE !== "undefined" ? API_BASE : "";
  return base + (url.startsWith("/") ? url : "/" + url);
}

async function loadMarketplacePage() {
  var grid = document.getElementById("marketplace-grid");
  if (!grid) return;
  grid.innerHTML = '<div class="loading">Loading marketplace…</div>';
  renderMarketplaceTabs();
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
  if (!mpProducts.length) {
    grid.innerHTML = '<div class="empty-state-premium"><div class="empty-icon">&#128722;</div><h3>No products yet</h3><p>Admin will add gadgets, laptops, phones and books here.</p></div>';
    return;
  }
  grid.innerHTML = mpProducts.map(function (p) {
    var img = mpImageUrl(p.image_url);
    return (
      '<div class="mp-product-card sx-card">' +
      (img
        ? '<div class="mp-product-img" style="background-image:url(' + mpEsc(img) + ')"></div>'
        : '<div class="mp-product-img mp-product-img-placeholder">&#128722;</div>') +
      '<div class="mp-product-body">' +
      '<span class="mp-product-cat">' + mpEsc(p.category || "item") + "</span>" +
      "<h3>" + mpEsc(p.title) + "</h3>" +
      '<p class="mp-product-desc">' + mpEsc((p.description || "").slice(0, 100)) + "</p>" +
      '<div class="mp-product-footer">' +
      '<strong class="mp-price">' + mpPrice(p) + "</strong>" +
      '<button type="button" class="btn-action btn-sm" onclick="openMarketplaceBook(\'' + mpEsc(String(p.id)) + '\')">Book item</button>' +
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
    await api("/api/v1/marketplace/products/" + productId + "/book", {
      method: "POST",
      body: JSON.stringify(body),
    });
    closeMarketplaceBook();
    alert("Booking sent! Scholaxia will contact you on WhatsApp or email.");
  } catch (ex) {
    if (err) err.textContent = ex.message || "Booking failed.";
  } finally {
    btn.disabled = false;
  }
}

if (typeof window !== "undefined") {
  window.loadMarketplacePage = loadMarketplacePage;
  window.setMarketplaceCategory = setMarketplaceCategory;
  window.openMarketplaceBook = openMarketplaceBook;
  window.closeMarketplaceBook = closeMarketplaceBook;
  window.submitMarketplaceBook = submitMarketplaceBook;
}
