part of 'package:player_flutter/main.dart';

class PlayerApp extends StatefulWidget {
  const PlayerApp({super.key});

  @override
  State<PlayerApp> createState() => _PlayerAppState();
}

class _PlayerAppState extends State<PlayerApp> {
  final AppStore store = AppStore();

  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '爆米花播放器',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2E7AF6)),
        scaffoldBackgroundColor: Colors.white,
        visualDensity: VisualDensity.compact,
        textTheme: ThemeData.light().textTheme.apply(fontSizeFactor: 0.92),
        useMaterial3: true,
      ),
      home: AnimatedBuilder(
        animation: store,
        builder: (_, __) => PlayerShell(store: store),
      ),
    );
  }
}
