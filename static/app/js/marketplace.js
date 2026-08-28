(function () {
  var api = window.ScholaxiaAPI;
  var products = [];
  var activeCat = "all";
  var searchQuery = "";
  var guestCart = [];
  var CART_KEY = "sia_market_guest_cart";

  function $(id) {
    return document.getElementById(id);
  }

  function money(n) {
    var v = Math.round(Number(n) || 0);
    return "₦" + v.toString().replace(/\B(?=(\d{3})+(?!\d))/g, ",");
  }

  function toast(msg) {
    var el = $("mktToast");
    if (!el) return;
    el.textContent = msg;
    el.hidden = false;
    clearTimeout(toast._t);
    toast._t = setTimeout(function () {
      el.hidden = true;
    }, 2600);
  }

  function isBuyerLoggedIn() {
    var role = (localStorage.getItem("sia_role") || "").toLowerCase();
    return !!(api.getToken() && (role === "student" || role === "kind"));
  }

  function loadGuestCart() {
    try {
      guestCart = JSON.parse(localStorage.getItem(CART_KEY) || "[]") || [];
    } catch (e) {
      guestCart = [];
    }
  }

  function saveGuestCart() {
    localStorage.setItem(CART_KEY, JSON.stringify(guestCart));
  }

  function cartCount() {
    if (isBuyerLoggedIn()) return cartCount._server || 0;
    return guestCart.reduce(function (sum, it) {
      return sum + (it.quantity || 1);
    }, 0);
  }

  function setCartBadge() {
    var el = $("cartCount");
    if (el) el.textContent = String(cartCount());
  }

  function openRoleModal() {
    $("roleModal").hidden = false;
  }

  function closeRoleModal() {
    $("roleModal").hidden = true;
  }

  function openCheckoutModal() {
    $("checkoutModal").hidden = false;
  }

  function closeCheckoutModal() {
    $("checkoutModal").hidden = true;
  }

  function marketAuthUrl(pick, mode) {
    var base = "portal.html?market=1&mode=" + (mode || "signup");
    if (pick === "vendor") {
      return (
        base +
        "&role=vendor&next=" +
        encodeURIComponent("marketplace.html?vendor=pending")
      );
    }
    return (
      base +
      "&role=student&next=" +
      encodeURIComponent("marketplace.html?checkout=1")
    );
  }

  function goAuth(pick) {
    window.location.href = marketAuthUrl(pick, "signup");
  }

  async function syncServerCartCount() {
    if (!isBuyerLoggedIn()) {
      cartCount._server = 0;
      setCartBadge();
      return;
    }
    try {
      var cart = await api.api("/api/v1/marketplace/cart");
      var items = (cart && cart.items) || [];
      cartCount._server = items.reduce(function (s, it) {
        return s + (it.quantity || 1);
      }, 0);
    } catch (e) {
      cartCount._server = 0;
    }
    setCartBadge();
  }

  async function flushGuestCartToServer() {
    if (!isBuyerLoggedIn() || !guestCart.length) return;
    for (var i = 0; i < guestCart.length; i++) {
      var it = guestCart[i];
      try {
        await api.api("/api/v1/marketplace/cart/add", {
          method: "POST",
          body: { product_id: it.product_id, quantity: it.quantity || 1 },
        });
      } catch (e) { /* skip bad lines */ }
    }
    guestCart = [];
    saveGuestCart();
  }

  function filteredProducts() {
    var list =
      activeCat === "all"
        ? products.slice()
        : products.filter(function (p) {
            return (p.category || "").toLowerCase() === activeCat;
          });
    var q = searchQuery.trim().toLowerCase();
    if (!q) return list;
    return list.filter(function (p) {
      var hay = [
        p.title,
        p.name,
        p.description,
        p.category,
      ]
        .join(" ")
        .toLowerCase();
      return hay.indexOf(q) >= 0;
    });
  }

  function renderTabs() {
    var wrap = $("mktTabs");
    if (!wrap) return;
    var cats = ["all"].concat(
      Array.from(
        new Set(
          products
            .map(function (p) {
              return (p.category || "").toLowerCase();
            })
            .filter(Boolean)
        )
      )
    );
    wrap.innerHTML = cats
      .map(function (c) {
        var label = c === "all" ? "All" : c.charAt(0).toUpperCase() + c.slice(1);
        return (
          '<button type="button" class="mkt-tab' +
          (c === activeCat ? " is-active" : "") +
          '" data-cat="' +
          c +
          '">' +
          label +
          "</button>"
        );
      })
      .join("");
  }

  function renderGrid() {
    var grid = $("mktGrid");
    if (!grid) return;
    var list = filteredProducts();
    if (!list.length) {
      grid.innerHTML = '<div class="mkt-empty">No products match this filter yet.</div>';
      return;
    }
    grid.innerHTML = list
      .map(function (p, i) {
        var img = p.image_url || p.secure_url || "";
        var desc = (p.description || "").trim();
        var price = Number(p.price || 0);
        return (
          '<article class="mkt-item mkt-item-enter" style="animation-delay:' +
          Math.min(i, 14) * 0.09 +
          's">' +
          '<div class="mkt-item-media">' +
          (img
            ? '<img src="' +
              img.replace(/"/g, "") +
              '" alt="" loading="lazy" />'
            : "") +
          "</div>" +
          '<div class="mkt-item-body">' +
          '<p class="mkt-item-cat">' +
          escapeHtml(p.category || "item") +
          "</p>" +
          '<h3 class="mkt-item-title">' +
          escapeHtml(p.title || "Product") +
          "</h3>" +
          (desc
            ? '<p class="mkt-item-desc">' + escapeHtml(desc) + "</p>"
            : "") +
          '<div class="mkt-item-foot">' +
          '<span class="mkt-price">' +
          (price > 0 ? money(price) : "Ask price") +
          "</span>" +
          '<button type="button" class="mkt-add" data-add="' +
          escapeHtml(String(p.id || "")) +
          '">Add to cart</button>' +
          "</div></div></article>"
        );
      })
      .join("");
  }

  function escapeHtml(s) {
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  async function addToCart(productId) {
    var product = products.filter(function (p) {
      return String(p.id) === String(productId);
    })[0];
    if (!product) return;
    if (!(Number(product.price) > 0)) {
      toast("This item has no checkout price yet.");
      return;
    }

    if (!isBuyerLoggedIn()) {
      var existing = guestCart.filter(function (it) {
        return String(it.product_id) === String(productId);
      })[0];
      if (existing) existing.quantity = (existing.quantity || 1) + 1;
      else {
        guestCart.push({
          product_id: productId,
          title: product.title,
          price: product.price,
          quantity: 1,
        });
      }
      saveGuestCart();
      setCartBadge();
      toast("Added — sign in at checkout");
      return;
    }

    try {
      await api.api("/api/v1/marketplace/cart/add", {
        method: "POST",
        body: { product_id: productId, quantity: 1 },
      });
      await syncServerCartCount();
      toast("Added to cart");
    } catch (err) {
      toast(err.message || "Could not add to cart");
    }
  }

  async function renderCartBody() {
    var body = $("cartBody");
    var totalEl = $("cartTotal");
    if (!body) return;

    if (isBuyerLoggedIn()) {
      try {
        var cart = await api.api("/api/v1/marketplace/cart");
        var items = (cart && cart.items) || [];
        cartCount._server = items.reduce(function (s, it) {
          return s + (it.quantity || 1);
        }, 0);
        setCartBadge();
        if (!items.length) {
          body.innerHTML = '<p class="mkt-empty">Your cart is empty.</p>';
          if (totalEl) totalEl.textContent = money(0);
          return;
        }
        body.innerHTML = items
          .map(function (it) {
            var title =
              (it.product && it.product.title) || it.title || "Product";
            return (
              '<div class="mkt-cart-row">' +
              "<strong>" +
              escapeHtml(title) +
              "</strong>" +
              "<span>Qty " +
              (it.quantity || 1) +
              " · " +
              money(it.line_total || 0) +
              "</span>" +
              '<button type="button" data-remove="' +
              escapeHtml(String(it.id || "")) +
              '">Remove</button>' +
              "</div>"
            );
          })
          .join("");
        if (totalEl) totalEl.textContent = money(cart.total_amount || 0);
      } catch (err) {
        body.innerHTML =
          '<p class="mkt-empty">' +
          escapeHtml(err.message || "Could not load cart") +
          "</p>";
      }
      return;
    }

    if (!guestCart.length) {
      body.innerHTML = '<p class="mkt-empty">Your cart is empty.</p>';
      if (totalEl) totalEl.textContent = money(0);
      return;
    }
    var total = 0;
    body.innerHTML = guestCart
      .map(function (it, idx) {
        var line = (Number(it.price) || 0) * (it.quantity || 1);
        total += line;
        return (
          '<div class="mkt-cart-row">' +
          "<strong>" +
          escapeHtml(it.title || "Product") +
          "</strong>" +
          "<span>Qty " +
          (it.quantity || 1) +
          " · " +
          money(line) +
          "</span>" +
          '<button type="button" data-remove-guest="' +
          idx +
          '">Remove</button>' +
          "</div>"
        );
      })
      .join("");
    if (totalEl) totalEl.textContent = money(total);
  }

  async function openCart() {
    $("cartDrawer").hidden = false;
    await renderCartBody();
  }

  function closeCart() {
    $("cartDrawer").hidden = true;
  }

  async function beginCheckout() {
    if (!isBuyerLoggedIn()) {
      openRoleModal();
      return;
    }
    if (guestCart.length) await flushGuestCartToServer();
    await renderCartBody();
    if (isBuyerLoggedIn() && !(cartCount._server > 0) && !guestCart.length) {
      toast("Your cart is empty.");
      return;
    }
    openCheckoutModal();
  }

  async function submitCheckout(e) {
    e.preventDefault();
    var address = $("checkoutAddress").value.trim();
    var phone = $("checkoutPhone").value.trim();
    if (address.length < 5) {
      toast("Enter a fuller delivery address.");
      return;
    }
    if (phone.length < 7) {
      toast("Enter a valid phone number.");
      return;
    }

    var btn = e.target.querySelector('button[type="submit"]');
    if (btn) {
      btn.disabled = true;
      btn.textContent = "Creating order…";
    }

    try {
      var res = await api.api("/api/v1/marketplace/checkout", {
        method: "POST",
        body: {
          delivery_address: address,
          contact_phone: phone,
        },
      });
      var orderId = res && res.order_id;
      if (!orderId) throw new Error("Checkout did not return an order id.");

      closeCheckoutModal();
      closeCart();

      if (typeof window.paystackPurchase === "function") {
        await window.paystackPurchase({
          productType: "marketplace_order",
          productId: orderId,
          returnPage: "marketplace",
        });
        return;
      }
      toast("Order created. Complete payment from My orders.");
    } catch (err) {
      toast(err.message || "Checkout failed");
    } finally {
      if (btn) {
        btn.disabled = false;
        btn.textContent = "Pay with Paystack";
      }
    }
  }

  async function loadOrders() {
    if (!isBuyerLoggedIn()) {
      window.location.href =
        "portal.html?market=1&mode=login&role=student&next=" +
        encodeURIComponent("marketplace.html");
      return;
    }
    try {
      var data = await api.api("/api/v1/marketplace/orders");
      var orders = Array.isArray(data)
        ? data
        : (data && (data.orders || data.items || data.results)) || [];
      if (!orders.length) {
        toast("No orders yet — checkout from your cart.");
        return;
      }
      var lines = orders
        .slice(0, 5)
        .map(function (o) {
          return (
            (o.status || "order") +
            " · " +
            money(o.total_amount || o.amount || 0)
          );
        })
        .join(" | ");
      toast(lines);
    } catch (err) {
      toast(err.message || "Could not load orders");
    }
  }

  async function loadProducts() {
    var grid = $("mktGrid");
    try {
      var data = await api.api("/api/v1/marketplace/products", { noAuth: true });
      products = Array.isArray(data)
        ? data
        : (data && (data.products || data.items || data.results)) || [];
      renderTabs();
      renderGrid();
    } catch (err) {
      if (grid) {
        grid.innerHTML =
          '<div class="mkt-empty">' +
          escapeHtml(err.message || "Could not load products") +
          "</div>";
      }
    }
  }

  document.addEventListener("DOMContentLoaded", async function () {
    loadGuestCart();
    setCartBadge();

    if (typeof window.resumePendingPaystack === "function") {
      try {
        var payRes = await window.resumePendingPaystack();
        if (payRes && payRes.paid) {
          toast("Payment confirmed — thank you!");
        }
      } catch (e) { /* ignore */ }
    }

    var params = new URLSearchParams(window.location.search);
    if (params.get("vendor") === "pending") {
      var banner = $("vendorBanner");
      if (banner) banner.hidden = false;
      toast("Vendor signup received — wait for admin approval.");
    }

    if (isBuyerLoggedIn()) {
      $("btnOrders").hidden = false;
      await flushGuestCartToServer();
      await syncServerCartCount();
      if (params.get("checkout") === "1") openCart();
    }

    await loadProducts();

    $("mktTabs").addEventListener("click", function (e) {
      var btn = e.target.closest("[data-cat]");
      if (!btn) return;
      activeCat = btn.dataset.cat;
      renderTabs();
      renderGrid();
    });

    var search = $("mktSearch");
    if (search) {
      search.addEventListener("input", function () {
        searchQuery = search.value || "";
        renderGrid();
      });
    }

    $("mktGrid").addEventListener("click", function (e) {
      var btn = e.target.closest("[data-add]");
      if (!btn) return;
      addToCart(btn.dataset.add);
    });

    $("btnCart").addEventListener("click", openCart);
    $("closeCart").addEventListener("click", closeCart);
    $("cartDrawer").addEventListener("click", function (e) {
      if (e.target === $("cartDrawer")) closeCart();
    });
    $("btnCheckout").addEventListener("click", beginCheckout);
    $("btnSell").addEventListener("click", function () {
      goAuth("vendor");
    });
    var btnJoin = $("btnJoin");
    if (btnJoin) {
      btnJoin.addEventListener("click", openRoleModal);
    }
    $("closeRole").addEventListener("click", closeRoleModal);
    $("roleModal").addEventListener("click", function (e) {
      if (e.target === $("roleModal")) closeRoleModal();
      var pick = e.target.closest("[data-pick]");
      if (pick) goAuth(pick.dataset.pick);
    });
    $("closeCheckout").addEventListener("click", closeCheckoutModal);
    $("checkoutModal").addEventListener("click", function (e) {
      if (e.target === $("checkoutModal")) closeCheckoutModal();
    });
    $("checkoutForm").addEventListener("submit", submitCheckout);

    $("cartBody").addEventListener("click", async function (e) {
      var rm = e.target.closest("[data-remove]");
      if (rm) {
        try {
          await api.api("/api/v1/marketplace/cart/" + rm.dataset.remove, {
            method: "DELETE",
          });
          await renderCartBody();
          await syncServerCartCount();
        } catch (err) {
          toast(err.message || "Could not remove item");
        }
        return;
      }
      var rg = e.target.closest("[data-remove-guest]");
      if (rg) {
        guestCart.splice(Number(rg.dataset.removeGuest), 1);
        saveGuestCart();
        setCartBadge();
        renderCartBody();
      }
    });

    $("btnOrders").addEventListener("click", loadOrders);
  });
})();
