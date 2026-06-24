/**
 * LiveKit video/audio/screen-share for Scholaxia live classroom.
 * Loaded before classroom.js — uses globals: liveSession, api, isTeacherRole, etc.
 */
(function () {
  var liveRoom = null;
  var liveVideoJoined = false;
  var liveKitConnecting = false;
  var liveKitRetryTimer = null;
  var tokenRefreshTimer = null;
  var mediaMode = "none"; // none | livekit | local
  var micOn = false;
  var camOn = false;
  var screenOn = false;
  var JOIN_TIMEOUT_MS = 45000;

  function lk() {
    return window.LivekitClient || null;
  }

  function LK() {
    var c = lk();
    if (!c) throw new Error("LiveKit SDK not loaded");
    return c;
  }

  function isJoined() {
    return liveVideoJoined;
  }

  function getMediaMode() {
    return mediaMode;
  }

  function normalizeSession(sess) {
    if (!sess) return sess;
    if (!sess.livekit_token) {
      sess.livekit_token = sess.agora_token || sess.token || "";
    }
    if (!sess.livekit_url) sess.livekit_url = "";
    if (!sess.identity) sess.identity = sess.user_id || "";
    return sess;
  }

  function hasValidLiveKitToken(token, url) {
    if (!token || !url) return false;
    if (token.indexOf("LIVEKIT_NOT_CONFIGURED") >= 0) return false;
    if (token.indexOf("TOKEN_ERROR") >= 0) return false;
    if (token.indexOf("AGORA_CERT_NOT_SET") >= 0) return false;
    return true;
  }

  function liveKitMissingMessage() {
    return (
      "Live video is not configured on the server. " +
      "Set LIVEKIT_URL, LIVEKIT_API_KEY, and LIVEKIT_API_SECRET on Render. Chat and board still work."
    );
  }

  function showLiveKitSetupBanner(message) {
    var bar = document.getElementById("livekit-setup-banner");
    var msg = document.getElementById("livekit-setup-msg");
    if (msg && message) msg.textContent = message;
    if (bar) bar.classList.remove("hidden");
  }

  function hideLiveKitSetupBanner() {
    var bar = document.getElementById("livekit-setup-banner");
    if (bar) bar.classList.add("hidden");
  }

  async function checkLiveKitServerConfig() {
    try {
      var status = await api("/api/v1/live-classes/livekit/status");
      if (status && !status.configured) {
        showLiveKitSetupBanner(status.message || liveKitMissingMessage());
        return false;
      }
      if (status && status.livekit_url && liveSession && !liveSession.livekit_url) {
        liveSession.livekit_url = status.livekit_url;
        if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
        else localStorage.setItem("live_session", JSON.stringify(liveSession));
      }
      return true;
    } catch (e) {
      return true;
    }
  }

  function withTimeout(promise, ms, message) {
    return Promise.race([
      promise,
      new Promise(function (_, reject) {
        setTimeout(function () { reject(new Error(message)); }, ms);
      }),
    ]);
  }

  async function refreshLiveKitToken() {
    liveSession = window.liveSession || liveSession;
    if (!liveSession) return false;
    var classId = liveSession.class_id || liveSession.classId;
    if (!classId) return false;
    try {
      var data = await api("/api/v1/live-classes/" + classId + "/token");
      liveSession.livekit_token = data.livekit_token || data.token;
      liveSession.livekit_url = data.livekit_url || liveSession.livekit_url;
      liveSession.identity = data.identity || liveSession.identity;
      liveSession.channel_id = data.channel_id || liveSession.channel_id;
      if (data.end_time) liveSession.end_time = data.end_time;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
      else localStorage.setItem("live_session", JSON.stringify(liveSession));
      window.liveSession = liveSession;
      return hasValidLiveKitToken(liveSession.livekit_token, liveSession.livekit_url);
    } catch (e) {
      return false;
    }
  }

  function stopLiveKitRetry() {
    if (liveKitRetryTimer) {
      clearInterval(liveKitRetryTimer);
      liveKitRetryTimer = null;
    }
  }

  function scheduleLiveKitRetry() {
    if (liveVideoJoined || liveKitRetryTimer) return;
    liveKitRetryTimer = setInterval(function () {
      if (liveVideoJoined || liveKitConnecting) return;
      tryConnectLiveVideo(true);
    }, 12000);
  }

  function scheduleTokenRefresh() {
    if (tokenRefreshTimer) clearInterval(tokenRefreshTimer);
    tokenRefreshTimer = setInterval(function () {
      if (!liveVideoJoined || !liveRoom) return;
      refreshLiveKitToken().then(function (ok) {
        if (!ok || !liveSession.livekit_token) return;
        try {
          if (liveRoom.engine && liveRoom.engine.client && liveRoom.engine.client.refreshToken) {
            liveRoom.engine.client.refreshToken(liveSession.livekit_token);
          }
        } catch (e) { /* reconnect on next interval if needed */ }
      });
    }, 45 * 60 * 1000);
  }

  function isScreenPublication(pub) {
    if (!pub) return false;
    var c = lk();
    if (!c) return false;
    return pub.source === c.Track.Source.ScreenShare || pub.source === "screen_share";
  }

  function attachRemoteTrack(track, publication) {
    var c = lk();
    if (!track || !c) return;
    if (track.kind === c.Track.Kind.Video || track.kind === "video") {
      var isScreen = isScreenPublication(publication);
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      var wrap = document.getElementById("video-remote");
      if (!wrap) return;
      wrap.innerHTML = "";
      wrap.classList.toggle("screen-active", !!isScreen);
      var box = document.createElement("div");
      box.className = "remote-user" + (isScreen ? " screen-share" : "");
      var el = track.attach();
      el.style.width = "100%";
      el.style.height = "100%";
      box.appendChild(el);
      wrap.appendChild(box);
      if (!isTeacherRole() && typeof showBoardForStudent === "function") {
        showBoardForStudent(false);
      }
      if (!isTeacherRole() && typeof maybeShowSaveClassHint === "function") {
        maybeShowSaveClassHint();
      }
    }
    if (track.kind === c.Track.Kind.Audio || track.kind === "audio") {
      track.attach();
      if (!isTeacherRole()) {
        if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
        if (typeof setStatus === "function") setStatus("Connected — you can hear the teacher");
        if (typeof maybeShowSaveClassHint === "function") maybeShowSaveClassHint();
      }
    }
  }

  function attachExistingRemoteTracks() {
    if (!liveRoom) return;
    liveRoom.remoteParticipants.forEach(function (participant) {
      participant.trackPublications.forEach(function (pub) {
        if (pub.track) attachRemoteTrack(pub.track, pub);
      });
    });
  }

  function attachLocalCameraPreview() {
    if (!liveRoom) return;
    var c = lk();
    var localEl = document.getElementById("video-local");
    if (!localEl || !c) return;
    liveRoom.localParticipant.videoTrackPublications.forEach(function (pub) {
      if (pub.source === c.Track.Source.Camera && pub.track) {
        localEl.innerHTML = "";
        var el = pub.track.attach();
        el.style.width = "100%";
        el.style.height = "100%";
        localEl.appendChild(el);
        localEl.classList.remove("hidden");
      }
    });
  }

  function attachLocalScreenPreview() {
    if (!liveRoom) return;
    var c = lk();
    var localEl = document.getElementById("video-local");
    if (!localEl || !c) return;
    liveRoom.localParticipant.videoTrackPublications.forEach(function (pub) {
      if (isScreenPublication(pub) && pub.track) {
        localEl.innerHTML = "";
        var el = pub.track.attach();
        el.style.width = "100%";
        el.style.height = "100%";
        localEl.appendChild(el);
        localEl.classList.remove("hidden");
        if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      }
    });
  }

  function getLocalMicTrack() {
    if (!liveRoom) return null;
    var c = lk();
    if (!c) return null;
    var pub = liveRoom.localParticipant.getTrackPublication(c.Track.Source.Microphone);
    return pub && pub.track ? pub.track : null;
  }

  function wireRoomEvents(room) {
    var c = LK();
    room.on(c.RoomEvent.TrackSubscribed, function (track, publication) {
      attachRemoteTrack(track, publication);
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.TrackUnsubscribed, function (track, publication) {
      if (track.kind === c.Track.Kind.Video || track.kind === "video") {
        if (isTeacherRole() && (camOn || screenOn)) return;
        var wrap = document.getElementById("video-remote");
        if (wrap) wrap.innerHTML = "";
        if (typeof showVideoPlaceholder === "function") {
          showVideoPlaceholder(
            isTeacherRole()
              ? (screenOn ? "Screen share active." : "Your camera is off.")
              : "Waiting for the teacher…"
          );
        }
      }
    });
    room.on(c.RoomEvent.ParticipantConnected, function () {
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.ParticipantDisconnected, function () {
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.LocalTrackUnpublished, function (publication) {
      if (isScreenPublication(publication)) {
        screenOn = false;
        var btn = document.getElementById("btn-share");
        if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
        if (camOn) setCam(true);
      }
    });
    room.on(c.RoomEvent.Disconnected, function () {
      liveVideoJoined = false;
    });
    room.on(c.RoomEvent.Connected, function () {
      scheduleTokenRefresh();
    });
  }

  async function reconnectWithFreshToken() {
    if (!liveRoom) return;
    var wasCam = camOn;
    var wasMic = micOn;
    var wasScreen = screenOn;
    try {
      await liveRoom.disconnect();
    } catch (e) { /* ignore */ }
    liveRoom = null;
    liveVideoJoined = false;
    await tryConnectLiveVideo(true);
    if (wasScreen) await setScreenShare(true);
    else {
      if (wasCam) await setCam(true);
      if (wasMic) await setMic(true);
    }
  }

  async function transitionHostToLiveBroadcast() {
    var wantCam = camOn || !!window.localPreviewStream;
    var wantMic = micOn || !!window.localPreviewStream;
    if (wantCam) await setCam(true);
    if (wantMic) await setMic(true);
    if (window.localPreviewStream) {
      window.localPreviewStream.getTracks().forEach(function (t) { t.stop(); });
      window.localPreviewStream = null;
      if (typeof stopSelfHear === "function") stopSelfHear();
      if (typeof stopMicMonitor === "function") stopMicMonitor();
    }
  }

  function enterChatOnlyMode(message) {
    liveVideoJoined = false;
    liveRoom = null;
    if (!camOn && !window.localPreviewStream && typeof showVideoPlaceholder === "function") {
      showVideoPlaceholder(message);
    }
    showLiveKitSetupBanner(message || liveKitMissingMessage());
    if (isTeacherRole()) {
      if (typeof showHostTools === "function") showHostTools(true);
      if (window.board) {
        window.board.canDraw = true;
        var ov = document.getElementById("board-overlay");
        if (ov) ov.classList.remove("view-only");
      }
      mediaMode = "local";
      if (typeof startLocalPreviewOnly === "function") {
        startLocalPreviewOnly().catch(function () {});
      }
      scheduleLiveKitRetry();
    } else {
      if (typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(false);
      scheduleLiveKitRetry();
    }
  }

  async function tryConnectLiveVideo(isRetry) {
    if (liveKitConnecting || liveVideoJoined) return;
    if (!isRetry && typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(false);

    if (!lk()) {
      enterChatOnlyMode("Class is live. Video SDK did not load — use class chat and board.");
      return;
    }

    if (isTeacherRole() && !window.localPreviewStream && !isRetry) {
      if (typeof startLocalPreviewOnly === "function") {
        startLocalPreviewOnly().catch(function () {});
      }
    }

    liveKitConnecting = true;
    liveSession = window.liveSession || liveSession;
    liveSession = normalizeSession(liveSession || (typeof loadLiveSession === "function" ? loadLiveSession() : null));
    window.liveSession = liveSession;
    await refreshLiveKitToken();
    var token = liveSession.livekit_token || "";
    var url = liveSession.livekit_url || "";
    if (!hasValidLiveKitToken(token, url)) {
      liveKitConnecting = false;
      if (!isRetry) {
        var certMsg = token.indexOf("LIVEKIT_NOT_CONFIGURED") >= 0
          ? liveKitMissingMessage()
          : "Class is live — chat and board work. Could not get live video token.";
        enterChatOnlyMode(certMsg);
      }
      return;
    }

    if (!camOn && !window.localPreviewStream && typeof showVideoPlaceholder === "function") {
      showVideoPlaceholder("Joining video room…");
    }

    try {
      if (!liveRoom) {
        var c = LK();
        liveRoom = new c.Room({ adaptiveStream: true, dynacast: true });
        wireRoomEvents(liveRoom);
      }

      if (!liveVideoJoined) {
        await withTimeout(liveRoom.connect(url, token), JOIN_TIMEOUT_MS, "Video join timed out");
      }

      liveVideoJoined = true;
      mediaMode = "livekit";
      stopLiveKitRetry();
      hideLiveKitSetupBanner();
      attachExistingRemoteTracks();
      if (typeof updateAudienceStats === "function") updateAudienceStats();
      if (typeof setVideoControlsEnabled === "function") {
        setVideoControlsEnabled(isTeacherRole() || window.studentMicAllowed);
      }
      if (typeof setStatus === "function") setStatus("Connected — video + chat");

      if (isTeacherRole()) {
        if (typeof showHostTools === "function") showHostTools(true);
        if (window.board) {
          window.board.canDraw = true;
          var ov2 = document.getElementById("board-overlay");
          if (ov2) ov2.classList.remove("view-only");
        }
        await transitionHostToLiveBroadcast();
        if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
        if (typeof addChatMessage === "function") {
          addChatMessage("", "You are live — students can see and hear you now.", true);
        }
      } else if (!liveRoom.remoteParticipants.size) {
        if (typeof showVideoPlaceholder === "function") {
          showVideoPlaceholder("Waiting for the teacher to start video…");
        }
      }
    } catch (err) {
      liveVideoJoined = false;
      liveRoom = null;
      if (!isRetry) {
        enterChatOnlyMode(
          "Video could not connect (" + (err.message || "error") + "). Chat and board still work."
        );
      }
      scheduleLiveKitRetry();
    } finally {
      liveKitConnecting = false;
    }
  }

  async function setMic(on) {
    if (mediaMode === "local" && window.localPreviewStream) {
      var audioTrack = window.localPreviewStream.getAudioTracks()[0];
      if (!audioTrack) return;
      audioTrack.enabled = on;
      micOn = on;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-mic"), on);
      }
      if (on) {
        if (typeof startMicMonitor === "function") startMicMonitor(window.localPreviewStream);
        if (typeof startSelfHear === "function") startSelfHear(window.localPreviewStream);
      } else {
        if (typeof stopMicMonitor === "function") stopMicMonitor();
        if (typeof stopSelfHear === "function") stopSelfHear();
      }
      return;
    }

    if (!liveVideoJoined || !liveRoom) return;
    var btn = document.getElementById("btn-mic");
    if (on === micOn) return;
    await liveRoom.localParticipant.setMicrophoneEnabled(on);
    micOn = on;
    if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    if (on) {
      var track = getLocalMicTrack();
      if (track) {
        if (typeof startMicMonitor === "function") startMicMonitor(track);
        if (typeof startSelfHear === "function") startSelfHear(track);
      }
    } else {
      if (typeof stopMicMonitor === "function") stopMicMonitor();
      if (typeof stopSelfHear === "function") stopSelfHear();
    }
  }

  async function setCam(on) {
    if (mediaMode === "local" && window.localPreviewStream) {
      if (on && !liveVideoJoined) tryConnectLiveVideo(true);
      var videoTrack = window.localPreviewStream.getVideoTracks()[0];
      var localEl = document.getElementById("video-local");
      if (!videoTrack) return;
      videoTrack.enabled = on;
      camOn = on;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-cam"), on);
      }
      if (on && localEl) localEl.classList.remove("hidden");
      else if (localEl) localEl.classList.add("hidden");
      return;
    }

    if (!liveVideoJoined || !liveRoom) return;
    var btn = document.getElementById("btn-cam");
    var localEl = document.getElementById("video-local");
    if (on === camOn && !screenOn) return;
    if (on && screenOn) await setScreenShare(false);
    await liveRoom.localParticipant.setCameraEnabled(on);
    camOn = on;
    if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    if (on) {
      attachLocalCameraPreview();
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      if (isTeacherRole() && typeof addChatMessage === "function") {
        addChatMessage("", "Camera is live — students can see you.", true);
      }
    } else {
      if (localEl) localEl.classList.add("hidden");
      if (!screenOn && typeof showVideoPlaceholder === "function") {
        showVideoPlaceholder(isTeacherRole() ? "Camera off." : "Waiting for the teacher…");
      }
    }
  }

  async function setScreenShare(on) {
    if (!liveVideoJoined || !liveRoom) return;
    var btn = document.getElementById("btn-share");
    if (on) {
      await liveRoom.localParticipant.setScreenShareEnabled(true);
      screenOn = true;
      if (camOn) await liveRoom.localParticipant.setCameraEnabled(false);
      attachLocalScreenPreview();
      if (typeof updateMediaButton === "function") updateMediaButton(btn, true);
      if (typeof addChatMessage === "function") {
        addChatMessage("", "You are sharing your screen — students can see it.", true);
      }
    } else {
      await liveRoom.localParticipant.setScreenShareEnabled(false);
      screenOn = false;
      if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
      var localEl = document.getElementById("video-local");
      if (localEl) localEl.classList.add("hidden");
    }
  }

  async function toggleMic() {
    if (!isTeacherRole() && !window.studentMicAllowed) {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Raise your hand and wait for the teacher to allow your mic.", true);
      }
      return;
    }
    if (mediaMode === "local" && window.localPreviewStream) {
      try { await setMic(!micOn); } catch (e) {
        if (typeof addChatMessage === "function") addChatMessage("", "Microphone: " + e.message, true);
      }
      return;
    }
    if (!liveVideoJoined || !liveRoom) {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Connecting live video… try again in a moment.", true);
      }
      return;
    }
    try {
      await setMic(!micOn);
    } catch (e) {
      if (typeof addChatMessage === "function") addChatMessage("", "Microphone: " + e.message, true);
    }
  }

  async function toggleCam() {
    if (mediaMode === "local" && window.localPreviewStream) {
      try { await setCam(!camOn); } catch (e) {
        if (typeof addChatMessage === "function") addChatMessage("", "Camera: " + e.message, true);
      }
      return;
    }
    if (!liveVideoJoined || !liveRoom) {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Connecting live video… try again in a moment.", true);
      }
      return;
    }
    try {
      await setCam(!camOn);
    } catch (e) {
      if (typeof addChatMessage === "function") addChatMessage("", "Camera: " + e.message, true);
    }
  }

  async function toggleScreenShare() {
    if (!isTeacherRole()) return;

    if (mediaMode === "local") {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Connecting live video first so students can see your screen…", true);
      }
      await tryConnectLiveVideo(true);
      if (mediaMode !== "livekit" || !liveVideoJoined) {
        if (typeof addChatMessage === "function") {
          addChatMessage("", "Screen share needs live video. Fix the banner at the top, then tap Retry video.", true);
        }
        return;
      }
    }

    if (!liveVideoJoined || !liveRoom) {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Connecting live video… try again in a moment.", true);
      }
      return;
    }

    try {
      if (!screenOn) {
        await setScreenShare(true);
      } else {
        await setScreenShare(false);
        if (camOn) await setCam(true);
        if (typeof addChatMessage === "function") addChatMessage("", "Screen share stopped.", true);
      }
    } catch (e) {
      if (typeof addChatMessage === "function") addChatMessage("", "Screen share: " + e.message, true);
    }
  }

  async function enableStudentMic() {
    window.studentMicAllowed = true;
    if (typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(true);
    if (typeof addChatMessage === "function") {
      addChatMessage("", "Your teacher let you speak. Turning on your mic…", true);
    }
    try {
      await refreshLiveKitToken();
      await reconnectWithFreshToken();
      await setMic(true);
    } catch (e) {
      if (typeof addChatMessage === "function") addChatMessage("", "Mic: " + e.message, true);
    }
  }

  async function disableStudentMic() {
    window.studentMicAllowed = false;
    try {
      await setMic(false);
      await refreshLiveKitToken();
      await reconnectWithFreshToken();
    } catch (e) { /* ignore */ }
    if (typeof updateMediaButton === "function") {
      updateMediaButton(document.getElementById("btn-mic"), false);
    }
  }

  function countVideoAudience() {
    if (!liveRoom || !liveVideoJoined) return 0;
    return liveRoom.remoteParticipants.size;
  }

  function getRemoteClassMediaStream() {
    if (!liveRoom) return null;
    var ms = new MediaStream();
    liveRoom.remoteParticipants.forEach(function (p) {
      p.trackPublications.forEach(function (pub) {
        if (pub.track && pub.track.mediaStreamTrack) {
          ms.addTrack(pub.track.mediaStreamTrack);
        }
      });
    });
    return ms.getTracks().length ? ms : null;
  }

  async function disconnectLiveVideo() {
    stopLiveKitRetry();
    if (tokenRefreshTimer) {
      clearInterval(tokenRefreshTimer);
      tokenRefreshTimer = null;
    }
    if (liveRoom) {
      try { await liveRoom.disconnect(); } catch (e) { /* ignore */ }
    }
    liveRoom = null;
    liveVideoJoined = false;
    mediaMode = "none";
    micOn = false;
    camOn = false;
    screenOn = false;
  }

  function loadLiveKitScript(cb) {
    if (lk()) { cb(); return; }
    var s = document.createElement("script");
    s.src = "https://cdn.jsdelivr.net/npm/livekit-client@2.9.3/dist/livekit-client.umd.js";
    s.onload = cb;
    s.onerror = function () { cb(); };
    document.head.appendChild(s);
  }

  function initLiveVideo() {
    loadLiveKitScript(function () {
      checkLiveKitServerConfig().then(function () {
        if (isTeacherRole() && typeof startLocalPreviewOnly === "function") {
          startLocalPreviewOnly().catch(function () {});
        }
        tryConnectLiveVideo();
      });
    });
  }

  window.LiveClassMedia = {
    isJoined: isJoined,
    getMediaMode: getMediaMode,
    getMicOn: function () { return micOn; },
    getCamOn: function () { return camOn; },
    setMicState: function (v) { micOn = v; },
    setCamState: function (v) { camOn = v; },
  };

  window.tryConnectLiveVideo = tryConnectLiveVideo;
  window.retryLiveKitConnect = function () {
    hideLiveKitSetupBanner();
    tryConnectLiveVideo(true);
  };
  window.initLiveVideo = initLiveVideo;
  window.disconnectLiveVideo = disconnectLiveVideo;
  window.refreshLiveKitToken = refreshLiveKitToken;
  window.setMic = setMic;
  window.setCam = setCam;
  window.toggleMic = toggleMic;
  window.toggleCam = toggleCam;
  window.toggleScreenShare = toggleScreenShare;
  window.enableStudentMic = enableStudentMic;
  window.disableStudentMic = disableStudentMic;
  window.countVideoAudience = countVideoAudience;
  window.getRemoteClassMediaStream = getRemoteClassMediaStream;
})();
