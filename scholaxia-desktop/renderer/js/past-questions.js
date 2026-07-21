/** Past Questions — merged into CBT Practice (mobile parity). */

async function loadPastQuestionsPage() {
  if (typeof showPage === "function") {
    showPage("cbt");
  }
}

if (typeof window !== "undefined") {
  window.loadPastQuestionsPage = loadPastQuestionsPage;
}
