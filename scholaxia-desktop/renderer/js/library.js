/**
 * Student Library — admin books + teacher notes/materials (free or paid).
 */

function libraryTypeLabel(type) {
  if (type === "pdf") return "PDF";
  if (type === "doc") return "Document";
  if (type === "image") return "Image";
  if (type === "video") return "Video";
  if (type === "note") return "Note";
  return "Link";
}

function libraryPriceTag(item) {
  if (item.source === "book") return '<span class="material-price free">Library book</span>';
  if (item.is_free || item.has_access) {
    return item.is_free
      ? '<span class="material-price free">Free</span>'
      : '<span class="material-price free">Unlocked</span>';
  }
  return '<span class="material-price">₦' + Number(item.price || 0).toLocaleString("en-NG") + "</span>";
}

async function openLibraryBookStudent(bookId) {
  try {
    var data = await api("/api/v1/library/" + encodeURIComponent(bookId) + "/read");
    if (data && data.read_url) {
      window.open(data.read_url, "_blank", "noopener,noreferrer");
    }
  } catch (e) {
    alert(e.message || "Could not open book.");
  }
}

async function openTeacherMaterial(item) {
  if (!item.is_free && !item.has_access) {
    await payForMaterial(item.id);
  }
  var access = await api("/api/v1/materials/" + encodeURIComponent(item.id) + "/access");
  if (!access.has_access) {
    alert("Unlock this material first.");
    return;
  }
  var list = await api("/api/v1/materials/student");
  var fresh = (list || []).find(function (m) { return m.id === item.id; });
  if (!fresh || !fresh.file_url) {
    alert("File not available.");
    return;
  }
  window.open(fresh.file_url, "_blank", "noopener,noreferrer");
}

async function loadLibrary() {
  var el = document.getElementById("library-list");
  var stats = document.getElementById("library-stats");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading library…</div>';
  if (stats) stats.innerHTML = "";

  var books = [];
  var materials = [];
  try {
    books = await api("/api/v1/library/student") || [];
  } catch (e) { books = []; }
  try {
    materials = await api("/api/v1/materials/student") || [];
  } catch (e) { materials = []; }

  var items = [];
  books.forEach(function (b) {
    items.push({
      id: b.id,
      source: "book",
      title: b.title,
      subject: b.subject || "General",
      type: "pdf",
      description: b.description || ("By " + (b.author || "Scholaxia")),
      teacher_name: b.author || "Scholaxia",
      cover: b.cover_image_url,
      is_free: true,
      has_access: true,
    });
  });
  materials.forEach(function (m) {
    items.push({
      id: m.id,
      source: "teacher",
      title: m.title,
      subject: m.subject || "General",
      type: m.material_type || "pdf",
      description: m.description || "",
      teacher_name: m.teacher_name || "Teacher",
      file_url: m.file_url,
      is_free: m.is_free,
      has_access: m.has_access,
      price: m.price,
    });
  });

  if (stats) {
    stats.innerHTML =
      '<div class="stat-pill"><strong>' + items.length + "</strong> items</div>" +
      '<div class="stat-pill"><strong>' + books.length + "</strong> books</div>" +
      '<div class="stat-pill"><strong>' + materials.length + "</strong> from teachers</div>";
  }

  if (!items.length) {
    el.innerHTML =
      '<div class="empty-state-premium">' +
      '<div class="empty-icon">&#128218;</div>' +
      "<h3>Your library is empty</h3>" +
      "<p>When your teacher shares notes or books, they will appear here. Paid items unlock after payment.</p>" +
      "</div>";
    return;
  }

  el.innerHTML = items.map(function (item) {
    var actions = "";
    if (item.source === "book") {
      actions = '<button type="button" class="btn-sm primary" data-lib-action="open-book" data-id="' + escHtml(item.id) + '">Read</button>';
    } else if (item.has_access || item.is_free) {
      actions = '<button type="button" class="btn-sm primary" data-lib-action="open-material" data-id="' + escHtml(item.id) + '">Open</button>';
    } else {
      actions = '<button type="button" class="btn-sm primary" data-lib-action="pay-material" data-id="' + escHtml(item.id) + '">Pay &amp; unlock</button>';
    }
    return (
      '<article class="material-card" data-material-id="' + escHtml(item.id) + '">' +
      (item.cover ? '<div class="material-cover" style="background-image:url(\'' + escHtml(item.cover) + '\')"></div>' : '<div class="material-icon">&#128218;</div>') +
      '<div class="material-body">' +
      "<h4>" + escHtml(item.title) + "</h4>" +
      '<p class="material-meta">' + escHtml(item.subject) + " · " + libraryTypeLabel(item.type) + "</p>" +
      '<p class="material-desc">' + escHtml(item.description || ("From " + item.teacher_name)) + "</p>" +
      '<div class="material-actions">' + libraryPriceTag(item) + " " + actions + "</div>" +
      "</div></article>"
    );
  }).join("");

  el.querySelectorAll("[data-lib-action]").forEach(function (btn) {
    btn.addEventListener("click", function () {
      var action = btn.dataset.libAction;
      var id = btn.dataset.id;
      if (action === "open-book") {
        openLibraryBookStudent(id);
        return;
      }
      var item = materials.find(function (m) { return m.id === id; });
      if (!item && action === "pay-material") {
        item = { id: id, is_free: false, has_access: false };
      }
      if (action === "pay-material") {
        payForMaterial(id).then(function () { loadLibrary(); }).catch(function (e) { alert(e.message); });
        return;
      }
      if (item) openTeacherMaterial(item);
    });
  });
}

window.loadLibrary = loadLibrary;
