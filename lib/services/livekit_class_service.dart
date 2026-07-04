import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:livekit_client/livekit_client.dart';

/// Manages a LiveKit room for live class video/audio.
class LiveKitClassService {
  LiveKitClassService({required this.onChanged});

  final VoidCallback onChanged;

  Room? room;
  EventsListener<RoomEvent>? _listener;

  VideoTrack? primaryRemoteVideo;
  VideoTrack? screenShareVideo;
  VideoTrack? cameraVideo;
  VideoTrack? localCameraVideo;
  String status = 'Connecting…';
  bool connected = false;
  bool screenShareOn = false;
  String? error;

  bool get showingScreenShare =>
      primaryRemoteVideo != null &&
      identical(primaryRemoteVideo, screenShareVideo);

  String get placeholderMessage {
    if (!connected) return status;
    if (localCameraVideo != null) return 'Your camera is live';
    if (screenShareVideo == null && cameraVideo == null) {
      return 'Video off — open board or share screen';
    }
    return 'Waiting for video…';
  }

  Future<void> connect({
    required String url,
    required String token,
    bool publishMic = false,
    bool publishCamera = false,
  }) async {
    await disconnect();

    final lkRoom = Room(
      roomOptions: const RoomOptions(
        adaptiveStream: true,
        dynacast: true,
        defaultAudioPublishOptions: AudioPublishOptions(name: 'microphone'),
        defaultVideoPublishOptions: VideoPublishOptions(name: 'camera'),
        defaultAudioCaptureOptions: AudioCaptureOptions(
          echoCancellation: true,
          noiseSuppression: true,
        ),
      ),
    );
    room = lkRoom;

    _listener = lkRoom.createListener()
      ..on<RoomConnectedEvent>((_) {
        connected = true;
        status = 'Connected';
        error = null;
        unawaited(_ensureAudioPlayback());
        _rescanAll();
      })
      ..on<RoomDisconnectedEvent>((_) {
        connected = false;
        onChanged();
      })
      ..on<TrackSubscribedEvent>((e) {
        if (e.track is AudioTrack) {
          unawaited(_ensureAudioPlayback());
        }
        _rescanAll();
      })
      ..on<TrackUnsubscribedEvent>((_) => _rescanAll())
      ..on<TrackMutedEvent>((_) => _rescanAll())
      ..on<TrackUnmutedEvent>((_) => _rescanAll())
      ..on<TrackPublishedEvent>((_) => _rescanAll())
      ..on<TrackUnpublishedEvent>((_) => _rescanAll())
      ..on<ParticipantConnectedEvent>((_) => _rescanAll())
      ..on<ParticipantDisconnectedEvent>((_) => _rescanAll())
      ..on<LocalTrackPublishedEvent>((_) => _scanLocal())
      ..on<LocalTrackUnpublishedEvent>((_) => _scanLocal());

    try {
      await lkRoom.connect(url, token);
      _rescanAll();

      if (publishMic) {
        await lkRoom.localParticipant?.setMicrophoneEnabled(true);
      }
      if (publishCamera) {
        await lkRoom.localParticipant?.setCameraEnabled(true);
      }
      _scanLocal();

      connected = true;
      status = 'Connected';
      error = null;
      unawaited(_ensureAudioPlayback());
    } catch (e) {
      connected = false;
      error = e.toString();
      status = 'Video connection failed';
    }
    onChanged();
  }

  Future<void> reconnect({
    required String url,
    required String token,
    bool micOn = false,
    bool camOn = false,
    bool shareOn = false,
  }) async {
    await room?.disconnect();
    primaryRemoteVideo = null;
    screenShareVideo = null;
    cameraVideo = null;
    localCameraVideo = null;
    screenShareOn = false;
    connected = false;
    onChanged();
    await connect(
      url: url,
      token: token,
      publishMic: micOn,
      publishCamera: camOn,
    );
    if (shareOn) {
      await setScreenShareEnabled(true);
    }
  }

  Future<void> setMicrophoneEnabled(bool enabled) async {
    await room?.localParticipant?.setMicrophoneEnabled(enabled);
    onChanged();
  }

  Future<void> setCameraEnabled(bool enabled) async {
    await room?.localParticipant?.setCameraEnabled(enabled);
    _scanLocal();
    onChanged();
  }

  Future<void> setScreenShareEnabled(bool enabled) async {
    try {
      await room?.localParticipant?.setScreenShareEnabled(enabled);
      screenShareOn = enabled;
      _scanLocal();
      _rescanAll();
    } catch (e) {
      error = e.toString();
    }
    onChanged();
  }

  Future<void> disconnect() async {
    _listener?.dispose();
    _listener = null;
    if (room != null) {
      await room!.disconnect();
      room!.dispose();
    }
    room = null;
    primaryRemoteVideo = null;
    screenShareVideo = null;
    cameraVideo = null;
    localCameraVideo = null;
    screenShareOn = false;
    connected = false;
  }

  void dispose() {
    _listener?.dispose();
    _listener = null;
    room?.dispose();
    room = null;
  }

  void _scanLocal() {
    final local = room?.localParticipant;
    if (local == null) return;
    localCameraVideo = null;
    for (final pub in local.videoTrackPublications) {
      if (pub.source == TrackSource.screenShareVideo && pub.track != null) {
        screenShareVideo = pub.track as VideoTrack?;
        continue;
      }
      if (pub.source == TrackSource.camera &&
          !pub.muted &&
          pub.track is VideoTrack) {
        localCameraVideo = pub.track as VideoTrack?;
      }
    }
    _updatePrimaryVideo();
  }

  void _rescanAll() {
    final lkRoom = room;
    if (lkRoom == null) return;

    final localShare = screenShareVideo;
    screenShareVideo = null;
    cameraVideo = null;

    _scanLocal();

    for (final participant in lkRoom.remoteParticipants.values) {
      _scanParticipant(participant);
    }

    // Keep local screen share if publishing
    if (screenShareOn && localShare != null && screenShareVideo == null) {
      screenShareVideo = localShare;
    }

    _updatePrimaryVideo();
    unawaited(_ensureAudioPlayback());
    onChanged();
  }

  void _scanParticipant(RemoteParticipant participant) {
    for (final pub in participant.videoTrackPublications) {
      if (!_isActiveVideoPublication(pub)) continue;

      final track = pub.track;
      if (track is! VideoTrack) continue;

      if (pub.source == TrackSource.screenShareVideo) {
        screenShareVideo = track;
      } else if (pub.source == TrackSource.camera) {
        cameraVideo = track;
      }
    }

    // Ensure remote audio tracks are subscribed and audible
    for (final pub in participant.audioTrackPublications) {
      if (pub.subscribed && pub.track != null && !pub.muted) {
        unawaited(_ensureAudioPlayback());
      }
    }
  }

  bool _isActiveVideoPublication(RemoteTrackPublication pub) {
    if (pub.muted) return false;
    if (!pub.subscribed) return false;
    if (pub.track == null) return false;
    return pub.kind == TrackType.VIDEO;
  }

  void _updatePrimaryVideo() {
    // Screen share / board share takes priority over camera.
    primaryRemoteVideo =
        screenShareVideo ?? localCameraVideo ?? cameraVideo;
  }

  Future<void> _ensureAudioPlayback() async {
    final lkRoom = room;
    if (lkRoom == null) return;
    if (!lkRoom.canPlaybackAudio) {
      try {
        await lkRoom.startAudio();
      } catch (_) {}
    }
  }
}
