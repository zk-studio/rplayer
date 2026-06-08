part of 'package:player_flutter/main.dart';

enum VideoFitMode { contain, cover, none, fill }

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({required this.store, required this.item, super.key});

  final AppStore store;
  final MediaItem item;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  Player? _player;
  VideoController? _controller;
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration? dragPreviewPosition;
  double dragDistance = 0;
  Duration dragStartPosition = Duration.zero;
  int? videoWidth;
  int? videoHeight;
  bool playing = false;
  bool ready = false;
  bool orientationLocked = false;
  bool seekingByDrag = false;
  bool streamsAttached = false;
  bool openedOnce = false;
  bool softwareDecoderFallback = false;
  bool fullscreen = false;
  VideoFitMode fitMode = VideoFitMode.contain;
  int transientCodecRetryCount = 0;
  int openAttempt = 0;
  Object? error;

  Player get player => _player ??= Player(
        configuration: const PlayerConfiguration(
          logLevel: MPVLogLevel.warn,
          bufferSize: 64 * 1024 * 1024,
        ),
      );

  VideoController get controller => _controller ??= VideoController(player);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) init();
    });
  }

  void attachStreams() {
    if (streamsAttached) return;
    streamsAttached = true;
    subscriptions
      ..add(player.stream.position.listen((value) => setStateIfMounted(() => position = value)))
      ..add(player.stream.duration.listen((value) => setStateIfMounted(() => duration = value)))
      ..add(player.stream.playing.listen((value) => setStateIfMounted(() => playing = value)))
      ..add(player.stream.width.listen((value) {
        videoWidth = value;
        applyVideoOrientation();
      }))
      ..add(player.stream.height.listen((value) {
        videoHeight = value;
        applyVideoOrientation();
      }))
      ..add(player.stream.error.listen(handlePlayerError));
  }

  Future<void> init({bool automaticRetry = true, bool resetCodecRetry = true}) async {
    final attempt = ++openAttempt;
    if (resetCodecRetry) {
      transientCodecRetryCount = 0;
      softwareDecoderFallback = false;
    }
    try {
      attachStreams();
      setState(() {
        error = null;
        ready = false;
      });
      final source = widget.store.sources.firstWhere((value) => value.id == widget.item.sourceId);
      final saved = widget.store.progress[widget.item.id] ?? 0;
      final uri = widget.item.type == SourceType.local ? Uri.file(widget.item.uri).toString() : widget.item.uri;
      await configureDecoder();
      if (openedOnce) {
        await player.stop();
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
      await player.open(
        Media(
          uri,
          httpHeaders: source.headers.isEmpty ? null : source.headers,
          start: saved > 0 ? Duration(milliseconds: saved) : null,
        ),
      );
      openedOnce = true;
      if (attempt == openAttempt) setStateIfMounted(() => ready = true);
    } catch (e) {
      if (automaticRetry && canRetryTransientCodec(e)) {
        await retryTransientCodec(attempt);
        return;
      }
      if (attempt == openAttempt) setStateIfMounted(() => error = e);
    }
  }

  Future<void> configureDecoder() async {
    try {
      final native = player.platform as dynamic;
      await native.setProperty('hwdec', softwareDecoderFallback ? 'no' : 'auto-safe');
      await native.setProperty('vd-lavc-threads', '0');
      await native.setProperty('video-sync', 'audio');
      await native.setProperty('framedrop', 'vo');
    } catch (_) {
      // Non-native platforms or older media_kit backends may not expose mpv properties.
    }
  }

  @override
  void dispose() {
    widget.store.updateProgress(widget.item.id, position);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  bool isTransientCodecError(Object value) {
    final text = value.toString().toLowerCase();
    return text.contains('could not open codec') || text.contains('failed to initialize a decoder');
  }

  bool canRetryTransientCodec(Object value) => isTransientCodecError(value) && transientCodecRetryCount < 2;

  Future<void> retryTransientCodec(int attempt) async {
    transientCodecRetryCount++;
    if (transientCodecRetryCount >= 2) softwareDecoderFallback = true;
    await Future<void>.delayed(const Duration(milliseconds: 450));
    if (!mounted || attempt != openAttempt) return;
    await player.stop();
    await init(automaticRetry: true, resetCodecRetry: false);
  }

  Future<void> handlePlayerError(Object value) async {
    final attempt = openAttempt;
    if (canRetryTransientCodec(value)) {
      await retryTransientCodec(attempt);
      return;
    }
    if (attempt == openAttempt) setStateIfMounted(() => error = value);
  }

  Future<void> applyVideoOrientation() async {
    if (orientationLocked) return;
    final width = videoWidth;
    final height = videoHeight;
    if (width == null || height == null || width <= 0 || height <= 0) return;

    orientationLocked = true;
    await SystemChrome.setPreferredOrientations(
      width >= height
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  }

  void beginSeekDrag(DragStartDetails details) {
    dragDistance = 0;
    dragStartPosition = position;
    seekingByDrag = false;
  }

  void updateSeekDrag(DragUpdateDetails details, double width) {
    if (duration == Duration.zero || width <= 0) return;
    dragDistance += details.delta.dx;
    if (!seekingByDrag && dragDistance.abs() < 18) return;
    seekingByDrag = true;
    final maxSeekMs = (duration.inMilliseconds * 0.18).clamp(5000, 120000).toInt();
    final offsetMs = (dragDistance / width * maxSeekMs).round();
    final nextMs = (dragStartPosition.inMilliseconds + offsetMs).clamp(0, duration.inMilliseconds);
    setStateIfMounted(() => dragPreviewPosition = Duration(milliseconds: nextMs));
  }

  Future<void> endSeekDrag() async {
    final target = seekingByDrag ? dragPreviewPosition : null;
    seekingByDrag = false;
    setStateIfMounted(() => dragPreviewPosition = null);
    if (target != null && duration > Duration.zero) {
      await player.seek(target);
    }
  }

  void togglePlayback() {
    playing ? player.pause() : player.play();
  }

  BoxFit get videoFit => switch (fitMode) {
        VideoFitMode.contain => BoxFit.contain,
        VideoFitMode.cover => BoxFit.cover,
        VideoFitMode.none => BoxFit.none,
        VideoFitMode.fill => BoxFit.fill,
      };

  Future<void> toggleFullscreen() async {
    final next = !fullscreen;
    setStateIfMounted(() => fullscreen = next);
    if (next) {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } else {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: SystemUiOverlay.values);
    }
  }

  void setFitMode(VideoFitMode value) {
    setStateIfMounted(() => fitMode = value);
  }

  List<Shadow> get controlShadows => const [
        Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 2)),
      ];

  IconThemeData get controlIconTheme => const IconThemeData(color: Colors.white, shadows: [
        Shadow(color: Color(0xCC000000), blurRadius: 8, offset: Offset(0, 1)),
        Shadow(color: Color(0x99000000), blurRadius: 18, offset: Offset(0, 2)),
      ]);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: beginSeekDrag,
            onHorizontalDragUpdate: (details) => updateSeekDrag(details, constraints.maxWidth),
            onHorizontalDragEnd: (_) => endSeekDrag(),
            onHorizontalDragCancel: () {
              seekingByDrag = false;
              setStateIfMounted(() => dragPreviewPosition = null);
            },
            onTap: toggleFullscreen,
            onDoubleTap: togglePlayback,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Center(
                  child: Video(
                    controller: controller,
                    fit: videoFit,
                    controls: NoVideoControls,
                  ),
                ),
                if (!ready && error == null) const Center(child: CircularProgressIndicator()),
                if (error != null) ErrorView(message: '$error', onRetry: init, dark: true),
                if (!fullscreen)
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    child: SafeArea(
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 12, 4),
                        child: IconTheme.merge(
                          data: controlIconTheme,
                          child: Row(
                          children: [
                            IconButton(
                              color: Colors.white,
                              onPressed: () => Navigator.of(context).maybePop(),
                              icon: const Icon(Icons.arrow_back),
                            ),
                            Expanded(
                              child: Text(
                                widget.item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600, shadows: controlShadows),
                              ),
                            ),
                          ],
                          ),
                        ),
                      ),
                    ),
                  ),
                if (!fullscreen && dragPreviewPosition != null)
                  Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: const Color(0xCC000000),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                        child: Text(
                          formatDuration(dragPreviewPosition!),
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ),
                if (!fullscreen)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(10, 0, 14, 6),
                        child: IconTheme.merge(
                          data: controlIconTheme,
                          child: Row(
                          children: [
                            IconButton(
                              color: Colors.white,
                              onPressed: togglePlayback,
                              icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3,
                                  activeTrackColor: Colors.white,
                                  inactiveTrackColor: Colors.white54,
                                  thumbColor: const Color(0xFF6F89D8),
                                  overlayColor: const Color(0x336F89D8),
                                ),
                                child: Slider(
                                  value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                                  max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                                  onChanged: (value) => player.seek(Duration(milliseconds: value.toInt())),
                                ),
                              ),
                            ),
                            PopupMenuButton<VideoFitMode>(
                              tooltip: '内容缩放',
                              icon: const Icon(Icons.aspect_ratio, color: Colors.white),
                              initialValue: fitMode,
                              onSelected: setFitMode,
                              itemBuilder: (_) => const [
                                PopupMenuItem(value: VideoFitMode.contain, child: Text('内容居中')),
                                PopupMenuItem(value: VideoFitMode.cover, child: Text('居中裁切')),
                                PopupMenuItem(value: VideoFitMode.none, child: Text('原始尺寸')),
                                PopupMenuItem(value: VideoFitMode.fill, child: Text('铺满屏幕')),
                              ],
                            ),
                            Padding(
                              padding: const EdgeInsets.only(right: 14),
                              child: Text(
                                '${formatDuration(position)} / ${formatDuration(duration)}',
                                style: TextStyle(color: Colors.white, shadows: controlShadows),
                              ),
                            ),
                          ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
