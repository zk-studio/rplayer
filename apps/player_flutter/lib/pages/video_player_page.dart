part of 'package:player_flutter/main.dart';

class VideoPlayerPage extends StatefulWidget {
  const VideoPlayerPage({required this.store, required this.item, super.key});

  final AppStore store;
  final MediaItem item;

  @override
  State<VideoPlayerPage> createState() => _VideoPlayerPageState();
}

class _VideoPlayerPageState extends State<VideoPlayerPage> {
  late final Player player = Player(
    configuration: const PlayerConfiguration(
      logLevel: MPVLogLevel.warn,
      bufferSize: 128 * 1024 * 1024,
    ),
  );
  late final VideoController controller = VideoController(player);
  final subscriptions = <StreamSubscription<dynamic>>[];
  Duration position = Duration.zero;
  Duration duration = Duration.zero;
  Duration? dragPreviewPosition;
  double dragDistance = 0;
  bool playing = false;
  bool ready = false;
  bool orientationLocked = false;
  Object? error;

  @override
  void initState() {
    super.initState();
    subscriptions
      ..add(player.stream.position.listen((value) => setStateIfMounted(() => position = value)))
      ..add(player.stream.duration.listen((value) => setStateIfMounted(() => duration = value)))
      ..add(player.stream.playing.listen((value) => setStateIfMounted(() => playing = value)))
      ..add(player.stream.videoParams.listen(applyVideoOrientation))
      ..add(player.stream.error.listen((value) => setStateIfMounted(() => error = value)));
    init();
  }

  Future<void> init() async {
    try {
      setState(() {
        error = null;
        ready = false;
      });
      final source = widget.store.sources.firstWhere((value) => value.id == widget.item.sourceId);
      final saved = widget.store.progress[widget.item.id] ?? 0;
      final uri = widget.item.type == SourceType.local ? Uri.file(widget.item.uri).toString() : widget.item.uri;
      await configureDecoder();
      await player.open(
        Media(
          uri,
          httpHeaders: source.headers.isEmpty ? null : source.headers,
          start: saved > 0 ? Duration(milliseconds: saved) : null,
        ),
      );
      setStateIfMounted(() => ready = true);
    } catch (e) {
      setStateIfMounted(() => error = e);
    }
  }

  Future<void> configureDecoder() async {
    try {
      final native = player.platform as dynamic;
      await native.setProperty('hwdec', 'no');
      await native.setProperty('vd-lavc-threads', '0');
    } catch (_) {
      // Non-native platforms or older media_kit backends may not expose mpv properties.
    }
  }

  @override
  void dispose() {
    widget.store.updateProgress(widget.item.id, position);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    for (final subscription in subscriptions) {
      subscription.cancel();
    }
    player.dispose();
    super.dispose();
  }

  void setStateIfMounted(VoidCallback update) {
    if (mounted) setState(update);
  }

  Future<void> applyVideoOrientation(VideoParams params) async {
    if (orientationLocked) return;
    final aspect = params.aspect;
    var width = params.dw ?? params.w;
    var height = params.dh ?? params.h;
    final rotate = (params.rotate ?? 0).abs() % 180;
    if (rotate == 90 && width != null && height != null) {
      final originalWidth = width;
      width = height;
      height = originalWidth;
    }

    if (width == null && height == null && (aspect == null || aspect <= 0)) return;
    final landscape = aspect != null && aspect > 0 ? aspect >= 1 : width != null && height != null && width >= height;

    orientationLocked = true;
    await SystemChrome.setPreferredOrientations(
      landscape
          ? [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]
          : [DeviceOrientation.portraitUp, DeviceOrientation.portraitDown],
    );
  }

  void beginSeekDrag(DragStartDetails details) {
    dragDistance = 0;
    setStateIfMounted(() => dragPreviewPosition = position);
  }

  void updateSeekDrag(DragUpdateDetails details, double width) {
    if (duration == Duration.zero || width <= 0) return;
    dragDistance += details.delta.dx;
    final seconds = (dragDistance / width * 90).round();
    final nextMs = (position.inMilliseconds + seconds * 1000).clamp(0, duration.inMilliseconds);
    setStateIfMounted(() => dragPreviewPosition = Duration(milliseconds: nextMs));
  }

  Future<void> endSeekDrag() async {
    final target = dragPreviewPosition;
    setStateIfMounted(() => dragPreviewPosition = null);
    if (target != null && duration > Duration.zero) {
      await player.seek(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(foregroundColor: Colors.white, backgroundColor: Colors.black, title: Text(widget.item.title)),
      body: error != null
          ? ErrorView(message: '$error', onRetry: init, dark: true)
          : !ready
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onHorizontalDragStart: beginSeekDrag,
                            onHorizontalDragUpdate: (details) => updateSeekDrag(details, constraints.maxWidth),
                            onHorizontalDragEnd: (_) => endSeekDrag(),
                            onHorizontalDragCancel: () => setStateIfMounted(() => dragPreviewPosition = null),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Center(
                                  child: Video(
                                    controller: controller,
                                    fit: BoxFit.contain,
                                    controls: NoVideoControls,
                                  ),
                                ),
                                if (dragPreviewPosition != null)
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
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    SafeArea(
                      top: false,
                      child: Row(
                        children: [
                          IconButton(
                            color: Colors.white,
                            onPressed: () => playing ? player.pause() : player.play(),
                            icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                          ),
                          Expanded(
                            child: Slider(
                              value: position.inMilliseconds.clamp(0, duration.inMilliseconds).toDouble(),
                              max: duration.inMilliseconds.toDouble().clamp(1, double.infinity),
                              onChanged: (value) => player.seek(Duration(milliseconds: value.toInt())),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.only(right: 14),
                            child: Text(
                              '${formatDuration(position)} / ${formatDuration(duration)}',
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }
}
