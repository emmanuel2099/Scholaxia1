/**
 * WhatsApp-style voice note recorder — tap mic, speak, tap again to stop, then send.
 */
function createVoiceRecorder(opts) {
  var btn = document.getElementById(opts.buttonId);
  var statusEl = document.getElementById(opts.statusId);
  var previewEl = document.getElementById(opts.previewId);
  var playbackEl = document.getElementById(opts.playbackId);
  var deleteBtn = opts.deleteButtonId ? document.getElementById(opts.deleteButtonId) : null;

  var state = {
    recording: false,
    mediaRecorder: null,
    chunks: [],
    stream: null,
    blob: null,
    previewUrl: null,
    timer: null,
    seconds: 0,
  };

  function pickMimeType() {
    var types = ["audio/webm;codecs=opus", "audio/webm", "audio/ogg;codecs=opus", "audio/mp4"];
    for (var i = 0; i < types.length; i++) {
      if (typeof MediaRecorder !== "undefined" && MediaRecorder.isTypeSupported(types[i])) {
        return types[i];
      }
    }
    return "";
  }

  function formatTime(sec) {
    var m = Math.floor(sec / 60);
    var s = sec % 60;
    return m + ":" + (s < 10 ? "0" : "") + s;
  }

  function revokePreview() {
    if (state.previewUrl) {
      URL.revokeObjectURL(state.previewUrl);
      state.previewUrl = null;
    }
  }

  function updateUI() {
    if (!btn) return;
    if (state.recording) {
      btn.classList.add("recording");
      btn.textContent = "⏹ Stop recording";
      if (statusEl) {
        statusEl.classList.remove("hidden");
        statusEl.textContent = "🔴 Recording " + formatTime(state.seconds) + " — tap stop when done";
      }
    } else if (state.blob) {
      btn.classList.remove("recording");
      btn.textContent = "🎤 Record again";
      if (statusEl) {
        statusEl.classList.remove("hidden");
        statusEl.textContent = "Voice note ready — tap Post / Send";
      }
    } else {
      btn.classList.remove("recording");
      btn.textContent = opts.idleLabel || "🎤 Tap to record voice";
      if (statusEl) statusEl.classList.add("hidden");
    }
    if (previewEl) previewEl.classList.toggle("hidden", !state.blob);
  }

  function showPreview() {
    if (!state.blob || !playbackEl) return;
    revokePreview();
    state.previewUrl = URL.createObjectURL(state.blob);
    playbackEl.src = state.previewUrl;
    updateUI();
  }

  function stopTracks() {
    if (state.stream) {
      state.stream.getTracks().forEach(function (t) { t.stop(); });
      state.stream = null;
    }
  }

  async function start() {
    if (typeof MediaRecorder === "undefined") {
      throw new Error("Voice recording is not supported in this browser.");
    }
    cancel();
    state.stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation: true, noiseSuppression: true },
    });
    var mime = pickMimeType();
    var options = mime ? { mimeType: mime } : {};
    state.mediaRecorder = new MediaRecorder(state.stream, options);
    state.chunks = [];
    state.mediaRecorder.ondataavailable = function (e) {
      if (e.data && e.data.size > 0) state.chunks.push(e.data);
    };
    state.mediaRecorder.onstop = function () {
      var type = (state.mediaRecorder && state.mediaRecorder.mimeType) || mime || "audio/webm";
      state.blob = new Blob(state.chunks, { type: type.split(";")[0] });
      stopTracks();
      showPreview();
      if (opts.onReady) opts.onReady();
    };
    state.mediaRecorder.start(250);
    state.recording = true;
    state.seconds = 0;
    updateUI();
    state.timer = setInterval(function () {
      state.seconds++;
      updateUI();
    }, 1000);
  }

  function stop() {
    if (!state.recording || !state.mediaRecorder) return;
    clearInterval(state.timer);
    state.timer = null;
    state.recording = false;
    try {
      state.mediaRecorder.stop();
    } catch (e) { /* ignore */ }
    updateUI();
  }

  function cancel() {
    if (state.recording) stop();
    clearInterval(state.timer);
    state.timer = null;
    state.recording = false;
    state.chunks = [];
    state.blob = null;
    revokePreview();
    if (playbackEl) playbackEl.removeAttribute("src");
    stopTracks();
    state.mediaRecorder = null;
    updateUI();
  }

  function getFile() {
    if (!state.blob) return null;
    var ext = "webm";
    if (state.blob.type.indexOf("ogg") >= 0) ext = "ogg";
    else if (state.blob.type.indexOf("mp4") >= 0) ext = "m4a";
    return new File([state.blob], "voice-note." + ext, { type: state.blob.type || "audio/webm" });
  }

  function hasRecording() {
    return !!state.blob;
  }

  function isRecording() {
    return state.recording;
  }

  if (btn) {
    btn.addEventListener("click", function () {
      if (state.recording) {
        stop();
        return;
      }
      start().catch(function (e) {
        cancel();
        if (opts.onError) opts.onError(e);
        else alert("Microphone: " + (e.message || "allow mic in Windows Settings"));
      });
    });
  }

  if (deleteBtn) {
    deleteBtn.addEventListener("click", function () {
      cancel();
      if (opts.onCancel) opts.onCancel();
    });
  }

  return {
    start: start,
    stop: stop,
    cancel: cancel,
    getFile: getFile,
    hasRecording: hasRecording,
    isRecording: isRecording,
  };
}
