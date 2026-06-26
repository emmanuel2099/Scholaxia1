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
      if (data.mic_allowed) liveSession.mic_allowed = true;
      if (data.can_publish) liveSession.can_publish = true;
      if (typeof applyStudentMediaPermissions === "function") applyStudentMediaPermissions(data);
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
        if (typeof showAudioUnlockBanner === "function") {
          showAudioUnlockBanner();
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
      if (typeof showAudioUnlockBanner === "function") showAudioUnlockBanner();
    }
    remoteAudioEls.forEach(playRemoteAudioElement);
  }

  function applyStudentMediaPermissions(data) {
    if (isTeacherRole() || !data) return;
    if (data.mic_allowed) {
      window.studentMicAllowed = true;
      if (typeof syncStudentMicState === "function") syncStudentMicState(true);
    }
    if (data.camera_allowed) {
      window.studentCameraAllowed = true;
    }
    if (data.can_publish && liveSession) {
      liveSession.can_publish = true;
      liveSession.mic_allowed = !!data.mic_allowed;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    } else if (data.mic_allowed && liveSession) {
      liveSession.mic_allowed = true;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    }
    if (typeof setVideoControlsEnabled === "function" && liveVideoJoined) {
      var canMic = window.studentMicAllowed;
      var canCam = window.studentCameraAllowed;
      setVideoControlsEnabled(canMic || canCam);
      var micBtn = document.getElementById("btn-mic");
      var camBtn = document.getElementById("btn-cam");
      if (micBtn) micBtn.disabled = !canMic;
      if (camBtn) camBtn.disabled = !canCam;
    }
  }

  function attachRemoteAudio(track, participant) {
    var c = lk();
    if (!track || !c) return;
    var pid = participant && participant.identity ? String(participant.identity) : "remote";
    remoteAudioEls = remoteAudioEls.filter(function (el) {
      if (el && el.getAttribute && el.getAttribute("data-participant-id") === pid) {
        try { el.remove(); } catch (e) { /* ignore */ }
        return false;
      }
      return true;
    });
    var audioWrap = ensureRemoteAudioContainer();
    var audioEl = track.attach();
    audioEl.setAttribute("data-participant-id", pid);
    audioWrap.appendChild(audioEl);
    remoteAudioEls.push(audioEl);
    playRemoteAudioElement(audioEl);
    ensureRoomAudioPlayback();
    if (isTeacherRole()) {
      if (typeof setStatus === "function") {
        setStatus("Connected — you can hear students when they speak");
      }
      if (typeof showAudioUnlockBanner === "function" && liveRoom && liveRoom.canPlaybackAudio === false) {
        showAudioUnlockBanner();
      }
    } else {
      if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
      if (typeof setStatus === "function") setStatus("Connected — you can hear the teacher");
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
    return normalizeParticipantId(participant.identity);
  }

  function getTeacherIdFromSession() {
    var sess = window.liveSession || (typeof loadLiveSession === "function" ? loadLiveSession() : null);
    if (!sess) return null;
    return sess.teacher_id || sess.teacherId || null;
  }

  function isTeacherParticipant(participant) {
    if (!participant || isTeacherRole()) return false;
    var teacherId = getTeacherIdFromSession();
    var pid = String(participant.identity || "");
    if (teacherId) {
      return pid === String(teacherId) || pid.toLowerCase() === String(teacherId).toLowerCase();
    }
    var sess = window.liveSession || {};
    var selfId = sess.identity || sess.user_id || "";
    if (selfId && pid === String(selfId)) return false;
    if (liveRoom && liveRoom.remoteParticipants.size === 1) {
      return pid !== String(selfId);
    }
    return false;
  }

  function clearStudentParticipantVideo(studentId, publication, participant) {
    if (studentId) {
      delete participantVideoTracks[studentId];
      if (typeof detachParticipantCameraVideo === "function") {
        detachParticipantCameraVideo(studentId);
      }
    }
  }

  function attachRemoteVideoToMainStage(track, publication) {
    if (typeof hideVideoPlaceholder === "function") hideVideoPlaceholder();
    var wrap = document.getElementById("video-remote");
    if (!wrap) return;
    var isScreen = isScreenPublication(publication);
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

  function clearMainStageVideo() {
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

  function reattachParticipantVideos() {
    if (!isTeacherRole()) return;
    Object.keys(participantVideoTracks).forEach(function (studentId) {
      var entry = participantVideoTracks[studentId];
      if (typeof isParticipantVideoLive === "function" && !isParticipantVideoLive(entry)) {
        clearStudentParticipantVideo(studentId);
        return;
      }
      if (entry && entry.track && typeof attachParticipantCameraVideo === "function") {
        attachParticipantCameraVideo(studentId, entry.track);
      }
    });
  }

  function reattachTeacherMainStage() {
    if (isTeacherRole() || !teacherVideoTrack) return;
    if (typeof isParticipantVideoLive === "function" && !isParticipantVideoLive(teacherVideoTrack)) {
      teacherVideoTrack = null;
      clearMainStageVideo();
      return;
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
        if (studentId && typeof attachParticipantCameraVideo === "function") {
          participantVideoTracks[studentId] = { track: track, publication: publication, participant: participant };
          attachParticipantCameraVideo(studentId, track);
        }
        return;
      }
      if (!isTeacherRole() && isCameraPublication(publication)) {
        if (isTeacherParticipant(participant)) {
          teacherVideoTrack = { track: track, publication: publication, participant: participant };
          attachRemoteVideoToMainStage(track, publication);
        }
        return;
      }
      attachRemoteVideoToMainStage(track, publication);
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
      clearMainStageVideo();
      return;
    }

    if (!isTeacherRole() && isCameraPublication(publication)) {
      return;
    }

    clearMainStageVideo();
  }

  function handleRemoteCameraMuted(publication, participant) {
    if (!isCameraPublication(publication)) return;
    if (isTeacherRole()) {
      var studentId = resolveStudentIdFromParticipant(participant);
      clearStudentParticipantVideo(studentId, publication, participant);
    } else if (isTeacherParticipant(participant)) {
      teacherVideoTrack = null;
      clearMainStageVideo();
    }
  }

  function attachExistingRemoteTracks() {
    if (!liveRoom) return;
    liveRoom.remoteParticipants.forEach(function (participant) {
      wireParticipantVideoEvents(participant);
      participant.trackPublications.forEach(function (pub) {
        if (pub.track) attachRemoteTrack(pub.track, pub, participant);
      });
    });
  }

  function attachLocalCameraPreview() {
    if (!liveRoom) return;
    var c = lk();
    if (!c) return;
    var localEl = document.getElementById("video-local");
    liveRoom.localParticipant.videoTrackPublications.forEach(function (pub) {
      if (!isCameraPublication(pub) || !pub.track) return;
      if (isTeacherRole()) {
        if (!localEl) return;
        localEl.innerHTML = "";
        var el = pub.track.attach();
        el.style.width = "100%";
        el.style.height = "100%";
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
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.TrackUnsubscribed, function (track, publication, participant) {
      detachRemoteVideo(track, publication, participant);
    });
    room.on(c.RoomEvent.TrackMuted, function (publication, participant) {
      handleRemoteCameraMuted(publication, participant);
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
    room.on(c.RoomEvent.ParticipantConnected, function (participant) {
      wireParticipantVideoEvents(participant);
      participant.trackPublications.forEach(function (pub) {
        if (pub.track) attachRemoteTrack(pub.track, pub, participant);
      });
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.ParticipantDisconnected, function (participant) {
      if (isTeacherRole()) {
        var studentId = resolveStudentIdFromParticipant(participant);
        if (studentId && participantVideoTracks[studentId]) {
          delete participantVideoTracks[studentId];
          if (typeof detachParticipantCameraVideo === "function") {
            detachParticipantCameraVideo(studentId);
          }
        }
      }
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.LocalTrackPublished, function (publication) {
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
    });
    room.on(c.RoomEvent.Connected, function () {
      scheduleTokenRefresh();
      ensureRoomAudioPlayback();
    });
    if (c.RoomEvent.AudioPlaybackStatusChanged) {
      room.on(c.RoomEvent.AudioPlaybackStatusChanged, function () {
        if (liveRoom && liveRoom.canPlaybackAudio === false) {
          if (typeof showAudioUnlockBanner === "function") showAudioUnlockBanner();
        }
      });
    }
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
    var wantMic = true;
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
        var canMic = isTeacherRole() || window.studentMicAllowed;
        var canCam = isTeacherRole() || window.studentCameraAllowed;
        setVideoControlsEnabled(canMic || canCam);
        var micBtn = document.getElementById("btn-mic");
        var camBtn = document.getElementById("btn-cam");
        if (micBtn) micBtn.disabled = !canMic;
        if (camBtn) camBtn.disabled = !canCam;
      }
      ensureRoomAudioPlayback();
      if (isTeacherRole() && liveRoom && liveRoom.canPlaybackAudio === false) {
        if (typeof showAudioUnlockBanner === "function") showAudioUnlockBanner();
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

    if (!liveVideoJoined || !liveRoom) return;
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
    try {
      await liveRoom.localParticipant.setCameraEnabled(on);
    } catch (e) {
      camOn = false;
      if (typeof updateMediaButton === "function") updateMediaButton(btn, false);
      if (typeof showClassroomToast === "function") {
        showClassroomToast(
          isTeacherRole()
            ? "Could not turn on camera. Close other apps using the camera and try again."
            : "Camera error: " + (e.message || "Try again."),
          true
        );
      }
      throw e;
    }
    camOn = on;
    if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    if (on) {
      attachLocalCameraPreview();
      if (isTeacherRole()) {
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
      await liveRoom.localParticipant.setScreenShareEnabled(true);
      screenOn = true;
      if (camOn) await liveRoom.localParticipant.setCameraEnabled(false);
      if (!micOn) {
        await liveRoom.localParticipant.setMicrophoneEnabled(true);
        micOn = true;
        if (typeof updateMediaButton === "function") {
          updateMediaButton(document.getElementById("btn-mic"), true);
        }
      }
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
    if (!isTeacherRole() && !window.studentCameraAllowed) {
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Raise your hand and wait for the teacher to allow your camera.", true);
      }
      return;
    }
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
    if (typeof syncStudentMicState === "function") syncStudentMicState(true);
    liveSession = window.liveSession || liveSession;
    if (liveSession) {
      liveSession.mic_allowed = true;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    }
    if (typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(true);
    var micBtn = document.getElementById("btn-mic");
    if (micBtn) micBtn.disabled = false;
    if (typeof showClassroomToast === "function") {
      showClassroomToast("You can speak now — mic turning on");
    }
    if (typeof addChatMessage === "function") {
      addChatMessage("", "Your teacher let you speak. Turning on your mic…", true);
    }
    try {
      var tokenOk = await refreshLiveKitToken();
      if (!tokenOk) throw new Error("Could not refresh permissions");
      if (!liveSession.mic_allowed && !liveSession.can_publish) {
        throw new Error("Server has not approved your mic yet — wait a few seconds");
      }
      if (!liveVideoJoined || !liveRoom) {
        await tryConnectLiveVideo(true);
      } else {
        await reconnectWithFreshToken();
      }
      micOn = false;
      await setMic(true);
      if (!micOn) {
        await reconnectWithFreshToken();
        micOn = false;
        await setMic(true);
      }
      if (typeof updateMediaButton === "function") {
        updateMediaButton(document.getElementById("btn-mic"), true);
      }
      if (typeof showClassroomToast === "function") {
        showClassroomToast("Mic is on — you can speak");
      }
    } catch (e) {
      if (micBtn) micBtn.disabled = false;
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Mic allowed — tap the Mic button to speak. (" + (e.message || "") + ")", true);
      }
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
    var micBtn = document.getElementById("btn-mic");
    if (micBtn) micBtn.disabled = true;
  }

  async function enableStudentCamera() {
    window.studentCameraAllowed = true;
    if (typeof showClassroomToast === "function") {
      showClassroomToast("Camera access approved — you can turn on your camera");
    }
    if (typeof addChatMessage === "function") {
      addChatMessage("", "Your teacher let you use your camera.", true);
    }
    try {
      await refreshLiveKitToken();
      await reconnectWithFreshToken();
      var camBtn = document.getElementById("btn-cam");
      if (camBtn) camBtn.disabled = false;
    } catch (e) {
      if (typeof addChatMessage === "function") addChatMessage("", "Camera: " + e.message, true);
    }
  }

  async function disableStudentCamera() {
    window.studentCameraAllowed = false;
    try {
      await setCam(false);
      await refreshLiveKitToken();
      await reconnectWithFreshToken();
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
  window.enableStudentCamera = enableStudentCamera;
  window.disableStudentCamera = disableStudentCamera;
  window.ensureRoomAudioPlayback = ensureRoomAudioPlayback;
  window.applyStudentMediaPermissions = applyStudentMediaPermissions;
  window.countVideoAudience = countVideoAudience;
  window.getRemoteClassMediaStream = getRemoteClassMediaStream;
  window.reattachParticipantVideos = reattachParticipantVideos;
  window.reattachTeacherMainStage = reattachTeacherMainStage;
})();
