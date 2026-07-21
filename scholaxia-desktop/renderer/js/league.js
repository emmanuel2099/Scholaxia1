/** Scholaxia Intellect League (SIL) — desktop portal */

var leagueProfile = null;
var leagueMeta = null;

function escLeague(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

async function loadLeaguePage() {
  var root = document.getElementById("league-root");
  if (!root) return;
  root.innerHTML = '<div class="loading">Loading Intellect League…</div>';

  try {
    if (!leagueMeta) {
      leagueMeta = await fetch(API_BASE + "/api/v1/sil/meta").then(function (r) { return r.json(); });
    }
    var status = await api("/api/v1/sil/status");
    if (!status || status.enrolled === false) {
      root.innerHTML = renderLeagueOnboarding(leagueMeta || {});
      return;
    }
    var dash = await api("/api/v1/sil/dashboard");
    leagueProfile = (dash && dash.profile) ? dash.profile : status;
    root.innerHTML = renderLeagueDashboard(dash || { profile: leagueProfile });
    loadLeagueLeaderboard();
  } catch (e) {
    root.innerHTML = '<div class="empty-state">' + escLeague(e.message || "Could not load League.") + "</div>";
  }
}

function renderLeagueOnboarding(meta) {
  var states = (meta && meta.states) || ["Lagos", "FCT", "Rivers", "Kano", "Oyo"];
  var classes = (meta && meta.classes) || ["JSS1", "JSS2", "JSS3", "SS1", "SS2", "SS3"];
  var stateOpts = states.map(function (s) {
    return '<option value="' + escLeague(s) + '">' + escLeague(s) + "</option>";
  }).join("");
  var classOpts = classes.map(function (c) {
    return '<option value="' + escLeague(c) + '">' + escLeague(c) + "</option>";
  }).join("");

  return (
    '<div class="league-hero">' +
    "<h2>&#127942; Scholaxia Intellect League</h2>" +
    "<p>Live quiz battles, coins, rankings, and school pride — join the League!</p>" +
    "</div>" +
    '<div class="game-play-area" style="max-width:480px">' +
    "<h3 style=\"margin-bottom:12px\">Create your League profile</h3>" +
    '<label class="field"><span class="field-label">Gamer tag</span>' +
    '<input type="text" id="league-gamer-tag" class="game-input" placeholder="Your gamer name (3+ chars)" minlength="3" /></label>' +
    '<label class="field"><span class="field-label">School name</span>' +
    '<input type="text" id="league-school" class="game-input" placeholder="Your school" /></label>' +
    '<label class="field"><span class="field-label">State</span>' +
    '<select id="league-state" class="field-select">' + stateOpts + "</select></label>" +
    '<label class="field"><span class="field-label">Class</span>' +
    '<select id="league-class" class="field-select">' + classOpts + "</select></label>" +
    '<p id="league-register-error" class="error-msg"></p>' +
    '<button type="button" class="btn-action" onclick="registerLeagueProfile()">Join the League</button>' +
    "</div>"
  );
}

async function registerLeagueProfile() {
  var err = document.getElementById("league-register-error");
  var tag = (document.getElementById("league-gamer-tag").value || "").trim();
  var school = (document.getElementById("league-school").value || "").trim();
  var state = document.getElementById("league-state").value;
  var cls = document.getElementById("league-class").value;
  if (!tag || tag.length < 3) {
    if (err) err.textContent = "Gamer tag must be at least 3 characters.";
    return;
  }
  if (!school) {
    if (err) err.textContent = "Please enter your school name.";
    return;
  }
  if (err) err.textContent = "";
  try {
    await api("/api/v1/sil/register", {
      method: "POST",
      body: JSON.stringify({
        gamer_tag: tag,
        school_name: school,
        state: state,
        academic_class: cls,
        accept_rules: true,
      }),
    });
    loadLeaguePage();
  } catch (e) {
    if (err) err.textContent = e.message || "Registration failed.";
  }
}

function renderLeagueDashboard(dash) {
  var p = dash.profile || {};
  var name = p.gamer_tag || "Explorer";
  var coins = p.coins != null ? p.coins : 0;
  var wins = p.wins || 0;
  var losses = p.losses || 0;
  var rank = p.national_rank > 0 ? p.national_rank : "—";

  return (
    '<div class="league-hero">' +
    "<h2>Welcome, " + escLeague(name) + "!</h2>" +
    "<p>" + escLeague(p.school_name || "Scholaxia Academy") + " · " + escLeague(p.state || "") + "</p>" +
    "</div>" +
    '<div class="league-stats-row">' +
    '<div class="league-stat"><strong>' + escLeague(String(coins)) + "</strong><span>Coins</span></div>" +
    '<div class="league-stat"><strong>' + escLeague(String(rank)) + "</strong><span>National rank</span></div>" +
    '<div class="league-stat"><strong>' + wins + "</strong><span>Wins</span></div>" +
    '<div class="league-stat"><strong>' + losses + "</strong><span>Losses</span></div>" +
    "</div>" +
    "<h3 class=\"dash-section-title\">Quick Actions</h3>" +
    '<div class="league-actions-grid">' +
    '<button type="button" class="league-action-card" onclick="startLeaguePractice()">' +
    "<h3>&#127919; Practice Match</h3><p>Warm up with a solo quiz round — no coins at risk.</p></button>" +
    '<button type="button" class="league-action-card" onclick="startLeagueAiMatch(1)">' +
    "<h3>&#129302; AI Battle (Beginner)</h3><p>Challenge the AI — entry 10 coins, win 20.</p></button>" +
    '<button type="button" class="league-action-card" onclick="showPage(\'games\')">' +
    "<h3>&#127918; Brain Breakers</h3><p>Spelling Bee, Math Arena &amp; Word games.</p></button>" +
    '<button type="button" class="league-action-card" onclick="loadLeagueWallet()">' +
    "<h3>&#128176; Wallet</h3><p>View balance and coin history.</p></button>" +
    "</div>" +
    '<div id="league-match-area" class="hidden"></div>" +
    "<h3 class=\"dash-section-title\" style=\"margin-top:24px\">Leaderboard</h3>" +
    '<div id="league-leaderboard" class="league-leaderboard"><div class="loading">Loading…</div></div>'
  );
}

async function loadLeagueLeaderboard() {
  var el = document.getElementById("league-leaderboard");
  if (!el) return;
  try {
    var data = await api("/api/v1/sil/leaderboard?limit=15");
    var rows = (data && data.entries) || [];
    if (!rows.length) {
      el.innerHTML = '<div class="empty-state" style="padding:24px">No rankings yet — be the first!</div>';
      return;
    }
    el.innerHTML =
      "<table><thead><tr><th>#</th><th>Player</th><th>School</th><th>Score</th></tr></thead><tbody>" +
      rows.map(function (r) {
        return "<tr><td>" + r.rank + "</td><td>" + escLeague(r.gamer_tag || "—") +
          "</td><td>" + escLeague(r.school_name || "—") + "</td><td>" + escLeague(String(r.score || 0)) + "</td></tr>";
      }).join("") +
      "</tbody></table>";
  } catch (e) {
    el.innerHTML = '<div class="empty-state">' + escLeague(e.message) + "</div>";
  }
}

async function loadLeagueWallet() {
  var area = document.getElementById("league-match-area");
  if (!area) return;
  area.classList.remove("hidden");
  area.innerHTML = '<div class="loading">Loading wallet…</div>';
  try {
    var w = await api("/api/v1/sil/wallet");
    var txs = (w && w.recent_transactions) || (w && w.transactions) || [];
    area.innerHTML =
      '<div class="game-play-area">' +
      "<h3>Wallet balance: <span style=\"color:#7c3aed\">" + escLeague(String(w.balance != null ? w.balance : (w.coins || 0))) + " coins</span></h3>" +
      (txs.length
        ? "<ul style=\"margin-top:12px;font-size:0.88rem\">" +
          txs.slice(0, 8).map(function (t) {
            return "<li>" + escLeague(t.description || t.type || "Transaction") + " — " + escLeague(String(t.amount || 0)) + "</li>";
          }).join("") +
          "</ul>"
        : "<p style=\"margin-top:8px;color:#6b6280\">No transactions yet.</p>") +
      '<button type="button" class="btn-secondary" style="margin-top:12px" onclick="document.getElementById(\'league-match-area\').classList.add(\'hidden\')">Close</button>' +
      "</div>";
  } catch (e) {
    area.innerHTML = '<div class="error-msg">' + escLeague(e.message) + "</div>";
  }
}

async function startLeaguePractice() {
  await startLeagueMatch("/api/v1/sil/matches/practice", { question_count: 10 });
}

async function startLeagueAiMatch(level) {
  await startLeagueMatch("/api/v1/sil/matches/ai", { level: level || 1 });
}

async function startLeagueMatch(path, body) {
  var area = document.getElementById("league-match-area");
  if (!area) return;
  area.classList.remove("hidden");
  area.innerHTML = '<div class="loading">Starting match…</div>';
  try {
    var match = await api(path, { method: "POST", body: JSON.stringify(body) });
    renderLeagueQuiz(match, area);
  } catch (e) {
    area.innerHTML = '<div class="error-msg">' + escLeague(e.message) + '</div>';
  }
}

function renderLeagueQuiz(match, area) {
  var questions = (match && match.questions) || [];
  if (!questions.length) {
    area.innerHTML = '<div class="empty-state">No questions in this match.</div>';
    return;
  }
  var qi = 0;
  var answers = [];
  var matchId = match.id;
  var qStart = Date.now();

  function showQ() {
    if (qi >= questions.length) {
      finishMatch(matchId, answers);
      return;
    }
    qStart = Date.now();
    var q = questions[qi];
    var opts = q.options || [];
    area.innerHTML =
      '<div class="game-play-area">' +
      "<p class=\"game-prompt\">Question " + (qi + 1) + " of " + questions.length + "</p>" +
      "<p class=\"game-prompt\" style=\"font-size:1.1rem\">" + escLeague(q.text || q.question || q.prompt) + "</p>" +
      (q.hint ? "<p style=\"font-size:0.82rem;color:#6b6280;margin-bottom:12px\">Hint: " + escLeague(q.hint) + "</p>" : "") +
      '<div class="game-options" id="league-q-opts"></div></div>';

    var optsEl = document.getElementById("league-q-opts");
    opts.forEach(function (opt, i) {
      var btn = document.createElement("button");
      btn.type = "button";
      btn.className = "game-option-btn";
      btn.textContent = opt;
      btn.onclick = function () {
        answers.push({
          question_index: qi,
          selected_index: i,
          elapsed_ms: Date.now() - qStart,
          skipped: false,
        });
        qi += 1;
        showQ();
      };
      optsEl.appendChild(btn);
    });
  }
  showQ();

  async function finishMatch(id, ans) {
    area.innerHTML = '<div class="loading">Submitting score…</div>';
    try {
      var result = await api("/api/v1/sil/matches/" + id + "/finish", {
        method: "POST",
        body: JSON.stringify({ answers: ans }),
      });
      var correct = (result && result.correct_count) || (result && result.my_correct) || 0;
      var coins = (result && result.coins_earned) || (result && result.reward_coins) || 0;
      area.innerHTML =
        '<div class="game-play-area" style="text-align:center">' +
        "<h3 style=\"color:#7c3aed\">Match complete!</h3>" +
        "<p>Correct: " + correct + "/" + questions.length + "</p>" +
        (coins ? "<p>You earned <strong>" + coins + "</strong> coins!</p>" : "") +
        '<button type="button" class="btn-action" onclick="loadLeaguePage()">Back to League</button>' +
        "</div>";
    } catch (e) {
      area.innerHTML =
        '<div class="game-play-area"><p class="error-msg">' + escLeague(e.message) + '</p>' +
        '<button type="button" class="btn-action" onclick="loadLeaguePage()">Back</button></div>';
    }
  }
}

if (typeof window !== "undefined") {
  window.loadLeaguePage = loadLeaguePage;
  window.registerLeagueProfile = registerLeagueProfile;
  window.startLeaguePractice = startLeaguePractice;
  window.startLeagueAiMatch = startLeagueAiMatch;
  window.loadLeagueWallet = loadLeagueWallet;
}
