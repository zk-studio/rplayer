# 架构设计

## 分层

```text
Flutter UI
  ├─ 海报墙、播放器页、设置页、WebDAV 浏览页
  ├─ 弹幕渲染层
  └─ 平台 texture / platform view

Bridge
  └─ flutter_rust_bridge 或平台 MethodChannel

Rust Core
  ├─ media: 扫描、文件名解析、影片候选生成
  ├─ tmdb: 搜索、详情、图片 URL 生成
  ├─ webdav: 远程目录浏览、媒体 URL/流读取
  ├─ danmu: danmu_api 搜索、匹配、弹幕下载
  ├─ subtitle: 字幕发现、字幕偏移、编码探测
  └─ playback: libmpv 命令、事件、播放状态

Native
  ├─ libmpv
  └─ OS filesystem / network / keychain
```

## 播放核心

libmpv 负责解码、音视频同步、字幕轨道和播放控制。Rust 侧维护一个 `PlayerSession`：

- 创建/销毁 mpv 实例
- 打开本地文件或 WebDAV URL
- 暴露 play/pause/seek/volume/speed 等命令
- 订阅 time-pos、duration、track-list、pause、end-file 等事件
- 将视频帧渲染到 Flutter 可消费的 texture 或平台视图

桌面端优先 texture/OpenGL；移动端可根据平台成熟度选择 texture 或 platform view。第一阶段可以先把 mpv 作为纯播放控制层接入，再迭代高性能渲染路径。

## 媒体识别

输入由父文件夹名和视频文件名组成：

```text
folder: Inception (2010)
file: Inception.2010.1080p.BluRay.x265.mkv
```

识别流程：

1. 合并 folder + file basename 形成原始标题上下文。
2. 去除扩展名、分辨率、编码、音频、来源、字幕组等噪声 token。
3. 解析年份、季、集，例如 `S01E02`、`Season 1`、`第02集`。
4. 电影优先搜索 `/search/movie`，带季集信息时搜索 `/search/tv`。
5. 候选按标题相似度、年份命中、语言、热度加权。
6. 用户手动确认后缓存 TMDB ID，避免重复误匹配。

## WebDAV

WebDAV 作为媒体源，不直接复制到本地。核心能力：

- 目录 PROPFIND
- Basic/Digest 或用户自定义 header
- Range 请求能力探测
- 远程文件 URL 传递给 libmpv
- 可选元数据和小文件缓存

如果服务器 Range 支持不好，播放器应提示用户并提供缓存播放选项。

## 弹幕

弹幕使用 danmu_api 服务：

- `POST /api/v2/match`: 自动匹配剧集或影片
- `GET /api/v2/comment/:commentId?format=json`: 获取指定弹幕
- `GET /api/v2/comment?url=...&format=json`: 通过视频 URL 获取弹幕

Rust 侧只负责请求和规范化弹幕事件；Flutter 侧负责渲染、过滤、密度、速度、透明度和时间偏移。

## 数据存储

推荐 SQLite：

- media_items: 本地/远程条目
- media_matches: TMDB 匹配缓存
- playback_history: 播放进度
- subtitle_tracks: 字幕索引
- danmu_cache: 弹幕缓存和来源
- settings: TMDB、WebDAV、弹幕 API 配置

