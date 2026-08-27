/** Brain Breakers — matches mobile Games tab (30 levels each, no API). */

var activeGameId = null;
var gameState = null;
var GAME_MAX_LEVELS = 30;

var STUDENT_GAMES = [
  { id: "spelling-bee", title: "Spelling Bee", subtitle: "Deep vocabulary. Strict timer. No mercy.", icon: "&#128221;", gradient: "linear-gradient(135deg, #7c3aed, #a855f7)", type: "spelling" },
  { id: "math-arena", title: "Math Arena", subtitle: "Hard equations. Solve x in real time.", icon: "&#10135;", gradient: "linear-gradient(135deg, #6366f1, #8b5cf6)", type: "math" },
  { id: "word-arrangement", title: "Word Arrangement", subtitle: "Unscramble brutal sentences fast.", icon: "&#128256;", gradient: "linear-gradient(135deg, #f59e0b, #fbbf24)", type: "scramble" },
];

var SPELLING_WORDS = [
  { word: "metamorphosis", clue: "Complete change of form in biology." },
  { word: "circumlocution", clue: "Talking around a point without being direct." },
  { word: "sesquipedalian", clue: "Fond of using very long words." },
  { word: "synecdoche", clue: "Figure of speech: part for the whole." },
  { word: "epistemology", clue: "Branch of philosophy about knowledge." },
  { word: "inconsequential", clue: "Not important; insignificant." },
  { word: "quintessential", clue: "The most perfect example of something." },
  { word: "idiosyncrasy", clue: "A peculiar personal habit or trait." },
  { word: "pharmacopoeia", clue: "Official book of medicines and drugs." },
  { word: "onomatopoeia", clue: "Word that imitates a sound." },
  { word: "acquiescence", clue: "Acceptance without protest." },
  { word: "bureaucracy", clue: "System of government by officials." },
  { word: "conscientious", clue: "Wishing to do what is right." },
  { word: "deleterious", clue: "Causing harm or damage." },
  { word: "ecclesiastical", clue: "Relating to the Christian Church." },
  { word: "flabbergasted", clue: "Greatly surprised or astonished." },
  { word: "grandiloquent", clue: "Pompous or extravagant in language." },
  { word: "heterogeneous", clue: "Diverse in character or content." },
  { word: "idempotent", clue: "Unchanged when applied repeatedly." },
  { word: "juxtaposition", clue: "Placing things side by side for contrast." },
  { word: "kaleidoscope", clue: "Constantly changing pattern or scene." },
  { word: "labyrinthine", clue: "Like a maze; complicated." },
  { word: "magnanimous", clue: "Generous in forgiving." },
  { word: "nomenclature", clue: "System of naming things." },
  { word: "obstreperous", clue: "Noisy and difficult to control." },
  { word: "perspicacious", clue: "Having keen mental perception." },
  { word: "quintessence", clue: "The most perfect embodiment of something." },
  { word: "recalcitrant", clue: "Stubbornly uncooperative." },
  { word: "serendipitous", clue: "Found by happy accident." },
  { word: "transcendental", clue: "Beyond ordinary physical experience." },
];

var SCRAMBLE_PUZZLES = [
  { sentence: "The mitochondria is the powerhouse of the cell", hint: "Biology" },
  { sentence: "Photosynthesis converts light energy into chemical energy", hint: "Plant science" },
  { sentence: "Newton second law relates force mass and acceleration", hint: "Physics" },
  { sentence: "Democracy derives its legitimacy from the consent of the governed", hint: "Government" },
  { sentence: "Supply and demand determine equilibrium price in a free market", hint: "Economics" },
  { sentence: "Metamorphic rocks form under intense heat and pressure", hint: "Geology" },
  { sentence: "The hypotenuse is the longest side of a right triangle", hint: "Mathematics" },
  { sentence: "Chlorophyll absorbs red and blue wavelengths of light", hint: "Botany" },
  { sentence: "Entropy always increases in an isolated thermodynamic system", hint: "Thermodynamics" },
  { sentence: "The Magna Carta limited the power of the English monarch", hint: "History" },
  { sentence: "Osmosis is the movement of water across a membrane", hint: "Biology" },
  { sentence: "Velocity equals displacement divided by time elapsed", hint: "Physics" },
  { sentence: "A catalyst speeds up a reaction without being consumed", hint: "Chemistry" },
  { sentence: "The executive branch enforces laws passed by the legislature", hint: "Civics" },
  { sentence: "Inflation reduces the purchasing power of money over time", hint: "Economics" },
  { sentence: "Igneous rocks crystallize from molten magma or lava", hint: "Geology" },
  { sentence: "The area of a circle equals pi times radius squared", hint: "Mathematics" },
  { sentence: "Evaporation occurs when molecules escape from liquid surface", hint: "Chemistry" },
  { sentence: "The Bill of Rights protects individual freedoms from government", hint: "History" },
  { sentence: "DNA carries genetic instructions for all living organisms", hint: "Biology" },
  { sentence: "Friction opposes the relative motion of surfaces in contact", hint: "Physics" },
  { sentence: "A balanced chemical equation obeys the law of conservation", hint: "Chemistry" },
  { sentence: "Separation of powers prevents any branch from dominating", hint: "Government" },
  { sentence: "Opportunity cost is the value of the next best alternative", hint: "Economics" },
  { sentence: "Sedimentary rocks form from compressed layers of sediment", hint: "Geology" },
  { sentence: "The Pythagorean theorem relates sides of a right triangle", hint: "Mathematics" },
  { sentence: "Transpiration releases water vapor through plant stomata", hint: "Botany" },
  { sentence: "The Renaissance sparked renewed interest in classical learning", hint: "History" },
  { sentence: "An ecosystem includes all living and nonliving components", hint: "Ecology" },
  { sentence: "Gravitational force is proportional to mass and inversely to distance", hint: "Physics" },
];

function escGame(s) {
  var d = document.createElement("div");
  d.textContent = s == null ? "" : String(s);
  return d.innerHTML;
}

function shuffleArr(arr) {
  var a = arr.slice();
  for (var i = a.length - 1; i > 0; i--) {
    var j = Math.floor(Math.random() * (i + 1));
    var t = a[i]; a[i] = a[j]; a[j] = t;
  }
  return a;
}

function createGameQueue(poolSize) {
  var order = shuffleArr(Array.from({ length: poolSize }, function (_, i) { return i; }));
  return order.slice(0, GAME_MAX_LEVELS);
}

function mathNz(v) { return v === 0 ? 1 : v; }
function mathPm(n) { return n >= 0 ? "+ " + n : "- " + Math.abs(n); }
function mathFmt(n) { return n === 1 ? "" : (n === -1 ? "-" : String(n)); }

function buildMathPool() {
  var pool = [];
  var seen = {};
  for (var seed = 0; pool.length < GAME_MAX_LEVELS && seed < 500; seed++) {
    var level = pool.length + 1;
    var rng = function (max) { return Math.floor(Math.random() * max); };
    var x = rng(21) - 10;
    var diff = Math.min(6, 1 + Math.floor(level / 3));
    var a = mathNz(rng(11) - 5);
    var b = rng(21) - 10;
    var c = rng(21) - 10;
    var d = mathNz(rng(9) - 4);
    var e = rng(21) - 10;
    var k = diff >= 4 ? rng(17) - 8 : 0;
    var expr, sol = x;
    if (diff <= 2) {
      var rhs = a * (x + b) + c;
      expr = mathFmt(a) + "(x " + mathPm(b) + ") " + mathPm(c) + " = " + rhs;
    } else {
      k = a * (x + b) + c - d * (x + e);
      expr = mathFmt(a) + "(x " + mathPm(b) + ") " + mathPm(c) + " = " + mathFmt(d) + "(x " + mathPm(e) + ") " + mathPm(k);
    }
    if (!seen[expr]) {
      seen[expr] = true;
      pool.push({ expression: expr, solution: sol });
    }
  }
  while (pool.length < GAME_MAX_LEVELS) {
    var n = pool.length + 1;
    pool.push({ expression: "2(x + " + n + ") = " + (2 * (n + 3)), solution: 3 });
  }
  return pool;
}

function loadGamesPage() {
  var list = document.getElementById("games-list");
  var play = document.getElementById("games-play-area");
  if (!list) return;
  if (play) play.classList.add("hidden");
  activeGameId = null;
  list.innerHTML = STUDENT_GAMES.map(function (g) {
    return (
      '<button type="button" class="game-card game-tile-btn" onclick="startStudentGame(\'' + g.id + '\')">' +
      '<div class="game-card-icon" style="background:' + g.gradient + '">' + g.icon + "</div>" +
      "<div class=\"game-tile-body\"><h3>" + escGame(g.title) + "</h3>" +
      "<p>" + escGame(g.subtitle) + "</p></div>" +
      '<span class="game-tile-chevron">›</span></button>'
    );
  }).join("");
}

function startStudentGame(id) {
  var game = STUDENT_GAMES.find(function (g) { return g.id === id; });
  if (!game) return;
  activeGameId = id;
  var poolSize = game.type === "spelling" ? SPELLING_WORDS.length : (game.type === "scramble" ? SCRAMBLE_PUZZLES.length : GAME_MAX_LEVELS);
  gameState = {
    score: 0,
    streak: 0,
    lives: 3,
    level: 0,
    queue: createGameQueue(poolSize),
    queueIdx: 0,
    timer: null,
    locked: false,
    mathPool: game.type === "math" ? buildMathPool() : null,
    finished: false,
    picked: [],
    scramblePool: [],
  };

  var list = document.getElementById("games-list");
  var play = document.getElementById("games-play-area");
  if (list) list.classList.add("hidden");
  if (play) play.classList.remove("hidden");
  nextGameRound();
}

function exitStudentGame() {
  if (gameState && gameState.timer) clearInterval(gameState.timer);
  gameState = null;
  activeGameId = null;
  var list = document.getElementById("games-list");
  var play = document.getElementById("games-play-area");
  if (list) list.classList.remove("hidden");
  if (play) play.classList.add("hidden");
  loadGamesPage();
}

function currentLevel() { return gameState ? gameState.level : 0; }

function nextGameRound() {
  if (!gameState || gameState.finished) return;
  if (gameState.timer) clearInterval(gameState.timer);
  if (gameState.lives <= 0 && activeGameId !== "spelling-bee") {
    finishStudentGame(true);
    return;
  }
  if (gameState.queueIdx >= gameState.queue.length) {
    finishStudentGame(false);
    return;
  }

  var game = STUDENT_GAMES.find(function (g) { return g.id === activeGameId; });
  var idx = gameState.queue[gameState.queueIdx++];
  gameState.level = gameState.queueIdx;
  gameState.locked = false;
  gameState.timeTotal = game.type === "scramble" ? Math.max(12, 25 - Math.floor(gameState.level / 4)) : Math.max(7, 18 - Math.floor(gameState.level / 3));
  if (game.type === "spelling") gameState.timeLeft = Math.max(8, 18 - Math.floor((gameState.level - 1) / 4));
  else gameState.timeLeft = gameState.timeTotal;

  if (game.type === "spelling") {
    gameState.current = SPELLING_WORDS[idx];
    renderSpellingRound();
  } else if (game.type === "math") {
    gameState.current = gameState.mathPool[idx];
    renderMathRound();
  } else {
    var p = SCRAMBLE_PUZZLES[idx];
    gameState.current = p;
    gameState.picked = [];
    gameState.scramblePool = shuffleArr(p.sentence.split(" "));
    renderScrambleRound();
  }

  gameState.timer = setInterval(function () {
    gameState.timeLeft -= 1;
    var t = document.getElementById("game-timer");
    if (t) t.textContent = gameState.timeLeft + "s";
    if (gameState.timeLeft <= 0) gameFail("Time up");
  }, 1000);
}

function renderGameShell(inner, extra) {
  var game = STUDENT_GAMES.find(function (g) { return g.id === activeGameId; });
  var play = document.getElementById("games-play-area");
  if (!play) return;
  var livesHtml = game.type !== "spelling" ? ' · <span class="game-lives">❤ ' + gameState.lives + "</span>" : "";
  var streakHtml = game.type === "spelling" && gameState.streak > 0 ? ' · Streak ' + gameState.streak : "";
  play.innerHTML =
    '<div class="game-play-area">' +
    '<div class="game-play-header">' +
    "<div><strong>" + escGame(game.title) + "</strong> — Level " + gameState.level + "/" + GAME_MAX_LEVELS + "</div>" +
    '<div><span class="game-score">Score: ' + gameState.score + "</span>" + livesHtml + streakHtml +
    ' · <span class="game-timer" id="game-timer">' + gameState.timeLeft + "s</span></div></div>" +
    inner +
    (extra || "") +
    '<div style="margin-top:16px"><button type="button" class="btn-secondary" onclick="exitStudentGame()">← Back to games</button></div></div>';
}

function renderSpellingRound() {
  renderGameShell(
    '<p class="game-prompt">Clue: ' + escGame(gameState.current.clue) + "</p>" +
    '<input type="text" class="game-input" id="game-answer" placeholder="Type the spelling..." autocomplete="off" />' +
    '<button type="button" class="btn-action" onclick="submitSpelling()">Submit</button>'
  );
  setTimeout(function () {
    var inp = document.getElementById("game-answer");
    if (inp) {
      inp.focus();
      inp.onkeydown = function (e) { if (e.key === "Enter") submitSpelling(); };
    }
  }, 50);
}

function submitSpelling() {
  if (gameState.locked) return;
  var inp = document.getElementById("game-answer");
  if (!inp) return;
  var typed = inp.value.trim().toLowerCase();
  if (!typed) return;
  if (typed === gameState.current.word.toLowerCase()) {
    clearInterval(gameState.timer);
    var bonus = Math.min(15, gameState.streak * 2);
    gameState.score += 15 + bonus + gameState.level;
    gameState.streak += 1;
    setTimeout(nextGameRound, 400);
  } else {
    gameState.streak = 0;
    gameFail("Wrong — correct: " + gameState.current.word);
  }
}

function renderMathRound() {
  renderGameShell(
    '<p class="game-prompt">Solve for <strong>x</strong>:</p>' +
    '<p class="game-math-expr">' + escGame(gameState.current.expression) + "</p>" +
    '<input type="text" class="game-input" id="game-answer" placeholder="Integer value of x" autocomplete="off" />' +
    '<p id="game-feedback" class="game-feedback"></p>' +
    '<button type="button" class="btn-action" onclick="submitMath()">Submit</button>'
  );
  setTimeout(function () {
    var inp = document.getElementById("game-answer");
    if (inp) {
      inp.focus();
      inp.onkeydown = function (e) { if (e.key === "Enter") submitMath(); };
    }
  }, 50);
}

function submitMath() {
  if (gameState.locked) return;
  var inp = document.getElementById("game-answer");
  if (!inp) return;
  var val = parseInt(inp.value.trim(), 10);
  if (isNaN(val)) {
    var fb = document.getElementById("game-feedback");
    if (fb) fb.textContent = "Enter an integer for x";
    return;
  }
  if (val === gameState.current.solution) {
    clearInterval(gameState.timer);
    var bonus = gameState.timeLeft + Math.min(25, gameState.level);
    gameState.score += 25 + bonus;
    setTimeout(nextGameRound, 500);
  } else {
    gameWrong("Wrong — x = " + gameState.current.solution);
  }
}

function renderScrambleRound() {
  var chips = gameState.scramblePool.map(function (w, i) {
    return '<button type="button" class="game-option-btn scramble-chip" data-i="' + i + '" onclick="pickScrambleWord(this)">' + escGame(w) + "</button>";
  }).join("");
  renderGameShell(
    '<p class="game-prompt">Hint: ' + escGame(gameState.current.hint) + "</p>" +
    '<p class="game-prompt">Tap words in order:</p>' +
    '<div class="game-options" id="scramble-chips">' + chips + "</div>" +
    '<p class="game-prompt" id="scramble-picked" style="min-height:28px;color:#7c3aed;font-weight:600"></p>' +
    '<button type="button" class="btn-secondary btn-sm" onclick="resetScramblePick()">Clear</button> ' +
    '<button type="button" class="btn-action" onclick="submitScramble()">Check</button>'
  );
}

function pickScrambleWord(btn) {
  if (!gameState || btn.disabled || gameState.locked) return;
  var i = parseInt(btn.getAttribute("data-i"), 10);
  gameState.picked.push(gameState.scramblePool[i]);
  btn.disabled = true;
  btn.style.opacity = "0.35";
  var el = document.getElementById("scramble-picked");
  if (el) el.textContent = gameState.picked.join(" ");
}

function resetScramblePick() {
  if (!gameState) return;
  gameState.picked = [];
  renderScrambleRound();
}

function submitScramble() {
  if (gameState.locked) return;
  var typed = gameState.picked.join(" ").toLowerCase();
  if (typed === gameState.current.sentence.toLowerCase()) {
    clearInterval(gameState.timer);
    gameState.score += 20 + gameState.timeLeft;
    setTimeout(nextGameRound, 500);
  } else {
    gameWrong("Wrong — " + gameState.current.sentence);
  }
}

function gameWrong(msg) {
  if (gameState.locked) return;
  gameState.locked = true;
  clearInterval(gameState.timer);
  gameState.lives -= 1;
  var fb = document.getElementById("game-feedback");
  if (fb) fb.textContent = msg;
  setTimeout(function () {
    if (gameState.lives <= 0) finishStudentGame(true);
    else nextGameRound();
  }, 900);
}

function gameFail(msg) {
  if (gameState.locked) return;
  gameState.locked = true;
  clearInterval(gameState.timer);
  var game = STUDENT_GAMES.find(function (g) { return g.id === activeGameId; });
  if (game && game.type === "spelling") {
    gameState.streak = 0;
    setTimeout(nextGameRound, 1800);
    return;
  }
  gameState.lives -= 1;
  setTimeout(function () {
    if (gameState.lives <= 0) finishStudentGame(true);
    else nextGameRound();
  }, 900);
}

function finishStudentGame(died) {
  if (gameState && gameState.timer) clearInterval(gameState.timer);
  var score = gameState ? gameState.score : 0;
  var level = gameState ? gameState.level : 0;
  gameState = { finished: true };
  var play = document.getElementById("games-play-area");
  if (!play) return;
  play.innerHTML =
    '<div class="game-play-area" style="text-align:center;padding:40px">' +
    "<div style=\"font-size:3rem;margin-bottom:12px\">" + (died ? "💔" : "🏆") + "</div>" +
    "<h2 style=\"color:#7c3aed;margin-bottom:8px\">" + (died ? "Out of lives!" : "All 30 levels complete!") + "</h2>" +
    "<p style=\"font-size:1.1rem;margin-bottom:20px\">Score: <strong>" + score + "</strong> · Level " + level + "/" + GAME_MAX_LEVELS + "</p>" +
    '<button type="button" class="btn-action" onclick="startStudentGame(\'' + activeGameId + '\')">Play again</button> ' +
    '<button type="button" class="btn-secondary" onclick="exitStudentGame()">Back to games</button></div>';
}

if (typeof window !== "undefined") {
  window.loadGamesPage = loadGamesPage;
  window.startStudentGame = startStudentGame;
  window.exitStudentGame = exitStudentGame;
  window.submitSpelling = submitSpelling;
  window.submitMath = submitMath;
  window.pickScrambleWord = pickScrambleWord;
  window.resetScramblePick = resetScramblePick;
  window.submitScramble = submitScramble;
}
