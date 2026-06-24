/**
 * Student Library — admin books only.
 */

function libraryPriceTag(item) {
  if (item.is_free || item.has_access) {
    return item.is_free
      ? '<span class="material-price free">Free</span>'
      : '<span class="material-price free">Unlocked</span>';
  }
  return '<span class="material-price">₦' + Number(item.price || 0).toLocaleString("en-NG") + "</span>";
}

async function openLibraryBookStudent(bookId, item) {
  item = item || {};
  if (!item.is_free && !item.has_access) {
    var pay = await payForBook(bookId);
    if (pay && pay.redirecting) return;
  }
  try {
    var data = await api("/api/v1/library/" + encodeURIComponent(bookId) + "/read");
    if (data && data.read_url) {
      window.open(data.read_url, "_blank", "noopener,noreferrer");
    }
  } catch (e) {
    if (e.message && e.message.indexOf("402") >= 0) {
      var r = await payForBook(bookId);
      if (r && r.redirecting) return;
    }
    alert(e.message || "Could not open book.");
  }
}

async function loadLibrary() {
  var el = document.getElementById("library-list");
  var stats = document.getElementById("library-stats");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading library…</div>';
  if (stats) stats.innerHTML = "";

  var books = [];
  try {
    books = await api("/api/v1/library/student") || [];
  } catch (e) {
    books = [];
  }

  if (stats) {
    stats.innerHTML =
      '<div class="stat-pill"><strong>' + books.length + "</strong> books</div>";
  }

  if (!books.length) {
    el.innerHTML =
      '<div class="empty-state-premium">' +
      '<div class="empty-icon">&#128218;</div>' +
      "<h3>No books yet</h3>" +
      "<p>When Scholaxia admin adds books, they will appear here.</p>" +
      "</div>";
    return;
  }

  el.innerHTML = books.map(function (b) {
    var actions = "";
    if (b.has_access || b.is_free) {
      actions = '<button type="button" class="btn-sm primary" data-lib-action="open-book" data-id="' + escHtml(b.id) + '">Read</button>';
    } else {
      actions = '<button type="button" class="btn-sm primary" data-lib-action="pay-book" data-id="' + escHtml(b.id) + '">Pay &amp; unlock</button>';
    }
    return (
      '<article class="material-card" data-book-id="' + escHtml(b.id) + '">' +
      (b.cover_image_url ? '<div class="material-cover" style="background-image:url(\'' + escHtml(b.cover_image_url) + '\')"></div>' : '<div class="material-icon">&#128218;</div>') +
      '<div class="material-body">' +
      "<h4>" + escHtml(b.title) + "</h4>" +
      '<p class="material-meta">' + escHtml(b.subject || "General") + " · Book</p>" +
      '<p class="material-desc">' + escHtml(b.description || ("By " + (b.author || "Scholaxia"))) + "</p>" +
      '<div class="material-actions">' + libraryPriceTag(b) + " " + actions + "</div>" +
      "</div></article>"
    );
  }).join("");

  el.querySelectorAll("[data-lib-action]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var action = btn.dataset.libAction;
      var id = btn.dataset.id;
      var book = books.find(function (b) { return b.id === id; });
      if (action === "open-book") {
        openLibraryBookStudent(id, book);
        return;
      }
      if (action === "pay-book") {
        payForBook(id).then(function (r) {
          if (r && r.redirecting) return;
          loadLibrary();
        }).catch(function (e) { alert(e.message); });
      }
    });
  });
}

window.loadLibrary = loadLibrary;
