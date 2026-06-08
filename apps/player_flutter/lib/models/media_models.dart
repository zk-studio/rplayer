part of 'package:player_flutter/main.dart';

enum SourceType { local, webdav }

class MediaSourceConfig {
  const MediaSourceConfig({
    required this.id,
    required this.name,
    required this.type,
    required this.directory,
    this.baseUrl = '',
    this.username = '',
    this.password = '',
    this.selectedPaths = const [],
  });

  factory MediaSourceConfig.local({required String id, required String name, required String directory}) {
    return MediaSourceConfig(id: id, name: name, type: SourceType.local, directory: directory);
  }

  factory MediaSourceConfig.webdav({
    required String id,
    required String name,
    required String baseUrl,
    required String username,
    required String password,
    required String directory,
    List<String> selectedPaths = const [],
  }) {
    return MediaSourceConfig(
      id: id,
      name: name,
      type: SourceType.webdav,
      baseUrl: baseUrl,
      username: username,
      password: password,
      directory: directory,
      selectedPaths: selectedPaths,
    );
  }

  final String id;
  final String name;
  final SourceType type;
  final String directory;
  final String baseUrl;
  final String username;
  final String password;
  final List<String> selectedPaths;

  String get displayPath => type == SourceType.local ? directory : '$baseUrl$directory';

  Map<String, String> get headers {
    if (username.isEmpty && password.isEmpty) return {};
    return {'Authorization': 'Basic ${base64Encode(utf8.encode('$username:$password'))}'};
  }

  Uri resolve(String remotePath) {
    final base = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final relative = remotePath.startsWith('/') ? remotePath.substring(1) : remotePath;
    return Uri.parse(base).resolve(relative.split('/').map(Uri.encodeComponent).join('/'));
  }

  MediaSourceConfig copyWith({
    String? id,
    String? name,
    SourceType? type,
    String? directory,
    String? baseUrl,
    String? username,
    String? password,
    List<String>? selectedPaths,
  }) {
    return MediaSourceConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      directory: directory ?? this.directory,
      baseUrl: baseUrl ?? this.baseUrl,
      username: username ?? this.username,
      password: password ?? this.password,
      selectedPaths: selectedPaths ?? this.selectedPaths,
    );
  }

  factory MediaSourceConfig.fromJson(Map<String, dynamic> json) => MediaSourceConfig(
        id: json['id'] as String,
        name: json['name'] as String,
        type: (json['type'] as String) == 'webdav' ? SourceType.webdav : SourceType.local,
        directory: json['directory'] as String,
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        selectedPaths: (json['selectedPaths'] as List<dynamic>? ?? const []).whereType<String>().toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type == SourceType.webdav ? 'webdav' : 'local',
        'directory': directory,
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'selectedPaths': selectedPaths,
      };
}

class MediaItem {
  const MediaItem({
    required this.id,
    required this.sourceId,
    required this.sourceName,
    required this.type,
    required this.title,
    required this.uri,
  });

  factory MediaItem.local({required MediaSourceConfig source, required String path}) => MediaItem(
        id: '${source.id}:$path',
        sourceId: source.id,
        sourceName: source.name,
        type: SourceType.local,
        title: p.basenameWithoutExtension(path),
        uri: path,
      );

  factory MediaItem.webdav({required MediaSourceConfig source, required WebdavEntry entry}) => MediaItem(
        id: '${source.id}:${entry.path}',
        sourceId: source.id,
        sourceName: source.name,
        type: SourceType.webdav,
        title: p.basenameWithoutExtension(entry.name),
        uri: entry.url,
      );

  final String id;
  final String sourceId;
  final String sourceName;
  final SourceType type;
  final String title;
  final String uri;

  factory MediaItem.fromJson(Map<String, dynamic> json) => MediaItem(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String,
        sourceName: json['sourceName'] as String,
        type: (json['type'] as String) == 'webdav' ? SourceType.webdav : SourceType.local,
        title: json['title'] as String,
        uri: json['uri'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sourceId': sourceId,
        'sourceName': sourceName,
        'type': type == SourceType.webdav ? 'webdav' : 'local',
        'title': title,
        'uri': uri,
      };
}

class WebdavSourceDraft {
  const WebdavSourceDraft({
    required this.name,
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.directory,
  });

  final String name;
  final String baseUrl;
  final String username;
  final String password;
  final String directory;
}

class SyncConfig {
  const SyncConfig({
    required this.baseUrl,
    required this.username,
    required this.password,
    required this.configPath,
  });

  final String baseUrl;
  final String username;
  final String password;
  final String configPath;

  MediaSourceConfig asSource() => MediaSourceConfig.webdav(
        id: 'sync',
        name: '同步 WebDAV',
        baseUrl: baseUrl,
        username: username,
        password: password,
        directory: '/',
      );

  factory SyncConfig.fromJson(Map<String, dynamic> json) => SyncConfig(
        baseUrl: json['baseUrl'] as String? ?? '',
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        configPath: json['configPath'] as String? ?? '/Player/config.json',
      );

  Map<String, dynamic> toJson() => {
        'baseUrl': baseUrl,
        'username': username,
        'password': password,
        'configPath': configPath,
      };
}

class WebdavEntry {
  const WebdavEntry({required this.name, required this.path, required this.url, required this.isDir, this.size});

  final String name;
  final String path;
  final String url;
  final bool isDir;
  final int? size;
}

class LocalEntry {
  const LocalEntry({required this.name, required this.path, required this.isDir, this.size});

  final String name;
  final String path;
  final bool isDir;
  final int? size;
}
