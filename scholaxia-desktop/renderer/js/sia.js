var siaHistory = [];
var siaPendingQuestion = "";
var siaAwaitingLevel = false;

var SIA_LEVELS = ["JSS1", "JSS2", "JSS3", "SS1", "SS2", "SS3", "JAMB", "WAEC", "NECO"];

function getSiaLevel() {
  return localStorage.getItem("sia_education_level") || "";
}

function setSiaLevel(level) {
  localStorage.setItem("sia_education_level", level);
  updateSiaLevelLabel();
}

function updateSiaLevelLabel() {
  var el = document.getElementById("sia-level-label");
  if (!el) return;
  var level = getSiaLevel();
  el.textContent = level ? "Level: " + level : "Level: not set";
}

function parseSiaLevel(text) {
  var upper = String(text || "").toUpperCase().trim();
  for (var i = 0; i < SIA_LEVELS.length; i++) {
    if (upper === SIA_LEVELS[i] || upper.indexOf(SIA_LEVELS[i]) !== -1) {
      return SIA_LEVELS[i];
    }
  }
  return "";
}

async function syncSiaLevelFromProfile() {
  if (getSiaLevel()) return getSiaLevel();
  try {
    var p = await api("/api/v1/students/me");
    if (p && p.education_level) {
      setSiaLevel(p.education_level);
      return p.education_level;
    }
  } catch (e) { /* ignore */ }
  return "";
}

function loadSia() {
  if (typeof isCbtExamActive === "function" && isCbtExamActive()) {
    var err = document.getElementById("sia-error");
    if (err) err.textContent = "Finish your exam before using Tutor AI.";
    return;
  }
  updateSiaLevelLabel();
  updateSiaModeLabel();
  if (siaHistory.length) return;

  syncSiaLevelFromProfile().then(function (level) {
    var el = siaMessagesEl();
    if (!el || siaHistory.length) return;

    if (level) {
      el.innerHTML =
        '<div class="sia-welcome"><div class="sia-orb">S</div>' +
        "<p>Hi! I'm <strong>Tutor AI</strong>, your study assistant.</p>" +
        "<p>I'll explain at <strong>" + escHtml(level) + "</strong> level. Ask me anything.</p></div>";
      return;
    }

    el.innerHTML =
      '<div class="sia-welcome"><div class="sia-orb">S</div>' +
      "<p>Hi! I'm <strong>Tutor AI</strong>, your study assistant.</p></div>";
    promptSiaLevel(true);
  });
}

function changeSiaLevel() {
  siaAwaitingLevel = true;
  promptSiaLevel(false);
}

function promptSiaLevel(isFirst) {
  siaAwaitingLevel = true;
  var intro = isFirst
    ? "Before I answer your questions, **what is your education level?**\n\nThis helps me explain at the right depth for you."
    : "**Choose your education level** so I can tailor my answers.";

  var div = createSiaMessageShell("sia");
  var content = div.querySelector(".sia-content");
  content.innerHTML =
    formatSiaMarkdown(intro) +
    '<div class="sia-level-pick">' +
    SIA_LEVELS.map(function (lv) {
      return '<button type="button" class="sia-level-btn" onclick="selectSiaLevel(\'' + lv + '\')">' + lv + "</button>";
    }).join("") +
    "</div>";

  siaHistory.push({ role: "sia", content: intro.replace(/\*\*/g, ""), meta: true });
}

function isLevelOnlyMessage(content) {
  return SIA_LEVELS.indexOf(String(content || "").trim().toUpperCase()) !== -1;
}

function buildSiaApiHistory() {
  return siaHistory
    .filter(function (m) {
      if (m.meta) return false;
      if (m.role === "user" && isLevelOnlyMessage(m.content)) return false;
      if (m.role === "sia" && /education level|tap one of the level|what would you like to learn/i.test(m.content)) {
        return false;
      }
      return true;
    })
    .slice(-8)
    .map(function (m) {
      return { role: m.role === "user" ? "user" : "assistant", content: m.content };
    });
}

function levelTeachingHint(level) {
  var hints = {
    JSS1: "simple words and short steps",
    JSS2: "clear basics with one example at a time",
    JSS3: "bridge-level explanations",
    SS1: "WAEC foundation depth",
    SS2: "SS2 curriculum depth with worked examples",
    SS3: "advanced secondary + exam traps",
    JAMB: "fast exam-focused CBT style",
    WAEC: "marking-scheme theory style",
    NECO: "NECO syllabus depth",
  };
  return hints[level] || "your class level";
}

function selectSiaLevel(level) {
  if (!level) return;
  setSiaLevel(level);
  siaAwaitingLevel = false;

  appendSiaMessage("user", level);
  siaHistory.push({ role: "user", content: level, meta: true });

  var pending = siaPendingQuestion;
  siaPendingQuestion = "";

  var confirm = pending
    ? "Got it — **" + level + "** level (" + levelTeachingHint(level) + ").\n\n**Your question:** " + pending + "\n\nLet me break this down for your class…"
    : "Perfect! I'll teach you at **" + level + "** level (" + levelTeachingHint(level) + ").\n\nWhat would you like to learn?";

  appendSiaMessage("sia", confirm, { scroll: false });
  siaHistory.push({ role: "sia", content: confirm.replace(/\*\*/g, ""), meta: true });

  if (pending) {
    setTimeout(function () { askSiaQuestion(pending, true); }, 500);
  }
}

function siaMessagesEl() {
  return document.getElementById("sia-messages");
}

function scrollSiaToBottom() {
  var el = siaMessagesEl();
  if (el) el.scrollTop = el.scrollHeight;
}

function normalizeSiaText(raw) {
  return String(raw || "")
    .replace(/\r\n/g, "\n")
    .replace(/([.!?])\s+(\d+[.)]\s+)/g, "$1\n\n$2")
    .replace(/(\d+[.)]\s+[^\n]+?)\s+(?=\d+[.)]\s+)/g, "$1\n")
    .replace(/([.!?])\s+([A-D][.)]\s+)/gi, "$1\n\n$2")
    .replace(/:\s+(\d+[.)]\s+)/g, ":\n\n$1")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
}

function inlineSiaFormat(text) {
  return escHtml(text)
    .replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>")
    .replace(/__(.+?)__/g, "<strong>$1</strong>")
    .replace(/\*(.+?)\*/g, "<em>$1</em>");
}

function formatSiaTextBlocks(raw) {
  var lines = normalizeSiaText(raw).split("\n");
  var html = [];
  var para = [];
  var listType = null;

  function closeList() {
    if (listType) {
      html.push("</" + listType + ">");
      listType = null;
    }
  }

  function flushPara() {
    closeList();
    if (!para.length) return;
    html.push("<p>" + inlineSiaFormat(para.join(" ")) + "</p>");
    para = [];
  }

  lines.forEach(function (line) {
    var trimmed = line.trim();

    if (!trimmed) {
      flushPara();
      return;
    }

    var h3 = trimmed.match(/^###\s+(.+)$/);
    if (h3) {
      flushPara();
      html.push("<h4 class=\"sia-h\">" + inlineSiaFormat(h3[1]) + "</h4>");
      return;
    }

    var h2 = trimmed.match(/^##\s+(.+)$/);
    if (h2) {
      flushPara();
      html.push("<h3 class=\"sia-h\">" + inlineSiaFormat(h2[1]) + "</h3>");
      return;
    }

    var heading = trimmed.match(/^(?:\*\*)?([A-Z][A-Za-z0-9 ,\-']{2,60})(?:\*\*)?:\s*$/);
    if (heading && trimmed.length < 70) {
      flushPara();
      html.push("<h4 class=\"sia-h\">" + inlineSiaFormat(heading[1]) + "</h4>");
      return;
    }

    var num = trimmed.match(/^(\d+)[.)]\s+(.+)$/);
    if (num) {
      flushPara();
      if (listType !== "ol") {
        closeList();
        html.push("<ol class=\"sia-list\">");
        listType = "ol";
      }
      html.push("<li>" + inlineSiaFormat(num[2]) + "</li>");
      return;
    }

    var bullet = trimmed.match(/^[-*•]\s+(.+)$/);
    if (bullet) {
      flushPara();
      if (listType !== "ul") {
        closeList();
        html.push("<ul class=\"sia-list\">");
        listType = "ul";
      }
      html.push("<li>" + inlineSiaFormat(bullet[1]) + "</li>");
      return;
    }

    var option = trimmed.match(/^([A-D])[.)]\s+(.+)$/i);
    if (option) {
      flushPara();
      if (listType !== "ul") {
        closeList();
        html.push("<ul class=\"sia-options\">");
        listType = "ul";
      }
      html.push("<li><strong>" + escHtml(option[1].toUpperCase()) + ")</strong> " + inlineSiaFormat(option[2]) + "</li>");
      return;
    }

    closeList();
    para.push(trimmed);
  });

  flushPara();
  closeList();

  if (!html.length) {
    return "<p>" + inlineSiaFormat(raw) + "</p>";
  }

  return html.join("");
}

function formatSiaMarkdown(raw) {
  var text = String(raw || "");
  if (!text.trim()) return "";

  var parts = [];
  var fenceRe = /```(\w*)\n?([\s\S]*?)```/g;
  var lastIndex = 0;
  var match;
  while ((match = fenceRe.exec(text)) !== null) {
    if (match.index > lastIndex) {
      parts.push({ type: "text", content: text.slice(lastIndex, match.index) });
    }
    parts.push({ type: "code", lang: match[1] || "code", content: match[2].replace(/\s+$/, "") });
    lastIndex = fenceRe.lastIndex;
  }
  if (lastIndex < text.length) {
    parts.push({ type: "text", content: text.slice(lastIndex) });
  }
  if (!parts.length) parts.push({ type: "text", content: text });

  return parts.map(function (part) {
    if (part.type === "code") {
      var langLabel = part.lang && part.lang !== "code" ? part.lang : "Code";
      return (
        '<div class="sia-code-wrap">' +
        '<div class="sia-code-head"><span>' + escHtml(langLabel) + '</span>' +
        '<button type="button" class="sia-code-copy" onclick="copySiaCode(this)">Copy</button></div>' +
        '<pre class="sia-code-block"><code>' + escHtml(part.content) + "</code></pre></div>"
      );
    }
    return formatSiaTextBlocks(part.content);
  }).join("");
}

function copySiaCode(btn) {
  var pre = btn && btn.closest(".sia-code-wrap") && btn.closest(".sia-code-wrap").querySelector("code");
  if (!pre) return;
  var text = pre.textContent || "";
  if (navigator.clipboard && navigator.clipboard.writeText) {
    navigator.clipboard.writeText(text).then(function () {
      btn.textContent = "Copied!";
      setTimeout(function () { btn.textContent = "Copy"; }, 1500);
    }).catch(function () { /* ignore */ });
  }
}

function isSiaSmartMode() {
  var v = localStorage.getItem("sia_tutor_mode");
  return v !== "plain";
}

function toggleSiaSmartMode() {
  var next = isSiaSmartMode() ? "plain" : "smart";
  localStorage.setItem("sia_tutor_mode", next);
  updateSiaModeLabel();
}

function updateSiaModeLabel() {
  var el = document.getElementById("sia-mode-label");
  if (!el) return;
  el.textContent = isSiaSmartMode() ? "Smart tutor ON" : "Plain text";
  el.classList.toggle("sia-mode-on", isSiaSmartMode());
}

function splitSiaBlocks(raw) {
  var text = normalizeSiaText(raw);
  if (!text) return [];

  var parts = text.split(/\n\s*\n/);
  if (parts.length > 1) return parts.map(function (p) { return p.trim(); }).filter(Boolean);

  var sentences = text.match(/[^.!?]+[.!?]+(?:\s+|$)|[^.!?]+$/g);
  if (!sentences || sentences.length <= 2) return [text];

  var blocks = [];
  var chunk = "";
  sentences.forEach(function (s) {
    chunk += s;
    if (chunk.length >= 180) {
      blocks.push(chunk.trim());
      chunk = "";
    }
  });
  if (chunk.trim()) blocks.push(chunk.trim());
  return blocks.length ? blocks : [text];
}

function createSiaMessageShell(role) {
  var el = siaMessagesEl();
  var welcome = el.querySelector(".sia-welcome");
  if (welcome) welcome.remove();

  var div = document.createElement("div");
  div.className = "sia-msg " + role;

  if (role === "sia") {
    div.innerHTML =
      '<div class="sia-avatar">S</div>' +
      '<div class="sia-bubble"><div class="sia-content"></div></div>';
  } else {
    div.innerHTML = '<div class="sia-bubble user">' + escHtml("") + "</div>";
  }

  el.appendChild(div);
  return div;
}

function appendSiaMessage(role, text, options) {
  options = options || {};
  var div = createSiaMessageShell(role);

  if (role === "user") {
    div.querySelector(".sia-bubble").textContent = text;
    if (options.scroll !== false) scrollSiaToBottom();
    return div;
  }

  var content = div.querySelector(".sia-content");
  content.innerHTML = formatSiaMarkdown(text);
  if (options.scroll !== false) scrollSiaToBottom();
  return div;
}

function revealSiaAnswer(div, rawText, onDone) {
  var content = div.querySelector(".sia-content");
  if (!content) return;

  var blocks = splitSiaBlocks(rawText);
  var index = 0;
  content.innerHTML = "";

  function showNext() {
    if (index >= blocks.length) {
      content.innerHTML = formatSiaMarkdown(rawText);
      if (onDone) onDone();
      return;
    }

    var slice = blocks.slice(0, index + 1).join("\n\n");
    content.innerHTML = formatSiaMarkdown(slice);
    index += 1;
    setTimeout(showNext, index === 1 ? 120 : 220);
  }

  showNext();
}

function siaSubject() {
  var subjects = getUser().subjects || [];
  return subjects.length ? subjects[0] : "General";
}

async function askSiaQuestion(question, alreadyShown) {
  var err = document.getElementById("sia-error");
  if (typeof isCbtExamActive === "function" && isCbtExamActive()) {
    if (err) err.textContent = "Tutor AI is locked during an exam. Submit your exam first.";
    return;
  }
  if (!alreadyShown) {
    siaHistory.push({ role: "user", content: question });
  } else if (!siaHistory.some(function (m) { return m.role === "user" && m.content === question && !m.meta; })) {
    siaHistory.push({ role: "user", content: question });
  }

  var thinking = createSiaMessageShell("sia");
  thinking.querySelector(".sia-content").innerHTML = '<span class="sia-thinking">Thinking at ' + escHtml(getSiaLevel()) + ' level…</span>';

  var level = getSiaLevel();
  var subject = siaSubject();

  try {
    var data = await api("/api/v1/sia/ask", {
      method: "POST",
      body: JSON.stringify({
        question: question,
        subject: subject,
        language: "english",
        education_level: level,
        conversation_history: buildSiaApiHistory().slice(0, -1),
        tutor_mode: isSiaSmartMode() ? "smart" : "plain",
      }),
    });
    var answer = (data && (data.sia || data.answer || data.result)) || "Sorry, I could not answer that.";
    revealSiaAnswer(thinking, answer, function () {
      siaHistory.push({ role: "sia", content: answer });
    });
  } catch (e) {
    thinking.remove();
    err.textContent = e.message;
    appendSiaMessage("sia", "Something went wrong. Please try again.", { scroll: false });
  }
}

async function sendSiaMessage() {
  var input = document.getElementById("sia-input");
  var err = document.getElementById("sia-error");
  if (typeof isCbtExamActive === "function" && isCbtExamActive()) {
    if (err) err.textContent = "Tutor AI is locked during an exam. Submit your exam first.";
    return;
  }
  var question = input.value.trim();
  if (!question) return;
  err.textContent = "";
  input.value = "";

  if (siaAwaitingLevel) {
    appendSiaMessage("user", question);
    var picked = parseSiaLevel(question);
    if (picked) {
      var extra = question.replace(new RegExp(picked, "ig"), "").replace(/^[\s,.-]+|[\s,.-]+$/g, "");
      if (extra.length > 3) siaPendingQuestion = extra;
      selectSiaLevel(picked);
    } else {
      appendSiaMessage(
        "sia",
        "Please tap one of the level buttons (e.g. **SS2**, **JAMB**) or type your level.",
        { scroll: false }
      );
    }
    return;
  }

  appendSiaMessage("user", question);

  if (!getSiaLevel()) {
    siaPendingQuestion = question;
    promptSiaLevel(false);
    return;
  }

  await askSiaQuestion(question);
}
