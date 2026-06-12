part of 'package:player_flutter/main.dart';

class AppStore extends ChangeNotifier {
  AppStore({this.scanner = const MediaScanService()});

  final MediaScanService scanner;
  final List<MediaSourceConfig> sources = [];
  final List<MediaItem> items = [];
  final Map<String, int> progress = {};
  final Map<String, int> durations = {};
  final Map<String, int> lastPlayedAt = {};
  final Map<String, String> folderOrientations = {};
  final Map<String, MediaMetadata> metadata = {};
  TmdbConfig tmdbConfig = const TmdbConfig();
  SyncConfig? syncConfig;
  bool loaded = false;
  bool metadataRefreshing = false;
  int metadataRevision = 0;
  bool diagnosticLoggingEnabled = false;
  String tmdbLastStatus = '';
  final List<String> diagnosticLogs = [];
  final Map<String, Uint8List?> _imageCache = {};

  Future<Directory> get appFilesDirectory async {
    var path = Directory.systemTemp.path;
    try {
      path = await appChannel.invokeMethod<String>('appFilesDir') ?? path;
    } on MissingPluginException {
      path = Directory.systemTemp.path;
    }
    final dir = Directory(path);
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> get configFile async {
    final dir = await appFilesDirectory;
    return File(p.join(dir.path, 'player_config.json'));
  }

  Future<File> get metadataDatabaseFile async {
    final dir = await appFilesDirectory;
    return File(p.join(dir.path, 'metadata.sqlite'));
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final file = await configFile;
    final text = await file.exists()
        ? await file.readAsString()
        : prefs.getString('app_state');
    if (text != null && text.isNotEmpty) {
      importSettingsJson(jsonDecode(text) as Map<String, dynamic>);
    }
    await loadMediaStateDatabase();
    await loadMetadataDatabase();
    loaded = true;
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> save() async {
    await saveSettings();
    await saveMediaStateDatabase();
    await pruneMetadataDatabase();
  }

  Future<void> saveSettings() async {
    final text = exportSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_state', text);
    await (await configFile).writeAsString(text);
  }

  Future<void> saveMediaStateDatabase() async {
    final text = exportMediaState();
    try {
      final db = await metadataDatabaseFile;
      RustCoreService.instance.appStatePut(db.path, text);
      final savedText = RustCoreService.instance.appStateGet(db.path);
      final saved = jsonDecode(savedText) as Map<String, dynamic>;
      final savedSources = (saved['sources'] as List<dynamic>? ?? const []);
      final savedItems = (saved['items'] as List<dynamic>? ?? const []);
      if (savedSources.length != sources.length ||
          savedItems.length != items.length) {
        throw StateError(
          'media state verify failed: memory sources=${sources.length}, db sources=${savedSources.length}, memory items=${items.length}, db items=${savedItems.length}',
        );
      }
    } catch (error) {
      addDiagnosticLog('media state database write failed: $error');
      rethrow;
    }
  }

  Future<void> loadMediaStateDatabase() async {
    try {
      final db = await metadataDatabaseFile;
      final text = RustCoreService.instance.appStateGet(db.path);
      if (text.trim().isNotEmpty && text.trim() != '{}') {
        importMediaStateJson(jsonDecode(text) as Map<String, dynamic>);
      }
    } catch (error) {
      addDiagnosticLog('media state database load failed: $error');
    }
  }

  Future<void> loadMetadataDatabase() async {
    try {
      final db = await metadataDatabaseFile;
      final values =
          await RustCoreService.instance.metadataGetAllAsync(db.path);
      if (values.isNotEmpty) {
        metadata
          ..clear()
          ..addAll(values);
      } else if (metadata.isNotEmpty) {
        await RustCoreService.instance.metadataReplaceAllAsync(
          db.path,
          metadata,
        );
      }
    } catch (error) {
      addDiagnosticLog('metadata database load failed: $error');
    }
  }

  Future<void> pruneMetadataDatabase() async {
    try {
      final liveItemIds = items.map((item) => item.id).toSet().toList();
      final liveTitleKeys =
          mediaFolderGroups(items).map((group) => group.key).toSet().toList();
      metadata.removeWhere((itemId, _) => !liveItemIds.contains(itemId));
      final db = await metadataDatabaseFile;
      await RustCoreService.instance.metadataPruneAsync(
        db.path,
        liveItemIds,
        liveTitleKeys,
      );
    } catch (error) {
      addDiagnosticLog('metadata database prune failed: $error');
    }
  }

  Future<void> saveMetadataToDatabase(
      String titleKey, String itemId, MediaMetadata value) async {
    try {
      final db = await metadataDatabaseFile;
      final metadataJson = jsonEncode(value.toJson());
      await RustCoreService.instance.metadataPutAsync(
        db.path,
        titleKey,
        itemId,
        metadataJson,
      );
      await RustCoreService.instance.metadataCacheImagesAsync(
        db.path,
        metadataJson,
        tmdbConfig.proxyUrl.trim(),
      );
    } catch (error) {
      addDiagnosticLog('metadata database write failed: $error');
    }
  }

  Future<void> reloadDatabaseBackedState() async {
    await loadMediaStateDatabase();
    await loadMetadataDatabase();
    notifyListeners();
  }

  Future<void> replaceMetadataDatabase() async {
    final db = await metadataDatabaseFile;
    await RustCoreService.instance.metadataReplaceAllAsync(db.path, const {});
    final groups = mediaFolderGroups(items);
    for (final group in groups) {
      for (final item in group.items) {
        final value = metadata[item.id];
        if (value == null) continue;
        await saveMetadataToDatabase(group.key, item.id, value);
      }
    }
  }

  String exportState() => exportSettings();

  String exportSettings() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 2,
      'tmdbConfig': tmdbConfig.toJson(),
      'syncConfig': syncConfig?.toJson(),
      'diagnosticLoggingEnabled': diagnosticLoggingEnabled,
    });
  }

  String exportMediaState() {
    return const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'sources': sources.map((source) => source.toJson()).toList(),
      'items': items.map((item) => item.toJson()).toList(),
      'progress': progress,
      'durations': durations,
      'lastPlayedAt': lastPlayedAt,
      'folderOrientations': folderOrientations,
    });
  }

  void importSettingsJson(Map<String, dynamic> json) {
    final tmdb = json['tmdbConfig'];
    tmdbConfig = tmdb == null
        ? const TmdbConfig()
        : TmdbConfig.fromJson(tmdb as Map<String, dynamic>);
    final sync = json['syncConfig'];
    syncConfig =
        sync == null ? null : SyncConfig.fromJson(sync as Map<String, dynamic>);
    diagnosticLoggingEnabled =
        json['diagnosticLoggingEnabled'] as bool? ?? false;
  }

  void importMediaStateJson(Map<String, dynamic> json) {
    sources
      ..clear()
      ..addAll(
        (json['sources'] as List<dynamic>? ?? []).map(
          (value) => MediaSourceConfig.fromJson(value as Map<String, dynamic>),
        ),
      );
    items
      ..clear()
      ..addAll(
        (json['items'] as List<dynamic>? ?? []).map(
          (value) => MediaItem.fromJson(value as Map<String, dynamic>)
              .withFreshIdentity(),
        ),
      );
    progress
      ..clear()
      ..addAll((json['progress'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)));
    durations
      ..clear()
      ..addAll((json['durations'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)));
    lastPlayedAt
      ..clear()
      ..addAll((json['lastPlayedAt'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as int)));
    folderOrientations
      ..clear()
      ..addAll((json['folderOrientations'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, value as String)));
  }

  Future<void> importState(String text, {bool persist = true}) async {
    final json = jsonDecode(text) as Map<String, dynamic>;
    importSettingsJson(json);
    if (persist) await saveSettings();
    notifyListeners();
  }

  Future<MediaSourceConfig> addLocalDirectory(String dir) async {
    addDiagnosticLog('add local source: $dir');
    final source = MediaSourceConfig.local(
      id: newId(),
      name: p.basename(dir).isEmpty ? '本地目录' : p.basename(dir),
      directory: dir,
    );
    sources.add(source);
    await save();
    notifyListeners();
    return source;
  }

  Future<MediaSourceConfig> addWebdavSource(WebdavSourceDraft draft) async {
    addDiagnosticLog('add webdav source: ${draft.baseUrl}${draft.directory}');
    final source = MediaSourceConfig.webdav(
      id: newId(),
      name: draft.name.isEmpty ? 'WebDAV' : draft.name,
      baseUrl: draft.baseUrl,
      username: draft.username,
      password: draft.password,
      directory: normalizeRemoteDir(draft.directory),
    );
    sources.add(source);
    await save();
    notifyListeners();
    return source;
  }

  Future<void> updateWebdavSource(
      MediaSourceConfig source, WebdavSourceDraft draft) async {
    addDiagnosticLog('update webdav source: ${source.name}');
    final updated = source.copyWith(
      name: draft.name.isEmpty ? source.name : draft.name,
      baseUrl: draft.baseUrl,
      username: draft.username,
      password: draft.password,
      directory: normalizeRemoteDir(draft.directory),
    );
    replaceSource(updated);
    await save();
    notifyListeners();
  }

  Future<void> removeSource(MediaSourceConfig source) async {
    addDiagnosticLog('remove source: ${source.name}');
    sources.removeWhere((value) => value.id == source.id);
    items.removeWhere((item) => item.sourceId == source.id);
    metadata.removeWhere((itemId, _) => itemId.startsWith('${source.id}:'));
    await save();
    notifyListeners();
  }

  Future<void> rescanAll() async {
    addDiagnosticLog('rescan all sources: ${sources.length}');
    final existing = List<MediaSourceConfig>.from(sources);
    items.clear();
    for (final source in existing) {
      await scanSourceIntoItems(source);
    }
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> rescanSource(MediaSourceConfig source) async {
    addDiagnosticLog('rescan source: ${source.name}');
    items.removeWhere((item) => item.sourceId == source.id);
    await scanSourceIntoItems(source);
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> scanSourceIntoItems(MediaSourceConfig source) async {
    addDiagnosticLog('scan source started: ${source.name}');
    var count = 0;
    for (final item in await scanner.scanSource(source)) {
      addOrReplaceItem(item);
      count++;
    }
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    addDiagnosticLog('scan source finished: ${source.name}, items=$count');
  }

  Future<void> addWebdavSelection(
      MediaSourceConfig source, WebdavEntry entry) async {
    addDiagnosticLog('add webdav selection: ${entry.path}');
    final normalizedPath =
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    final updated = source.copyWith(
      selectedPaths: {...source.selectedPaths, normalizedPath}.toList()..sort(),
    );
    replaceSource(updated);

    if (entry.isDir) {
      final client = WebdavClient.fromSource(updated);
      final entries = await client.scanVideos(entry.path, maxDepth: 8);
      for (final video in entries) {
        addOrReplaceItem(MediaItem.webdav(source: updated, entry: video));
      }
    } else if (isVideoName(entry.name)) {
      addOrReplaceItem(MediaItem.webdav(source: updated, entry: entry));
    }
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> addLocalSelection(
      MediaSourceConfig source, LocalEntry entry) async {
    addDiagnosticLog('add local selection: ${entry.path}');
    final normalizedPath = entry.path;
    final updated = source.copyWith(
      selectedPaths: {...source.selectedPaths, normalizedPath}.toList()..sort(),
    );
    replaceSource(updated);

    if (entry.isDir) {
      final found = await scanner.scanLocalPath(updated, entry.path);
      for (final item in found) {
        addOrReplaceItem(item);
      }
    } else if (isVideoName(entry.name)) {
      addOrReplaceItem(MediaItem.local(source: updated, path: entry.path));
    }
    items
        .sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> removeLocalSelection(
      MediaSourceConfig source, LocalEntry entry) async {
    addDiagnosticLog('remove local selection: ${entry.path}');
    final updated = source.copyWith(
      selectedPaths:
          source.selectedPaths.where((path) => path != entry.path).toList(),
    );
    replaceSource(updated);
    items.removeWhere((item) => item.sourceId == source.id);
    await scanSourceIntoItems(updated);
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  Future<void> removeWebdavSelection(
      MediaSourceConfig source, WebdavEntry entry) async {
    addDiagnosticLog('remove webdav selection: ${entry.path}');
    final normalizedPath =
        entry.isDir ? normalizeRemoteDir(entry.path) : entry.path;
    final updated = source.copyWith(
      selectedPaths:
          source.selectedPaths.where((path) => path != normalizedPath).toList(),
    );
    replaceSource(updated);
    items.removeWhere((item) => item.sourceId == source.id);
    await scanSourceIntoItems(updated);
    metadata
        .removeWhere((itemId, _) => !items.any((item) => item.id == itemId));
    await save();
    notifyListeners();
    unawaited(refreshMissingMetadata());
  }

  void addOrReplaceItem(MediaItem item) {
    items.removeWhere((value) => value.id == item.id);
    items.add(item);
  }

  MediaItem? itemById(String id) {
    return items.where((item) => item.id == id).firstOrNull;
  }

  void replaceSource(MediaSourceConfig source) {
    final index = sources.indexWhere((value) => value.id == source.id);
    if (index >= 0) sources[index] = source;
  }

  Future<void> setSyncConfig(SyncConfig config) async {
    syncConfig = config;
    await saveSettings();
    notifyListeners();
  }

  Future<void> setTmdbConfig(TmdbConfig config) async {
    tmdbConfig = config;
    await saveSettings();
    notifyListeners();
    unawaited(refreshMissingMetadata(force: true));
  }

  Future<void> setDiagnosticLoggingEnabled(bool value) async {
    diagnosticLoggingEnabled = value;
    await saveSettings();
    notifyListeners();
    if (value) addDiagnosticLog('diagnostic logging enabled');
  }

  Future<void> refreshMissingMetadata({bool force = false}) async {
    if (!tmdbConfig.enabled || metadataRefreshing) return;
    metadataRefreshing = true;
    tmdbLastStatus = 'TMDB refresh started';
    addDiagnosticLog(
        'TMDB refresh started, force=$force, items=${items.length}');
    notifyListeners();
    try {
      final service = TmdbMetadataService(tmdbConfig, log: addDiagnosticLog);
      var matched = 0;
      var failed = 0;
      var skipped = 0;
      final targetItems = <MediaItem>[];
      for (final item in List<MediaItem>.from(items)) {
        addDiagnosticLog('TMDB item: ${describeMediaItem(item)}');
        final cached = metadata[item.id];
        if (!force && cached != null && metadataCompleteForItem(item, cached)) {
          skipped++;
          addDiagnosticLog('TMDB skip cached: ${describeMediaItem(item)}');
          continue;
        }
        targetItems.add(item);
      }
      final targetGroups = mediaFolderGroups(targetItems);
      final allGroupsByKey = {
        for (final group in mediaFolderGroups(items)) group.key: group,
      };

      var cursor = 0;
      Future<void> worker() async {
        while (true) {
          if (cursor >= targetGroups.length) return;
          final group = targetGroups[cursor++];
          if (!metadataRefreshing) return;
          addDiagnosticLog(
              'TMDB worker group: ${group.title} items=${group.items.length}');
          Map<String, MediaMetadata> values;
          try {
            final fullGroup = allGroupsByKey[group.key] ?? group;
            final cachedTitle = mediaGroupMetadata(fullGroup, metadata);
            values = await service.lookupGroup(group, cachedTitle: cachedTitle);
          } catch (error) {
            failed += group.items.length;
            tmdbLastStatus = 'TMDB error: ${group.title} - $error';
            addDiagnosticLog(tmdbLastStatus);
            notifyListeners();
            continue;
          }
          if (values.isNotEmpty) {
            for (final entry in values.entries) {
              metadata[entry.key] = entry.value;
              metadataRevision++;
              matched++;
              addDiagnosticLog(
                  'TMDB matched item=${entry.key} tmdb=${entry.value.tmdbId} type=${entry.value.mediaType} poster=${entry.value.posterPath} still=${entry.value.stillPath}');
              await saveMetadataToDatabase(group.key, entry.key, entry.value);
            }
            notifyListeners();
          } else {
            failed += group.items.length;
            tmdbLastStatus = 'TMDB no match: ${group.title}';
            addDiagnosticLog(tmdbLastStatus);
            notifyListeners();
          }
        }
      }

      final workerCount = math.min(4, math.max(1, targetGroups.length));
      await Future.wait([
        for (var i = 0; i < workerCount; i++) worker(),
      ]);
      await save();
      metadataRevision++;
      tmdbLastStatus =
          'TMDB refresh done: $matched matched, $failed failed, $skipped skipped';
      addDiagnosticLog(tmdbLastStatus);
    } finally {
      metadataRefreshing = false;
      notifyListeners();
    }
  }

  bool metadataCompleteForItem(MediaItem item, MediaMetadata value) {
    if (value.schemaVersion < currentMetadataSchemaVersion) return false;
    if (value.mediaType != 'tv') return true;
    final episode = inferredEpisodeNumber(item);
    if (episode == null) return true;
    return value.episodeName?.trim().isNotEmpty == true &&
        value.stillPath?.trim().isNotEmpty == true;
  }

  void addDiagnosticLog(String message) {
    if (!diagnosticLoggingEnabled) return;
    final time = DateTime.now().toIso8601String();
    diagnosticLogs.add('$time $message');
    if (diagnosticLogs.length > 1000) {
      diagnosticLogs.removeRange(0, diagnosticLogs.length - 1000);
    }
  }

  String exportDiagnosticLogs() => diagnosticLogs.join('\n');

  Future<String> exportDiagnosticLogFile() async {
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'player_diagnostic_logs_$timestamp.txt';
    final text = exportDiagnosticLogs();
    final bytes = Uint8List.fromList(utf8.encode(text));
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '导出诊断日志',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['txt'],
      bytes: bytes,
    );
    if (picked != null) return picked;
    final dir = await appFilesDirectory;
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> exportConfigFile() async {
    await saveSettings();
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'player_config_$timestamp.json';
    final bytes = Uint8List.fromList(utf8.encode(exportSettings()));
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '导出配置文件',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      bytes: bytes,
    );
    if (picked != null) return picked;
    final dir = await appFilesDirectory;
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> exportDatabaseFile() async {
    await saveMediaStateDatabase();
    await pruneMetadataDatabase();
    final db = await metadataDatabaseFile;
    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final fileName = 'metadata_$timestamp.sqlite';
    final bytes = await db.readAsBytes();
    final picked = await FilePicker.platform.saveFile(
      dialogTitle: '导出元数据数据库',
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: const ['sqlite', 'db'],
      bytes: bytes,
    );
    if (picked != null) return picked;
    final dir = await appFilesDirectory;
    final file = File(p.join(dir.path, fileName));
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  Future<String> libraryHomeJson() async {
    final db = await metadataDatabaseFile;
    return RustCoreService.instance.libraryHomeJsonAsync(db.path);
  }

  Future<List<LibraryHomeEntry>> loadLibraryHome() async {
    final text = await libraryHomeJson();
    return (jsonDecode(text) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(LibraryHomeEntry.fromJson)
        .toList();
  }

  Future<String> libraryShowDetailJson(String folderKey) async {
    final db = await metadataDatabaseFile;
    return RustCoreService.instance.libraryShowDetailJsonAsync(
      db.path,
      folderKey,
    );
  }

  Future<LibraryShowDetail> loadLibraryShowDetail(String folderKey) async {
    final text = await libraryShowDetailJson(folderKey);
    return LibraryShowDetail.fromJson(jsonDecode(text) as Map<String, dynamic>);
  }

  Future<String> libraryRecentJson() async {
    final db = await metadataDatabaseFile;
    return RustCoreService.instance.libraryRecentJsonAsync(db.path);
  }

  Future<List<LibraryRecentEntry>> loadLibraryRecent() async {
    final text = await libraryRecentJson();
    return (jsonDecode(text) as List<dynamic>)
        .whereType<Map<String, dynamic>>()
        .map(LibraryRecentEntry.fromJson)
        .toList();
  }

  Future<void> clearDiagnosticLogs() async {
    diagnosticLogs.clear();
    tmdbLastStatus = '';
    await save();
    notifyListeners();
  }

  Future<Uint8List?> cachedTmdbImageBytes(String imagePath, String size) async {
    if (imagePath.trim().isEmpty) return null;
    final normalized = imagePath.startsWith('/') ? imagePath : '/$imagePath';
    final key = '$size:$normalized';
    if (_imageCache.containsKey(key)) return _imageCache[key];
    final db = await metadataDatabaseFile;
    try {
      final bytes = await RustCoreService.instance.metadataCachedImageAsync(
        db.path,
        normalized,
        size,
      );
      if (bytes != null && bytes.isNotEmpty) {
        _imageCache[key] = bytes;
        return bytes;
      }
    } catch (error) {
      addDiagnosticLog('cached image read failed: $key - $error');
    }
    final url = tmdbImageUrl(normalized, size);
    if (url == null) {
      _imageCache[key] = null;
      return null;
    }
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _imageCache[key] = null;
        return null;
      }
      final bytes = response.bodyBytes;
      if (bytes.isEmpty) {
        _imageCache[key] = null;
        return null;
      }
      final contentType = response.headers['content-type'];
      await RustCoreService.instance.metadataPutCachedImageAsync(
        db.path,
        normalized,
        size,
        url,
        contentType,
        bytes,
      );
      _imageCache[key] = bytes;
      return bytes;
    } catch (error) {
      addDiagnosticLog('cached image download failed: $key - $error');
      _imageCache[key] = null;
      return null;
    }
  }

  Future<void> updateProgress(String itemId, Duration position,
      [Duration? duration]) async {
    progress[itemId] = position.inMilliseconds;
    if (duration != null && duration > Duration.zero) {
      durations[itemId] = duration.inMilliseconds;
    }
    lastPlayedAt[itemId] = DateTime.now().millisecondsSinceEpoch;
    await save();
    notifyListeners();
  }

  Future<void> rememberDuration(String itemId, Duration duration) async {
    if (duration <= Duration.zero) return;
    final milliseconds = duration.inMilliseconds;
    if (durations[itemId] == milliseconds) return;
    durations[itemId] = milliseconds;
    await save();
    notifyListeners();
  }

  Future<void> rememberFolderOrientation(MediaItem item, bool landscape) async {
    folderOrientations[mediaFolderKey(item)] =
        landscape ? 'landscape' : 'portrait';
    await save();
    notifyListeners();
  }
}
