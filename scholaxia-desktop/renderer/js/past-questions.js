/** Past Questions — timed CBT papers uploaded separately from CBT Practice. */

function pqEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

async function loadPastQuestionsPage() {
  var root = document.getElementById("past-questions-root");
  if (!root) return;
  root.innerHTML = '<div class="loading">Loading past question papers…</div>';

  if (!getToken || !getToken()) {
    root.innerHTML =
      '<div class="as-empty"><h3>Sign in required</h3><p>Log in to sit past questions as timed CBT.</p></div>';
    return;
  }

  try {
    var data = await api("/api/v1/cbt/exams/for-me?paper_kind=past_questions") || {};
    var seen = {};
    var list = []
      .concat(data.practice_exams || [])
      .concat(data.jamb_exams || [])
      .concat(data.ssce_exams || [])
      .filter(function (exam) {
        var id = exam && exam.id;
        if (!id || seen[id]) return false;
        seen[id] = true;
        return true;
      });
    if (!list.length) {
      root.innerHTML =
        '<div class="as-empty">' +
        '<div class="as-empty-icon">&#128196;</div>' +
        "<h3>No past-question papers yet</h3>" +
        "<p>Admin uploads these under CBT → Past Questions. You sit them here as timed CBT. They are not mixed with CBT Practice.</p>" +
        "</div>";
      return;
    }

    root.innerHTML =
      '<div class="pq-intro">' +
      "<p>These are past-question papers. Tap Start to sit the paper as a timed CBT — not as a PDF.</p>" +
      "</div>" +
      '<div class="pq-grid">' +
      list
        .map(function (e) {
          var id = String(e.id);
          return (
            '<article class="pq-card">' +
            '<div class="pq-card-icon">&#128221;</div>' +
            '<div class="pq-card-body">' +
            "<h3>" + pqEsc(e.title || "Past questions") + "</h3>" +
            "<p>" +
            pqEsc(e.subject || "") +
            (e.exam_type ? " · " + pqEsc(e.exam_type) : "") +
            (e.year ? " · " + pqEsc(e.year) : "") +
            (e.total_questions ? " · " + pqEsc(e.total_questions) + " Qs" : "") +
            "</p>" +
            "</div>" +
            '<button type="button" class="btn-action pq-pay-btn" onclick="startPastQuestionExam(\'' +
            pqEsc(id) +
            "')\">Start CBT</button>" +
            "</article>"
          );
        })
        .join("") +
      "</div>";
  } catch (e) {
    root.innerHTML = '<div class="as-empty"><h3>Could not load</h3><p>' + pqEsc(e.message) + "</p></div>";
  }
}

async function startPastQuestionExam(examId) {
  if (typeof cbtHubStart === "function") {
    await cbtHubStart(examId);
    return;
  }
  if (typeof showPage === "function") showPage("cbt");
}

window.loadPastQuestionsPage = loadPastQuestionsPage;
window.startPastQuestionExam = startPastQuestionExam;
