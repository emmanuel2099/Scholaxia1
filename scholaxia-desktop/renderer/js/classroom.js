var liveSession = null;
var liveSocket = null;
var agoraClient = null;
var agoraJoined = false;
var agoraAvailable = false;
var localTracks = { audio: null, video: null, screen: null, screenAudio: null };
var micOn = false;
var camOn = false;
var screenOn = false;
var localPreviewStream = null;
var localScreenStream = null;
var mediaMode = "none"; // none | agora | local
var micMonitorTimer = null;
var micMonitorCtx = null;
var selfHearAudio = null;
var classAutoEndTimer = null;
var agoraRetryTimer = null;
var agoraConnecting = false;
var raisedHands = {};
var wsStudentCount = 0;
var API_WS = "wss://scholaxia1.onrender.com";
var JOIN_TIMEOUT_MS = 45000;

var SUBJECT_SYMBOLS = {
  mathematics: {
    label: "Mathematics",
    symbols: [
      "+", "−", "×", "÷", "=", "≠", "≈", "≤", "≥", "±", "∞", "√", "∛", "∜",
      "π", "θ", "α", "β", "γ", "Δ", "∫", "∑", "∏", "∂", "∇", "°", "′", "″",
      "x²", "x³", "xⁿ", "½", "¼", "¾", "⅓", "⅔", "→", "↔", "⇒", "∈", "∉",
      "⊂", "⊃", "∪", "∩", "∅", "ℝ", "ℕ", "ℤ", "ℚ", "ℂ", "sin", "cos", "tan",
      "log", "ln", "lim", "f(x)", "dy/dx", "∴", "∵", "(", ")", "[", "]", "{", "}"
    ]
  },
  physics: {
    label: "Physics",
    symbols: [
      "F", "m", "a", "v", "u", "t", "s", "d", "E", "W", "P", "V", "I", "R", "Q",
      "Ω", "λ", "ν", "f", "Hz", "J", "N", "kg", "m/s", "m/s²", "Δ", "ρ", "μ",
      "ε", "σ", "θ", "ω", "α", "β", "γ", "Φ", "Ψ", "∫", "∇", "×", "·", "→", "↑", "↓",
      "F=ma", "V=IR", "P=IV", "E=mc²", "KE", "PE", "W=Fd", "v²=u²+2as",
      "°C", "K", "Pa", "N·m", "W/m²", "c", "h", "e", "π", "±", "≈", "∝"
    ]
  },
  chemistry: {
    label: "Chemistry",
    symbols: [
      "H", "He", "Li", "C", "N", "O", "Na", "Cl", "Fe", "Cu", "Zn", "Ag", "Au",
      "H₂", "O₂", "N₂", "CO₂", "H₂O", "NaCl", "H⁺", "OH⁻", "e⁻", "→", "⇌", "⇋",
      "↑", "↓", "(s)", "(l)", "(g)", "(aq)", "Δ", "°C", "mol", "M", "mol/L",
      "pH", "pKa", "Ksp", "K_eq", "E°", "ΔG", "ΔH", "ΔS", "+", "−", "=", "≡",
      "#", "[", "]", "(", ")", "¹", "²", "³", "⁴", "⁺", "⁻", "½", "⅓", "⁄"
    ]
  },
  english: {
    label: "English",
    symbols: [
      "—", "–", "…", "\u2019", "\u2018", "\u201C", "\u201D", "«", "»", ";", ":", "?", "!", "@",
      "#", "%", "&", "*", "(", ")", "[", "]", "{", "}", "§", "†", "‡", "•",
      "¿", "¡", "/", "\\", "|", "~", "^", "_", "+", "=", "<", ">", "A", "B",
      "C", "D", "E", "F", "G", "H", "I", "J", "K", "L", "M", "N", "O", "P"
    ]
  },
  igbo: {
    label: "Igbo",
    symbols: [
      "a", "b", "ch", "d", "e", "f", "g", "gb", "gh", "gw", "h", "i", "ị", "j",
      "k", "kp", "kw", "l", "m", "n", "ṅ", "nw", "ny", "o", "ọ", "p", "r", "s",
      "sh", "t", "u", "ụ", "v", "w", "y", "z", "á", "à", "é", "è", "í", "ì",
      "ó", "ò", "ú", "ù", "ḿ", "ń", "A", "B", "CH", "D", "E", "Ị", "Ọ", "Ụ",
      "kedu", "biko", "daalụ", "nno", "ọ dị mma", "?", "!", "."
    ]
  }
};

var board = {
  open: false,
  ctx: null,
  canvas: null,
  drawing: false,
  lastX: 0,
  lastY: 0,
  tool: "type",
  pendingSymbol: null,
  canDraw: false,
  history: [],
  textX: 24,
  textY: 48,
  liveText: "",
  fontSize: 28,
  lineHeight: 36,
  imageCache: {}
};

var liveSaveRecorder = null;
var liveSaveChunks = [];
var liveSaveActive = false;
var liveSaveStartedAt = null;

function parseJwt(token) {
  try {
    var part = token.split(".")[1];
    if (!part) return {};
    part = part.replace(/-/g, "+").replace(/_/g, "/");
    while (part.length % 4) part += "=";
    return JSON.parse(atob(part));
  } catch (e) {
    return {};
  }
}

function getAuthToken() {
  return localStorage.getItem("sia_token") || localStorage.getItem("sia_teacher_token") || localStorage.getItem("sia_admin_token") || "";
}

function loadLiveSession() {
  try {
    return JSON.parse(localStorage.getItem("live_session") || "null");
  } catch (e) {
    return null;
  }
}

function isTeacherRole() {
  return liveSession && (liveSession.role === "teacher" || liveSession.role === "admin");
}

function setStatus(text) {
  var el = document.getElementById("cr-status");
  if (el) el.textContent = text;
}

function showHostTools(show) {
  document.querySelectorAll(".host-only").forEach(function (el) {
    if (show) el.classList.remove("hidden");
    else el.classList.add("hidden");
  });
}

function showStudentTools(show) {
  document.querySelectorAll(".student-only").forEach(function (el) {
    if (show) el.classList.remove("hidden");
    else el.classList.add("hidden");
  });
}

function getRemoteClassMediaStream() {
  if (!agoraClient) return null;
  var users = agoraClient.remoteUsers || [];
  for (var i = 0; i < users.length; i++) {
    var user = users[i];
    if (!user.videoTrack && !user.audioTrack) continue;
    var ms = new MediaStream();
    try {
      if (user.videoTrack && user.videoTrack.getMediaStreamTrack) {
        ms.addTrack(user.videoTrack.getMediaStreamTrack());
      }
      if (user.audioTrack && user.audioTrack.getMediaStreamTrack) {
        ms.addTrack(user.audioTrack.getMediaStreamTrack());
      }
    } catch (e) { /* ignore */ }
    if (ms.getTracks().length) return ms;
  }
  return null;
}

function updateSaveLiveUi() {
  var btn = document.getElementById("btn-save-live");
  var badge = document.getElementById("save-live-badge");
  if (btn) btn.classList.toggle("save-active", liveSaveActive);
  if (badge) badge.classList.toggle("hidden", !liveSaveActive);
}

function pickRecorderMimeType() {
  var types = ["video/webm;codecs=vp9,opus", "video/webm;codecs=vp8,opus", "video/webm"];
  for (var i = 0; i < types.length; i++) {
    if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(types[i])) return types[i];
  }
  return "video/webm";
}

function toggleSaveLive() {
  if (isTeacherRole()) return;
  if (liveSaveActive) {
    stopLiveSaveAndStore(true);
    return;
  }
  var stream = getRemoteClassMediaStream();
  if (!stream) {
    addChatMessage("", "Wait for the teacher video/audio to connect, then tap Save live again.", true);
    return;
  }
  liveSaveChunks = [];
  liveSaveStartedAt = Date.now();
  try {
    liveSaveRecorder = new MediaRecorder(stream, { mimeType: pickRecorderMimeType() });
  } catch (e) {
    liveSaveRecorder = new MediaRecorder(stream);
  }
  liveSaveRecorder.ondataavailable = function (ev) {
    if (ev.data && ev.data.size) liveSaveChunks.push(ev.data);
  };
  liveSaveRecorder.start(1000);
  liveSaveActive = true;
  updateSaveLiveUi();
  addChatMessage("", "Saving this class on your computer. Tap Save live again to finish.", true);
}

async function stopLiveSaveAndStore(showNotice) {
  if (!liveSaveActive && !liveSaveRecorder) return;
  liveSaveActive = false;
  updateSaveLiveUi();
  if (!liveSaveRecorder) return;
  var recorder = liveSaveRecorder;
  liveSaveRecorder = null;
  return new Promise(function (resolve) {
    recorder.onstop = async function () {
      try {
        if (!liveSaveChunks.length) {
          resolve();
          return;
        }
        var blob = new Blob(liveSaveChunks, { type: recorder.mimeType || "video/webm" });
        liveSaveChunks = [];
        var mins = liveSaveStartedAt ? Math.max(1, Math.round((Date.now() - liveSaveStartedAt) / 60000)) : 0;
        await saveLiveRecording({
          title: (liveSession && liveSession.title) || "Live class",
          subject: liveSession && liveSession.subject,
          teacher: liveSession && liveSession.teacher_name,
          class_id: liveSession && liveSession.class_id,
          duration_hint: mins ? (mins + " min") : "",
        }, blob);
        if (showNotice) {
          addChatMessage("", "Live class saved on this device. Open Saved Lives in the app to watch.", true);
        }
      } catch (e) {
        if (showNotice) addChatMessage("", "Could not save recording: " + e.message, true);
      }
      resolve();
    };
    try {
      recorder.stop();
    } catch (e) {
      resolve();
    }
  });
}

function setVideoControlsEnabled(enabled) {
  var ids = ["btn-mic", "btn-cam"];
  if (isTeacherRole()) ids.push("btn-share");
  ids.forEach(function (id) {
    var btn = document.getElementById(id);
    if (!btn) return;
    btn.disabled = !enabled;
  });
}

function updateMediaButton(btn, on) {
  if (!btn) return;
  btn.classList.toggle("off", !on);
  btn.classList.toggle("on", on);
}

function showMicMeter(show) {
  var meter = document.getElementById("mic-meter");
  if (meter) meter.classList.toggle("hidden", !show);
}

function showMicLiveBadge(show, text) {
  var badge = document.getElementById("mic-live-badge");
  if (!badge) return;
  if (typeof text === "string") badge.textContent = text;
  badge.classList.toggle("hidden", !show);
}

function countVideoAudience() {
  if (!agoraClient || !agoraJoined) return 0;
  return (agoraClient.remoteUsers || []).length;
}

function updateAudienceStats() {
  var badge = document.getElementById("audience-badge");
  if (!badge || !isTeacherRole()) return;
  var inChat = wsStudentCount;
  var inVideo = countVideoAudience();
  var parts = [];
  if (inChat > 0) parts.push(inChat + " in chat");
  if (inVideo > 0) parts.push(inVideo + " on video");
  if (!parts.length) {
    badge.textContent = "No students yet";
    badge.classList.remove("hidden");
    return;
  }
  badge.textContent = parts.join(" · ");
  badge.classList.remove("hidden");
}

function updateMicAudienceBadge(level) {
  if (!isTeacherRole()) return;
  var audience = countVideoAudience();
  var inChat = wsStudentCount;
  if (mediaMode === "local") {
    showMicLiveBadge(
      micOn && level > 8,
      inChat > 0
        ? "Mic on — students can't hear yet (" + inChat + " waiting)"
        : "Mic on — preview only (video not connected)"
    );
    return;
  }
  if (micOn && level > 8 && audience > 0) {
    showMicLiveBadge(true, audience + " student(s) can hear you");
  } else if (micOn && agoraJoined && audience === 0) {
    showMicLiveBadge(true, "Mic live — waiting for students to join video");
  } else {
    showMicLiveBadge(micOn && level > 8, "Students hear you");
  }
}

function stopMicMonitor() {
  if (micMonitorTimer) {
    clearInterval(micMonitorTimer);
    micMonitorTimer = null;
  }
  if (micMonitorCtx) {
    try { micMonitorCtx.close(); } catch (e) { /* ignore */ }
    micMonitorCtx = null;
  }
  showMicMeter(false);
  showMicLiveBadge(false);
}

function startMicMonitor(streamOrTrack) {
  stopMicMonitor();
  if (!streamOrTrack) return;

  var stream = streamOrTrack;
  if (streamOrTrack.getMediaStreamTrack) {
    stream = new MediaStream([streamOrTrack.getMediaStreamTrack()]);
  } else if (streamOrTrack.mediaStreamTrack) {
    stream = new MediaStream([streamOrTrack.mediaStreamTrack]);
  }

  try {
    micMonitorCtx = new (window.AudioContext || window.webkitAudioContext)();
    var source = micMonitorCtx.createMediaStreamSource(stream);
    var analyser = micMonitorCtx.createAnalyser();
    analyser.fftSize = 256;
    source.connect(analyser);
    var data = new Uint8Array(analyser.frequencyBinCount);
    showMicMeter(true);

    micMonitorTimer = setInterval(function () {
      analyser.getByteFrequencyData(data);
      var sum = 0;
      for (var i = 0; i < data.length; i++) sum += data[i];
      var level = Math.min(100, Math.round((sum / data.length) * 1.4));
      var fill = document.getElementById("mic-meter-fill");
      if (fill) fill.style.width = level + "%";
      updateMicAudienceBadge(level);
    }, 80);
  } catch (e) { /* ignore */ }
}

function startSelfHear(streamOrTrack) {
  stopSelfHear();
  try {
    var stream = streamOrTrack;
    if (streamOrTrack.getMediaStreamTrack) {
      stream = new MediaStream([streamOrTrack.getMediaStreamTrack()]);
    } else if (streamOrTrack.mediaStreamTrack) {
      stream = new MediaStream([streamOrTrack.mediaStreamTrack]);
    }
    selfHearAudio = document.createElement("audio");
    selfHearAudio.srcObject = stream;
    selfHearAudio.volume = 0.35;
    selfHearAudio.autoplay = true;
    selfHearAudio.muted = false;
    document.body.appendChild(selfHearAudio);
  } catch (e) { /* ignore */ }
}

function stopSelfHear() {
  if (!selfHearAudio) return;
  try {
    selfHearAudio.pause();
    selfHearAudio.srcObject = null;
    selfHearAudio.remove();
  } catch (e) { /* ignore */ }
  selfHearAudio = null;
}

function getStudentName() {
  return localStorage.getItem("sia_name") || "Student";
}

function renderRaisedHands() {
  var list = document.getElementById("raise-hand-list");
  if (!list || !isTeacherRole()) return;
  var ids = Object.keys(raisedHands);
  if (!ids.length) {
    list.innerHTML = '<p class="raise-hand-empty">No students waiting.</p>';
    return;
  }
  list.innerHTML = ids.map(function (id) {
    var item = raisedHands[id];
    var name = escHtml(item.name || "Student");
    var safeId = id.replace(/\\/g, "\\\\").replace(/'/g, "\\'");
    return '<div class="raise-hand-item"><span>&#9995; ' + name + '</span>' +
      '<button type="button" onclick="grantStudentMic(\'' + safeId + '\')">Allow mic</button></div>';
  }).join("");
}

function addRaisedHand(userId, name) {
  if (!userId || isTeacherRole()) return;
  raisedHands[userId] = { name: name || "Student" };
  renderRaisedHands();
}

function removeRaisedHand(userId) {
  delete raisedHands[userId];
  renderRaisedHands();
}

async function grantStudentMic(userId) {
  if (!isTeacherRole() || !userId) return;
  var item = raisedHands[userId] || { name: "Student" };
  var classId = liveSession.class_id || liveSession.classId;
  try {
    await api("/api/v1/live-classes/" + classId + "/students/" + userId + "/unmute", { method: "POST" });
    if (liveSocket && liveSocket.readyState === WebSocket.OPEN) {
      liveSocket.send(JSON.stringify({ event: "grant_mic", target_user_id: userId }));
    }
    removeRaisedHand(userId);
    addChatMessage("", item.name + " can speak now — mic allowed.", true);
  } catch (e) {
    if (liveSocket && liveSocket.readyState === WebSocket.OPEN) {
      liveSocket.send(JSON.stringify({ event: "grant_mic", target_user_id: userId }));
      removeRaisedHand(userId);
      addChatMessage("", item.name + " can speak now.", true);
    } else {
      addChatMessage("", "Could not allow mic: " + e.message, true);
    }
  }
}

function playRemoteVideo(user, isScreen) {
  if (!user || !user.videoTrack) return;
  hideVideoPlaceholder();
  var wrap = document.getElementById("video-remote");
  wrap.innerHTML = "";
  wrap.classList.toggle("screen-active", !!isScreen);
  var box = document.createElement("div");
  box.className = "remote-user" + (isScreen ? " screen-share" : "");
  var vid = document.createElement("div");
  vid.style.width = "100%";
  vid.style.height = "100%";
  user.videoTrack.play(vid);
  box.appendChild(vid);
  wrap.appendChild(box);
  if (!isTeacherRole()) showBoardForStudent(false);
}

function isScreenShareTrack(track) {
  if (!track) return false;
  try {
    var msTrack = track.getMediaStreamTrack ? track.getMediaStreamTrack() : track;
    if (msTrack && msTrack.label) {
      var label = msTrack.label.toLowerCase();
      return label.indexOf("screen") >= 0 || label.indexOf("window") >= 0 || label.indexOf("display") >= 0;
    }
  } catch (e) { /* ignore */ }
  return false;
}

async function subscribeToExistingUsers() {
  if (!agoraClient || !agoraJoined) return;
  var users = agoraClient.remoteUsers || [];
  for (var i = 0; i < users.length; i++) {
    var user = users[i];
    try {
      if (user.hasVideo) {
        await agoraClient.subscribe(user, "video");
        playRemoteVideo(user, isScreenShareTrack(user.videoTrack));
      }
      if (user.hasAudio) {
        await agoraClient.subscribe(user, "audio");
        user.audioTrack.setVolume(100);
        user.audioTrack.play();
      }
    } catch (e) { /* ignore */ }
  }
}

async function enableStudentMic() {
  studentMicAllowed = true;
  setVideoControlsEnabled(true);
  addChatMessage("", "Your teacher let you speak. Turning on your mic…", true);
  try {
    await refreshAgoraToken();
    if (agoraJoined && agoraClient && liveSession.agora_token) {
      await agoraClient.renewToken(liveSession.agora_token);
    }
    await setMic(true);
  } catch (e) {
    addChatMessage("", "Mic: " + e.message, true);
  }
}

async function disableStudentMic() {
  studentMicAllowed = false;
  try {
    await setMic(false);
    await refreshAgoraToken();
    if (agoraJoined && agoraClient && liveSession.agora_token) {
      await agoraClient.renewToken(liveSession.agora_token);
    }
  } catch (e) { /* ignore */ }
  updateMediaButton(document.getElementById("btn-mic"), false);
}

function withTimeout(promise, ms, message) {
  return Promise.race([
    promise,
    new Promise(function (_, reject) {
      setTimeout(function () { reject(new Error(message)); }, ms);
    })
  ]);
}

function addChatMessage(name, text, isSystem) {
  var log = document.getElementById("chat-log");
  if (!log) return;
  var div = document.createElement("div");
  div.className = "chat-msg" + (isSystem ? " system" : "");
  if (isSystem) {
    div.textContent = text;
  } else {
    div.innerHTML = "<strong>" + escHtml(name) + "</strong>" + escHtml(text);
  }
  log.appendChild(div);
  log.scrollTop = log.scrollHeight;
}

function sendBoardEvent(action, data) {
  if (!liveSocket || liveSocket.readyState !== WebSocket.OPEN) return;
  liveSocket.send(JSON.stringify({ event: "whiteboard", action: action, data: data }));
}

function showBoardForStudent(forceOpen) {
  if (isTeacherRole()) return;
  var overlay = document.getElementById("board-overlay");
  if (!overlay) return;
  if (forceOpen !== false) {
    board.open = true;
    overlay.classList.remove("hidden");
    hideVideoPlaceholder();
    resizeBoardCanvas();
  }
}

function syncBoardToRoom() {
  if (!isTeacherRole() || !liveSocket || liveSocket.readyState !== WebSocket.OPEN) return;
  sendBoardEvent("board_open", { open: board.open });
  for (var i = 0; i < board.history.length; i++) {
    var item = board.history[i];
    sendBoardEvent(item.type, item.data);
  }
  if (board.liveText) {
    sendBoardEvent("text_stream", {
      x: board.textX,
      y: board.textY,
      text: board.liveText,
      size: board.fontSize,
    });
  }
}

function initWhiteboard() {
  board.canvas = document.getElementById("whiteboard");
  if (!board.canvas) return;
  board.ctx = board.canvas.getContext("2d");
  board.canDraw = isTeacherRole();
  resizeBoardCanvas();
  window.addEventListener("resize", resizeBoardCanvas);

  board.canvas.addEventListener("mousedown", onBoardPointerDown);
  board.canvas.addEventListener("mousemove", onBoardPointerMove);
  board.canvas.addEventListener("mouseup", onBoardPointerUp);
  board.canvas.addEventListener("mouseleave", onBoardPointerUp);
  board.canvas.addEventListener("touchstart", onBoardTouchStart, { passive: false });
  board.canvas.addEventListener("touchmove", onBoardTouchMove, { passive: false });
  board.canvas.addEventListener("touchend", onBoardPointerUp);

  var typeInput = document.getElementById("board-type-input");
  if (typeInput) {
    typeInput.addEventListener("input", onBoardTypeInput);
    typeInput.addEventListener("keydown", onBoardTypeKeydown);
  }

  var imageInput = document.getElementById("board-image-input");
  if (imageInput) {
    imageInput.addEventListener("change", onBoardImageSelected);
  }

  var overlay = document.getElementById("board-overlay");
  if (overlay && !board.canDraw) overlay.classList.add("view-only");

  if (isTeacherRole()) {
    var subj = (liveSession.subject || "mathematics").toLowerCase();
    var key = "mathematics";
    if (subj.indexOf("phys") >= 0) key = "physics";
    else if (subj.indexOf("chem") >= 0) key = "chemistry";
    else if (subj.indexOf("eng") >= 0) key = "english";
    else if (subj.indexOf("igbo") >= 0) key = "igbo";
    else if (subj.indexOf("math") >= 0) key = "mathematics";
    var sel = document.getElementById("subject-keyboard");
    if (sel) sel.value = key;
    renderSymbolPalette();
    setBoardTool("type");
  }
}

function redrawBoard() {
  if (!board.ctx || !board.canvas) return;
  board.ctx.clearRect(0, 0, board.canvas.width, board.canvas.height);
  var idx = 0;
  function drawNext() {
    if (idx >= board.history.length) {
      if (board.liveText) {
        applyBoardText({
          x: board.textX,
          y: board.textY,
          text: board.liveText,
          size: board.fontSize
        }, false);
      }
      updateBoardCursor();
      return;
    }
    var item = board.history[idx++];
    if (item.type === "draw") {
      applyDrawStroke(item.data, false);
      drawNext();
    } else if (item.type === "erase") {
      applyEraseStroke(item.data, false);
      drawNext();
    } else if (item.type === "text") {
      applyBoardText(item.data, false);
      drawNext();
    } else if (item.type === "image") {
      loadBoardImage(item.data.url, function (img) {
        board.ctx.drawImage(img, item.data.x, item.data.y, item.data.w, item.data.h);
        drawNext();
      }, drawNext);
    } else {
      drawNext();
    }
  }
  drawNext();
}

function loadBoardImage(url, onLoad, onError) {
  if (board.imageCache[url]) {
    onLoad(board.imageCache[url]);
    return;
  }
  var img = new Image();
  img.crossOrigin = "anonymous";
  img.onload = function () {
    board.imageCache[url] = img;
    onLoad(img);
  };
  img.onerror = function () {
    if (onError) onError();
  };
  img.src = url;
}

function fitImageOnBoard(img) {
  var cw = board.canvas.width;
  var ch = board.canvas.height;
  var maxW = cw * 0.88;
  var maxH = ch * 0.5;
  var scale = Math.min(maxW / img.width, maxH / img.height, 1);
  var w = img.width * scale;
  var h = img.height * scale;
  return {
    x: (cw - w) / 2,
    y: 20,
    w: w,
    h: h
  };
}

function pickBoardImage() {
  if (!board.canDraw) return;
  var input = document.getElementById("board-image-input");
  if (input) input.click();
}

function onBoardImageSelected(ev) {
  var file = ev.target.files && ev.target.files[0];
  ev.target.value = "";
  if (!file || !board.canDraw) return;
  if (!file.type || file.type.indexOf("image/") !== 0) {
    addChatMessage("", "Please choose a JPEG, PNG, or WebP image.", true);
    return;
  }
  if (file.size > 10 * 1024 * 1024) {
    addChatMessage("", "Image is too large. Maximum size is 10MB.", true);
    return;
  }
  uploadBoardImage(file);
}

async function uploadBoardImage(file) {
  try {
    addChatMessage("", "Uploading image to the board…", true);
    var uploaded = await apiUpload("/api/v1/community/upload", file);
    if (!uploaded || !uploaded.file_url) throw new Error("No image URL returned");
    await placeBoardImage(uploaded.file_url, true);
    addChatMessage("", "Image is on the board — students can see it.", true);
  } catch (e) {
    addChatMessage("", "Image upload failed: " + e.message, true);
  }
}

function placeBoardImage(url, broadcast) {
  return new Promise(function (resolve, reject) {
    loadBoardImage(url, function (img) {
      var box = fitImageOnBoard(img);
      addBoardImage({ url: url, x: box.x, y: box.y, w: box.w, h: box.h }, broadcast)
        .then(resolve).catch(reject);
    }, function () {
      reject(new Error("Could not load image"));
    });
  });
}

function addBoardImage(data, broadcast) {
  return new Promise(function (resolve, reject) {
    loadBoardImage(data.url, function (img) {
      board.history.push({ type: "image", data: data });
      board.ctx.drawImage(img, data.x, data.y, data.w, data.h);
      if (broadcast !== false) sendBoardEvent("image", data);
      resolve();
    }, function () {
      reject(new Error("Could not load image"));
    });
  });
}

function updateBoardCursor() {
  var cursor = document.getElementById("board-cursor");
  var canvas = board.canvas;
  var overlay = document.getElementById("board-overlay");
  if (!cursor || !canvas || !overlay) return;
  if (!board.open || board.tool !== "type" || !board.canDraw) {
    cursor.classList.add("hidden");
    return;
  }
  var rect = canvas.getBoundingClientRect();
  var overlayRect = overlay.getBoundingClientRect();
  var scaleX = rect.width / canvas.width;
  var scaleY = rect.height / canvas.height;
  cursor.style.left = (rect.left - overlayRect.left + board.textX * scaleX) + "px";
  cursor.style.top = (rect.top - overlayRect.top + (board.textY - board.fontSize) * scaleY) + "px";
  cursor.style.height = (board.fontSize * scaleY) + "px";
  cursor.classList.remove("hidden");
}

function onBoardTypeInput() {
  if (!board.canDraw) return;
  var inp = document.getElementById("board-type-input");
  board.liveText = inp ? inp.value : "";
  redrawBoard();
  sendBoardEvent("text_stream", {
    x: board.textX,
    y: board.textY,
    text: board.liveText,
    size: board.fontSize
  });
}

function onBoardTypeKeydown(e) {
  if (!board.canDraw || e.key !== "Enter") return;
  e.preventDefault();
  commitBoardLine();
}

function commitBoardLine() {
  var inp = document.getElementById("board-type-input");
  var text = inp ? inp.value.trim() : "";
  if (text) {
    var data = { x: board.textX, y: board.textY, text: text, size: board.fontSize };
    board.history.push({ type: "text", data: data });
    sendBoardEvent("text", data);
  }
  if (inp) inp.value = "";
  board.liveText = "";
  board.textY += board.lineHeight;
  redrawBoard();
  sendBoardEvent("text_stream", { x: board.textX, y: board.textY, text: "", size: board.fontSize });
  if (inp) inp.focus();
}

function resizeBoardCanvas() {
  if (!board.canvas) return;
  var stage = document.getElementById("video-stage");
  if (!stage) return;
  var rect = stage.getBoundingClientRect();
  board.canvas.width = rect.width;
  board.canvas.height = Math.max(rect.height - (board.canDraw ? 160 : 0), 200);
  if (board.ctx) {
    board.ctx.lineCap = "round";
    board.ctx.lineJoin = "round";
    board.ctx.strokeStyle = "#e8f5ec";
    board.ctx.lineWidth = 3;
  }
  redrawBoard();
}

function boardCoords(ev) {
  var rect = board.canvas.getBoundingClientRect();
  return {
    x: (ev.clientX - rect.left) * (board.canvas.width / rect.width),
    y: (ev.clientY - rect.top) * (board.canvas.height / rect.height)
  };
}

function onBoardTouchStart(ev) {
  if (!board.canDraw || ev.touches.length !== 1) return;
  ev.preventDefault();
  var t = ev.touches[0];
  onBoardPointerDown({ clientX: t.clientX, clientY: t.clientY, preventDefault: function () {} });
}

function onBoardTouchMove(ev) {
  if (!board.canDraw || ev.touches.length !== 1) return;
  ev.preventDefault();
  var t = ev.touches[0];
  onBoardPointerMove({ clientX: t.clientX, clientY: t.clientY });
}

function onBoardPointerDown(ev) {
  if (!board.open || !board.canDraw) return;
  var p = boardCoords(ev);
  if (board.tool === "type") {
    commitBoardLine();
    board.textX = p.x;
    board.textY = p.y;
    var inp = document.getElementById("board-type-input");
    if (inp) { inp.focus(); }
    updateBoardCursor();
    sendBoardEvent("text_stream", { x: board.textX, y: board.textY, text: board.liveText, size: board.fontSize });
    return;
  }
  if (board.tool !== "draw" && board.tool !== "erase") return;
  board.drawing = true;
  board.lastX = p.x;
  board.lastY = p.y;
}

function onBoardPointerMove(ev) {
  if (!board.drawing || !board.ctx) return;
  var p = boardCoords(ev);
  if (board.tool === "erase") {
    var eraseStroke = {
      x0: board.lastX, y0: board.lastY, x1: p.x, y1: p.y, width: 28
    };
    applyEraseStroke(eraseStroke, false);
    sendBoardEvent("erase", eraseStroke);
    board.history.push({ type: "erase", data: eraseStroke });
    board.lastX = p.x;
    board.lastY = p.y;
    return;
  }
  var stroke = {
    x0: board.lastX, y0: board.lastY, x1: p.x, y1: p.y,
    color: "#e8f5ec", width: 3
  };
  applyDrawStroke(stroke, false);
  sendBoardEvent("draw", stroke);
  board.history.push({ type: "draw", data: stroke });
  board.lastX = p.x;
  board.lastY = p.y;
}

function onBoardPointerUp() {
  board.drawing = false;
}

function applyEraseStroke(data, save) {
  if (!board.ctx || !data) return;
  board.ctx.save();
  board.ctx.globalCompositeOperation = "destination-out";
  board.ctx.lineCap = "round";
  board.ctx.lineJoin = "round";
  board.ctx.strokeStyle = "rgba(0,0,0,1)";
  board.ctx.lineWidth = data.width || 28;
  board.ctx.beginPath();
  board.ctx.moveTo(data.x0, data.y0);
  board.ctx.lineTo(data.x1, data.y1);
  board.ctx.stroke();
  board.ctx.restore();
  if (save !== false) board.history.push({ type: "erase", data: data });
}

function applyDrawStroke(data, save) {
  if (!board.ctx || !data) return;
  board.ctx.strokeStyle = data.color || "#e8f5ec";
  board.ctx.lineWidth = data.width || 3;
  board.ctx.beginPath();
  board.ctx.moveTo(data.x0, data.y0);
  board.ctx.lineTo(data.x1, data.y1);
  board.ctx.stroke();
  if (save !== false) board.history.push({ type: "draw", data: data });
}

function placeSymbol(x, y, text, broadcast) {
  if (!board.ctx) return;
  var data = { x: x, y: y, text: text, size: board.fontSize };
  applyBoardText(data, false);
  board.history.push({ type: "text", data: data });
  if (broadcast !== false) sendBoardEvent("text", data);
}

function applyBoardText(data, save) {
  if (!board.ctx || !data) return;
  board.ctx.font = "600 " + (data.size || board.fontSize) + "px Inter, sans-serif";
  board.ctx.fillStyle = "#e8f5ec";
  board.ctx.fillText(data.text, data.x, data.y);
  if (save !== false) board.history.push({ type: "text", data: data });
}

function clearBoardCanvas(broadcast) {
  if (!board.ctx || !board.canvas) return;
  board.history = [];
  board.liveText = "";
  var inp = document.getElementById("board-type-input");
  if (inp) inp.value = "";
  redrawBoard();
  if (broadcast !== false && board.canDraw) sendBoardEvent("clear", {});
}

function clearBoard() {
  clearBoardCanvas(true);
}

function setBoardTool(tool) {
  board.tool = tool;
  board.pendingSymbol = null;
  document.querySelectorAll(".sym-btn.active").forEach(function (b) { b.classList.remove("active"); });
  var typeBtn = document.getElementById("btn-board-type");
  var drawBtn = document.getElementById("btn-board-draw");
  var eraseBtn = document.getElementById("btn-board-erase");
  if (typeBtn) typeBtn.classList.toggle("active", tool === "type");
  if (drawBtn) drawBtn.classList.toggle("active", tool === "draw");
  if (eraseBtn) eraseBtn.classList.toggle("active", tool === "erase");
  if (tool === "type") {
    var inp = document.getElementById("board-type-input");
    if (inp && board.canDraw) inp.focus();
    updateBoardCursor();
  } else {
    var cursor = document.getElementById("board-cursor");
    if (cursor) cursor.classList.add("hidden");
  }
}

function renderSymbolPalette() {
  var sel = document.getElementById("subject-keyboard");
  var palette = document.getElementById("symbol-palette");
  if (!sel || !palette) return;
  var key = sel.value || "mathematics";
  var pack = SUBJECT_SYMBOLS[key] || SUBJECT_SYMBOLS.mathematics;
  palette.innerHTML = pack.symbols.map(function (sym, i) {
    return '<button type="button" class="sym-btn" data-sym-idx="' + i + '">' + escHtml(sym) + "</button>";
  }).join("");
  palette.querySelectorAll(".sym-btn").forEach(function (btn, i) {
    btn.addEventListener("click", function () { pickSymbol(pack.symbols[i]); });
  });
}

function pickSymbol(sym) {
  setBoardTool("type");
  var inp = document.getElementById("board-type-input");
  if (!inp) return;
  inp.value += sym;
  inp.focus();
  onBoardTypeInput();
  document.querySelectorAll(".sym-btn").forEach(function (b) {
    b.classList.toggle("active", b.textContent === sym);
  });
  setTimeout(function () {
    document.querySelectorAll(".sym-btn.active").forEach(function (b) { b.classList.remove("active"); });
  }, 300);
}

function toggleBoard(forceOpen) {
  var overlay = document.getElementById("board-overlay");
  if (!overlay) return;
  var open = typeof forceOpen === "boolean" ? forceOpen : !board.open;
  board.open = open;
  overlay.classList.toggle("hidden", !open);
  if (open) {
    resizeBoardCanvas();
    hideVideoPlaceholder();
    if (board.canDraw) {
      setBoardTool("type");
      var inp = document.getElementById("board-type-input");
      if (inp) setTimeout(function () { inp.focus(); }, 100);
    }
  }
  if (board.canDraw) sendBoardEvent("board_open", { open: open });
}

function handleBoardMessage(msg) {
  if (!msg) return;
  if (msg.action === "board_open") {
    board.open = !!msg.data.open;
    var overlay = document.getElementById("board-overlay");
    if (overlay) overlay.classList.toggle("hidden", !board.open);
    if (board.open) {
      hideVideoPlaceholder();
      resizeBoardCanvas();
    }
    return;
  }
  if (!isTeacherRole()) showBoardForStudent();
  if (msg.action === "draw") {
    applyDrawStroke(msg.data, true);
    redrawBoard();
    return;
  }
  if (msg.action === "erase") {
    applyEraseStroke(msg.data, true);
    redrawBoard();
    return;
  }
  if (msg.action === "text") {
    applyBoardText(msg.data, true);
    board.liveText = "";
    redrawBoard();
    return;
  }
  if (msg.action === "text_stream") {
    board.textX = msg.data.x;
    board.textY = msg.data.y;
    board.liveText = msg.data.text || "";
    redrawBoard();
    return;
  }
  if (msg.action === "image") {
    addBoardImage(msg.data, false).then(function () {
      redrawBoard();
    }).catch(function () { /* ignore */ });
    return;
  }
  if (msg.action === "clear") clearBoardCanvas(false);
}

function connectChat() {
  if (!liveSession || !liveSession.room_id) return;
  var payload = parseJwt(getAuthToken());
  var userId = payload.sub || liveSession.user_id || "user";
  var role = isTeacherRole() ? "teacher" : "student";
  var url = API_WS + "/ws/live-class/" + encodeURIComponent(liveSession.room_id)
    + "?user_id=" + encodeURIComponent(userId) + "&role=" + encodeURIComponent(role);

  liveSocket = new WebSocket(url);
  liveSocket.onopen = function () {
    setStatus("Connected — chat ready");
    addChatMessage("", "You joined the class. Use the chat to talk with everyone.", true);
    if (!isTeacherRole()) {
      liveSocket.send(JSON.stringify({ event: "request_board_sync" }));
    }
    updateAudienceStats();
  };
  liveSocket.onmessage = function (ev) {
    try {
      var msg = JSON.parse(ev.data);
      if (msg.event === "chat") {
        var who = msg.role === "teacher" ? "Teacher" : "Student";
        addChatMessage(who, msg.text || "");
      } else if (msg.event === "user_joined") {
        if (msg.role === "student") wsStudentCount++;
        updateAudienceStats();
        addChatMessage("", "Someone joined the class.", true);
        if (isTeacherRole() && msg.role === "student") {
          setTimeout(syncBoardToRoom, 300);
        }
      } else if (msg.event === "user_left") {
        if (msg.role === "student" && wsStudentCount > 0) wsStudentCount--;
        updateAudienceStats();
        addChatMessage("", "Someone left the class.", true);
      } else if (msg.event === "request_board_sync") {
        if (isTeacherRole()) syncBoardToRoom();
      } else if (msg.event === "class_ended") {
        handleClassEnded(msg.message || "The teacher ended the class.");
      } else if (msg.event === "class_started") {
        if (!isTeacherRole()) {
          addChatMessage("", "Class is live — video connecting…", true);
          if (!agoraJoined && !agoraConnecting) tryStartAgora(true);
        }
      } else if (msg.event === "raise_hand") {
        if (isTeacherRole()) {
          addRaisedHand(msg.user_id, msg.name);
          addChatMessage("", (msg.name || "A student") + " raised their hand.", true);
        }
      } else if (msg.event === "lower_hand") {
        removeRaisedHand(msg.user_id);
      } else if (msg.event === "mic_access_granted") {
        enableStudentMic();
      } else if (msg.event === "mic_access_revoked") {
        disableStudentMic();
        addChatMessage("", msg.message || "Your mic was turned off by the teacher.", true);
      } else if (msg.event === "whiteboard") {
        handleBoardMessage(msg);
      } else if (msg.event === "whiteboard_access_granted") {
        board.canDraw = true;
        var ov = document.getElementById("board-overlay");
        if (ov) ov.classList.remove("view-only");
        addChatMessage("", msg.message || "You can use the board now.", true);
      }
    } catch (e) { /* ignore */ }
  };
  liveSocket.onclose = function () {
    setStatus("Chat disconnected");
  };
  liveSocket.onerror = function () {
    setStatus("Chat connection error");
  };
}

function sendChatMessage(e) {
  e.preventDefault();
  var input = document.getElementById("chat-input");
  var text = input.value.trim();
  if (!text || !liveSocket || liveSocket.readyState !== WebSocket.OPEN) return;
  liveSocket.send(JSON.stringify({ event: "chat", text: text }));
  addChatMessage("You", text);
  input.value = "";
}

function raiseHand() {
  if (!liveSocket || liveSocket.readyState !== WebSocket.OPEN) return;
  if (isTeacherRole()) {
    addChatMessage("", "Students raise their hand — you are the teacher.", true);
    return;
  }
  liveSocket.send(JSON.stringify({ event: "raise_hand", name: getStudentName() }));
  addChatMessage("", "You raised your hand. Wait for the teacher to allow your mic.", true);
}

function showVideoPlaceholder(text) {
  var ph = document.getElementById("video-placeholder");
  var txt = document.getElementById("video-placeholder-text");
  if (txt) txt.textContent = text;
  if (ph) ph.classList.remove("hidden");
}

function hideVideoPlaceholder() {
  var ph = document.getElementById("video-placeholder");
  if (ph) ph.classList.add("hidden");
}

function hasValidAgoraToken(token) {
  if (!liveSession.app_id) return false;
  if (!token) return false;
  if (token.indexOf("AGORA_CERT_NOT_SET") >= 0) return false;
  if (token.indexOf("TOKEN_ERROR") >= 0) return false;
  return true;
}

function agoraCertMissingMessage() {
  return (
    "Live video is not configured on the server (Agora certificate missing on Render). " +
    "Chat and board still work. Ask admin to set AGORA_APP_CERTIFICATE in Render environment variables."
  );
}

async function refreshAgoraToken() {
  var classId = liveSession.class_id || liveSession.classId;
  if (!classId) return false;
  try {
    var data = await api("/api/v1/live-classes/" + classId + "/token");
    liveSession.agora_token = data.token;
    liveSession.uid = data.uid;
    liveSession.app_id = data.app_id;
    liveSession.channel_id = data.channel_id;
    if (data.end_time) liveSession.end_time = data.end_time;
    localStorage.setItem("live_session", JSON.stringify(liveSession));
    return hasValidAgoraToken(data.token);
  } catch (e) {
    return false;
  }
}

async function startLocalPreviewOnly() {
  if (!isTeacherRole()) return;
  if (localPreviewStream) {
    restoreLocalCameraPreview();
    if (mediaMode !== "agora") setVideoControlsEnabled(true);
    return;
  }
  try {
    localPreviewStream = await navigator.mediaDevices.getUserMedia({
      video: { facingMode: "user", width: { ideal: 1280 }, height: { ideal: 720 } },
      audio: { echoCancellation: true, noiseSuppression: true },
    });
    if (mediaMode === "agora") {
      localPreviewStream.getTracks().forEach(function (t) { t.stop(); });
      localPreviewStream = null;
      return;
    }
    var localEl = document.getElementById("video-local");
    var vid = document.createElement("video");
    vid.srcObject = localPreviewStream;
    vid.autoplay = true;
    vid.muted = true;
    vid.playsInline = true;
    localEl.innerHTML = "";
    localEl.appendChild(vid);
    localEl.classList.remove("hidden");
    hideVideoPlaceholder();
    micOn = true;
    camOn = true;
    updateMediaButton(document.getElementById("btn-cam"), true);
    updateMediaButton(document.getElementById("btn-mic"), true);
    setVideoControlsEnabled(true);
    startMicMonitor(localPreviewStream);
    startSelfHear(localPreviewStream);
    if (!agoraJoined) {
      setStatus("Camera on — connecting live video for students…");
      addChatMessage(
        "",
        "You can see yourself. Students will see you when live video connects (top right should say Connected — video + chat).",
        true
      );
    }
  } catch (e) {
    addChatMessage("", "Camera/mic: " + e.message + " — allow camera & microphone in Windows Settings → Privacy.", true);
  }
}

function scheduleClassAutoEnd() {
  if (!liveSession || !liveSession.end_time) return;
  var endMs = new Date(liveSession.end_time).getTime() - Date.now();
  if (classAutoEndTimer) clearTimeout(classAutoEndTimer);
  if (endMs <= 0) {
    if (isTeacherRole()) autoEndClassSession();
    else handleClassEnded("Class time is over.");
    return;
  }
  classAutoEndTimer = setTimeout(function () {
    if (isTeacherRole()) autoEndClassSession();
    else handleClassEnded("Class ended at the scheduled time.");
  }, endMs);
  if (isTeacherRole()) {
    addChatMessage(
      "",
      "Class scheduled to end at " + new Date(liveSession.end_time).toLocaleString() + " (like Zoom/Meet).",
      true
    );
  }
}

function handleClassEnded(message) {
  addChatMessage("", message || "Class has ended.", true);
  setStatus("Class ended");
  setTimeout(function () { leaveClassroom(); }, 2500);
}

async function autoEndClassSession() {
  if (!isTeacherRole() || !liveSession) return;
  var classId = liveSession.class_id || liveSession.classId;
  try {
    await api("/api/v1/live-classes/" + classId + "/end", { method: "POST" });
    setStatus("Class ended");
    addChatMessage("", "Scheduled end time reached — class closed for all students.", true);
    setTimeout(function () { leaveClassroom(); }, 2500);
  } catch (e) {
    addChatMessage("", "Could not auto-end: " + e.message, true);
  }
}

function stopAgoraRetry() {
  if (agoraRetryTimer) {
    clearInterval(agoraRetryTimer);
    agoraRetryTimer = null;
  }
}

function scheduleAgoraRetry() {
  if (agoraJoined || agoraRetryTimer) return;
  agoraRetryTimer = setInterval(function () {
    if (agoraJoined || agoraConnecting) return;
    tryStartAgora(true);
  }, 12000);
}

async function transitionHostToAgoraBroadcast() {
  var wantCam = camOn || !!localPreviewStream;
  var wantMic = micOn || !!localPreviewStream;
  if (localPreviewStream) {
    localPreviewStream.getTracks().forEach(function (t) { t.stop(); });
    localPreviewStream = null;
    stopSelfHear();
    stopMicMonitor();
  }
  localTracks = { audio: null, video: null, screen: null };
  micOn = false;
  camOn = false;
  if (wantCam) await setCam(true);
  if (wantMic) await setMic(true);
}

async function ensureHostPublishing() {
  if (!isTeacherRole() || !agoraJoined || !agoraClient || mediaMode !== "agora") return;
  try {
    if (camOn && !screenOn && !localTracks.video) await setCam(true);
    if (micOn && !localTracks.audio) await setMic(true);
  } catch (e) { /* ignore */ }
}

function restoreLocalCameraPreview() {
  if (!localPreviewStream) return;
  var localEl = document.getElementById("video-local");
  var vid = document.createElement("video");
  vid.srcObject = localPreviewStream;
  vid.autoplay = true;
  vid.muted = true;
  vid.playsInline = true;
  localEl.innerHTML = "";
  localEl.appendChild(vid);
  localEl.classList.remove("hidden");
  camOn = true;
  updateMediaButton(document.getElementById("btn-cam"), true);
}

function enterChatOnlyMode(message) {
  agoraAvailable = false;
  agoraJoined = false;
  agoraClient = null;
  if (!camOn && !localPreviewStream) showVideoPlaceholder(message);
  if (isTeacherRole()) {
    showHostTools(true);
    board.canDraw = true;
    var ov = document.getElementById("board-overlay");
    if (ov) ov.classList.remove("view-only");
    mediaMode = "local";
    startLocalPreviewOnly();
    scheduleAgoraRetry();
  } else {
    setVideoControlsEnabled(false);
    scheduleAgoraRetry();
  }
}

async function tryStartAgora(isRetry) {
  if (agoraConnecting || agoraJoined) return;
  if (!isRetry) setVideoControlsEnabled(false);

  if (typeof AgoraRTC === "undefined") {
    enterChatOnlyMode("Class is live. Video SDK did not load — use class chat and board.");
    return;
  }

  if (isTeacherRole() && !localPreviewStream && !isRetry) {
    startLocalPreviewOnly().catch(function () {});
  }

  agoraConnecting = true;
  await refreshAgoraToken();
  var token = liveSession.agora_token || liveSession.token || "";
  if (!hasValidAgoraToken(token)) {
    agoraConnecting = false;
    if (!isRetry) {
      var certMsg = token.indexOf("AGORA_CERT_NOT_SET") >= 0
        ? agoraCertMissingMessage()
        : "Class is live — chat and board work. Could not get live video token.";
      enterChatOnlyMode(certMsg);
    }
    return;
  }

  agoraAvailable = true;
  if (!camOn && !localPreviewStream) showVideoPlaceholder("Joining video room…");

  try {
    if (!agoraClient) {
      agoraClient = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });
      agoraClient.on("user-published", async function (user, mediaType) {
        try {
          await agoraClient.subscribe(user, mediaType);
          if (mediaType === "video") {
            playRemoteVideo(user, isScreenShareTrack(user.videoTrack));
          }
          if (mediaType === "audio") {
            user.audioTrack.setVolume(100);
            user.audioTrack.play();
            if (!isTeacherRole()) {
              hideVideoPlaceholder();
              setStatus("Connected — you can hear the teacher");
            }
          }
          updateAudienceStats();
        } catch (e) {
          addChatMessage("", "Could not receive video/audio: " + e.message, true);
        }
      });
      agoraClient.on("user-joined", function () {
        updateAudienceStats();
      });
      agoraClient.on("user-left", function () {
        updateAudienceStats();
      });
      agoraClient.on("user-unpublished", function (user, mediaType) {
        if (mediaType === "video") {
          if (isTeacherRole() && (camOn || screenOn)) return;
          var wrap = document.getElementById("video-remote");
          if (wrap) wrap.innerHTML = "";
          showVideoPlaceholder(isTeacherRole()
            ? (screenOn ? "Screen share active." : "Your camera is off.")
            : "Waiting for the teacher…");
        }
      });
    }

    var channel = liveSession.channel_id || liveSession.room_id;
    var uid = Number(liveSession.uid);
    if (!uid && uid !== 0) uid = null;

    if (!agoraJoined) {
      await withTimeout(
        agoraClient.join(liveSession.app_id, channel, token || null, uid),
        JOIN_TIMEOUT_MS,
        "Video join timed out"
      );
    } else {
      await agoraClient.renewToken(token);
    }

    agoraJoined = true;
    mediaMode = "agora";
    stopAgoraRetry();
    await subscribeToExistingUsers();
    updateAudienceStats();
    setVideoControlsEnabled(isTeacherRole() || studentMicAllowed);
    setStatus("Connected — video + chat");

    if (isTeacherRole()) {
      showHostTools(true);
      board.canDraw = true;
      var ov = document.getElementById("board-overlay");
      if (ov) ov.classList.remove("view-only");
      await transitionHostToAgoraBroadcast();
      hideVideoPlaceholder();
      addChatMessage("", "You are live — students can see and hear you now.", true);
    } else {
      var remotes = agoraClient.remoteUsers || [];
      if (remotes.length) hideVideoPlaceholder();
      else showVideoPlaceholder("Waiting for the teacher to start video…");
    }
  } catch (err) {
    agoraJoined = false;
    if (!isRetry) {
      agoraClient = null;
      enterChatOnlyMode(
        "Video could not connect (" + (err.message || "error") + "). Chat and board still work."
      );
    }
    scheduleAgoraRetry();
  } finally {
    agoraConnecting = false;
  }
}

async function startHostMedia() {
  if (!agoraJoined || !isTeacherRole()) return;
  try {
    await setCam(true);
    await setMic(true);
    hideVideoPlaceholder();
    addChatMessage("", "You are live — students can see and hear you. Speak to test the green mic bar.", true);
  } catch (e) {
    setVideoControlsEnabled(true);
    addChatMessage("", "Could not start camera/mic: " + e.message, true);
  }
}

async function setMic(on) {
  if (mediaMode === "local" && localPreviewStream) {
    var audioTrack = localPreviewStream.getAudioTracks()[0];
    if (!audioTrack) return;
    audioTrack.enabled = on;
    micOn = on;
    updateMediaButton(document.getElementById("btn-mic"), on);
    if (on) {
      startMicMonitor(localPreviewStream);
      startSelfHear(localPreviewStream);
    } else {
      stopMicMonitor();
      stopSelfHear();
    }
    return;
  }

  if (!agoraJoined || !agoraClient) return;
  var btn = document.getElementById("btn-mic");
  if (on === micOn) return;
  if (on) {
    if (!localTracks.audio) {
      localTracks.audio = await AgoraRTC.createMicrophoneAudioTrack();
    }
    await agoraClient.publish([localTracks.audio]);
    micOn = true;
    updateMediaButton(btn, true);
    startMicMonitor(localTracks.audio);
    startSelfHear(localTracks.audio);
  } else {
    if (localTracks.audio) {
      await agoraClient.unpublish([localTracks.audio]);
      localTracks.audio.stop();
      localTracks.audio.close();
      localTracks.audio = null;
    }
    micOn = false;
    updateMediaButton(btn, false);
    stopMicMonitor();
    stopSelfHear();
  }
}

async function setCam(on) {
  if (mediaMode === "local" && localPreviewStream) {
    if (on && !agoraJoined) {
      tryStartAgora(true);
    }
    var videoTrack = localPreviewStream.getVideoTracks()[0];
    var localEl = document.getElementById("video-local");
    if (!videoTrack) return;
    videoTrack.enabled = on;
    camOn = on;
    updateMediaButton(document.getElementById("btn-cam"), on);
    if (on) localEl.classList.remove("hidden");
    else localEl.classList.add("hidden");
    return;
  }

  if (!agoraJoined || !agoraClient) return;
  var btn = document.getElementById("btn-cam");
  var localEl = document.getElementById("video-local");
  if (on === camOn && !screenOn) return;
  if (on) {
    if (screenOn) await stopScreenShare();
    if (!localTracks.video) {
      localTracks.video = await AgoraRTC.createCameraVideoTrack();
    }
    await agoraClient.publish([localTracks.video]);
    localTracks.video.play(localEl);
    localEl.classList.remove("hidden");
    hideVideoPlaceholder();
    camOn = true;
    updateMediaButton(btn, true);
    if (isTeacherRole()) {
      addChatMessage("", "Camera is live — students can see you.", true);
    }
  } else {
    if (localTracks.video) {
      await agoraClient.unpublish([localTracks.video]);
      localTracks.video.stop();
      localTracks.video.close();
      localTracks.video = null;
    }
    localEl.classList.add("hidden");
    camOn = false;
    updateMediaButton(btn, false);
    if (!screenOn) {
      showVideoPlaceholder(isTeacherRole() ? "Camera off." : "Waiting for the teacher…");
    }
  }
}

async function toggleMic() {
  if (!isTeacherRole() && !studentMicAllowed) {
    addChatMessage("", "Raise your hand and wait for the teacher to allow your mic.", true);
    return;
  }
  if (mediaMode === "local" && localPreviewStream) {
    try { await setMic(!micOn); } catch (e) { addChatMessage("", "Microphone: " + e.message, true); }
    return;
  }
  if (!agoraJoined || !agoraClient) {
    addChatMessage("", "Connecting live video… try again in a moment.", true);
    return;
  }
  try {
    await setMic(!micOn);
  } catch (e) {
    addChatMessage("", "Microphone: " + e.message, true);
  }
}

async function toggleCam() {
  if (mediaMode === "local" && localPreviewStream) {
    try { await setCam(!camOn); } catch (e) { addChatMessage("", "Camera: " + e.message, true); }
    return;
  }
  if (!agoraJoined || !agoraClient) {
    addChatMessage("", "Connecting live video… try again in a moment.", true);
    return;
  }
  try {
    await setCam(!camOn);
  } catch (e) {
    addChatMessage("", "Camera: " + e.message, true);
  }
}

async function createScreenTrack() {
  var result = await AgoraRTC.createScreenVideoTrack(
    { encoderConfig: "1080p_1", optimizationMode: "detail" },
    "auto"
  );
  if (Array.isArray(result)) {
    return { video: result[0], audio: result[1] || null };
  }
  return { video: result, audio: null };
}

async function stopScreenShare() {
  var btn = document.getElementById("btn-share");
  var localEl = document.getElementById("video-local");
  if (localTracks.screenAudio && agoraClient) {
    try {
      await agoraClient.unpublish([localTracks.screenAudio]);
      localTracks.screenAudio.stop();
      localTracks.screenAudio.close();
    } catch (e) { /* ignore */ }
    localTracks.screenAudio = null;
  }
  if (localTracks.screen) {
    await agoraClient.unpublish([localTracks.screen]);
    localTracks.screen.stop();
    localTracks.screen.close();
    localTracks.screen = null;
  }
  screenOn = false;
  updateMediaButton(btn, false);
  localEl.classList.add("hidden");
}

async function toggleScreenShare() {
  if (!isTeacherRole()) return;

  if (mediaMode === "local") {
    var localEl = document.getElementById("video-local");
    try {
      if (!screenOn) {
        localScreenStream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: false });
        var vid = document.createElement("video");
        vid.srcObject = localScreenStream;
        vid.autoplay = true;
        vid.muted = true;
        vid.playsInline = true;
        localEl.innerHTML = "";
        localEl.appendChild(vid);
        localEl.classList.remove("hidden");
        screenOn = true;
        updateMediaButton(document.getElementById("btn-share"), true);
        addChatMessage("", "Screen preview on your device only — students cannot see it until live video connects. Open Board for teaching meanwhile.", true);
        localScreenStream.getVideoTracks()[0].onended = function () {
          screenOn = false;
          updateMediaButton(document.getElementById("btn-share"), false);
          restoreLocalCameraPreview();
        };
      } else {
        if (localScreenStream) {
          localScreenStream.getTracks().forEach(function (t) { t.stop(); });
          localScreenStream = null;
        }
        screenOn = false;
        updateMediaButton(document.getElementById("btn-share"), false);
        restoreLocalCameraPreview();
      }
    } catch (e) {
      addChatMessage("", "Screen share: " + e.message, true);
    }
    return;
  }

  if (!agoraJoined || !agoraClient) {
    addChatMessage("", "Connecting live video… try again in a moment.", true);
    return;
  }
  var btn = document.getElementById("btn-share");
  var localEl = document.getElementById("video-local");
  try {
    if (!screenOn) {
      var tracks = await createScreenTrack();
      localTracks.screen = tracks.video;
      localTracks.screenAudio = tracks.audio;
      var publishList = [tracks.video];
      if (tracks.audio) publishList.push(tracks.audio);
      await agoraClient.publish(publishList);
      if (camOn && localTracks.video) {
        await agoraClient.unpublish([localTracks.video]);
      }
      localTracks.screen.play(localEl);
      localEl.classList.remove("hidden");
      hideVideoPlaceholder();
      screenOn = true;
      updateMediaButton(btn, true);
      addChatMessage("", "You are sharing your screen — students can see it.", true);
      localTracks.screen.on("track-ended", function () {
        stopScreenShare().then(function () {
          if (camOn) setCam(true);
        });
      });
    } else {
      await stopScreenShare();
      if (camOn) await setCam(true);
      addChatMessage("", "Screen share stopped.", true);
    }
  } catch (e) {
    addChatMessage("", "Screen share: " + e.message, true);
  }
}

async function leaveClassroom() {
  if (liveSaveActive) {
    await stopLiveSaveAndStore(false);
  }
  try {
    if (liveSession && liveSession.class_id && liveSession.role === "student") {
      await api("/api/v1/live-classes/" + liveSession.class_id + "/leave", { method: "POST" });
    }
  } catch (e) { /* ignore */ }

  if (localPreviewStream) {
    localPreviewStream.getTracks().forEach(function (t) { t.stop(); });
  }
  if (localScreenStream) {
    localScreenStream.getTracks().forEach(function (t) { t.stop(); });
  }
  stopAgoraRetry();
  stopMicMonitor();
  stopSelfHear();
  if (liveSocket) {
    try { liveSocket.close(); } catch (e) { /* ignore */ }
  }
  if (agoraClient && agoraJoined) {
    try { await agoraClient.leave(); } catch (e) { /* ignore */ }
  }
  localStorage.removeItem("live_session");
  if (liveSession && (liveSession.role === "teacher" || liveSession.role === "admin")) {
    window.location.href = localStorage.getItem("sia_teacher_token") ? "teacher.html" : "admin.html";
  } else {
    window.location.href = "app.html";
  }
}

function loadAgoraScript(cb) {
  if (typeof AgoraRTC !== "undefined") { cb(); return; }
  var s = document.createElement("script");
  s.src = "https://download.agora.io/sdk/release/AgoraRTC_N-4.20.2.js";
  s.onload = cb;
  s.onerror = function () { cb(); };
  document.head.appendChild(s);
}

window.onload = function () {
  if (!getAuthToken()) {
    window.location.href = "index.html";
    return;
  }
  liveSession = loadLiveSession();
  if (!liveSession || !liveSession.room_id) {
    window.location.href = "app.html";
    return;
  }

  document.getElementById("cr-title").textContent = liveSession.title || "Live Class";
  document.getElementById("cr-meta").textContent =
    (liveSession.subject || "Subject") + " · " + (liveSession.teacher_name || liveSession.role || "Class");

  initWhiteboard();
  setVideoControlsEnabled(false);
  if (isTeacherRole()) {
    showHostTools(true);
    var rhPanel = document.getElementById("raise-hand-panel");
    if (rhPanel) rhPanel.classList.remove("hidden");
    var audBadge = document.getElementById("audience-badge");
    if (audBadge) audBadge.classList.remove("hidden");
  } else {
    showStudentTools(true);
  }
  connectChat();
  scheduleClassAutoEnd();
  if (isTeacherRole()) {
    var startClassId = liveSession.class_id || liveSession.classId;
    if (startClassId) {
      api("/api/v1/live-classes/" + startClassId + "/start", { method: "POST" })
        .then(function () {
          addChatMessage("", "Students can now see this class on Live Class and tap Join.", true);
        })
        .catch(function () { /* already live or network */ });
    }
  }
  loadAgoraScript(function () {
    if (isTeacherRole()) {
      startLocalPreviewOnly().catch(function () {});
    }
    tryStartAgora();
  });
};
