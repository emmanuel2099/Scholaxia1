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
  var remoteAudioEls = [];
  var participantVideoTracks = {};
  var teacherVideoTrack = null;
  var sidebarVideoOrder = []; // student ids with mounted cam tiles (budgeted)
  var MAX_SIDEBAR_VIDEOS = 24;
  var JOIN_TIMEOUT_MS = 45000;
  var STUDENT_JOIN_TIMEOUT_MS = 18000;
  var PUBLISH_TIMEOUT_MS = 45000;
  var AUDIO_CAPTURE_OPTS = {
    echoCancellation: { ideal: true },
    noiseSuppression: { ideal: true },
    autoGainControl: { ideal: true },
  };

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
    if (!isTeacherRole()) {
      if (liveVideoJoined) return;
      if (message && /reconnect/i.test(String(message))) return;
    }
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
      var status = await withTimeout(
        api("/api/v1/live-classes/livekit/status"),
        8000,
        "LiveKit status timed out"
      );
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
      // Never block joining on a slow/cold API — try with the session token we already have.
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
      var data = await withTimeout(
        api("/api/v1/live-classes/" + classId + "/token"),
        20000,
        "Token refresh timed out"
      );
      liveSession.livekit_token = data.livekit_token || data.token;
      liveSession.livekit_url = data.livekit_url || liveSession.livekit_url;
      liveSession.identity = data.identity || liveSession.identity;
      liveSession.channel_id = data.channel_id || liveSession.channel_id;
      if (data.room_id) liveSession.room_id = data.room_id;
      if (data.end_time) liveSession.end_time = data.end_time;
      if (data.teacher_id) liveSession.teacher_id = data.teacher_id;
      if (
        typeof data.mic_allowed === "boolean" ||
        typeof data.camera_allowed === "boolean" ||
        typeof data.can_publish === "boolean"
      ) {
        applyTokenMediaPermissions(data);
      }
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
      else localStorage.setItem("live_session", JSON.stringify(liveSession));
      window.liveSession = liveSession;
      return hasValidLiveKitToken(liveSession.livekit_token, liveSession.livekit_url);
    } catch (e) {
      // Keep existing session token if refresh fails/times out.
      return hasValidLiveKitToken(
        liveSession.livekit_token || "",
        liveSession.livekit_url || ""
      );
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
    var src = pub.source;
    if (c && c.Track && c.Track.Source) {
      if (src === c.Track.Source.ScreenShare || src === c.Track.Source.ScreenShareAudio) {
        return true;
      }
    }
    var s = String(src || "").toLowerCase();
    if (s === "screen_share" || s === "screen_share_audio" || s === "screenshare") return true;
    try {
      if (pub.trackName && /screen/i.test(String(pub.trackName))) return true;
    } catch (e) { /* ignore */ }
    return false;
  }

  function ensureRemoteAudioContainer() {
    var wrap = document.getElementById("remote-audio-wrap");
    if (!wrap) {
      wrap = document.createElement("div");
      wrap.id = "remote-audio-wrap";
      wrap.className = "remote-audio-wrap";
      wrap.setAttribute("aria-hidden", "true");
      document.body.appendChild(wrap);
    }
    return wrap;
  }

  function playRemoteAudioElement(el) {
    if (!el) return;
    el.autoplay = true;
    el.playsInline = true;
    el.volume = 1;
    el.muted = false;
    var p = el.play && el.play();
    if (p && p.catch) {
      p.catch(function () {
        if (liveRoom && typeof liveRoom.startAudio === "function") {
          liveRoom.startAudio().then(function () {
            if (el.play) el.play().catch(function () {});
          }).catch(function () {});
        }
      });
    }
  }

  async function ensureRoomAudioPlayback() {
    if (!liveRoom) return;
    try {
      if (typeof liveRoom.startAudio === "function") {
        await liveRoom.startAudio();
      }
    } catch (e) {
      /* Browser may require a tap — unlockClassAudio handles that once */
    }
    remoteAudioEls.forEach(playRemoteAudioElement);
  }

  /** Token refresh may lag behind teacher grant — never downgrade local mic/cam grants here. */
  function applyTokenMediaPermissions(data) {
    if (isTeacherRole() || !data) return;
    var upgraded = false;
    if (data.mic_allowed === true) {
      window.studentMicAllowed = true;
      if (liveSession) liveSession.mic_allowed = true;
      if (typeof syncStudentMicState === "function") syncStudentMicState(true);
      upgraded = true;
    }
    if (data.camera_allowed === true) {
      window.studentCameraAllowed = true;
      if (liveSession) liveSession.camera_allowed = true;
      upgraded = true;
    }
    if (liveSession && typeof data.can_publish === "boolean") {
      liveSession.can_publish = data.can_publish;
    }
    if (typeof syncStudentMediaControls === "function") syncStudentMediaControls();
    if (upgraded && liveSession) {
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
      else localStorage.setItem("live_session", JSON.stringify(liveSession));
    }
  }

  function applyStudentMediaPermissions(data) {
    applyTokenMediaPermissions(data);
  }

  function applyLocalMicGrant() {
    if (isTeacherRole()) return;
    window.studentMicAllowed = true;
    if (typeof syncStudentMicState === "function") syncStudentMicState(true);
    liveSession = window.liveSession || liveSession;
    if (liveSession) {
      liveSession.mic_allowed = true;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    }
    if (typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(true);
    var micBtn = document.getElementById("btn-mic");
    if (micBtn) {
      micBtn.disabled = false;
      micBtn.classList.remove("media-locked");
    }
    if (typeof syncStudentMediaControls === "function") syncStudentMediaControls();
  }

  function detachRemoteAudio(participant) {
    var pid = participant && participant.identity ? String(participant.identity) : "";
    if (!pid) return;
    remoteAudioEls = remoteAudioEls.filter(function (el) {
      if (el && el.getAttribute && el.getAttribute("data-participant-id") === pid) {
        try { el.srcObject = null; } catch (e) { /* ignore */ }
        try { el.remove(); } catch (e2) { /* ignore */ }
        return false;
      }
      return true;
    });
  }

  function softDetachRemoteAudio(track) {
    if (!track) return;
    try { track.detach(); } catch (e) { /* ignore */ }
  }

  function pruneRemoteAudioElements() {
    remoteAudioEls.forEach(function (el) {
      if (!el) return;
      try { el.srcObject = null; } catch (e) { /* ignore */ }
      try { el.remove(); } catch (e2) { /* ignore */ }
    });
    remoteAudioEls = [];
  }

  /** Student client: keep teacher microphone subscribed and playing. */
  function reattachTeacherAudio() {
    if (!liveRoom || isTeacherRole()) return;
    var c = lk();
    if (!c) return;
    liveRoom.remoteParticipants.forEach(function (participant) {
      if (!isTeacherParticipant(participant)) return;
      participant.trackPublications.forEach(function (pub) {
        var isAudio = pub.kind === c.Track.Kind.Audio || pub.kind === "audio";
        if (!isAudio) return;
        setPublicationSubscribed(pub, true);
        if (pub.track && !pub.isMuted && !pub.track.isMuted) {
          attachRemoteAudio(pub.track, participant);
        }
      });
    });
  }

  function participantRoleFromMeta(participant) {
    if (!participant || !participant.metadata) return "";
    try {
      var meta = typeof participant.metadata === "string"
        ? JSON.parse(participant.metadata)
        : participant.metadata;
      return String((meta && meta.role) || "").toLowerCase();
    } catch (e) {
      return "";
    }
  }

  function setPublicationSubscribed(publication, want) {
    if (!publication || typeof publication.setSubscribed !== "function") return;
    try {
      if (!!publication.isSubscribed === !!want) return;
      publication.setSubscribed(!!want);
    } catch (e) { /* ignore */ }
  }

  /** Subscribe only to tracks we need — saves bandwidth vs Zoom-style full mesh. */
  function shouldSubscribePublication(pub, participant) {
    if (!pub || !participant) return false;
    var c = lk();
    var isAudio = !!(c && (pub.kind === c.Track.Kind.Audio || pub.kind === "audio"));
    if (isAudio) {
      if (isTeacherRole()) return true;
      return isTeacherParticipant(participant);
    }
    if (isScreenPublication(pub)) {
      if (!isTeacherRole()) return true;
      return false;
    }
    if (!isCameraPublication(pub)) return false;
    if (isTeacherRole()) {
      if (isTeacherParticipant(participant)) return false;
      return true;
    }
    if (!isTeacherParticipant(participant)) return false;
    if (remoteTeacherScreenActive()) return false;
    if (window.board && window.board.open) return false;
    return true;
  }

  function syncParticipantSubscriptions(participant) {
    if (!participant) return;
    wireParticipantVideoEvents(participant);
    participant.trackPublications.forEach(function (pub) {
      var want = shouldSubscribePublication(pub, participant);
      setPublicationSubscribed(pub, want);
      if (!want && isTeacherRole() && isCameraPublication(pub)) {
        var studentId = resolveStudentIdFromParticipant(participant);
        if (studentId && typeof detachParticipantCameraVideo === "function") {
          detachParticipantCameraVideo(studentId);
        }
      }
      if (want && pub.track) {
        attachRemoteTrack(pub.track, pub, participant);
      }
    });
  }

  function syncRemoteSubscriptions() {
    if (!liveRoom) return;
    liveRoom.remoteParticipants.forEach(syncParticipantSubscriptions);
  }

  function reattachAllRemoteAudio() {
    if (!liveRoom) return;
    var c = lk();
    liveRoom.remoteParticipants.forEach(function (participant) {
      participant.trackPublications.forEach(function (pub) {
        var isAudio = !!(c && (pub.kind === c.Track.Kind.Audio || pub.kind === "audio"));
        if (!isAudio || !shouldSubscribePublication(pub, participant)) return;
        setPublicationSubscribed(pub, true);
        if (pub.track) attachRemoteAudio(pub.track, participant);
      });
    });
    ensureRoomAudioPlayback();
  }

  function buildLiveKitRoomOptions(isHost) {
    var c = LK();
    var speech = c.AudioPresets && c.AudioPresets.speech;
    var publishDefaults = {
      dtx: true,
      red: true,
      simulcast: isHost,
      videoCodec: "vp8",
      audioPreset: speech || undefined,
      videoEncoding: isHost
        ? { maxBitrate: 750000, maxFramerate: 24 }
        : { maxBitrate: 160000, maxFramerate: 15 },
      screenShareEncoding: { maxBitrate: 1200000, maxFramerate: 15 },
    };
    if (isHost && c.VideoPresets) {
      publishDefaults.videoSimulcastLayers = [
        c.VideoPresets.h180,
        c.VideoPresets.h360,
      ];
    }
    return {
      adaptiveStream: { pixelDensity: isHost ? 1 : 0.85, pauseVideoInBackground: false },
      dynacast: isHost,
      disconnectOnPageLeave: true,
      stopLocalTrackOnUnpublish: true,
      publishDefaults: publishDefaults,
      audioCaptureDefaults: {
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
      videoCaptureDefaults: {
        resolution: isHost
          ? { width: 1280, height: 720, frameRate: 24 }
          : { width: 426, height: 240, frameRate: 15 },
      },
    };
  }

  /** Student IDs with an active (or pending) camera publication — not only already-attached tracks. */
  function collectStudentCameraIds() {
    var ids = Object.keys(participantVideoTracks);
    if (!liveRoom) return ids;
    liveRoom.remoteParticipants.forEach(function (participant) {
      if (isTeacherParticipant(participant)) return;
      var studentId = resolveStudentIdFromParticipant(participant);
      if (!studentId) return;
      participant.trackPublications.forEach(function (pub) {
        if (isCameraPublication(pub) && ids.indexOf(studentId) < 0) {
          ids.push(studentId);
        }
      });
    });
    return ids;
  }

  function prioritizeSidebarVideoIds() {
    var raised = (typeof window.raisedHands === "object" && window.raisedHands) || {};
    var ids = collectStudentCameraIds();
    ids.sort(function (a, b) {
      var ar = raised[a] ? 1 : 0;
      var br = raised[b] ? 1 : 0;
      if (ar !== br) return br - ar;
      var ai = sidebarVideoOrder.indexOf(a);
      var bi = sidebarVideoOrder.indexOf(b);
      if (ai < 0) ai = 9999;
      if (bi < 0) bi = 9999;
      return ai - bi;
    });
    return ids;
  }

  function applyStudentVideoBudget() {
    if (!isTeacherRole()) return;
    var ranked = prioritizeSidebarVideoIds();
    sidebarVideoOrder = ranked.slice(0, MAX_SIDEBAR_VIDEOS);
    syncRemoteSubscriptions();
  }

  function attachRemoteAudio(track, participant) {
    var c = lk();
    if (!track || !c) return;
    var pid = participant && participant.identity ? String(participant.identity) : "remote";
    var audioWrap = ensureRemoteAudioContainer();
    var audioEl = null;
    for (var i = 0; i < remoteAudioEls.length; i++) {
      var el = remoteAudioEls[i];
      if (el && el.getAttribute && el.getAttribute("data-participant-id") === pid) {
        audioEl = el;
        break;
      }
    }
    if (!audioEl || !audioEl.srcObject) {
      if (audioEl) {
        try { audioEl.remove(); } catch (eRm) { /* ignore */ }
        remoteAudioEls = remoteAudioEls.filter(function (x) { return x !== audioEl; });
      }
      audioEl = track.attach();
      audioEl.setAttribute("data-participant-id", pid);
      audioWrap.appendChild(audioEl);
      remoteAudioEls.push(audioEl);
    } else {
      try {
        track.attach(audioEl);
      } catch (e) {
        try { audioEl.remove(); } catch (eRm2) { /* ignore */ }
        remoteAudioEls = remoteAudioEls.filter(function (x) { return x !== audioEl; });
        audioEl = track.attach();
        audioEl.setAttribute("data-participant-id", pid);
        audioWrap.appendChild(audioEl);
        remoteAudioEls.push(audioEl);
      }
    }
    playRemoteAudioElement(audioEl);
    ensureRoomAudioPlayback();
    if (isTeacherRole()) {
      if (typeof setStatus === "function") {
        setStatus("Connected — you can hear students when they speak");
      }
    } else {
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      if (typeof maybeShowSaveClassHint === "function") maybeShowSaveClassHint();
    }
  }

  function isCameraPublication(pub) {
    if (!pub) return false;
    if (isScreenPublication(pub)) return false;
    var c = lk();
    if (!c) return true;
    if (pub.source === c.Track.Source.Camera || pub.source === "camera") return true;
    if (pub.kind === c.Track.Kind.Video || pub.kind === "video") return true;
    return pub.source === undefined || pub.source === null;
  }

  function normalizeParticipantId(id) {
    return id ? String(id) : null;
  }

  function resolveStudentIdFromParticipant(participant) {
    if (!participant) return null;
    var id = normalizeParticipantId(participant.identity);
    if (!id) return null;
    if (typeof findParticipantCard === "function" && findParticipantCard(id)) return id;
    var cards = document.querySelectorAll(".participant-card[data-student-id]");
    var idLower = id.toLowerCase();
    for (var i = 0; i < cards.length; i++) {
      var sid = cards[i].getAttribute("data-student-id") || "";
      if (sid.toLowerCase() === idLower) return sid;
    }
    return id;
  }

  function getTeacherIdFromSession() {
    var sess = window.liveSession || (typeof loadLiveSession === "function" ? loadLiveSession() : null);
    if (!sess) return null;
    return sess.teacher_id || sess.teacherId || null;
  }

  function isTeacherParticipant(participant) {
    if (!participant || isTeacherRole()) return false;
    var role = participantRoleFromMeta(participant);
    if (role === "teacher" || role === "host" || role === "admin") return true;
    var teacherId = getTeacherIdFromSession();
    var pid = String(participant.identity || "");
    if (teacherId) {
      return pid === String(teacherId) || pid.toLowerCase() === String(teacherId).toLowerCase();
    }
    var sess = window.liveSession || {};
    var selfId = sess.identity || sess.user_id || "";
    if (selfId && pid === String(selfId)) return false;
    // Without a known teacher_id, only treat the sole remote as teacher.
    if (liveRoom && liveRoom.remoteParticipants.size === 1) {
      return pid !== String(selfId);
    }
    return false;
  }

  function clearStudentParticipantVideo(studentId, publication, participant) {
    if (studentId) {
      delete participantVideoTracks[studentId];
      sidebarVideoOrder = sidebarVideoOrder.filter(function (id) { return id !== studentId; });
      if (typeof detachParticipantCameraVideo === "function") {
        detachParticipantCameraVideo(studentId);
      }
    }
  }

  function attachRemoteVideoToMainStage(track, publication) {
    var isScreen = isScreenPublication(publication);
    if (!isTeacherRole() && !isScreen && window.board && window.board.open) {
      return;
    }
    if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
    var wrap = document.getElementById("video-remote");
    if (!wrap || !track) return;
    var trackId = "";
    try {
      trackId = (track.mediaStreamTrack && track.mediaStreamTrack.id) ||
        (track.sid || track.trackSid || "") || "";
    } catch (eId) { /* ignore */ }
    var existingVid = wrap.querySelector("video");
    if (existingVid && trackId && existingVid.dataset && existingVid.dataset.lkTrackId === trackId) {
      wrap.classList.toggle("screen-active", !!isScreen);
      if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
      if (isScreen && typeof window.onScreenShareStageChange === "function") {
        window.onScreenShareStageChange(true);
      }
      return;
    }
    // Screen share must not sit under an open board overlay
    if (isScreen && !isTeacherRole()) {
      window._teacherScreenSharing = true;
      try {
        if (typeof window.hideBoardForStudent === "function") window.hideBoardForStudent();
        else if (typeof window.pauseStudentBoardSyncForScreenShare === "function") {
          window.pauseStudentBoardSyncForScreenShare();
        }
      } catch (eHide) { /* ignore */ }
    }
    wrap.innerHTML = "";
    wrap.classList.toggle("screen-active", !!isScreen);
    var box = document.createElement("div");
    box.className = "remote-user" + (isScreen ? " screen-share" : "");
    var el = track.attach();
    if (trackId) el.dataset.lkTrackId = trackId;
    el.style.width = "100%";
    el.style.height = "100%";
    el.style.objectFit = isScreen ? "contain" : "cover";
    el.muted = true;
    el.autoplay = true;
    el.playsInline = true;
    box.appendChild(el);
    wrap.appendChild(box);
    try {
      var playP = el.play && el.play();
      if (playP && playP.catch) playP.catch(function () {});
    } catch (ePlay) { /* ignore */ }
    if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
    if (isScreen && typeof window.onScreenShareStageChange === "function") {
      window.onScreenShareStageChange(true);
    }
    if (isScreen && !isTeacherRole() && typeof window.hideBoardForStudent === "function") {
      window.hideBoardForStudent();
    }
    if (!isTeacherRole() && !isScreen && typeof maybeShowSaveClassHint === "function") {
      maybeShowSaveClassHint();
    }
  }

  function remoteTeacherScreenActive() {
    if (!liveRoom) return !!window._teacherScreenSharing;
    var active = !!window._teacherScreenSharing;
    liveRoom.remoteParticipants.forEach(function (participant) {
      if (!isTeacherParticipant(participant)) return;
      participant.trackPublications.forEach(function (pub) {
        if (isScreenPublication(pub) && pub.track && !pub.isMuted) active = true;
      });
    });
    return active;
  }

  function clearMainStageVideo() {
    if (!isTeacherRole()) {
      if (window.board && window.board.open) return;
      if (remoteTeacherScreenActive()) return;
    }
    var wrap = document.getElementById("video-remote");
    if (wrap) {
      wrap.innerHTML = "";
      wrap.classList.remove("screen-active");
    }
    if (typeof window.onScreenShareStageChange === "function") window.onScreenShareStageChange(false);
    if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
    if (typeof showVideoPlaceholder === "function") {
      showVideoPlaceholder(
        isTeacherRole()
          ? (screenOn ? "Screen share active." : "Your camera is off.")
          : "Waiting for the teacher…"
      );
    }
  }

  function reattachParticipantVideos() {
    if (!isTeacherRole()) return;
    Object.keys(participantVideoTracks).forEach(function (studentId) {
      var entry = participantVideoTracks[studentId];
      if (typeof isParticipantVideoLive === "function" && !isParticipantVideoLive(entry)) {
        clearStudentParticipantVideo(studentId);
      }
    });
    applyStudentVideoBudget();
  }

  function reattachTeacherScreenShare() {
    if (!liveRoom || isTeacherRole()) return;
    var c = lk();
    if (!c) return;
    var attached = false;
    liveRoom.remoteParticipants.forEach(function (participant) {
      if (!isTeacherParticipant(participant)) return;
      participant.trackPublications.forEach(function (pub) {
        if (!isScreenPublication(pub) || !pub.track || pub.isMuted) return;
        setPublicationSubscribed(pub, true);
        attachRemoteVideoToMainStage(pub.track, pub);
        attached = true;
      });
    });
    return attached;
  }

  function reattachTeacherMainStage() {
    if (isTeacherRole() || !teacherVideoTrack) return;
    if (remoteTeacherScreenActive()) {
      reattachTeacherScreenShare();
      return;
    }
    if (window.board && window.board.open && !remoteTeacherScreenActive()) return;
    if (typeof isParticipantVideoLive === "function" && !isParticipantVideoLive(teacherVideoTrack)) {
      teacherVideoTrack = null;
      if (!window.board || !window.board.open) clearMainStageVideo();
      return;
    }
    var wrap = document.getElementById("video-remote");
    if (wrap && wrap.querySelector("video")) {
      var v = wrap.querySelector("video");
      if (v && v.readyState >= 2 && !v.paused) return;
    }
    if (teacherVideoTrack.track) {
      attachRemoteVideoToMainStage(teacherVideoTrack.track, teacherVideoTrack.publication);
    }
  }

  function attachRemoteTrack(track, publication, participant) {
    var c = lk();
    if (!track || !c) return;
    if (track.kind === c.Track.Kind.Video || track.kind === "video") {
      if (isScreenPublication(publication)) {
        attachRemoteVideoToMainStage(track, publication);
        return;
      }
      if (isTeacherRole() && isCameraPublication(publication)) {
        var studentId = resolveStudentIdFromParticipant(participant);
        var displayName = (participant && (participant.name || participant.identity)) || "Student";
        if (studentId && typeof ensureParticipantCardForStudent === "function") {
          ensureParticipantCardForStudent(studentId, displayName);
        }
        if (studentId) {
          participantVideoTracks[studentId] = {
            track: track,
            publication: publication,
            participant: participant,
          };
          if (sidebarVideoOrder.indexOf(studentId) < 0) {
            sidebarVideoOrder.push(studentId);
          }
          applyStudentVideoBudget();
          // Force attach even if roster was empty a moment ago
          if (typeof attachParticipantCameraVideo === "function") {
            attachParticipantCameraVideo(studentId, track);
          }
          maybeShowStudentOnMainStage(studentId, track, publication);
          if (typeof reattachParticipantVideos === "function") {
            setTimeout(function () { reattachParticipantVideos(); }, 100);
          }
        }
        return;
      }
      if (!isTeacherRole() && isCameraPublication(publication)) {
        if (isTeacherParticipant(participant)) {
          teacherVideoTrack = { track: track, publication: publication, participant: participant };
          if (remoteTeacherScreenActive()) return;
          if (!window.board || !window.board.open) {
            attachRemoteVideoToMainStage(track, publication);
          }
        }
        // Ignore peer student cameras on the student main stage (prevents flicker).
        return;
      }
      // Unknown role/heuristic — only mount if this is clearly the teacher.
      if (isTeacherParticipant(participant)) {
        attachRemoteVideoToMainStage(track, publication);
      }
    }
    if (track.kind === c.Track.Kind.Audio || track.kind === "audio") {
      attachRemoteAudio(track, participant);
    }
  }

  function detachRemoteVideo(track, publication, participant) {
    var c = lk();
    if (!track || !c) return;
    if (track.kind !== c.Track.Kind.Video && track.kind !== "video") return;

    if (isScreenPublication(publication)) {
      if (!isTeacherRole()) {
        window._teacherScreenSharing = false;
        if (typeof window.resumeStudentBoardSyncAfterScreenShare === "function") {
          window.resumeStudentBoardSyncAfterScreenShare();
        }
      }
      var wrap = document.getElementById("video-remote");
      if (wrap) {
        wrap.innerHTML = "";
        wrap.classList.remove("screen-active");
      }
      if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
      if (!isTeacherRole() && window.board && window.board.open) return;
      if (!isTeacherRole() && remoteTeacherScreenActive()) return;
      clearMainStageVideo();
      return;
    }

    if (isTeacherRole() && isCameraPublication(publication)) {
      var studentId = resolveStudentIdFromParticipant(participant);
      clearStudentParticipantVideo(studentId, publication, participant);
      return;
    }

    if (!isTeacherRole() && isTeacherParticipant(participant) && isCameraPublication(publication)) {
      teacherVideoTrack = null;
      if (!remoteTeacherScreenActive() && (!window.board || !window.board.open)) clearMainStageVideo();
      return;
    }

    if (!isTeacherRole() && isCameraPublication(publication)) {
      return;
    }

    clearMainStageVideo();
  }

  function handleRemoteCameraMuted(publication, participant) {
    if (!isCameraPublication(publication)) return;
    if (publication && publication.track && !publication.isMuted && !publication.track.isMuted) return;
    if (isTeacherRole()) {
      var studentId = resolveStudentIdFromParticipant(participant);
      clearStudentParticipantVideo(studentId, publication, participant);
    } else if (isTeacherParticipant(participant)) {
      teacherVideoTrack = null;
      if (!remoteTeacherScreenActive() && (!window.board || !window.board.open)) clearMainStageVideo();
    }
  }

  function subscribeTeacherScreenShares() {
    if (!liveRoom || isTeacherRole()) return;
    liveRoom.remoteParticipants.forEach(function (participant) {
      participant.trackPublications.forEach(function (pub) {
        if (!isScreenPublication(pub)) return;
        setPublicationSubscribed(pub, true);
        if (pub.track) attachRemoteVideoToMainStage(pub.track, pub);
      });
    });
  }

  function attachExistingRemoteTracks() {
    syncRemoteSubscriptions();
    if (!isTeacherRole()) subscribeTeacherScreenShares();
    ensureRoomAudioPlayback();
  }

  function reattachRemoteClassAudio() {
    if (!liveRoom) return;
    reattachAllRemoteAudio();
  }
  window.reattachRemoteClassAudio = reattachRemoteClassAudio;
  window.ensureRoomAudioPlayback = ensureRoomAudioPlayback;

  function getStageSpotlightMode() {
    var stage = document.getElementById("video-stage");
    return (stage && stage.getAttribute("data-spotlight")) || "teacher";
  }

  function attachStudentVideoToMainStage(studentId, track, publication) {
    if (!isTeacherRole() || !track) return false;
    if (screenOn) return false;
    var mode = getStageSpotlightMode();
    if (mode === "board" && window.board && window.board.open) return false;
    if (mode === "screen") return false;
    if (mode === "student" && window.spotlightUserId && String(window.spotlightUserId) !== String(studentId)) {
      return false;
    }
    if (mode === "teacher" && camOn) return false;
    var wrap = document.getElementById("video-remote");
    if (!wrap || wrap.classList.contains("screen-active")) return false;
    var trackId = "";
    try {
      trackId = (track.mediaStreamTrack && track.mediaStreamTrack.id) ||
        (track.sid || track.trackSid || "") || "";
    } catch (eId) { /* ignore */ }
    var existing = wrap.querySelector(".remote-user.student-main-stage video");
    if (existing && trackId && existing.dataset && existing.dataset.lkTrackId === trackId) {
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      return true;
    }
    wrap.innerHTML = "";
    wrap.classList.remove("screen-active");
    var box = document.createElement("div");
    box.className = "remote-user student-main-stage";
    box.setAttribute("data-student-id", String(studentId || ""));
    var el = track.attach();
    if (trackId) el.dataset.lkTrackId = trackId;
    el.style.width = "100%";
    el.style.height = "100%";
    el.style.objectFit = "cover";
    el.muted = true;
    el.autoplay = true;
    el.playsInline = true;
    box.appendChild(el);
    wrap.appendChild(box);
    try {
      var playP = el.play && el.play();
      if (playP && playP.catch) playP.catch(function () {});
    } catch (ePlay) { /* ignore */ }
    if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
    if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
    return true;
  }

  function maybeShowStudentOnMainStage(studentId, track, publication) {
    if (!isTeacherRole() || !studentId || !track) return;
    attachStudentVideoToMainStage(studentId, track, publication);
  }

  function attachTeacherCameraToMainStage() {
    if (!isTeacherRole() || !liveRoom || !camOn) return false;
    if (getStageSpotlightMode() !== "teacher") return false;
    if (screenOn) return false;
    var wrap = document.getElementById("video-remote");
    if (!wrap || wrap.classList.contains("screen-active")) return false;
    var c = lk();
    if (!c) return false;
    var pub = liveRoom.localParticipant.getTrackPublication(c.Track.Source.Camera);
    if (!pub || !pub.track || pub.isMuted || pub.track.isMuted) return false;

    var trackId = "";
    try {
      trackId = (pub.track.mediaStreamTrack && pub.track.mediaStreamTrack.id) ||
        (pub.track.sid || pub.track.trackSid || "") || "";
    } catch (eId) { /* ignore */ }
    var existingTeacher = wrap.querySelector(".remote-user.teacher-self video");
    if (existingTeacher && trackId && existingTeacher.dataset && existingTeacher.dataset.lkTrackId === trackId) {
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      return true;
    }

    wrap.innerHTML = "";
    wrap.classList.remove("screen-active");
    var box = document.createElement("div");
    box.className = "remote-user teacher-self";
    var el = pub.track.attach();
    if (trackId) el.dataset.lkTrackId = trackId;
    el.style.width = "100%";
    el.style.height = "100%";
    el.style.objectFit = "cover";
    el.muted = true;
    el.autoplay = true;
    el.playsInline = true;
    box.appendChild(el);
    wrap.appendChild(box);
    try {
      var playP = el.play && el.play();
      if (playP && playP.catch) playP.catch(function () {});
    } catch (ePlay) { /* ignore */ }
    if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
    if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
    return true;
  }

  function refreshTeacherVideoLayout() {
    if (!isTeacherRole()) return;
    var localEl = document.getElementById("video-local");
    var wrap = document.getElementById("video-remote");
    var spotlight = getStageSpotlightMode();
    if (spotlight === "teacher" && camOn && attachTeacherCameraToMainStage()) {
      if (localEl) localEl.classList.add("hidden");
      return;
    }
    if (!screenOn && spotlight === "teacher" && !camOn) {
      var hasStudentMain = wrap && wrap.querySelector(".remote-user.student-main-stage video");
      if (!hasStudentMain && typeof showVideoPlaceholder === "function") {
        showVideoPlaceholder("Your camera is off — student video appears here when they turn on cam");
      }
    }
    if (wrap && !screenOn && spotlight === "teacher") {
      var teacherSelf = wrap.querySelector(".remote-user.teacher-self");
      if (teacherSelf && camOn) wrap.innerHTML = "";
    }
    attachLocalCameraPreview();
  }
  window.refreshTeacherVideoLayout = refreshTeacherVideoLayout;

  function attachLocalCameraPreview() {
    if (!liveRoom) return;
    var c = lk();
    if (!c) return;
    var localEl = document.getElementById("video-local");
    liveRoom.localParticipant.videoTrackPublications.forEach(function (pub) {
      if (!isCameraPublication(pub) || !pub.track) return;
      if (isTeacherRole()) {
        if (screenOn) {
          if (localEl) localEl.classList.add("hidden");
          return;
        }
        if (getStageSpotlightMode() === "teacher" && attachTeacherCameraToMainStage()) {
          if (localEl) localEl.classList.add("hidden");
          return;
        }
        var remoteWrap = document.getElementById("video-remote");
        if (remoteWrap && remoteWrap.querySelector(".remote-user.teacher-self video")) {
          if (localEl) localEl.classList.add("hidden");
          return;
        }
        if (!localEl) return;
        localEl.innerHTML = "";
        var el = pub.track.attach();
        el.style.width = "100%";
        el.style.height = "100%";
        el.muted = true;
        el.autoplay = true;
        el.playsInline = true;
        localEl.appendChild(el);
        localEl.classList.remove("hidden");
      } else if (typeof showStudentSelfPreview === "function") {
        showStudentSelfPreview(pub.track);
      }
    });
  }

  function attachLocalScreenPreview() {
    if (!liveRoom) return;
    var c = lk();
    if (!c) return;
    var screenPub = null;
    liveRoom.localParticipant.videoTrackPublications.forEach(function (pub) {
      if (isScreenPublication(pub) && pub.track) screenPub = pub;
    });
    if (!screenPub || !screenPub.track) return;

    // Show on main stage so teacher sees the same feed students get
    var wrap = document.getElementById("video-remote");
    if (wrap) {
      wrap.innerHTML = "";
      wrap.classList.add("screen-active");
      var box = document.createElement("div");
      box.className = "remote-user screen-share";
      var mainEl = screenPub.track.attach();
      mainEl.style.width = "100%";
      mainEl.style.height = "100%";
      mainEl.muted = true;
      mainEl.autoplay = true;
      mainEl.playsInline = true;
      box.appendChild(mainEl);
      wrap.appendChild(box);
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
    }

    var localEl = document.getElementById("video-local");
    if (localEl) {
      localEl.innerHTML = "";
      localEl.classList.add("hidden");
    }
  }

  function isLocalMicPublished() {
    if (!liveRoom) return false;
    var c = lk();
    if (!c) return false;
    var pub = liveRoom.localParticipant.getTrackPublication(c.Track.Source.Microphone);
    return !!(pub && pub.track && !pub.isMuted);
  }

  function isLocalCamPublished() {
    if (!liveRoom) return false;
    var c = lk();
    if (!c) return false;
    var pub = liveRoom.localParticipant.getTrackPublication(c.Track.Source.Camera);
    return !!(pub && pub.track && !pub.isMuted);
  }

  function getLocalMicTrack() {
    if (!liveRoom) return null;
    var c = lk();
    if (!c) return null;
    var pub = liveRoom.localParticipant.getTrackPublication(c.Track.Source.Microphone);
    return pub && pub.track ? pub.track : null;
  }

  function wireParticipantVideoEvents(participant) {
    if (!participant) return;
    var c = lk();
    if (!c || !c.ParticipantEvent) return;
    if (participant._siaVideoWired) return;
    participant._siaVideoWired = true;
    participant.on(c.ParticipantEvent.TrackUnpublished, function (publication) {
      if (publication && publication.track) {
        detachRemoteVideo(publication.track, publication, participant);
      } else {
        handleRemoteCameraMuted(publication, participant);
      }
    });
  }

  function wireRoomEvents(room) {
    var c = LK();
    room.on(c.RoomEvent.TrackSubscribed, function (track, publication, participant) {
      attachRemoteTrack(track, publication, participant);
      if (!isTeacherRole() && isScreenPublication(publication)) {
        if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
        if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
      }
      if (track && (track.kind === "audio" || publication && publication.kind === "audio")) {
        ensureRoomAudioPlayback();
      }
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.TrackUnsubscribed, function (track, publication, participant) {
      if (track && (track.kind === c.Track.Kind.Audio || track.kind === "audio")) {
        softDetachRemoteAudio(track);
        if (!isTeacherRole() && isTeacherParticipant(participant)) {
          setTimeout(function () { reattachTeacherAudio(); ensureRoomAudioPlayback(); }, 300);
        }
        return;
      }
      detachRemoteVideo(track, publication, participant);
    });
    room.on(c.RoomEvent.TrackMuted, function (publication, participant) {
      if (publication && (publication.kind === c.Track.Kind.Audio || publication.kind === "audio")) {
        if (!participant || participant.isLocal) return;
        return;
      }
      handleRemoteCameraMuted(publication, participant);
    });
    room.on(c.RoomEvent.TrackUnmuted, function (publication, participant) {
      if (!publication || !publication.track) return;
      if (publication.kind === c.Track.Kind.Audio || publication.kind === "audio") {
        if (!participant || participant.isLocal) return;
        attachRemoteAudio(publication.track, participant);
        return;
      }
      attachRemoteTrack(publication.track, publication, participant);
    });
    if (c.RoomEvent.TrackUnpublished) {
      room.on(c.RoomEvent.TrackUnpublished, function (publication, participant) {
        if (publication && publication.track) {
          detachRemoteVideo(publication.track, publication, participant);
        } else {
          handleRemoteCameraMuted(publication, participant);
        }
      });
    }
    room.on(c.RoomEvent.TrackPublished, function (publication, participant) {
      if (!participant || participant.isLocal) return;
      if (!isTeacherRole() && isScreenPublication(publication)) {
        if (typeof window.hideBoardForStudent === "function") window.hideBoardForStudent();
        setPublicationSubscribed(publication, true);
        if (publication.track) {
          attachRemoteVideoToMainStage(publication.track, publication);
        }
        return;
      }
      if (shouldSubscribePublication(publication, participant)) {
        setPublicationSubscribed(publication, true);
      }
      if (isTeacherRole() && isCameraPublication(publication)) {
        setTimeout(function () {
          if (typeof reattachParticipantVideos === "function") reattachParticipantVideos();
        }, 50);
      }
    });
    room.on(c.RoomEvent.ParticipantConnected, function (participant) {
      syncParticipantSubscriptions(participant);
      if (!isTeacherRole() && isTeacherParticipant(participant)) {
        reattachTeacherAudio();
        ensureRoomAudioPlayback();
      }
      if (typeof updateAudienceStats === "function") updateAudienceStats();
      if (typeof refreshLiveKitRosterDebounced === "function") refreshLiveKitRosterDebounced();
      else if (typeof refreshLiveKitRoster === "function") refreshLiveKitRoster();
    });
    room.on(c.RoomEvent.ParticipantDisconnected, function (participant) {
      detachRemoteAudio(participant);
      if (isTeacherRole()) {
        var studentId = resolveStudentIdFromParticipant(participant);
        if (studentId && participantVideoTracks[studentId]) {
          clearStudentParticipantVideo(studentId);
          applyStudentVideoBudget();
        }
      } else if (isTeacherParticipant(participant)) {
        teacherVideoTrack = null;
        clearMainStageVideo();
      }
      if (typeof updateAudienceStats === "function") updateAudienceStats();
      if (typeof refreshLiveKitRosterDebounced === "function") refreshLiveKitRosterDebounced();
      else if (typeof refreshLiveKitRoster === "function") refreshLiveKitRoster();
    });
    room.on(c.RoomEvent.LocalTrackPublished, function (publication) {
      if (publication && (publication.kind === c.Track.Kind.Audio || publication.kind === "audio")) {
        micOn = true;
        if (typeof updateMediaButton === "function") {
          updateMediaButton(document.getElementById("btn-mic"), true);
        }
        return;
      }
      if (isScreenPublication(publication)) {
        screenOn = true;
        attachLocalScreenPreview();
        if (typeof updateMediaButton === "function") {
          updateMediaButton(document.getElementById("btn-share"), true);
        }
        return;
      }
      if (!isCameraPublication(publication) || !publication.track) return;
      if (isTeacherRole()) {
        attachLocalCameraPreview();
      } else if (typeof showStudentSelfPreview === "function") {
        showStudentSelfPreview(publication.track);
      }
    });
    room.on(c.RoomEvent.LocalTrackUnpublished, function (publication) {
      if (isScreenPublication(publication)) {
        screenOn = false;
        var btn = document.getElementById("btn-share");
        if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
        if (camOn) setCam(true);
        return;
      }
      if (isCameraPublication(publication) && !isTeacherRole()) {
        if (typeof hideStudentSelfPreview === "function") hideStudentSelfPreview();
      }
    });
    room.on(c.RoomEvent.Disconnected, function () {
      liveVideoJoined = false;
      if (isTeacherRole()) {
        if (typeof showReconnectBanner === "function") {
          showReconnectBanner(true, "Video disconnected. Reconnecting…");
        }
        if (typeof setStatus === "function") setStatus("Video reconnecting…");
      }
      scheduleLiveKitRetry();
    });
    room.on(c.RoomEvent.Connected, function () {
      scheduleTokenRefresh();
      ensureRoomAudioPlayback();
      if (typeof showReconnectBanner === "function") showReconnectBanner(false);
      if (isTeacherRole() && typeof setStatus === "function") setStatus("Connected — video + chat");
      hideLiveKitSetupBanner();
      if (typeof maybeHideJoinOverlay === "function") maybeHideJoinOverlay();
      setTimeout(function () { ensureRoomAudioPlayback(); }, 300);
      setTimeout(function () { ensureRoomAudioPlayback(); }, 1200);
    });
    if (c.RoomEvent.Reconnecting) {
      room.on(c.RoomEvent.Reconnecting, function () {
        if (isTeacherRole() && typeof showReconnectBanner === "function") {
          showReconnectBanner(true, "Video reconnecting…");
        }
      });
    }
    if (c.RoomEvent.Reconnected) {
      room.on(c.RoomEvent.Reconnected, function () {
        if (typeof showReconnectBanner === "function") showReconnectBanner(false);
        if (typeof reattachRemoteTracks === "function") reattachRemoteTracks();
        else if (typeof attachExistingRemoteTracks === "function") attachExistingRemoteTracks();
      });
    }
    if (c.RoomEvent.ActiveSpeakersChanged) {
      room.on(c.RoomEvent.ActiveSpeakersChanged, function (speakers) {
        var ids = {};
        (speakers || []).forEach(function (p) {
          if (p && p.identity) ids[String(p.identity).toLowerCase()] = true;
        });
        document.querySelectorAll(".participant-card[data-student-id]").forEach(function (card) {
          var sid = String(card.getAttribute("data-student-id") || "").toLowerCase();
          card.classList.toggle("is-speaking", !!ids[sid]);
        });
      });
    }
    if (c.RoomEvent.AudioPlaybackStatusChanged) {
      room.on(c.RoomEvent.AudioPlaybackStatusChanged, function () {
        if (liveRoom && liveRoom.canPlaybackAudio === false) {
          ensureRoomAudioPlayback();
        }
      });
    }
  }

  async function disconnectAndReconnectRoom() {
    var wasCam = camOn;
    var wasMic = micOn;
    var wasScreen = screenOn;
    liveKitConnecting = false;
    if (liveRoom) {
      try {
        await liveRoom.disconnect();
      } catch (e) { /* ignore */ }
    }
    pruneRemoteAudioElements();
    liveRoom = null;
    liveVideoJoined = false;
    await refreshLiveKitToken();
    await tryConnectLiveVideo(true);
    if (!liveVideoJoined) return;
    if (wasScreen) {
      await setScreenShare(true);
    } else {
      if (wasCam) {
        camOn = false;
        await setCam(true);
      }
      if (wasMic) {
        micOn = false;
        await setMic(true);
      }
    }
  }

  async function refreshPublishAccess() {
    if (!liveVideoJoined || !liveRoom) {
      await tryConnectLiveVideo(true);
      return !!liveVideoJoined;
    }
    await refreshLiveKitToken();
    var refreshed = await refreshRoomToken();
    if (refreshed) return true;
    await reconnectWithFreshToken();
    return !!liveVideoJoined;
  }

  async function refreshRoomToken() {
    var ok = await refreshLiveKitToken();
    if (!ok || !liveRoom || !liveSession || !liveSession.livekit_token) return false;
    try {
      var client = liveRoom.engine && liveRoom.engine.client;
      if (client && typeof client.refreshToken === "function") {
        await client.refreshToken(liveSession.livekit_token);
        return true;
      }
      if (liveSession.livekit_url && typeof liveRoom.connect === "function") {
        await liveRoom.connect(liveSession.livekit_url, liveSession.livekit_token);
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  async function ensurePublishPermissions(forceReconnect) {
    if (!liveVideoJoined || !liveRoom) {
      await tryConnectLiveVideo(true);
      return !!liveVideoJoined;
    }
    if (forceReconnect) {
      await reconnectWithFreshToken();
      return !!liveVideoJoined;
    }
    return await refreshPublishAccess();
  }

  async function reconnectWithFreshToken() {
    var wasCam = camOn;
    var wasMic = micOn;
    var wasScreen = screenOn;
    await disconnectAndReconnectRoom();
    if (!liveVideoJoined) return;
    if (wasScreen) await setScreenShare(true);
    else {
      if (wasCam) await setCam(true);
      if (wasMic) await setMic(true);
    }
  }

  async function publishMicrophoneEnabled(on) {
    if (!liveRoom) throw new Error("Not connected to video room");
    var run = function () {
      return withTimeout(
        liveRoom.localParticipant.setMicrophoneEnabled(on, on ? AUDIO_CAPTURE_OPTS : undefined),
        PUBLISH_TIMEOUT_MS,
        "publication of local track timed out, no response from server"
      );
    };
    try {
      await run();
    } catch (e) {
      if (!on || isTeacherRole()) throw e;
      if (await refreshRoomToken()) {
        try {
          await run();
          return;
        } catch (e2) { /* try full reconnect */ }
      }
      if (await studentReconnectForPublish()) {
        await run();
        return;
      }
      throw e;
    }
  }

  async function publishCameraEnabled(on) {
    if (!liveRoom) throw new Error("Not connected to video room");
    var run = function () {
      return withTimeout(
        liveRoom.localParticipant.setCameraEnabled(on),
        PUBLISH_TIMEOUT_MS,
        "publication of local track timed out, no response from server"
      );
    };
    try {
      await run();
    } catch (e) {
      if (!on || isTeacherRole()) throw e;
      if (await refreshRoomToken()) {
        try {
          await run();
          return;
        } catch (e2) { /* try full reconnect */ }
      }
      if (await studentReconnectForPublish()) {
        await run();
        return;
      }
      throw e;
    }
  }

  async function transitionHostToLiveBroadcast() {
    var wantCam = camOn || !!window.localPreviewStream;
    var wantMic = true;
    if (typeof clearLocalPreviewStream === "function") {
      clearLocalPreviewStream();
    } else if (window.localPreviewStream) {
      window.localPreviewStream.getTracks().forEach(function (t) { t.stop(); });
      window.localPreviewStream = null;
    }
    if (typeof stopSelfHear === "function") stopSelfHear();
    if (typeof stopMicMonitor === "function") stopMicMonitor();
    micOn = false;
    if (wantMic) await setMic(true);
    if (wantCam) {
      camOn = false;
      await setCam(true);
    }
  }

  async function waitForRoomConnected(maxMs) {
    if (!liveRoom) return false;
    var c = lk();
    var deadline = Date.now() + (maxMs || 8000);
    while (Date.now() < deadline) {
      try {
        if (liveRoom.state === "connected") return true;
        if (c && c.ConnectionState && liveRoom.state === c.ConnectionState.Connected) return true;
      } catch (e) { /* ignore */ }
      await new Promise(function (r) { setTimeout(r, 200); });
    }
    return false;
  }

  /** Connect (or reconnect) LiveKit before mic/cam publish — students often sit in chat-only mode. */
  async function ensureLiveVideoReady(maxMs, opts) {
    opts = opts || {};
    if (liveRoom && await waitForRoomConnected(1500)) {
      liveVideoJoined = true;
      return true;
    }
    if (liveVideoJoined && liveRoom) return true;
    if (!opts.silent && typeof showClassroomToast === "function") {
      showClassroomToast("Connecting video…");
    }
    var deadline = Date.now() + (maxMs || 35000);
    while (Date.now() < deadline) {
      if (liveVideoJoined && liveRoom) return true;
      if (!liveKitConnecting) {
        try {
          await tryConnectLiveVideo(true);
        } catch (eConn) { /* retry */ }
      }
      if (await waitForRoomConnected(5000)) {
        liveVideoJoined = true;
        return true;
      }
      await new Promise(function (r) { setTimeout(r, 400); });
    }
    return liveVideoJoined && liveRoom;
  }

  async function ensureStudentPublishReady(kind) {
    if (isTeacherRole()) return true;
    if (!liveVideoJoined || !liveRoom) {
      if (!await ensureLiveVideoReady(20000, { silent: true })) return false;
    }
    var checkAllowed = function () {
      return kind === "cam"
        ? window.studentCameraAllowed === true ||
          !!(liveSession && (liveSession.camera_allowed || liveSession.can_publish))
        : window.studentMicAllowed === true ||
          !!(liveSession && (liveSession.mic_allowed || liveSession.can_publish));
    };
    await refreshLiveKitToken();
    await refreshRoomToken();
    if (checkAllowed() && await waitForRoomConnected(3000)) return true;
    var deadline = Date.now() + 6000;
    while (Date.now() < deadline) {
      await refreshLiveKitToken();
      await refreshRoomToken();
      if (checkAllowed() && await waitForRoomConnected(2000)) return true;
      await new Promise(function (r) { setTimeout(r, 500); });
    }
    return false;
  }

  async function publishWithRetries(kind, on) {
    var attempts = on ? 4 : 2;
    var lastErr = null;
    for (var i = 1; i <= attempts; i++) {
      try {
        if (kind === "mic") await publishMicrophoneEnabled(on);
        else await publishCameraEnabled(on);
        return;
      } catch (e) {
        lastErr = e;
        if (i >= attempts) break;
        if (!on || isTeacherRole()) break;
        await refreshLiveKitToken();
        await refreshRoomToken();
        if (i >= 3) await studentReconnectForPublish();
        await new Promise(function (r) { setTimeout(r, 300 * i); });
      }
    }
    throw lastErr || new Error("Could not publish " + kind);
  }

  function formatStudentVideoMessage(message) {
    var friendly = String(message || "");
    if (/timeout|timed out|no response|publication of local track/i.test(friendly)) {
      return "Connection is slow — tap Mic or Cam to try again.";
    }
    if (friendly) return "Video reconnecting — chat and board still work.";
    return "Connecting to class…";
  }

  function enterChatOnlyMode(message) {
    var friendly = message || "";
    if (!isTeacherRole()) {
      friendly = formatStudentVideoMessage(friendly);
      liveVideoJoined = false;
      if (typeof setStatus === "function") setStatus("Connected — video loading in background");
      if (typeof maybeHideJoinOverlay === "function") maybeHideJoinOverlay();
      if (!camOn && !window.localPreviewStream && typeof showVideoPlaceholder === "function") {
        showVideoPlaceholder(friendly);
      }
      if (typeof showClassroomToast === "function") {
        showClassroomToast(friendly, true);
      }
      if (typeof setVideoControlsEnabled === "function") {
        var canMic = window.studentMicAllowed === true;
        var canCam = window.studentCameraAllowed === true;
        setVideoControlsEnabled(canMic || canCam);
      } else if (typeof syncStudentMediaControls === "function") {
        syncStudentMediaControls();
      }
      scheduleLiveKitRetry();
      return;
    }
    liveVideoJoined = false;
    liveRoom = null;
    if (typeof setStatus === "function") setStatus("Chat only — video reconnecting…");
    if (!camOn && !window.localPreviewStream && typeof showVideoPlaceholder === "function") {
      showVideoPlaceholder(message || "Connecting to class…");
    }
    showLiveKitSetupBanner(message || liveKitMissingMessage());
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
  }

  async function studentReconnectForPublish() {
    if (isTeacherRole()) return false;
    await refreshLiveKitToken();
    if (!liveSession || !liveSession.livekit_token || !liveSession.livekit_url) return false;
    try {
      if (liveRoom) {
        try { await liveRoom.disconnect(); } catch (eDisc) { /* ignore */ }
      }
      liveRoom = null;
      liveVideoJoined = false;
      liveKitConnecting = false;
      await tryConnectLiveVideo(true);
      return !!(liveVideoJoined && liveRoom);
    } catch (eRec) {
      return false;
    }
  }

  async function tryConnectLiveVideo(isRetry) {
    if (liveKitConnecting) return;
    if (liveVideoJoined && liveRoom) return;
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
    if (typeof setStatus === "function") setStatus("Connecting live video…");
    liveSession = window.liveSession || liveSession;
    liveSession = normalizeSession(liveSession || (typeof loadLiveSession === "function" ? loadLiveSession() : null));
    window.liveSession = liveSession;

    // Prefer the token already saved at join — don't block on a slow /token API.
    var token = liveSession.livekit_token || "";
    var url = liveSession.livekit_url || "";
    if (!hasValidLiveKitToken(token, url)) {
      await refreshLiveKitToken();
      token = liveSession.livekit_token || "";
      url = liveSession.livekit_url || "";
    } else {
      // Refresh in background for grants; connect with what we have now.
      refreshLiveKitToken().catch(function () {});
    }
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
        var isHost = isTeacherRole();
        liveRoom = new c.Room(buildLiveKitRoomOptions(isHost));
        wireRoomEvents(liveRoom);
      }

      if (!liveVideoJoined) {
        await withTimeout(
          liveRoom.connect(url, token, { autoSubscribe: false }),
          isTeacherRole() ? JOIN_TIMEOUT_MS : STUDENT_JOIN_TIMEOUT_MS,
          "Video join timed out"
        );
      }

      liveVideoJoined = true;
      mediaMode = "livekit";
      stopLiveKitRetry();
      hideLiveKitSetupBanner();
      attachExistingRemoteTracks();
      if (typeof updateAudienceStats === "function") updateAudienceStats();
      if (typeof refreshLiveKitRosterDebounced === "function") refreshLiveKitRosterDebounced();
      else if (typeof refreshLiveKitRoster === "function") refreshLiveKitRoster();
      if (typeof setVideoControlsEnabled === "function") {
        var canMic = isTeacherRole() || window.studentMicAllowed === true;
        var canCam = isTeacherRole() || window.studentCameraAllowed === true;
        setVideoControlsEnabled(canMic || canCam || isTeacherRole());
        var micBtn = document.getElementById("btn-mic");
        var camBtn = document.getElementById("btn-cam");
        if (micBtn) micBtn.disabled = isTeacherRole() ? false : !canMic;
        if (camBtn) camBtn.disabled = isTeacherRole() ? false : !canCam;
      }
      if (typeof setStatus === "function") setStatus("Connected — video + chat");
      if (typeof maybeHideJoinOverlay === "function") maybeHideJoinOverlay();
      await ensureRoomAudioPlayback();
      // Keep remote student audio alive for the teacher (autoplay / resubscribe).
      if (isTeacherRole()) {
        if (window._sxAudioKeepAlive) clearInterval(window._sxAudioKeepAlive);
        window._sxAudioKeepAlive = setInterval(function () {
          if (!liveVideoJoined) return;
          remoteAudioEls.forEach(function (el) {
            if (el && el.paused) playRemoteAudioElement(el);
          });
        }, 15000);
      } else {
        reattachTeacherAudio();
        if (window._sxVideoKeepAlive) clearInterval(window._sxVideoKeepAlive);
        window._sxVideoKeepAlive = setInterval(function () {
          if (!liveVideoJoined) return;
          if (remoteTeacherScreenActive()) {
            var wrapSs = document.getElementById("video-remote");
            var vidSs = wrapSs && wrapSs.querySelector("video");
            if (!vidSs || vidSs.paused || vidSs.readyState < 2) {
              reattachTeacherScreenShare();
            }
            remoteAudioEls.forEach(function (el) {
              if (el && el.paused) playRemoteAudioElement(el);
            });
            return;
          }
          reattachTeacherAudio();
          if (!window.board || !window.board.open) {
            reattachTeacherMainStage();
          }
          remoteAudioEls.forEach(function (el) {
            if (el && el.paused) playRemoteAudioElement(el);
          });
        }, 20000);
      }
      var studBadge = document.getElementById("audience-badge");
      if (studBadge && !isTeacherRole()) {
        studBadge.textContent = "";
        studBadge.classList.add("hidden");
      }

      if (isTeacherRole()) {
        if (typeof showHostTools === "function") showHostTools(true);
        if (window.board) {
          window.board.canDraw = true;
          var ov2 = document.getElementById("board-overlay");
          if (ov2) ov2.classList.remove("view-only");
        }
        await transitionHostToLiveBroadcast();
        // Stop leftover preview mic/cam so browser AEC is not fighting a second capture (echo).
        if (typeof clearLocalPreviewStream === "function") {
          clearLocalPreviewStream();
        }
        // Always publish mic so students can hear the teacher.
        try { await setMic(true); } catch (e) {}
        if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
        if (typeof addChatMessage === "function") {
          addChatMessage("", "You are live — students can see and hear you now.", true);
        }
      } else {
        window.studentMicAllowed = !!(liveSession && liveSession.mic_allowed);
        window.studentCameraAllowed = !!(liveSession && liveSession.camera_allowed);
        if (typeof syncStudentMicState === "function") syncStudentMicState(window.studentMicAllowed);
        micOn = false;
        camOn = false;
        if (typeof updateMediaButton === "function") {
          updateMediaButton(document.getElementById("btn-mic"), false);
          updateMediaButton(document.getElementById("btn-cam"), false);
        }
        var micBtnStu = document.getElementById("btn-mic");
        var camBtnStu = document.getElementById("btn-cam");
        if (micBtnStu) micBtnStu.disabled = !window.studentMicAllowed;
        if (camBtnStu) camBtnStu.disabled = !window.studentCameraAllowed;
        if (typeof syncStudentMediaControls === "function") syncStudentMediaControls();
        if (!liveRoom.remoteParticipants.size) {
          if (typeof showVideoPlaceholder === "function") {
            showVideoPlaceholder("Waiting for the teacher to start video…");
          }
        }
        reattachTeacherAudio();
        await ensureRoomAudioPlayback();
      }
    } catch (err) {
      liveVideoJoined = false;
      if (isTeacherRole()) {
        liveRoom = null;
      } else if (liveRoom) {
        try { await liveRoom.disconnect(); } catch (eDisc) { /* ignore */ }
        liveRoom = null;
      }
      if (!isRetry) {
        var errMsg = err && err.message ? String(err.message) : "error";
        enterChatOnlyMode(
          isTeacherRole()
            ? "Video could not connect (" + errMsg + "). Chat and board still work."
            : errMsg
        );
      }
      scheduleLiveKitRetry();
    } finally {
      liveKitConnecting = false;
    }
  }

  function reportLocalMediaState() {
    try {
      if (typeof liveSocket !== "undefined" && liveSocket && liveSocket.readyState === 1) {
        liveSocket.send(JSON.stringify({
          event: "participant_media_state",
          cameraEnabled: !!camOn,
          microphoneEnabled: !!micOn,
        }));
      }
    } catch (e) { /* ignore */ }
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
      } else {
        if (typeof stopMicMonitor === "function") stopMicMonitor();
        if (typeof stopSelfHear === "function") stopSelfHear();
      }
      return;
    }

    if (!liveVideoJoined || !liveRoom) {
      var connected = await ensureLiveVideoReady(35000);
      if (!connected) {
        if (typeof showClassroomToast === "function") {
          showClassroomToast("Could not connect video — check network and tap Mic again", true);
        }
        if (typeof addChatMessage === "function") {
          addChatMessage("", "Video not connected — tap Mic again in a few seconds.", true);
        }
        return;
      }
    }
    var btn = document.getElementById("btn-mic");
    if (on === micOn && isLocalMicPublished() === on) return;
    if (!isTeacherRole() && on) {
      micOn = true;
      if (typeof updateMediaButton === "function") updateMediaButton(btn, true);
    }
    try {
      if (!isTeacherRole() && on) {
        var micReady = await ensureStudentPublishReady("mic");
        if (!micReady) throw new Error("Mic not approved yet — wait a moment and tap again");
      }
      await publishWithRetries("mic", on);
      micOn = on;
      if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    } catch (e) {
      if (!isTeacherRole() && on) {
        micOn = false;
        if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
        if (typeof showClassroomToast === "function") {
          showClassroomToast(friendlyMediaError(e, "mic"), true);
        }
        throw e;
      }
      throw e;
    }
    micOn = on;
    if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    reportLocalMediaState();
    if (on) {
      var track = getLocalMicTrack();
      if (track && typeof startMicMonitor === "function") startMicMonitor(track);
    } else {
      if (typeof stopMicMonitor === "function") stopMicMonitor();
      if (typeof stopSelfHear === "function") stopSelfHear();
    }
  }

  function friendlyMediaError(err, kind) {
    var msg = String((err && err.message) || err || "").toLowerCase();
    var name = String((err && err.name) || "");
    if (name === "NotAllowedError" || msg.indexOf("permission") >= 0 || msg.indexOf("denied") >= 0) {
      return kind === "mic"
        ? "Microphone access is blocked. Allow mic in browser/device settings."
        : "Camera access is blocked. Allow camera in browser/device settings.";
    }
    if (name === "NotFoundError" || msg.indexOf("not found") >= 0 || msg.indexOf("device") >= 0) {
      return kind === "mic" ? "No microphone found on this device." : "No camera found on this device.";
    }
    if (msg.indexOf("timeout") >= 0 || msg.indexOf("publication of local") >= 0 || msg.indexOf("no response") >= 0) {
      return kind === "mic"
        ? "Mic is slow — tap Mic again. Allow mic in browser settings if asked."
        : "Camera is slow — tap Cam again. Allow camera in browser settings if asked.";
    }
    return (err && err.message) || (kind === "mic" ? "Could not use microphone." : "Could not use camera.");
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
      if (on) {
        if (isTeacherRole() && localEl) {
          localEl.classList.remove("hidden");
        } else if (!isTeacherRole() && typeof showStudentSelfPreview === "function") {
          showStudentSelfPreview(videoTrack);
        }
      } else {
        if (localEl) localEl.classList.add("hidden");
        if (!isTeacherRole() && typeof hideStudentSelfPreview === "function") {
          hideStudentSelfPreview();
        }
      }
      return;
    }

    if (!liveVideoJoined || !liveRoom) {
      var camConnected = await ensureLiveVideoReady(35000);
      if (!camConnected) {
        if (typeof showClassroomToast === "function") {
          showClassroomToast("Could not connect video — tap Cam again", true);
        }
        return;
      }
    }
    var btn = document.getElementById("btn-cam");
    var localEl = document.getElementById("video-local");
    var c = lk();
    var hasLiveCamPub = false;
    if (c && liveRoom.localParticipant) {
      var camPub = liveRoom.localParticipant.getTrackPublication(c.Track.Source.Camera);
      hasLiveCamPub = !!(camPub && camPub.track && !camPub.isMuted);
    }
    if (on === camOn && !screenOn && hasLiveCamPub === on) return;
    if (on && screenOn) await setScreenShare(false);
    if (!isTeacherRole() && on) {
      camOn = true;
      if (typeof updateMediaButton === "function") updateMediaButton(btn, true);
    }
    try {
      if (!isTeacherRole() && on) {
        var camReady = await ensureStudentPublishReady("cam");
        if (!camReady) throw new Error("Camera not approved yet — wait a moment and tap again");
      }
      await publishWithRetries("cam", on);
    } catch (e) {
      camOn = false;
      if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
      var friendly = friendlyMediaError(e, "cam");
      if (typeof showClassroomToast === "function") {
        showClassroomToast(friendly, true);
      }
      if (typeof showVideoPlaceholder === "function" && isTeacherRole()) {
        showVideoPlaceholder(friendly);
      }
      throw e;
    }
    camOn = on;
    if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    reportLocalMediaState();
    if (on) {
      attachLocalCameraPreview();
      if (isTeacherRole()) {
        refreshTeacherVideoLayout();
        if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
        if (typeof addChatMessage === "function") {
          addChatMessage("", "Camera is live — students can see you on the main screen.", true);
        }
      }
    } else {
      if (localEl) localEl.classList.add("hidden");
      if (!isTeacherRole() && typeof hideStudentSelfPreview === "function") {
        hideStudentSelfPreview();
      }
      if (!screenOn && typeof showVideoPlaceholder === "function") {
        showVideoPlaceholder(isTeacherRole() ? "Camera off." : "Waiting for the teacher…");
      }
    }
  }

  async function setScreenShare(on) {
    if (!liveVideoJoined || !liveRoom) return;
    var btn = document.getElementById("btn-share");
    if (on) {
      // Prefer audio+video screen share when the browser allows it
      try {
        await liveRoom.localParticipant.setScreenShareEnabled(true, {
          audio: true,
          resolution: { width: 1920, height: 1080, frameRate: 15 },
        });
      } catch (eOpts) {
        await liveRoom.localParticipant.setScreenShareEnabled(true);
      }
      screenOn = true;
      if (camOn) {
        try {
          await liveRoom.localParticipant.setCameraEnabled(false);
        } catch (eCam) { /* ignore */ }
      }
      if (!micOn) {
        try {
          await liveRoom.localParticipant.setMicrophoneEnabled(true, AUDIO_CAPTURE_OPTS);
          micOn = true;
          if (typeof updateMediaButton === "function") {
            updateMediaButton(document.getElementById("btn-mic"), true);
          }
        } catch (eMic) { /* ignore */ }
      }
      attachLocalScreenPreview();
      var screenReady = document.getElementById("video-remote") &&
        document.getElementById("video-remote").querySelector("video");
      if (!screenReady) {
        for (var waitI = 0; waitI < 20; waitI++) {
          await new Promise(function (r) { setTimeout(r, 50); });
          attachLocalScreenPreview();
          screenReady = document.getElementById("video-remote") &&
            document.getElementById("video-remote").querySelector("video");
          if (screenReady) break;
        }
      }
      if (typeof window.syncMainStageLayers === "function") window.syncMainStageLayers();
      attachExistingRemoteTracks();
      if (typeof updateMediaButton === "function") updateMediaButton(btn, true);
      if (typeof addChatMessage === "function") {
        addChatMessage("", "You are sharing your screen — students should see it on the main screen.", true);
      }
      if (typeof applySpotlight === "function") applySpotlight("screen", false);
      // Tell students via chat WS so they force-subscribe / hide board
      try {
        if (typeof liveSocket !== "undefined" && liveSocket && liveSocket.readyState === 1) {
          liveSocket.send(JSON.stringify({ event: "screen_share", active: true }));
        }
      } catch (eWs) { /* ignore */ }
    } else {
      await liveRoom.localParticipant.setScreenShareEnabled(false);
      screenOn = false;
      var wrap = document.getElementById("video-remote");
      if (wrap) {
        wrap.classList.remove("screen-active");
        wrap.innerHTML = "";
      }
      if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
      var localEl = document.getElementById("video-local");
      if (localEl) localEl.classList.add("hidden");
      if (typeof applySpotlight === "function") applySpotlight("teacher", false);
      try {
        if (typeof liveSocket !== "undefined" && liveSocket && liveSocket.readyState === 1) {
          liveSocket.send(JSON.stringify({ event: "screen_share", active: false }));
        }
      } catch (eWs2) { /* ignore */ }
    }
  }

  async function toggleMic() {
    if (typeof unlockClassAudio === "function") unlockClassAudio();
    if (!isTeacherRole() && window.classPermissions && classPermissions.studentsCanUseMicrophone === false && !window.studentMicAllowed) {
      if (typeof showClassroomToast === "function") showClassroomToast("Mic is disabled by the teacher", true);
      return;
    }
    if (!isTeacherRole() && !window.studentMicAllowed) {
      if (typeof showClassroomToast === "function") {
        showClassroomToast("Raise your hand — teacher must allow your mic first", true);
      }
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Raise your hand and wait for the teacher to allow your mic.", true);
      }
      return;
    }
    if (!isTeacherRole() && mediaMode === "local" && window.localPreviewStream) {
      if (typeof showClassroomToast === "function") {
        showClassroomToast("Wait for the teacher to allow your mic", true);
      }
      return;
    }
    if (!liveVideoJoined || !liveRoom) {
      if (typeof showClassroomToast === "function") showClassroomToast("Connecting audio…", true);
      var connected = await ensureLiveVideoReady(35000);
      if (!connected) {
        if (typeof showClassroomToast === "function") {
          showClassroomToast("Could not connect — tap Mic again", true);
        }
        return;
      }
    }
    try {
      await setMic(!micOn);
    } catch (e) {
      var m2 = friendlyMediaError(e, "mic");
      if (typeof showClassroomToast === "function") showClassroomToast(m2, true);
      if (typeof addChatMessage === "function") addChatMessage("", m2, true);
    }
  }

  async function toggleCam() {
    if (typeof unlockClassAudio === "function") unlockClassAudio();
    if (!isTeacherRole() && window.classPermissions && classPermissions.studentsCanUseCamera === false && !window.studentCameraAllowed) {
      if (typeof showClassroomToast === "function") showClassroomToast("Camera is disabled by the teacher", true);
      return;
    }
    if (!isTeacherRole() && !window.studentCameraAllowed) {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Raise your hand and wait for the teacher to allow your camera.", true);
      }
      return;
    }
    if (!isTeacherRole() && mediaMode === "local" && window.localPreviewStream) {
      if (typeof showClassroomToast === "function") {
        showClassroomToast("Wait for the teacher to allow your camera", true);
      }
      return;
    }
    if (!liveVideoJoined || !liveRoom) {
      if (typeof showClassroomToast === "function") showClassroomToast("Connecting camera…", true);
      var camConnected = await ensureLiveVideoReady(35000);
      if (!camConnected) {
        if (typeof showClassroomToast === "function") {
          showClassroomToast("Could not connect — tap Cam again", true);
        }
        return;
      }
    }
    try {
      await setCam(!camOn);
    } catch (e) {
      var c2 = friendlyMediaError(e, "cam");
      if (typeof showClassroomToast === "function") showClassroomToast(c2, true);
      if (typeof addChatMessage === "function") addChatMessage("", c2, true);
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

  async function enableStudentMic(opts) {
    opts = opts || {};
    if (isLocalMicPublished()) {
      micOn = true;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-mic"), true);
      }
      return;
    }
    if (window._sxMicEnableBusy) {
      var busyMs = Date.now() - (window._sxMicEnableBusyAt || 0);
      if (busyMs < 15000) return;
    }
    window._sxMicEnableBusy = true;
    window._sxMicEnableBusyAt = Date.now();
    applyLocalMicGrant();
    if (!opts.silent) {
      micOn = true;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-mic"), true);
      }
    }
    if (!opts.silent && typeof showClassroomToast === "function") {
      showClassroomToast("Turning on your mic…");
    }
    try {
      if (!await ensureLiveVideoReady(20000, { silent: true })) {
        throw new Error("Video not connected — tap Mic to retry");
      }
      if (typeof refreshLiveKitToken === "function") await refreshLiveKitToken();
      if (typeof refreshRoomToken === "function") await refreshRoomToken();
      if (!await ensureStudentPublishReady("mic")) {
        throw new Error("Server has not approved your mic yet — wait a few seconds");
      }
      micOn = false;
      await publishWithRetries("mic", true);
      micOn = true;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-mic"), true);
      }
      if (typeof reattachTeacherAudio === "function") reattachTeacherAudio();
      await ensureRoomAudioPlayback();
      if (!opts.silent && typeof showClassroomToast === "function") {
        showClassroomToast("Mic is on — you can speak");
      }
    } catch (e) {
      applyLocalMicGrant();
      micOn = false;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-mic"), false);
      }
      var micMsg = friendlyMediaError(e, "mic");
      if (!opts.silent && typeof showClassroomToast === "function") {
        showClassroomToast(micMsg, true);
      }
      if (!opts.silent && typeof addChatMessage === "function") {
        addChatMessage("", micMsg, true);
      }
    } finally {
      window._sxMicEnableBusy = false;
    }
  }

  async function disableStudentMic() {
    window.studentMicAllowed = false;
    if (typeof syncStudentMicState === "function") syncStudentMicState(false);
    liveSession = window.liveSession || liveSession;
    if (liveSession) {
      liveSession.mic_allowed = false;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    }
    try {
      await publishMicrophoneEnabled(false);
      micOn = false;
      await refreshLiveKitToken();
      await refreshRoomToken();
    } catch (e) { /* ignore */ }
    if (typeof updateMediaButton === "function") {
      updateMediaButton(document.getElementById("btn-mic"), false);
    }
    var micBtn = document.getElementById("btn-mic");
    if (micBtn) micBtn.disabled = true;
  }

  async function enableStudentCamera(opts) {
    opts = opts || {};
    if (isLocalCamPublished()) {
      camOn = true;
      attachLocalCameraPreview();
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-cam"), true);
      }
      return;
    }
    window.studentCameraAllowed = true;
    liveSession = window.liveSession || liveSession;
    if (liveSession) {
      liveSession.camera_allowed = true;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    }
    if (!opts.silent) {
      camOn = true;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-cam"), true);
      }
      if (typeof showClassroomToast === "function") {
        showClassroomToast("Turning on your camera…");
      }
    }
    try {
      if (!await ensureLiveVideoReady(20000, { silent: true })) {
        throw new Error("Video not connected — tap Cam to retry");
      }
      if (typeof refreshLiveKitToken === "function") await refreshLiveKitToken();
      if (typeof refreshRoomToken === "function") await refreshRoomToken();
      if (!await ensureStudentPublishReady("cam")) {
        throw new Error("Server has not approved your camera yet — wait a few seconds");
      }
      if (typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(true);
      var camBtn = document.getElementById("btn-cam");
      if (camBtn) camBtn.disabled = false;
      camOn = false;
      await publishWithRetries("cam", true);
      camOn = true;
      attachLocalCameraPreview();
      if (typeof updateMediaButton === "function") {
        updateMediaButton(camBtn, true);
      }
      reportLocalMediaState();
      if (!opts.silent && typeof showClassroomToast === "function") {
        showClassroomToast("Camera is on");
      }
    } catch (e) {
      camOn = false;
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-cam"), false);
      }
      var camMsg = friendlyMediaError(e, "cam");
      if (!opts.silent && typeof showClassroomToast === "function") {
        showClassroomToast(camMsg, true);
      }
      if (!opts.silent && typeof addChatMessage === "function") {
        addChatMessage("", camMsg, true);
      }
    }
  }

  async function disableStudentCamera() {
    window.studentCameraAllowed = false;
    try {
      await publishCameraEnabled(false);
      camOn = false;
      await refreshLiveKitToken();
      await refreshRoomToken();
    } catch (e) { /* ignore */ }
    if (typeof updateMediaButton === "function") {
      updateMediaButton(document.getElementById("btn-cam"), false);
    }
    var camBtn = document.getElementById("btn-cam");
    if (camBtn) camBtn.disabled = true;
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
        if (pub.track && pub.track.mediaStreamTrack && !pub.isMuted && !pub.track.isMuted) {
          ms.addTrack(pub.track.mediaStreamTrack);
        }
      });
    });
    return ms.getTracks().length ? ms : null;
  }

  function getLocalClassRecordStream() {
    if (!liveRoom || !liveVideoJoined) return null;
    var ms = new MediaStream();
    var remote = getRemoteClassMediaStream();
    if (remote) {
      remote.getTracks().forEach(function (t) { ms.addTrack(t); });
    }
    try {
      var c = lk();
      if (c && liveRoom.localParticipant) {
        liveRoom.localParticipant.trackPublications.forEach(function (pub) {
          if (!pub.track || !pub.track.mediaStreamTrack || pub.isMuted || pub.track.isMuted) return;
          if (pub.kind === c.Track.Kind.Audio || pub.kind === "audio" ||
              pub.kind === c.Track.Kind.Video || pub.kind === "video") {
            ms.addTrack(pub.track.mediaStreamTrack);
          }
        });
      }
    } catch (e) { /* ignore */ }
    return ms.getTracks().length ? ms : null;
  }

  async function disconnectLiveVideo() {
    stopLiveKitRetry();
    if (window._sxAudioKeepAlive) {
      clearInterval(window._sxAudioKeepAlive);
      window._sxAudioKeepAlive = null;
    }
    if (window._sxVideoKeepAlive) {
      clearInterval(window._sxVideoKeepAlive);
      window._sxVideoKeepAlive = null;
    }
    if (tokenRefreshTimer) {
      clearInterval(tokenRefreshTimer);
      tokenRefreshTimer = null;
    }
    if (liveRoom) {
      try { await liveRoom.disconnect(); } catch (e) { /* ignore */ }
    }
    pruneRemoteAudioElements();
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
      if (!isTeacherRole() && typeof maybeHideJoinOverlay === "function") {
        maybeHideJoinOverlay();
      }
      // Connect immediately — never wait on /livekit/status (Render cold starts hang it).
      if (isTeacherRole() && typeof startLocalPreviewOnly === "function") {
        startLocalPreviewOnly().catch(function () {});
      }
      tryConnectLiveVideo();
      checkLiveKitServerConfig().then(function () {
        if (!liveVideoJoined) tryConnectLiveVideo(true);
      });
    });
  }

  function looksLikeUuid(value) {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      String(value || "").trim()
    );
  }

  function resolveRosterDisplayName(participant) {
    if (!participant) return "Student";
    var pid = String(participant.identity || "");
    var n = String(participant.name || "").trim();
    if (n && n.toLowerCase() !== "student" && !looksLikeUuid(n)) return n;
    if (typeof window.resolveStudentDisplayName === "function") {
      return window.resolveStudentDisplayName({ student_id: pid, name: n });
    }
    if (window.__participantNames && pid && window.__participantNames[pid]) {
      return window.__participantNames[pid];
    }
    return "Student";
  }

  function listRemoteRosterParticipants() {
    if (!liveRoom) return [];
    var out = [];
    liveRoom.remoteParticipants.forEach(function (p) {
      out.push({
        student_id: String(p.identity || ""),
        name: resolveRosterDisplayName(p),
        mic_allowed: !!(p.isMicrophoneEnabled || (p.audioTrackPublications && p.audioTrackPublications.size)),
        camera_allowed: !!(p.isCameraEnabled || (p.videoTrackPublications && p.videoTrackPublications.size)),
        is_teacher: isTeacherParticipant(p) || participantRoleFromMeta(p) === "teacher",
      });
    });
    return out;
  }

  window.isLocalMicPublished = isLocalMicPublished;
  window.isLocalCamPublished = isLocalCamPublished;
  window.LiveClassMedia = {
    isJoined: isJoined,
    getMediaMode: getMediaMode,
    getMicOn: function () { return micOn; },
    getCamOn: function () { return camOn; },
    setMicState: function (v) { micOn = v; },
    setCamState: function (v) { camOn = v; },
    listRemoteRoster: listRemoteRosterParticipants,
    reattachRemoteTracks: attachExistingRemoteTracks,
  };

  window.ensureLiveVideoReady = ensureLiveVideoReady;
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
  window.enableStudentCamera = enableStudentCamera;
  window.disableStudentCamera = disableStudentCamera;
  window.ensureRoomAudioPlayback = ensureRoomAudioPlayback;
  window.applyStudentMediaPermissions = applyStudentMediaPermissions;
  window.countVideoAudience = countVideoAudience;
  window.getRemoteClassMediaStream = getRemoteClassMediaStream;
  window.getLocalClassRecordStream = getLocalClassRecordStream;
  window.reattachParticipantVideos = reattachParticipantVideos;
  window.reattachTeacherMainStage = reattachTeacherMainStage;
  window.reattachTeacherScreenShare = reattachTeacherScreenShare;
  window.remoteTeacherScreenActive = remoteTeacherScreenActive;
  window.reattachRemoteClassAudio = reattachRemoteClassAudio;
  window.reattachTeacherAudio = reattachTeacherAudio;
  window.syncRemoteSubscriptions = syncRemoteSubscriptions;
  window.attachExistingRemoteTracks = attachExistingRemoteTracks;
})();
