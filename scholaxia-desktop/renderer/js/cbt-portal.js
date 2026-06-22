(function () {
  var cfg = window.CBT_PORTAL_CONFIG;
  if (!cfg) return;

  var poolCache = {};

  function normalizeSubjectKey(name) {
    return String(name || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  }

  function resolveCategory(examType) {
    var cat = String(examType || "JAMB").trim().toUpperCase();
    if (cat === "JAMB" || cat === "WAEC" || cat === "NECO") return cat;
    return "JAMB";
  }

  function questionCount(category, subject) {
    var subj = String(subject || "").toLowerCase();
    if (category === "JAMB") return subj.includes("english") ? 60 : 40;
    if (category === "WAEC" || category === "NECO") return 80;
    return 10;
  }

  function durationMinutes(category) {
    if (category === "JAMB") return 90;
    if (category === "WAEC" || category === "NECO") return 40;
    return 30;
  }

  function optionLetter(index) {
    return ["A", "B", "C", "D"][index] || "A";
  }

  function convertQuestion(q, index, subject) {
    var options = Array.isArray(q.options) ? q.options : [];
    var correctIdx = typeof q.correctAnswer === "number" ? q.correctAnswer : 0;
    return {
      id: "portal-q-" + index,
      question_text: q.question || q.text || "",
      option_a: options[0] || "",
      option_b: options[1] || "",
      option_c: options[2] || "",
      option_d: options[3] || "",
      correct_option: optionLetter(correctIdx),
      explanation: q.explanation || "",
      topic: subject || "",
      image_url: q.image_url || q.image || "",
    };
  }

  async function fetchPracticePool(category) {
    var key = resolveCategory(category);
    if (poolCache[key]) return poolCache[key];
    var url = cfg.practiceBaseUrl + "/" + key.toLowerCase() + ".json";
    var res = await fetch(url, { signal: typeof fetchTimeout === "function" ? fetchTimeout(45000) : undefined });
    if (!res.ok) throw new Error("CBT question bank unavailable (" + key + ")");
    var data = await res.json();
    var raw = Array.isArray(data)
      ? data
      : (Array.isArray(data.subjects) ? data.subjects : (Array.isArray(data.questions) ? data.questions : []));
    poolCache[key] = raw;
    return raw;
  }

  function findSubjectEntry(pool, subjectName) {
    var target = normalizeSubjectKey(subjectName);
    return pool.find(function (entry) {
      return normalizeSubjectKey(entry && entry.subject) === target;
    });
  }

  function portalExamId(category, subject) {
    return "portal:" + resolveCategory(category) + ":" + subject;
  }

  function parsePortalExamId(examId) {
    var parts = String(examId || "").split(":");
    if (parts.length < 3 || parts[0] !== "portal") return null;
    return { category: parts[1], subject: parts.slice(2).join(":") };
  }

  async function loadPortalPracticeExams() {
    var user = typeof getUser === "function" ? getUser() : {};
    var category = resolveCategory(user.examType);
    var subjects = Array.isArray(user.subjects) ? user.subjects : [];
    if (!subjects.length) return [];

    var pool;
    try {
      pool = await fetchPracticePool(category);
    } catch (e) {
      console.warn("Portal CBT load failed", e);
      return [];
    }

    return subjects.map(function (subject) {
      var entry = findSubjectEntry(pool, subject);
      if (!entry || !Array.isArray(entry.questions) || !entry.questions.length) return null;
      var count = Math.min(questionCount(category, subject), entry.questions.length);
      return {
        id: portalExamId(category, subject),
        title: category + " " + subject + " Practice",
        subject: subject,
        exam_type: category,
        total_questions: count,
        duration_minutes: durationMinutes(category),
        is_portal: true,
        source: "Scholaxia CBT Bank",
      };
    }).filter(Boolean);
  }

  async function beginPortalExam(examId) {
    var parsed = parsePortalExamId(examId);
    if (!parsed) throw new Error("Invalid portal exam");

    var pool = await fetchPracticePool(parsed.category);
    var entry = findSubjectEntry(pool, parsed.subject);
    if (!entry || !Array.isArray(entry.questions) || !entry.questions.length) {
      throw new Error("No questions found for " + parsed.subject);
    }

    var count = questionCount(parsed.category, parsed.subject);
    var items = entry.questions.slice(0, count).map(function (q, i) {
      return convertQuestion(q, i, parsed.subject);
    });

    window.currentSession = {
      session_id: "portal-" + Date.now(),
      is_portal: true,
      is_school_exam: false,
    };
    window.currentExam = {
      id: examId,
      title: parsed.category + " " + parsed.subject + " Practice",
      subject: parsed.subject,
      exam_type: parsed.category,
      duration_minutes: durationMinutes(parsed.category),
      total_questions: items.length,
      questions: items,
    };
    window.answers = {};
    window.currentQ = 0;
    window.secondsLeft = durationMinutes(parsed.category) * 60;

    document.getElementById("cbt-grid").classList.add("hidden");
    document.getElementById("result-screen").classList.add("hidden");
    document.getElementById("exam-screen").classList.remove("hidden");
    document.getElementById("exam-title").textContent = window.currentExam.title;
    document.getElementById("exam-meta").textContent =
      parsed.subject + " · " + items.length + " questions · Scholaxia CBT Bank";

    if (typeof buildQNav === "function") buildQNav();
    if (typeof renderQuestion === "function") renderQuestion();
    if (typeof startTimer === "function") startTimer();
  }

  function scorePortalExam() {
    var exam = window.currentExam;
    var total = exam.questions.length;
    var correct = 0;
    exam.questions.forEach(function (q, i) {
      if (window.answers[i] === q.correct_option) correct++;
    });
    return {
      correct: correct,
      wrong: total - correct,
      total: total,
      score_percent: total ? (correct / total) * 100 : 0,
    };
  }

  window.loadPortalPracticeExams = loadPortalPracticeExams;
  window.beginPortalExam = beginPortalExam;
  window.scorePortalExam = scorePortalExam;
  window.isPortalExamId = function (id) {
    return String(id || "").indexOf("portal:") === 0;
  };
})();
