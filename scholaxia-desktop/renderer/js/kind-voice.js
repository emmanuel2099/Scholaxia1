/** Kid / Kind voice — reads questions & Sia replies aloud (matches mobile SiaVoiceService). */

var kindVoiceEnabled = true;
var kindVoiceAudio = null;
var kindVoiceObjectUrl = null;

function kindVoiceClean(text) {
  return String(text || "")
    .replace(/```[\s\S]*?```/g, " ")
    .replace(/`([^`]+)`/g, "$1")
    .replace(/\*\*([^*]+)\*\*/g, "$1")
    .replace(/\*([^*]+)\*/g, "$1")
    .replace(/^#+\s*/gm, "")
    .replace(/\s+/g, " ")
    .trim()
    .slice(0, 1400);
}

function kindVoiceRevokeUrl() {
  if (kindVoiceObjectUrl) {
    try { URL.revokeObjectURL(kindVoiceObjectUrl); } catch (e) { /* ignore */ }
    kindVoiceObjectUrl = null;
  }
}

function kindStopVoice() {
  if (kindVoiceAudio) {
    try {
      kindVoiceAudio.pause();
      kindVoiceAudio.currentTime = 0;
    } catch (e) { /* ignore */ }
    kindVoiceAudio = null;
  }
  kindVoiceRevokeUrl();
  if (typeof window !== "undefined" && window.speechSynthesis) {
    try { window.speechSynthesis.cancel(); } catch (e) { /* ignore */ }
  }
}

function kindSpeakBrowser(text) {
  if (!window.speechSynthesis) return false;
  try {
    window.speechSynthesis.cancel();
    var u = new SpeechSynthesisUtterance(text);
    u.rate = 0.92;
    u.pitch = 1.05;
    u.lang = "en-US";
    var voices = window.speechSynthesis.getVoices();
    var pick = voices.find(function (v) {
      var n = (v.name || "").toLowerCase();
      return n.indexOf("zira") >= 0 || n.indexOf("samantha") >= 0 || n.indexOf("jenny") >= 0 || n.indexOf("female") >= 0;
    });
    if (pick) u.voice = pick;
    window.speechSynthesis.speak(u);
    return true;
  } catch (e) {
    return false;
  }
}

async function kindSpeak(text, language) {
  if (!kindVoiceEnabled) return;
  var cleaned = kindVoiceClean(text);
  if (!cleaned) return;
  kindStopVoice();

  var base = typeof API_BASE !== "undefined" ? API_BASE : "";
  var token = typeof getToken === "function" ? getToken() : "";
  if (base && token) {
    try {
      var res = await fetch(base + "/api/v1/sia/speak", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: "Bearer " + token,
        },
        body: JSON.stringify({ text: cleaned, language: language || "english" }),
      });
      if (res.ok) {
        var blob = await res.blob();
        if (blob && blob.size > 0) {
          kindVoiceRevokeUrl();
          kindVoiceObjectUrl = URL.createObjectURL(blob);
          kindVoiceAudio = new Audio(kindVoiceObjectUrl);
          kindVoiceAudio.onended = function () { kindVoiceRevokeUrl(); };
          await kindVoiceAudio.play();
          return;
        }
      }
    } catch (e) {
      /* fall through to browser TTS */
    }
  }
  kindSpeakBrowser(cleaned);
}

function kindSpeakQuestion(q) {
  if (!q) return;
  var text = (q.speak_word && String(q.speak_word).trim()) || q.prompt || "";
  kindSpeak(text);
}

function kindToggleVoice() {
  kindVoiceEnabled = !kindVoiceEnabled;
  if (!kindVoiceEnabled) kindStopVoice();
  document.querySelectorAll(".kind-voice-toggle").forEach(function (btn) {
    btn.textContent = kindVoiceEnabled ? "🔊 Sound on" : "🔇 Sound off";
    btn.setAttribute("aria-pressed", kindVoiceEnabled ? "true" : "false");
  });
}

if (typeof window !== "undefined") {
  window.kindSpeak = kindSpeak;
  window.kindSpeakQuestion = kindSpeakQuestion;
  window.kindStopVoice = kindStopVoice;
  window.kindToggleVoice = kindToggleVoice;
  if (window.speechSynthesis) {
    window.speechSynthesis.onvoiceschanged = function () { /* preload voices */ };
  }
}
