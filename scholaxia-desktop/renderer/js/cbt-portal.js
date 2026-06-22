(function () {
  var cfg = window.CBT_PORTAL_CONFIG;
  if (!cfg) return;

  var poolCache = {};

  function normalizeSubjectKey(name) {
    return String(name || "").toLowerCase().replace(/[^a-z0-9]/g, "");
  }

  function resolveCategory(examType) {
    var cat = String(examType || "JAMB").trim().toUpperCase();
    if (cat.indexOf("JAMB") >= 0) return "JAMB";
    if (cat.indexOf("WAEC") >= 0) return "WAEC";
    if (cat.indexOf("NECO") >= 0) return "NECO";
    if (cat === "JAMB" || cat === "WAEC" || cat === "NECO") return cat;
    return "JAMB";
  }

  function questionCount(category, subject) {
    var subj = String(subject || "").toLowerCase();
    if (category === "JAMB") return subj.includes("english") ? 60 : 40;
    if (category === "WAEC" || category === "NECO") return 80;
    return 10;
  }

  function durationMinutes(category, isCombinedJamb) {
    if (isCombinedJamb) return 120;
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
    var data = null;
    if (typeof api === "function") {
      data = await api("/api/v1/cbt/practice-bank/" + key);
    } else {
      var url = cfg.practiceBaseUrl + "/" + key.toLowerCase() + ".json";
      var res = await fetch(url, { signal: typeof fetchTimeout === "function" ? fetchTimeout(45000) : undefined });
      if (!res.ok) throw new Error("CBT question bank unavailable (" + key + ")");
      data = await res.json();
    }
    var raw = Array.isArray(data)
      ? data
      : (Array.isArray(data.subjects) ? data.subjects : (Array.isArray(data.questions) ? data.questions : []));
    raw = raw.filter(function (e) {
      return e && e.subject && Array.isArray(e.questions) && e.questions.length > 0;
    });
    poolCache[key] = raw;
    return raw;
  }

  function findSubjectEntry(pool, subjectName) {
    var target = normalizeSubjectKey(subjectName);
    if (!target) return null;

    var exact = pool.find(function (entry) {
      return normalizeSubjectKey(entry && entry.subject) === target;
    });
    if (exact) return exact;

    return pool.find(function (entry) {
      var key = normalizeSubjectKey(entry && entry.subject);
      if (!key || !Array.isArray(entry.questions) || !entry.questions.length) return false;
      if (key.includes(target) || target.includes(key)) return true;
      if (target.indexOf("english") >= 0 && key.indexOf("english") >= 0) return true;
      if (target.indexOf("math") >= 0 && key.indexOf("math") >= 0) return true;
      if (target.indexOf("econ") >= 0 && key.indexOf("econ") >= 0) return true;
      if (target.indexOf("lit") >= 0 && key.indexOf("literature") >= 0) return true;
      if (target.indexOf("gov") >= 0 && key.indexOf("government") >= 0) return true;
      if (target.indexOf("crk") >= 0 && (key.indexOf("christian") >= 0 || key.indexOf("religious") >= 0)) return true;
      return false;
    }) || null;
  }

  function portalExamId(category, subject) {
    return "portal:" + resolveCategory(category) + ":" + subject;
  }

  var JAMB_COMBINED_ID = "portal:JAMB:combined";

  function orderJambSubjects(subjects) {
    var list = (subjects || []).slice();
    var englishIdx = list.findIndex(function (s) {
      return String(s || "").toLowerCase().indexOf("english") >= 0;
    });
    if (englishIdx > 0) {
      var eng = list.splice(englishIdx, 1)[0];
      list.unshift(eng);
    }
    return list;
  }

  function jambCombinedQuestionTotal(subjects) {
    return (subjects || []).reduce(function (sum, subject) {
      return sum + questionCount("JAMB", subject);
    }, 0);
  }

  function buildCombinedJambExam(pool, subjects, opts) {
    opts = opts || {};
    var allowPartial = !!opts.allowPartial;
    var ordered = orderJambSubjects(subjects);
    var items = [];
    var sections = [];
    var matched = [];
    var missing = [];
    ordered.forEach(function (subject) {
      var entry = findSubjectEntry(pool, subject);
      if (!entry || !Array.isArray(entry.questions) || !entry.questions.length) {
        if (allowPartial) {
          missing.push(subject);
          return;
        }
        throw new Error("No questions found for " + subject);
      }
      matched.push(subject);
      var count = Math.min(questionCount("JAMB", subject), entry.questions.length);
      var start = items.length;
      entry.questions.slice(0, count).forEach(function (q, i) {
        items.push(convertQuestion(q, start + i, subject));
      });
      sections.push({ subject: subject, start: start, count: count });
    });
    return { questions: items, sections: sections, subjects: matched, missing: missing };
  }

  function getProfileSubjects() {
    if (typeof getUser === "function") {
      var user = getUser();
      if (user.subjects && user.subjects.length) return user.subjects;
    }
    try {
      return JSON.parse(localStorage.getItem("sia_subjects") || "[]");
    } catch (e) {
      return [];
    }
  }

  function parsePortalExamId(examId) {
    var parts = String(examId || "").split(":");
    if (parts.length < 3 || parts[0] !== "portal") return null;
    return { category: parts[1], subject: parts.slice(2).join(":") };
  }

  async function loadAlocJambPreview() {
    if (typeof api !== "function") return null;
    try {
      return await api("/api/v1/cbt/aloc/jamb-preview");
    } catch (e) {
      return null;
    }
  }

  async function loadPortalPracticeExams(profileOverride) {
    var examType = "";
    var subjects = [];
    var profile = profileOverride;

    if (!profile && typeof api === "function") {
      try {
        profile = await api("/api/v1/students/me");
      } catch (e) {
        profile = null;
      }
    }

    if (profile) {
      examType = profile.exam_type || "";
      subjects = profile.selected_subjects || [];
      if (typeof localStorage !== "undefined") {
        if (examType) localStorage.setItem("sia_exam_type", formatExamType(examType));
        localStorage.setItem("sia_subjects", JSON.stringify(subjects));
      }
    }

    if (!subjects.length && typeof getUser === "function") {
      var user = getUser();
      examType = examType || user.examType;
      subjects = Array.isArray(user.subjects) ? user.subjects : [];
    }
    if (!subjects.length) return [];

    var category = resolveCategory(examType);

    var pool;
    try {
      pool = await fetchPracticePool(category);
    } catch (e) {
      console.warn("Portal CBT load failed", e);
      return [];
    }

    if (category === "JAMB" && subjects.length === 4) {
      var alocCard = await loadAlocJambPreview();
      if (alocCard && alocCard.id) return [alocCard];

      var ordered = orderJambSubjects(subjects);
      var matched = [];
      var missing = [];
      ordered.forEach(function (subject) {
        var entry = findSubjectEntry(pool, subject);
        if (entry && Array.isArray(entry.questions) && entry.questions.length) matched.push(subject);
        else missing.push(subject);
      });
      if (!matched.length) return [];
      return [{
        id: JAMB_COMBINED_ID,
        title: "JAMB CBT Practice Exam",
        subject: matched.join(" · "),
        exam_type: "JAMB",
        total_questions: jambCombinedQuestionTotal(matched),
        duration_minutes: durationMinutes("JAMB", true),
        is_portal: true,
        is_combined: true,
        subjects: matched,
        missing_subjects: missing,
        source: "CBT Bank",
      }];
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
        source: "CBT Bank",
      };
    }).filter(Boolean);
  }

  async function beginPortalExam(examId, opts) {
    opts = opts || {};
    if (String(examId || "").indexOf("aloc:") === 0) {
      if (typeof api !== "function") throw new Error("ALOC exam requires API connection");
      var path = "/api/v1/cbt/aloc/jamb-exam";
      if (opts.year) path += "?year=" + encodeURIComponent(opts.year);
      var alocOpts = typeof fetchTimeout === "function" ? { signal: fetchTimeout(120000) } : {};
      var aloc = await api(path, alocOpts);
      if (!aloc || !aloc.exam || !aloc.exam.questions || !aloc.exam.questions.length) {
        throw new Error("ALOC returned no questions. Check server ALOC_ACCESS_TOKEN.");
      }
      return {
        session: aloc.session,
        exam: aloc.exam,
        meta: aloc.meta,
        secondsLeft: aloc.secondsLeft || aloc.exam.duration_minutes * 60,
      };
    }

    var parsed = parsePortalExamId(examId);
    if (!parsed) throw new Error("Invalid portal exam");

    var pool = await fetchPracticePool(parsed.category);
    var items;
    var title;
    var meta;
    var sections = null;
    var subjects = [];

    if (parsed.category === "JAMB" && parsed.subject === "combined") {
      subjects = getProfileSubjects();
      if (subjects.length !== 4) {
        throw new Error("JAMB requires exactly 4 subjects in Profile before starting the full CBT.");
      }
      var combined = buildCombinedJambExam(pool, subjects, { allowPartial: true });
      if (!combined.questions.length) {
        throw new Error("Your subjects are not in the CBT bank yet. Change subjects in Profile.");
      }
      items = combined.questions;
      sections = combined.sections;
      subjects = combined.subjects;
      title = "JAMB CBT Practice Exam";
      meta = subjects.join(" · ") + " · " + items.length + " questions · 2 hrs · CBT Bank";
      if (combined.missing.length) {
        meta += " · Missing in bank: " + combined.missing.join(", ");
      }
    } else {
      var entry = findSubjectEntry(pool, parsed.subject);
      if (!entry || !Array.isArray(entry.questions) || !entry.questions.length) {
        throw new Error("No questions found for " + parsed.subject);
      }
      var count = questionCount(parsed.category, parsed.subject);
      items = entry.questions.slice(0, count).map(function (q, i) {
        return convertQuestion(q, i, parsed.subject);
      });
      title = parsed.category + " " + parsed.subject + " Practice";
      meta = parsed.subject + " · " + items.length + " questions · CBT Bank";
    }

    var isCombinedJamb = parsed.category === "JAMB" && parsed.subject === "combined";
    var mins = durationMinutes(parsed.category, isCombinedJamb);

    return {
      session: {
        session_id: "portal-" + Date.now(),
        is_portal: true,
        is_school_exam: false,
      },
      exam: {
        id: examId,
        title: title,
        subject: subjects.length ? subjects.join(", ") : parsed.subject,
        exam_type: parsed.category,
        duration_minutes: mins,
        total_questions: items.length,
        questions: items,
        sections: sections,
        is_combined: isCombinedJamb,
      },
      meta: meta,
      secondsLeft: mins * 60,
    };
  }

  function scorePortalExam(exam) {
    exam = exam || window.currentExam;
    if (!exam || !exam.questions) {
      return { correct: 0, wrong: 0, total: 0, score_percent: 0, by_subject: {} };
    }
    var total = exam.questions.length;
    var correct = 0;
    var bySubject = {};
    exam.questions.forEach(function (q, i) {
      var subj = q.topic || "Subject";
      if (!bySubject[subj]) bySubject[subj] = { correct: 0, total: 0 };
      bySubject[subj].total++;
      if (window.answers[i] === q.correct_option) {
        correct++;
        bySubject[subj].correct++;
      }
    });
    return {
      correct: correct,
      wrong: total - correct,
      total: total,
      score_percent: total ? (correct / total) * 100 : 0,
      by_subject: bySubject,
    };
  }

  window.loadPortalPracticeExams = loadPortalPracticeExams;
  window.beginPortalExam = beginPortalExam;
  window.scorePortalExam = scorePortalExam;
  window.isPortalExamId = function (id) {
    var s = String(id || "");
    return s.indexOf("portal:") === 0 || s.indexOf("aloc:") === 0;
  };
  window.JAMB_COMBINED_ID = JAMB_COMBINED_ID;
  window.listPortalBankSubjects = async function (examType) {
    var pool = await fetchPracticePool(resolveCategory(examType || "JAMB"));
    return pool.map(function (e) { return e.subject; });
  };
})();
