var liveSession = null;
var liveSocket = null;
var agoraClient = null;
var localTracks = { audio: null, video: null };
var micOn = false;
var camOn = false;
var API_WS = "wss://scholaxia1.onrender.com";

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
  return localStorage.getItem("sia_token") || localStorage.getItem("sia_admin_token") || "";
}

function getAuthRole() {
  return localStorage.getItem("sia_admin_token")
    ? (localStorage.getItem("sia_admin_role") || "admin")
    : (localStorage.getItem("sia_role") || "student");
}

function loadLiveSession() {
  try {
    return JSON.parse(localStorage.getItem("live_session") || "null");
  } catch (e) {
    return null;
  }
}

function setStatus(text) {
  var el = document.getElementById("cr-status");
  if (el) el.textContent = text;
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

function connectChat() {
  if (!liveSession || !liveSession.room_id) return;
  var payload = parseJwt(getAuthToken());
  var userId = payload.sub || liveSession.user_id || "user";
  var role = liveSession.role === "teacher" || liveSession.role === "admin" ? "teacher" : "student";
  var url = API_WS + "/ws/live-class/" + encodeURIComponent(liveSession.room_id)
    + "?user_id=" + encodeURIComponent(userId) + "&role=" + encodeURIComponent(role);

  liveSocket = new WebSocket(url);
  liveSocket.onopen = function () {
    setStatus("Connected");
    addChatMessage("", "You joined the class.", true);
  };
  liveSocket.onmessage = function (ev) {
    try {
      var msg = JSON.parse(ev.data);
      if (msg.event === "chat") {
        var who = msg.role === "teacher" ? "Teacher" : "Student";
        addChatMessage(who, msg.text || "");
      } else if (msg.event === "user_joined") {
        addChatMessage("", "Someone joined the class.", true);
      } else if (msg.event === "user_left") {
        addChatMessage("", "Someone left the class.", true);
      } else if (msg.event === "raise_hand") {
        addChatMessage("", "A student raised their hand.", true);
      }
    } catch (e) { /* ignore */ }
  };
  liveSocket.onclose = function () {
    setStatus("Disconnected");
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
  if (liveSocket && liveSocket.readyState === WebSocket.OPEN) {
    liveSocket.send(JSON.stringify({ event: "raise_hand" }));
    addChatMessage("", "You raised your hand.", true);
  }
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

async function tryStartAgora() {
  if (typeof AgoraRTC === "undefined") {
    showVideoPlaceholder("Live video is not loaded. You can still use class chat.");
    return;
  }
  var token = liveSession.agora_token || liveSession.token || "";
  if (!liveSession.app_id || token.indexOf("AGORA_CERT_NOT_SET") >= 0 || token.indexOf("TOKEN_ERROR") >= 0) {
    showVideoPlaceholder("You are in the class. Video will work when Agora is fully configured — use chat for now.");
    return;
  }

  try {
    agoraClient = AgoraRTC.createClient({ mode: "rtc", codec: "vp8" });
    agoraClient.on("user-published", async function (user, mediaType) {
      await agoraClient.subscribe(user, mediaType);
      if (mediaType === "video") {
        hideVideoPlaceholder();
        var wrap = document.getElementById("video-remote");
        wrap.innerHTML = "";
        var box = document.createElement("div");
        box.className = "remote-user";
        var vid = document.createElement("div");
        user.videoTrack.play(vid);
        box.appendChild(vid);
        wrap.appendChild(box);
      }
      if (mediaType === "audio") {
        user.audioTrack.play();
      }
    });
    agoraClient.on("user-unpublished", function () {
      document.getElementById("video-remote").innerHTML = "";
      showVideoPlaceholder("Waiting for the teacher to start video…");
    });

    await agoraClient.join(
      liveSession.app_id,
      liveSession.channel_id || liveSession.room_id,
      token,
      liveSession.uid
    );
    setStatus("In live room");
    showVideoPlaceholder("Waiting for the teacher to start video…");
  } catch (err) {
    showVideoPlaceholder("Could not start video: " + (err.message || "unknown error") + ". Chat still works.");
  }
}

async function toggleMic() {
  if (!agoraClient) {
    addChatMessage("", "Turn on video connection first, or use chat.", true);
    return;
  }
  var btn = document.getElementById("btn-mic");
  try {
    if (!micOn) {
      if (!localTracks.audio) {
        localTracks.audio = await AgoraRTC.createMicrophoneAudioTrack();
      }
      await agoraClient.publish([localTracks.audio]);
      micOn = true;
      if (btn) btn.classList.remove("off");
    } else {
      if (localTracks.audio) {
        await agoraClient.unpublish([localTracks.audio]);
        localTracks.audio.stop();
        localTracks.audio.close();
        localTracks.audio = null;
      }
      micOn = false;
      if (btn) btn.classList.add("off");
    }
  } catch (e) {
    addChatMessage("", "Microphone: " + e.message, true);
  }
}

async function toggleCam() {
  if (!agoraClient) {
    addChatMessage("", "Turn on video connection first, or use chat.", true);
    return;
  }
  var btn = document.getElementById("btn-cam");
  var localEl = document.getElementById("video-local");
  try {
    if (!camOn) {
      if (!localTracks.video) {
        localTracks.video = await AgoraRTC.createCameraVideoTrack();
      }
      await agoraClient.publish([localTracks.video]);
      localTracks.video.play(localEl);
      localEl.classList.remove("hidden");
      hideVideoPlaceholder();
      camOn = true;
      if (btn) btn.classList.remove("off");
    } else {
      if (localTracks.video) {
        await agoraClient.unpublish([localTracks.video]);
        localTracks.video.stop();
        localTracks.video.close();
        localTracks.video = null;
      }
      localEl.classList.add("hidden");
      camOn = false;
      if (btn) btn.classList.add("off");
    }
  } catch (e) {
    addChatMessage("", "Camera: " + e.message, true);
  }
}

async function leaveClassroom() {
  try {
    if (liveSession && liveSession.class_id && liveSession.role === "student") {
      await api("/api/v1/live-classes/" + liveSession.class_id + "/leave", { method: "POST" });
    }
  } catch (e) { /* ignore */ }

  if (liveSocket) {
    try { liveSocket.close(); } catch (e) { /* ignore */ }
  }
  if (agoraClient) {
    try { await agoraClient.leave(); } catch (e) { /* ignore */ }
  }
  localStorage.removeItem("live_session");
  window.location.href = liveSession && liveSession.role !== "student" ? "admin.html" : "app.html";
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

  connectChat();
  loadAgoraScript(tryStartAgora);
};
