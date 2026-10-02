/** Sia voice — reads the AI Teacher's replies aloud. */

var siaVoiceEnabled = false; // no auto-read — tap 🔊 on a reply (or "Voice on") to hear it
var siaVoiceAudio = null;
var siaVoiceObjectUrl = null;

function siaVoiceClean(text) {
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

function siaVoiceRevokeUrl() {
  if (siaVoiceObjectUrl) {
    try { URL.revokeObjectURL(siaVoiceObjectUrl); } catch (e) { /* ignore */ }
    siaVoiceObjectUrl = null;
  }
}

function siaStopVoice() {
  if (siaVoiceAudio) {
    try {
      siaVoiceAudio.pause();
      siaVoiceAudio.currentTime = 0;
    } catch (e) { /* ignore */ }
    siaVoiceAudio = null;
  }
  siaVoiceRevokeUrl();
  if (typeof window !== "undefined" && window.speechSynthesis) {
    try { window.speechSynthesis.cancel(); } catch (e) { /* ignore */ }
  }
}

function siaSpeakBrowser(text) {
  if (!window.speechSynthesis) return false;
  try {
    window.speechSynthesis.cancel();
    var u = new SpeechSynthesisUtterance(text);
    u.rate = 0.95;
    u.pitch = 1.02;
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

async function siaSpeak(text) {
  if (!siaVoiceEnabled) return;
  var cleaned = siaVoiceClean(text);
  if (!cleaned) return;
  siaStopVoice();

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
        body: JSON.stringify({ text: cleaned, language: "english" }),
      });
      if (res.ok) {
        var blob = await res.blob();
        if (blob && blob.size > 0) {
          siaVoiceRevokeUrl();
          siaVoiceObjectUrl = URL.createObjectURL(blob);
          siaVoiceAudio = new Audio(siaVoiceObjectUrl);
          siaVoiceAudio.onended = function () { siaVoiceRevokeUrl(); };
          await siaVoiceAudio.play();
          return;
        }
      }
    } catch (e) {
      /* fall through to browser TTS */
    }
  }
  siaSpeakBrowser(cleaned);
}

function siaToggleVoice() {
  siaVoiceEnabled = !siaVoiceEnabled;
  try { localStorage.setItem("sia_voice_on", siaVoiceEnabled ? "1" : "0"); } catch (e) { /* ignore */ }
  if (!siaVoiceEnabled) siaStopVoice();
  document.querySelectorAll(".sia-voice-toggle").forEach(function (btn) {
    btn.textContent = siaVoiceEnabled ? "🔊 Voice on" : "🔇 Voice off";
    btn.setAttribute("aria-pressed", siaVoiceEnabled ? "true" : "false");
  });
}

/* Init saved preference */
try {
  if (localStorage.getItem("sia_voice_on") === "1") siaVoiceEnabled = true;
} catch (e) { /* ignore */ }

if (typeof window !== "undefined") {
  window.siaSpeak = siaSpeak;
  window.siaStopVoice = siaStopVoice;
  window.siaToggleVoice = siaToggleVoice;
  if (window.speechSynthesis) {
    window.speechSynthesis.onvoiceschanged = function () { /* preload voices */ };
  }
}
