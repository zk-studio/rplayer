# API 契约

## Flutter 调 Rust

### 媒体库

```text
scanLocalFolder(path) -> ScanSummary
listMedia(query, sort, filter) -> List<MediaItem>
refreshMetadata(mediaId) -> MediaMetadata
setManualTmdbMatch(mediaId, tmdbMediaType, tmdbId) -> void
```

### WebDAV

```text
testWebdavConnection(config) -> ConnectionResult
listWebdavDirectory(sourceId, path) -> List<RemoteEntry>
addWebdavSource(config) -> SourceId
```

### 播放

```text
open(mediaId, optionalSourceUrl) -> PlayerState
play() -> void
pause() -> void
seek(seconds) -> void
setVolume(value) -> void
setSpeed(value) -> void
selectSubtitle(trackId) -> void
observePlayerEvents() -> Stream<PlayerEvent>
```

### 字幕

```text
discoverSubtitles(mediaId) -> List<SubtitleTrack>
addExternalSubtitle(mediaId, pathOrUrl) -> SubtitleTrack
setSubtitleDelay(milliseconds) -> void
```

### 弹幕

```text
matchDanmu(query) -> DanmuMatch
loadDanmu(commentId) -> List<DanmuEvent>
setDanmuDelay(milliseconds) -> void
```

## TMDB

TMDB v3 常用流程：

- 搜索电影: `GET https://api.themoviedb.org/3/search/movie?query=...`
- 搜索剧集: `GET https://api.themoviedb.org/3/search/tv?query=...`
- 查询详情: `GET https://api.themoviedb.org/3/movie/{id}` 或 `/tv/{id}`
- 图片 URL: `base_url + size + file_path`，例如 poster 使用 `w500`

认证建议使用 Bearer token，不把 token 写入代码仓库。

## danmu_api

默认本地服务：

```text
http://127.0.0.1:9321/87654321
```

默认 token 为 `87654321` 时，项目 README 说明可以省略 token。

常用接口：

```text
GET  /api/v2/search/anime?keyword={title}
POST /api/v2/match
GET  /api/v2/search/episodes?anime={title}
GET  /api/v2/bangumi/{animeId}
GET  /api/v2/comment/{commentId}?format=json
GET  /api/v2/comment?url={videoUrl}&format=json
GET  /api/logs
```

播放器内部建议统一转换为：

```text
DanmuEvent {
  time_ms: u64,
  mode: scroll | top | bottom,
  color: u32,
  text: string,
  source: string
}
```

