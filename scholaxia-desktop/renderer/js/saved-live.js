/**
 * Save live classes locally on the desktop (IndexedDB) — not uploaded to cloud.
 */
var SAVED_LIVE_DB = "scholaxia_saved_lives_v1";
var SAVED_LIVE_STORE = "recordings";

function openSavedLiveDb() {
  return new Promise(function (resolve, reject) {
    var req = indexedDB.open(SAVED_LIVE_DB, 1);
    req.onupgradeneeded = function () {
      var db = req.result;
      if (!db.objectStoreNames.contains(SAVED_LIVE_STORE)) {
        db.createObjectStore(SAVED_LIVE_STORE, { keyPath: "id" });
      }
    };
    req.onsuccess = function () { resolve(req.result); };
    req.onerror = function () { reject(req.error || new Error("Could not open saved lives database")); };
  });
}

async function saveLiveRecording(meta, blob) {
  var db = await openSavedLiveDb();
  return new Promise(function (resolve, reject) {
    var record = {
      id: "live-" + Date.now(),
      title: meta.title || "Live class",
      subject: meta.subject || "",
      teacher: meta.teacher || "",
      class_id: meta.class_id || "",
      saved_at: new Date().toISOString(),
      duration_hint: meta.duration_hint || "",
      blob: blob,
    };
    var tx = db.transaction(SAVED_LIVE_STORE, "readwrite");
    tx.objectStore(SAVED_LIVE_STORE).put(record);
    tx.oncomplete = function () { resolve(record.id); };
    tx.onerror = function () { reject(tx.error); };
  });
}

async function listSavedLives() {
  var db = await openSavedLiveDb();
  return new Promise(function (resolve, reject) {
    var tx = db.transaction(SAVED_LIVE_STORE, "readonly");
    var req = tx.objectStore(SAVED_LIVE_STORE).getAll();
    req.onsuccess = function () {
      var rows = (req.result || []).sort(function (a, b) {
        return (b.saved_at || "").localeCompare(a.saved_at || "");
      });
      resolve(rows);
    };
    req.onerror = function () { reject(req.error); };
  });
}

async function deleteSavedLive(id) {
  var db = await openSavedLiveDb();
  return new Promise(function (resolve, reject) {
    var tx = db.transaction(SAVED_LIVE_STORE, "readwrite");
    tx.objectStore(SAVED_LIVE_STORE).delete(id);
    tx.oncomplete = function () { resolve(); };
    tx.onerror = function () { reject(tx.error); };
  });
}

async function loadSavedLivesPage() {
  var el = document.getElementById("saved-lives-list");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading saved classes…</div>';
  var rows = [];
  try {
    rows = await listSavedLives();
  } catch (e) {
    el.innerHTML = '<p class="error-msg">Could not read saved classes on this device.</p>';
    return;
  }
  if (!rows.length) {
    el.innerHTML =
      '<div class="empty-state-premium">' +
      '<div class="empty-icon">&#127909;</div>' +
      "<h3>No saved live classes yet</h3>" +
      "<p>During a live class, tap <strong>Save live</strong> to record on this computer. You can watch it later even after leaving.</p>" +
      "</div>";
    return;
  }
  el.innerHTML = rows.map(function (r) {
    var when = r.saved_at ? new Date(r.saved_at).toLocaleString() : "";
    return (
      '<article class="material-card saved-live-card" data-id="' + escHtml(r.id) + '">' +
      '<div class="material-icon">&#127909;</div>' +
      '<div class="material-body">' +
      "<h4>" + escHtml(r.title) + "</h4>" +
      '<p class="material-meta">' + escHtml(r.subject || "Live class") + (r.teacher ? " · " + escHtml(r.teacher) : "") + "</p>" +
      '<p class="material-desc">Saved on this device · ' + escHtml(when) + "</p>" +
      '<div class="material-actions">' +
      '<button type="button" class="btn-sm primary" data-saved-action="play" data-id="' + escHtml(r.id) + '">Watch</button> ' +
      '<button type="button" class="btn-sm danger" data-saved-action="delete" data-id="' + escHtml(r.id) + '">Delete</button>' +
      "</div></div></article>"
    );
  }).join("");

  el.querySelectorAll("[data-saved-action]").forEach(function (btn) {
    btn.addEventListener("click", async function () {
      var id = btn.dataset.id;
      var rows = await listSavedLives();
      var row = rows.find(function (r) { return r.id === id; });
      if (!row) return;
      if (btn.dataset.savedAction === "delete") {
        if (!confirm("Delete this saved recording from this device?")) return;
        await deleteSavedLive(id);
        loadSavedLivesPage();
        return;
      }
      var url = URL.createObjectURL(row.blob);
      var modal = document.getElementById("saved-live-player-modal");
      var video = document.getElementById("saved-live-video");
      var title = document.getElementById("saved-live-player-title");
      if (!modal || !video) {
        window.open(url, "_blank");
        return;
      }
      if (title) title.textContent = row.title || "Saved live class";
      video.src = url;
      modal.classList.remove("hidden");
      video.play().catch(function () { /* ignore */ });
    });
  });
}

function closeSavedLivePlayer() {
  var modal = document.getElementById("saved-live-player-modal");
  var video = document.getElementById("saved-live-video");
  if (video) {
    video.pause();
    if (video.src && video.src.indexOf("blob:") === 0) URL.revokeObjectURL(video.src);
    video.removeAttribute("src");
  }
  if (modal) modal.classList.add("hidden");
}

window.loadSavedLivesPage = loadSavedLivesPage;
window.closeSavedLivePlayer = closeSavedLivePlayer;
window.saveLiveRecording = saveLiveRecording;
window.listSavedLives = listSavedLives;
