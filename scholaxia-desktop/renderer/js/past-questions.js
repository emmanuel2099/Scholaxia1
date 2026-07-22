/** Past Questions — paid library PDFs uploaded by admin (Paystack). */

function pqEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function pqIsPastQuestion(book) {
  var cat = String((book && book.category) || "").toLowerCase();
  return cat.indexOf("past") >= 0;
}

async function openPastQuestionBook(bookId, btn) {
  if (!bookId) return;
  if (btn) {
    btn.disabled = true;
    btn.textContent = "Please wait…";
  }
  try {
    var books = await api("/api/v1/library/student") || [];
    var book = (books || []).find(function (b) { return String(b.id) === String(bookId); });
    if (!book) throw new Error("Past question not found.");

    if (!book.is_free && !book.has_access) {
      if (typeof payForBook !== "function") {
        throw new Error("Payment is not available. Refresh and try again.");
      }
      await payForBook(bookId);
    }

    if (typeof openLibraryBook === "function") {
      await openLibraryBook(bookId);
    } else {
      var data = await api("/api/v1/library/" + encodeURIComponent(bookId) + "/read");
      var url = (data && (data.file_url || data.url)) || "";
      if (url) window.open(url, "_blank");
      else alert("Opened. If the PDF did not appear, refresh Library.");
    }
    loadPastQuestionsPage();
  } catch (e) {
    alert(e.message || "Could not open past question.");
  } finally {
    if (btn) {
      btn.disabled = false;
      btn.textContent = btn.dataset.label || "Open / Pay";
    }
  }
}

async function loadPastQuestionsPage() {
  var root = document.getElementById("past-questions-root");
  if (!root) return;
  root.innerHTML = '<div class="loading">Loading past questions…</div>';

  if (!getToken || !getToken()) {
    root.innerHTML =
      '<div class="as-empty"><h3>Sign in required</h3><p>Log in to buy and open past questions.</p></div>';
    return;
  }

  try {
    var books = await api("/api/v1/library/student") || [];
    var list = (books || []).filter(pqIsPastQuestion);
    if (!list.length) {
      root.innerHTML =
        '<div class="as-empty">' +
        '<div class="as-empty-icon">&#128218;</div>' +
        "<h3>No past questions yet</h3>" +
        "<p>When admin uploads Past Questions (paid), they show here. You can also practise in CBT.</p>" +
        '<button type="button" class="btn-secondary" onclick="showPage(\'cbt\')">Open CBT Practice</button>' +
        "</div>";
      return;
    }

    root.innerHTML =
      '<div class="pq-intro">' +
      "<p>Past questions uploaded by Scholaxia admin are <strong>paid</strong>. Tap Pay to unlock with Paystack, then open the PDF.</p>" +
      "</div>" +
      '<div class="pq-grid">' +
      list
        .map(function (b) {
          var paid = !!(b.is_free || b.has_access);
          var price = Number(b.price || 0);
          var label = paid ? "Open PDF" : "Pay ₦" + price.toLocaleString("en-NG");
          return (
            '<article class="pq-card">' +
            '<div class="pq-card-icon">&#128196;</div>' +
            '<div class="pq-card-body">' +
            "<h3>" + pqEsc(b.title || "Past questions") + "</h3>" +
            "<p>" +
            pqEsc(b.subject || "") +
            (b.exam_type ? " · " + pqEsc(b.exam_type) : "") +
            "</p>" +
            '<span class="pq-price">' +
            (paid ? (b.is_free ? "Free" : "Unlocked") : "₦" + price.toLocaleString("en-NG")) +
            "</span>" +
            "</div>" +
            '<button type="button" class="btn-action pq-pay-btn" data-label="' +
            pqEsc(label) +
            '" onclick="openPastQuestionBook(\'' +
            pqEsc(b.id) +
            "', this)\">" +
            pqEsc(label) +
            "</button>" +
            "</article>"
          );
        })
        .join("") +
      "</div>";
  } catch (e) {
    root.innerHTML = '<div class="as-empty"><h3>Could not load</h3><p>' + pqEsc(e.message) + "</p></div>";
  }
}

window.loadPastQuestionsPage = loadPastQuestionsPage;
window.openPastQuestionBook = openPastQuestionBook;
