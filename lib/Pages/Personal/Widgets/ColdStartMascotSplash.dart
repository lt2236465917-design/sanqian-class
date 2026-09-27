import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class ColdStartMascotSplash extends StatefulWidget {
  final Widget child;
  final VoidCallback? onNativeSplashReady;

  const ColdStartMascotSplash({
    super.key,
    required this.child,
    this.onNativeSplashReady,
  });

  @override
  State<ColdStartMascotSplash> createState() => _ColdStartMascotSplashState();
}

class _ColdStartMascotSplashState extends State<ColdStartMascotSplash>
    with WidgetsBindingObserver {
  static const _videoAsset = 'res/mascot/cold-start-splash.mp4';
  static const _posterAsset = 'res/mascot/cold-start-splash-poster.png';
  static const _posterHold = Duration(milliseconds: 500);

  late final VideoPlayerController _videoController;

  Timer? _finishTimer;
  Timer? _posterHoldTimer;
  bool _showSplash = true;
  bool _videoReady = false;
  bool _posterHoldElapsed = false;
  bool _showVideo = false;
  bool _playbackStartScheduled = false;
  bool _playbackStarted = false;
  bool _hasBeenResumed = false;
  bool _nativeSplashRemoved = false;
  bool _animationFailed = false;
  bool _playbackFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _hasBeenResumed =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _videoController = VideoPlayerController.asset(_videoAsset);
    unawaited(_initializeVideo());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showSplash) return;
      _removeNativeSplash();
      _posterHoldTimer = Timer(_posterHold, () {
        _posterHoldElapsed = true;
        _revealVideoIfReady();
      });
    });
  }

  Future<void> _initializeVideo() async {
    try {
      await _videoController.initialize();
      await _videoController.setLooping(false);
      _videoController.addListener(_onVideoValueChanged);
      if (!mounted || !_showSplash) return;

      setState(() => _videoReady = true);
      _revealVideoIfReady();
    } catch (error, stackTrace) {
      _onAnimationError(error, stackTrace);
    }
  }

  Future<void> _startVideoPlayback() async {
    try {
      final playback = _videoController.play();
      _playbackStarted = true;
      final duration = _videoController.value.duration;
      if (duration > Duration.zero) {
        _finishTimer = Timer(duration + const Duration(milliseconds: 300), () {
          if (mounted) _finishAnimation();
        });
      }
      _removeNativeSplash();
      await playback;
    } catch (error, stackTrace) {
      _onAnimationError(error, stackTrace);
    }
  }

  void _revealVideoIfReady() {
    if (!mounted || !_showSplash || _showVideo) return;
    if (!_posterHoldElapsed || !_videoReady) return;
    setState(() => _showVideo = true);
    _schedulePlaybackAfterVideoLayerMounts();
  }

  void _schedulePlaybackAfterVideoLayerMounts() {
    if (_playbackStartScheduled) return;
    _playbackStartScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_showSplash) return;
      unawaited(_startVideoPlayback());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _dismiss();
      });
    }
  }

  void _onVideoValueChanged() {
    if (!_showSplash || !_playbackStarted || _playbackFinished) return;
    final value = _videoController.value;
    if (!value.isInitialized || value.isBuffering) return;

    final duration = value.duration;
    final endThreshold = duration - const Duration(milliseconds: 80);
    if (duration > Duration.zero && value.position >= endThreshold) {
      _playbackFinished = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _finishAnimation();
      });
    }
  }

  void _onAnimationError(Object error, StackTrace? stackTrace) {
    if (_animationFailed) return;
    _animationFailed = true;
    debugPrint('Unable to play cold-start splash animation: $error');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _dismiss();
    });
  }

  void _finishAnimation() {
    _finishTimer?.cancel();
    _videoController.pause();
    if (_showSplash && mounted) setState(() => _showSplash = false);
    _removeNativeSplash();
  }

  void _removeNativeSplash() {
    if (_nativeSplashRemoved) return;
    _nativeSplashRemoved = true;
    widget.onNativeSplashReady?.call();
  }

  void _dismiss() {
    _posterHoldTimer?.cancel();
    _finishTimer?.cancel();
    _videoController.pause();
    _removeNativeSplash();
    if (!_showSplash) return;
    setState(() => _showSplash = false);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _hasBeenResumed = true;
      return;
    }

    if (_hasBeenResumed &&
        _playbackStarted &&
        (state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused ||
            state == AppLifecycleState.detached)) {
      _dismiss();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _posterHoldTimer?.cancel();
    _finishTimer?.cancel();
    _videoController.removeListener(_onVideoValueChanged);
    _videoController.dispose();
    super.dispose();
  }

  Widget _square(Widget child) => Positioned.fill(
    child: Center(child: AspectRatio(aspectRatio: 1, child: child)),
  );

  Widget _poster() => _square(
    Image.asset(
      _posterAsset,
      key: const ValueKey('cold-start-mascot-poster'),
      fit: BoxFit.contain,
      gaplessPlayback: true,
    ),
  );

  Widget _video() => _square(
    VideoPlayer(
      _videoController,
      key: const ValueKey('cold-start-mascot-video'),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            key: const ValueKey('cold-start-mascot-splash'),
            child: Semantics(
              button: true,
              label: '跳过开屏动画',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _dismiss,
                child: ColoredBox(
                  color: Colors.white,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _poster(),
                      if (_showVideo && _videoReady) _video(),
                      SafeArea(
                        child: Align(
                          alignment: Alignment.topRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4, right: 8),
                            child: TextButton(
                              key: const ValueKey('skip-cold-start-splash'),
                              onPressed: _dismiss,
                              child: const Text('跳过'),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
