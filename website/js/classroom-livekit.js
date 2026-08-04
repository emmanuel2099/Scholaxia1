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
  var MAX_SIDEBAR_VIDEOS = 9;
  var JOIN_TIMEOUT_MS = 45000;
  var PUBLISH_TIMEOUT_MS = 35000;
  var AUDIO_CAPTURE_OPTS = { echoCancellation: true, noiseSuppression: true, autoGainControl: true };

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
      if (data.camera_allowed) liveSession.camera_allowed = true;
      if (data.can_publish) liveSession.can_publish = true;
      if (data.teacher_id) liveSession.teacher_id = data.teacher_id;
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
      liveSession.camera_allowed = !!data.camera_allowed;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    } else {
      if (data.mic_allowed && liveSession) {
        liveSession.mic_allowed = true;
        if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
      }
      if (data.camera_allowed && liveSession) {
        liveSession.camera_allowed = true;
        if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
      }
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

  function detachRemoteAudio(participant) {
    var pid = participant && participant.identity ? String(participant.identity) : "";
    if (!pid) return;
    remoteAudioEls = remoteAudioEls.filter(function (el) {
      if (el && el.getAttribute && el.getAttribute("data-participant-id") === pid) {
        try {
          if (el.srcObject) {
            el.srcObject.getTracks().forEach(function (t) {
              try { t.stop(); } catch (e) { /* ignore */ }
            });
          }
        } catch (e) { /* ignore */ }
        try { el.remove(); } catch (e2) { /* ignore */ }
        return false;
      }
      return true;
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

  function prioritizeSidebarVideoIds() {
    var raised = (typeof window.raisedHands === "object" && window.raisedHands) || {};
    var ids = Object.keys(participantVideoTracks);
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
    var keep = ranked.slice(0, MAX_SIDEBAR_VIDEOS);
    var keepSet = {};
    keep.forEach(function (id) { keepSet[id] = true; });
    sidebarVideoOrder = keep.slice();

    ranked.forEach(function (studentId) {
      var entry = participantVideoTracks[studentId];
      if (!entry) return;
      if (keepSet[studentId]) {
        setPublicationSubscribed(entry.publication, true);
        if (entry.track && typeof attachParticipantCameraVideo === "function") {
          attachParticipantCameraVideo(studentId, entry.track);
        }
      } else {
        setPublicationSubscribed(entry.publication, false);
        if (typeof detachParticipantCameraVideo === "function") {
          detachParticipantCameraVideo(studentId);
        }
      }
    });
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
    if (!audioEl) {
      audioEl = track.attach();
      audioEl.setAttribute("data-participant-id", pid);
      audioWrap.appendChild(audioEl);
      remoteAudioEls.push(audioEl);
    } else {
      try {
        track.attach(audioEl);
      } catch (e) {
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
    el.muted = true;
    el.autoplay = true;
    el.playsInline = true;
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
      }
    });
    applyStudentVideoBudget();
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
        }
        return;
      }
      if (!isTeacherRole() && isCameraPublication(publication)) {
        if (isTeacherParticipant(participant)) {
          teacherVideoTrack = { track: track, publication: publication, participant: participant };
          attachRemoteVideoToMainStage(track, publication);
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
    if (publication && publication.track && !publication.isMuted && !publication.track.isMuted) return;
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
      if (typeof updateAudienceStats === "function") updateAudienceStats();
    });
    room.on(c.RoomEvent.TrackUnsubscribed, function (track, publication, participant) {
      if (track && (track.kind === c.Track.Kind.Audio || track.kind === "audio")) {
        detachRemoteAudio(participant);
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
    room.on(c.RoomEvent.ParticipantConnected, function (participant) {
      wireParticipantVideoEvents(participant);
      participant.trackPublications.forEach(function (pub) {
        if (pub.track) attachRemoteTrack(pub.track, pub, participant);
      });
      if (typeof updateAudienceStats === "function") updateAudienceStats();
      if (typeof refreshLiveKitRoster === "function") refreshLiveKitRoster();
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
      if (typeof refreshLiveKitRoster === "function") refreshLiveKitRoster();
    });
    room.on(c.RoomEvent.LocalTrackPublished, function (publication) {
      if (publication && (publication.kind === c.Track.Kind.Audio || publication.kind === "audio")) {
        micOn = true;
        if (typeof updateMediaButton === "function") {
          updateMediaButton(document.getElementById("btn-mic"), true);
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

  async function disconnectAndReconnectRoom() {
    liveKitConnecting = false;
    if (liveRoom) {
      try {
        await liveRoom.disconnect();
      } catch (e) { /* ignore */ }
    }
    liveRoom = null;
    liveVideoJoined = false;
    await refreshLiveKitToken();
    await tryConnectLiveVideo(true);
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
      await disconnectAndReconnectRoom();
      return !!liveVideoJoined;
    }
    var refreshed = await refreshRoomToken();
    if (refreshed) return true;
    await disconnectAndReconnectRoom();
    return !!liveVideoJoined;
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
      await disconnectAndReconnectRoom();
      if (!liveVideoJoined) throw e;
      await run();
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
      await disconnectAndReconnectRoom();
      if (!liveVideoJoined) throw e;
      await run();
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
        var isHost = isTeacherRole();
        liveRoom = new c.Room({
          adaptiveStream: true,
          dynacast: true,
          audioCaptureDefaults: {
            echoCancellation: true,
            noiseSuppression: true,
            autoGainControl: true,
          },
          videoCaptureDefaults: {
            // Students publish lighter video; teacher can use HD for the main stage.
            resolution: isHost
              ? { width: 1280, height: 720, frameRate: 24 }
              : { width: 640, height: 360, frameRate: 20 },
          },
        });
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
      if (typeof refreshLiveKitRoster === "function") refreshLiveKitRoster();
      if (typeof setVideoControlsEnabled === "function") {
        var canMic = isTeacherRole() || window.studentMicAllowed || !!(liveSession && liveSession.mic_allowed);
        var canCam = isTeacherRole() || window.studentCameraAllowed || !!(liveSession && liveSession.camera_allowed);
        if (canMic && !isTeacherRole()) {
          window.studentMicAllowed = true;
        }
        setVideoControlsEnabled(canMic || canCam);
        var micBtn = document.getElementById("btn-mic");
        var camBtn = document.getElementById("btn-cam");
        if (micBtn) micBtn.disabled = !canMic;
        if (camBtn) camBtn.disabled = !canCam;
      }
      await ensureRoomAudioPlayback();
      if (liveRoom && liveRoom.canPlaybackAudio === false) {
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
      } else {
        // Open mic when already allowed so the teacher can hear this student.
        if ((window.studentMicAllowed || (liveSession && liveSession.mic_allowed)) && !micOn) {
          try {
            await setMic(true);
          } catch (micErr) { /* user gesture / permission may still be needed */ }
        }
        if (!liveRoom.remoteParticipants.size) {
          if (typeof showVideoPlaceholder === "function") {
            showVideoPlaceholder("Waiting for the teacher to start video…");
          }
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
      } else {
        if (typeof stopMicMonitor === "function") stopMicMonitor();
        if (typeof stopSelfHear === "function") stopSelfHear();
      }
      return;
    }

    if (!liveVideoJoined || !liveRoom) return;
    var btn = document.getElementById("btn-mic");
    if (on === micOn && isLocalMicPublished() === on) return;
    await publishMicrophoneEnabled(on);
    micOn = on;
    if (typeof updateMediaButton === "function") updateMediaButton(btn, on);
    if (on) {
      var track = getLocalMicTrack();
      if (track && typeof startMicMonitor === "function") startMicMonitor(track);
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
      await publishCameraEnabled(on);
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
        await liveRoom.localParticipant.setMicrophoneEnabled(true, AUDIO_CAPTURE_OPTS);
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
    if (!isTeacherRole() && window.studentMicAllowed && !micOn) {
      try {
        await refreshLiveKitToken();
        await ensurePublishPermissions(true);
      } catch (e) { /* setMic retry may still work */ }
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
    if (!isTeacherRole() && window.studentCameraAllowed && !camOn) {
      try {
        await refreshLiveKitToken();
        await ensurePublishPermissions(true);
      } catch (e) { /* setCam retry may still work */ }
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
      if (!liveSession.can_publish && !liveSession.mic_allowed) {
        await new Promise(function (r) { setTimeout(r, 600); });
        tokenOk = await refreshLiveKitToken();
        if (!tokenOk || (!liveSession.can_publish && !liveSession.mic_allowed)) {
          throw new Error("Server has not approved your mic yet — wait a few seconds");
        }
      }
      await ensurePublishPermissions(true);
      micOn = false;
      await setMic(true);
      if (!micOn || !isLocalMicPublished()) {
        await ensurePublishPermissions(true);
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
    liveSession = window.liveSession || liveSession;
    if (liveSession) {
      liveSession.camera_allowed = true;
      if (typeof persistLiveSession === "function") persistLiveSession(liveSession);
    }
    if (typeof showClassroomToast === "function") {
      showClassroomToast("Camera access approved — turning on your camera");
    }
    if (typeof addChatMessage === "function") {
      addChatMessage("", "Your teacher let you use your camera. Turning it on…", true);
    }
    try {
      var tokenOk = await refreshLiveKitToken();
      if (!tokenOk) throw new Error("Could not refresh permissions");
      if (!liveSession.can_publish && !liveSession.camera_allowed) {
        await new Promise(function (r) { setTimeout(r, 600); });
        tokenOk = await refreshLiveKitToken();
        if (!tokenOk || (!liveSession.can_publish && !liveSession.camera_allowed)) {
          throw new Error("Server has not approved your camera yet — wait a few seconds");
        }
      }
      await ensurePublishPermissions(true);
      if (typeof setVideoControlsEnabled === "function") setVideoControlsEnabled(true);
      var camBtn = document.getElementById("btn-cam");
      if (camBtn) camBtn.disabled = false;
      camOn = false;
      await setCam(true);
      if (!camOn || !isLocalCamPublished()) {
        await ensurePublishPermissions(true);
        camOn = false;
        await setCam(true);
      }
      if (typeof updateMediaButton === "function") {
        updateMediaButton(camBtn, true);
      }
      if (typeof showClassroomToast === "function") {
        showClassroomToast("Camera is on");
      }
    } catch (e) {
      var camBtnErr = document.getElementById("btn-cam");
      if (camBtnErr) camBtnErr.disabled = false;
      if (typeof addChatMessage === "function") {
        addChatMessage("", "Camera allowed — tap the Cam button. (" + (e.message || "") + ")", true);
      }
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

  function listRemoteRosterParticipants() {
    if (!liveRoom) return [];
    var out = [];
    liveRoom.remoteParticipants.forEach(function (p) {
      out.push({
        student_id: String(p.identity || ""),
        name: p.name || String(p.identity || "Participant"),
        mic_allowed: !!(p.isMicrophoneEnabled || (p.audioTrackPublications && p.audioTrackPublications.size)),
        camera_allowed: !!(p.isCameraEnabled || (p.videoTrackPublications && p.videoTrackPublications.size)),
        is_teacher: isTeacherParticipant(p) || participantRoleFromMeta(p) === "teacher",
      });
    });
    return out;
  }

  window.LiveClassMedia = {
    isJoined: isJoined,
    getMediaMode: getMediaMode,
    getMicOn: function () { return micOn; },
    getCamOn: function () { return camOn; },
    setMicState: function (v) { micOn = v; },
    setCamState: function (v) { camOn = v; },
    listRemoteRoster: listRemoteRosterParticipants,
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
  window.reattachRemoteClassAudio = attachExistingRemoteTracks;
})();
