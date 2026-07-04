import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../models/saved_live_class.dart';
import '../../../theme/app_theme.dart';

class SavedClassPlayerScreen extends StatefulWidget {
  final SavedLiveClass item;

  const SavedClassPlayerScreen({super.key, required this.item});

  @override
  State<SavedClassPlayerScreen> createState() => _SavedClassPlayerScreenState();
}

class _SavedClassPlayerScreenState extends State<SavedClassPlayerScreen> {
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  Future<void> _initPlayer() async {
    try {
      final file = File(widget.item.filePath);
      if (!await file.exists()) {
        if (mounted) setState(() => _error = 'Recording file not found.');
        return;
      }

      if (widget.item.isVideo) {
        final controller = VideoPlayerController.file(file);
        await controller.initialize();
        _video = controller;
      } else {
        final player = AudioPlayer();
        await player.setSourceDeviceFile(widget.item.filePath);
        _audio = player;
      }
      if (mounted) setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not open recording.');
    }
  }

  @override
  void dispose() {
    _video?.dispose();
    _audio?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.bgColor,
      appBar: AppBar(
        backgroundColor: context.headerColor,
        foregroundColor: context.textColor,
        title: Text(
          widget.item.title,
          style: const TextStyle(fontSize: 16),
        ),
      ),
      body: _error != null
          ? Center(
              child: Text(_error!,
                  style: TextStyle(color: context.greyColor)),
            )
          : !_ready
              ? Center(
                  child: CircularProgressIndicator(color: context.accentColor),
                )
              : Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: widget.item.isVideo && _video != null
                            ? AspectRatio(
                                aspectRatio: _video!.value.aspectRatio,
                                child: VideoPlayer(_video!),
                              )
                            : Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.headphones_rounded,
                                      size: 72,
                                      color: context.accentColor),
                                  const SizedBox(height: 16),
                                  Text(
                                    widget.item.subject.isNotEmpty
                                        ? widget.item.subject
                                        : 'Lesson recording',
                                    style: TextStyle(
                                      color: context.greyColor,
                                      fontSize: 14,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          IconButton.filled(
                            iconSize: 36,
                            style: IconButton.styleFrom(
                              backgroundColor: context.accentColor,
                            ),
                            onPressed: _togglePlay,
                            icon: Icon(
                              _isPlaying ? Icons.pause : Icons.play_arrow,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  bool get _isPlaying {
    if (_video != null) return _video!.value.isPlaying;
    return _audio?.state == PlayerState.playing;
  }

  Future<void> _togglePlay() async {
    if (_video != null) {
      if (_video!.value.isPlaying) {
        await _video!.pause();
      } else {
        await _video!.play();
      }
    } else if (_audio != null) {
      if (_audio!.state == PlayerState.playing) {
        await _audio!.pause();
      } else {
        await _audio!.resume();
      }
    }
    if (mounted) setState(() {});
  }
}
