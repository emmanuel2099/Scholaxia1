/** Scholaxia Kids desktop — sidebar layout */

var kindCurrentPage = "home";
var kindSiaHistory = [];
var kindActiveGame = null;

var KIND_PAGE_TITLES = {
  home: "Home",
  sia: "Sia AI",
  live: "Live Class",
  saved: "Saved",
  games: "Games",
};

function kindEsc(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

document.addEventListener("DOMContentLoaded", function () {
  if (!getToken() || localStorage.getItem("sia_role") !== "kind") {
    window.location.href = "index.html?role=kind";
    return;
  }
  initKindSidebar();
  initKindApp();
});

function initKindSidebar() {
  var shell = document.querySelector(".kind-desktop");
  var btn = document.getElementById("kind-sidebar-toggle");
  if (!shell || !btn) return;

  if (localStorage.getItem("kind_sidebar_collapsed") === "1") {
    shell.classList.add("sidebar-collapsed");
  }
  updateKindSidebarToggle(btn, shell.classList.contains("sidebar-collapsed"));

  btn.addEventListener("click", function () {
    shell.classList.toggle("sidebar-collapsed");
    var collapsed = shell.classList.contains("sidebar-collapsed");
    localStorage.setItem("kind_sidebar_collapsed", collapsed ? "1" : "0");
    updateKindSidebarToggle(btn, collapsed);
  });
}

function updateKindSidebarToggle(btn, collapsed) {
  btn.textContent = collapsed ? "\u203A" : "\u2039";
  btn.setAttribute("aria-label", collapsed ? "Show menu" : "Hide menu");
  btn.title = collapsed ? "Show menu" : "Hide menu";
}

function initKindApp() {
  var name = localStorage.getItem("sia_name") || "Friend";
  var first = name.split(" ")[0];
  var age = localStorage.getItem("sia_age_group") || "";

  document.getElementById("kind-user-name").textContent = first;
  document.getElementById("kind-greeting").textContent = "Hi, " + first + "!";
  document.getElementById("kind-avatar").textContent = first.charAt(0).toUpperCase();

  var ageEl = document.getElementById("kind-user-age");
  if (ageEl) ageEl.textContent = age ? "Ages " + age : "Scholaxia Kids";

  kindSiaHistory.push({
    isAi: true,
    text: "Hi " + first + "! I'm Sia, your learning buddy. Ask me anything — I'll explain it in a fun way!",
  });
  renderKindSia();
  loadKindHome();
}

function kindNav(page) {
  kindCurrentPage = page;
  document.querySelectorAll(".kind-page").forEach(function (p) { p.classList.remove("active"); });
  document.querySelectorAll(".kind-nav-btn").forEach(function (b) {
    b.classList.toggle("active", b.getAttribute("data-kind-page") === page);
  });
  var el = document.getElementById("kind-page-" + page);
  if (el) el.classList.add("active");

  var title = document.getElementById("kind-page-title");
  if (title) title.textContent = KIND_PAGE_TITLES[page] || page;

  if (page === "live") loadKindLive();
  else if (page === "saved") loadKindSaved();
  else if (page === "games") loadKindGames();
  else if (page === "home") loadKindHome();
}

function kindRefresh() {
  if (kindCurrentPage === "home") loadKindHome();
  else if (kindCurrentPage === "live") loadKindLive();
  else if (kindCurrentPage === "saved") loadKindSaved();
  else if (kindCurrentPage === "games") loadKindGames();
}

async function loadKindHome() {
  var stats = document.getElementById("kind-home-stats");
  var liveStat = document.getElementById("kind-stat-live");
  try {
    var me = await api("/api/v1/kind/me");
    if (me && me.full_name) {
      var first = me.full_name.split(" ")[0];
      document.getElementById("kind-greeting").textContent = "Hi, " + first + "!";
      document.getElementById("kind-user-name").textContent = first;
      document.getElementById("kind-avatar").textContent = first.charAt(0).toUpperCase();
      if (me.age_group) {
        document.getElementById("kind-hero-sub").textContent =
          "Age group " + me.age_group + " — learn, play, and grow with Scholaxia Kids!";
        var ageEl = document.getElementById("kind-user-age");
        if (ageEl) ageEl.textContent = "Ages " + me.age_group;
        localStorage.setItem("sia_age_group", me.age_group);
      }
    }
    var live = await api("/api/v1/live-classes?status=live");
    var count = Array.isArray(live) ? live.filter(function (c) { return c.is_live; }).length : 0;
    if (liveStat) liveStat.textContent = String(count);
    if (stats) {
      stats.innerHTML = count
        ? '<div class="kind-banner-card"><div><strong>&#128308; ' + count + " live class" + (count === 1 ? "" : "es") + '</strong> available right now — join a lesson!</div><button type="button" class="btn-action btn-sm" onclick="kindNav(\'live\')">View classes</button></div>'
        : '<div class="kind-banner-card"><div>No live classes right now. Try Sia AI or play a game while you wait!</div><button type="button" class="btn-secondary btn-sm" onclick="kindNav(\'games\')">Play games</button></div>';
    }
  } catch (e) {
    if (stats) stats.innerHTML = "";
  }
}

function renderKindSia() {
  var el = document.getElementById("kind-sia-messages");
  if (!el) return;
  el.innerHTML = kindSiaHistory.map(function (m) {
    return '<div class="kind-sia-msg ' + (m.isAi ? "ai" : "user") + '">' + kindEsc(m.text) + "</div>";
  }).join("");
  el.scrollTop = el.scrollHeight;
}

async function kindSendSia() {
  var inp = document.getElementById("kind-sia-input");
  var err = document.getElementById("kind-sia-error");
  if (!inp) return;
  var q = inp.value.trim();
  if (!q) return;
  inp.value = "";
  if (err) err.textContent = "";
  kindSiaHistory.push({ isAi: false, text: q });
  renderKindSia();

  try {
    var history = kindSiaHistory.slice(-10).map(function (m) {
      return { role: m.isAi ? "assistant" : "user", content: m.text };
    });
    var r = await api("/api/v1/kind/sia/chat", {
      method: "POST",
      body: JSON.stringify({ question: q, subject: "General", conversation_history: history }),
    });
    var reply = (r && (r.text || r.response || r.answer)) || "I'm here to help! Can you ask in another way?";
    kindSiaHistory.push({ isAi: true, text: reply });
    renderKindSia();
    if (typeof kindSpeak === "function") kindSpeak(reply);
  } catch (e) {
    if (err) err.textContent = e.message || "Sia is resting. Try again!";
  }
}

async function loadKindLive() {
  var el = document.getElementById("kind-live-list");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading live classes…</div>';
  try {
    var rows = await api("/api/v1/live-classes?status=live");
    if (!Array.isArray(rows) || !rows.length) {
      el.innerHTML = '<div class="empty-state">No live classes right now. Check back soon!</div>';
      return;
    }
    el.innerHTML = rows.map(function (c) {
      var live = c.is_live;
      return (
        '<div class="kind-live-card' + (live ? " live-now" : "") + '">' +
        "<div><strong>" + kindEsc(c.title || c.subject || "Live class") + "</strong>" +
        '<br><span style="font-size:0.82rem;color:#6b6280">' + kindEsc(c.teacher_name || "Teacher") + "</span></div>" +
        (live ? '<button type="button" class="btn-action btn-sm" onclick="kindJoinLive(\'' + kindEsc(String(c.id)) + '\')">Join class</button>' : "") +
        "</div>"
      );
    }).join("");
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + kindEsc(e.message) + "</div>";
  }
}

function kindJoinLive(classId) {
  window.location.href = "app.html?join=" + encodeURIComponent(classId);
}

async function loadKindSaved() {
  var el = document.getElementById("kind-saved-list");
  if (!el) return;
  el.innerHTML = '<div class="loading">Loading saved lessons…</div>';
  try {
    var rows = await api("/api/v1/saved-live-classes");
    if (!Array.isArray(rows) || !rows.length) {
      el.innerHTML = '<div class="empty-state">No saved lessons yet. Save a live class replay to watch here!</div>';
      return;
    }
    el.innerHTML = rows.map(function (s) {
      return (
        '<div class="kind-live-card">' +
        "<div><strong>" + kindEsc(s.title || s.class_title || "Saved lesson") + "</strong></div>" +
        (s.recording_url
          ? '<a href="' + kindEsc(s.recording_url) + '" target="_blank" rel="noopener" class="btn-action btn-sm">Watch replay</a>'
          : "") +
        "</div>"
      );
    }).join("");
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + kindEsc(e.message) + "</div>";
  }
}

async function loadKindGames() {
  var grid = document.getElementById("kind-games-grid");
  var play = document.getElementById("kind-game-play");
  if (!grid) return;
  if (play) play.classList.add("hidden");
  kindActiveGame = null;
  try {
    var data = await api("/api/v1/kind/games/catalog");
    var games = (data && data.games) || [];
    if (!games.length) {
      grid.innerHTML = '<div class="empty-state">No games available yet.</div>';
      return;
    }
    grid.innerHTML = games.map(function (g) {
      var leaf = localStorage.getItem("kind_leaf_" + g.id) || "1";
      return (
        '<button type="button" class="kind-game-card" onclick="startKindGame(\'' + kindEsc(g.id) + '\',\'' + kindEsc(g.title) + '\')">' +
        '<div style="font-size:2rem;margin-bottom:8px">&#127918;</div>' +
        "<strong>" + kindEsc(g.title) + "</strong>" +
        '<div class="leaf">&#127810; Leaf ' + kindEsc(leaf) + "</div>" +
        "</button>"
      );
    }).join("");
  } catch (e) {
    grid.innerHTML = '<div class="empty-state">' + kindEsc(e.message) + "</div>";
  }
}

var KIND_SAMPLE_QUESTIONS = [
  { prompt: "What color is the sky on a sunny day?", options: ["Green", "Blue", "Red", "Yellow"], correct: 1 },
  { prompt: "How many legs does a dog have?", options: ["2", "4", "6", "8"], correct: 1 },
  { prompt: "Which animal says 'Meow'?", options: ["Dog", "Cat", "Cow", "Bird"], correct: 1 },
  { prompt: "What comes after 5?", options: ["4", "6", "7", "3"], correct: 1 },
  { prompt: "What do plants need to grow?", options: ["Ice", "Sunlight", "Darkness", "Salt"], correct: 1 },
];

async function startKindGame(gameId, title) {
  if (typeof kindStopVoice === "function") kindStopVoice();
  kindActiveGame = { id: gameId, title: title, qi: 0, score: 0, questions: [], answered: false };
  var grid = document.getElementById("kind-games-grid");
  var play = document.getElementById("kind-game-play");
  if (grid) grid.classList.add("hidden");
  if (play) play.classList.remove("hidden");

  try {
    var data = await api("/api/v1/kind/games/" + encodeURIComponent(gameId) + "/questions");
    var qs = (data && data.questions) || [];
    kindActiveGame.questions = qs.length
      ? qs.map(function (q) {
          return {
            prompt: q.prompt,
            options: q.options,
            correct: q.correct_index,
            speak_word: q.speak_word || null,
          };
        })
      : KIND_SAMPLE_QUESTIONS.slice();
  } catch (e) {
    kindActiveGame.questions = KIND_SAMPLE_QUESTIONS.slice();
  }
  showKindGameQuestion();
}

function showKindGameQuestion() {
  var play = document.getElementById("kind-game-play");
  if (!play || !kindActiveGame) return;
  var qs = kindActiveGame.questions;
  if (kindActiveGame.qi >= qs.length) {
    finishKindGame();
    return;
  }
  if (kindActiveGame.answered) return;

  var q = qs[kindActiveGame.qi];
  var progress = Math.round(((kindActiveGame.qi + 1) / qs.length) * 100);
  play.innerHTML =
    '<div class="kind-game-play-area">' +
    '<div class="kind-game-play-head">' +
    "<strong>" + kindEsc(kindActiveGame.title) + "</strong>" +
    '<span>Question ' + (kindActiveGame.qi + 1) + " of " + qs.length + " · Score " + kindActiveGame.score + "</span></div>" +
    '<div class="kind-game-progress"><div class="kind-game-progress-fill" style="width:' + progress + '%"></div></div>' +
    '<div class="kind-game-prompt-card">' +
    '<p class="game-prompt kind-game-prompt">' + kindEsc(q.prompt) + "</p>" +
    '<button type="button" class="kind-hear-btn" onclick="kindSpeakQuestion(kindActiveGame.questions[kindActiveGame.qi])">&#128266; Hear question</button>' +
    "</div>" +
    '<div class="game-options kind-game-options">' +
    q.options.map(function (opt, i) {
      return '<button type="button" class="game-option-btn kind-game-opt" onclick="answerKindGame(' + i + ',' + q.correct + ')">' + kindEsc(opt) + "</button>";
    }).join("") +
    "</div>" +
    '<button type="button" class="btn-secondary" style="margin-top:16px" onclick="exitKindGame()">← Back to games</button></div>';

  if (typeof kindSpeakQuestion === "function") {
    setTimeout(function () { kindSpeakQuestion(q); }, 300);
  }
}

function answerKindGame(picked, correct) {
  if (!kindActiveGame || kindActiveGame.answered) return;
  kindActiveGame.answered = true;
  var ok = picked === correct;
  if (ok) kindActiveGame.score += 1;

  var play = document.getElementById("kind-game-play");
  if (!play) return;
  var q = kindActiveGame.questions[kindActiveGame.qi];
  var feedback = ok ? "🎉 Correct! Great job!" : "💡 Good try!";
  var optsHtml = q.options.map(function (opt, i) {
    var cls = "game-option-btn kind-game-opt";
    if (kindActiveGame.answered) {
      if (i === correct) cls += " kind-opt-correct";
      else if (i === picked && !ok) cls += " kind-opt-wrong";
      cls += " disabled";
    }
    return '<button type="button" class="' + cls + '" disabled>' + kindEsc(opt) + "</button>";
  }).join("");

  play.innerHTML =
    '<div class="kind-game-play-area">' +
    '<div class="kind-game-play-head"><strong>' + kindEsc(kindActiveGame.title) + "</strong></div>" +
    '<div class="kind-game-prompt-card"><p class="game-prompt kind-game-prompt">' + kindEsc(q.prompt) + "</p></div>" +
    '<div class="game-options kind-game-options">' + optsHtml + "</div>" +
    '<p class="kind-game-feedback' + (ok ? " ok" : "") + '">' + feedback + "</p>" +
    '<button type="button" class="btn-action" onclick="nextKindGameQuestion()">' +
    (kindActiveGame.qi + 1 >= kindActiveGame.questions.length ? "See my score" : "Next") +
    "</button></div>";
}

function nextKindGameQuestion() {
  if (!kindActiveGame) return;
  kindActiveGame.qi += 1;
  kindActiveGame.answered = false;
  showKindGameQuestion();
}

function finishKindGame() {
  var play = document.getElementById("kind-game-play");
  if (!kindActiveGame || !play) return;
  var leaf = parseInt(localStorage.getItem("kind_leaf_" + kindActiveGame.id) || "1", 10);
  if (kindActiveGame.score >= Math.ceil(kindActiveGame.questions.length * 0.6)) {
    leaf = Math.min(30, leaf + 1);
    localStorage.setItem("kind_leaf_" + kindActiveGame.id, String(leaf));
  }
  play.innerHTML =
    '<div class="game-play-area" style="text-align:center;padding:40px">' +
    '<div style="font-size:3.5rem">&#127775;</div>' +
    '<h2 style="color:#7c3aed;margin:16px 0 8px">Great job!</h2>' +
    "<p style=\"font-size:1.1rem;margin-bottom:8px\">Score: <strong>" + kindActiveGame.score + "/" + kindActiveGame.questions.length + "</strong></p>" +
    '<p style="color:#10b981;font-weight:700">&#127810; Leaf level ' + leaf + "</p>" +
    '<button type="button" class="btn-action" style="margin-top:20px" onclick="exitKindGame()">Play more games</button></div>';
}

function exitKindGame() {
  if (typeof kindStopVoice === "function") kindStopVoice();
  kindActiveGame = null;
  var grid = document.getElementById("kind-games-grid");
  var play = document.getElementById("kind-game-play");
  if (grid) grid.classList.remove("hidden");
  if (play) play.classList.add("hidden");
  loadKindGames();
}

function kindLogout() {
  clearSession();
  window.location.href = "index.html";
}

if (typeof window !== "undefined") {
  window.kindNav = kindNav;
  window.kindRefresh = kindRefresh;
  window.kindSendSia = kindSendSia;
  window.kindJoinLive = kindJoinLive;
  window.startKindGame = startKindGame;
  window.answerKindGame = answerKindGame;
  window.nextKindGameQuestion = nextKindGameQuestion;
  window.exitKindGame = exitKindGame;
  window.kindLogout = kindLogout;
}
