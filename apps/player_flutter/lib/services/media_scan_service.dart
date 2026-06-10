part of 'package:player_flutter/main.dart';

class MediaScanService {
  const MediaScanService();

  Future<List<MediaItem>> scanSource(MediaSourceConfig source) {
    return source.type == SourceType.local
        ? scanLocalDirectory(source)
        : scanWebdavSelections(source);
  }

  Future<List<MediaItem>> scanLocalDirectory(MediaSourceConfig source) async {
    final items = <MediaItem>[];
    for (final path in source.selectedPaths) {
      items.addAll(await scanLocalPath(source, path));
    }
    return items;
  }

  Future<List<MediaItem>> scanLocalPath(
      MediaSourceConfig source, String path) async {
    final items = <MediaItem>[];
    final file = File(path);
    if (await file.exists()) {
      if (isVideoName(path)) {
        items.add(MediaItem.local(source: source, path: path));
      }
      return items;
    }

    final dir = Directory(path);
    if (!await dir.exists()) return [];

    return (await RustCoreService.instance.scanLocalVideosAsync(path))
        .map((video) => MediaItem.local(source: source, path: video.path))
        .toList();
  }

  Future<List<MediaItem>> scanWebdavSelections(MediaSourceConfig source) async {
    final client = WebdavClient.fromSource(source);
    final items = <MediaItem>[];
    for (final path in source.selectedPaths) {
      if (path.endsWith('/')) {
        final entries = await client.scanVideos(path, maxDepth: 8);
        items.addAll(entries
            .map((entry) => MediaItem.webdav(source: source, entry: entry)));
      } else if (isVideoName(path)) {
        final entry = await client.findFile(path);
        if (entry != null) {
          items.add(MediaItem.webdav(source: source, entry: entry));
        }
      }
    }
    return items;
  }
}
