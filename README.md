# Player

一个基于 libmpv、Rust 后端和 Flutter 前端的跨平台视频播放器。目标是优先做好本地媒体库、WebDAV 远程播放、TMDB 海报墙、字幕和弹幕。

## 目标平台

- Windows
- macOS
- Linux
- Android
- iOS

## 核心功能

- 本地视频文件扫描和媒体库管理
- WebDAV 目录浏览与远程视频播放
- 基于文件夹名 + 文件名的影片识别
- TMDB 元数据匹配、海报墙、详情页
- libmpv 播放内核
- 外挂字幕、本地字幕发现、字幕轨道切换
- 弹幕搜索、匹配、加载和渲染

## 技术路线

- `apps/player_flutter`: Flutter 前端应用
- `crates/player_core`: Rust 核心库，负责媒体扫描、元数据、WebDAV、弹幕 API、播放状态建模
- `docs`: 架构、API 契约和开发路线

Flutter 与 Rust 建议使用 `flutter_rust_bridge` 做业务 API 桥接；libmpv 渲染建议按平台实现 Flutter texture 或 platform view，再由 Rust 侧统一管理 mpv 播放实例。

## 外部服务

- TMDB API: 用于搜索影片/剧集、获取详情和海报路径
- danmu_api: 用于搜索、匹配、获取弹幕，兼容弹弹 play 风格接口

## 开发准备

需要安装：

- Flutter SDK
- Rust toolchain
- libmpv 开发库或对应平台动态库

本机当前尚未检测到 Cargo，`flutter --version` 检查超时，所以这里先提交项目骨架和接口设计。安装工具链后可继续补齐编译验证。

## 推荐环境变量

```bash
TMDB_ACCESS_TOKEN=...
DANMU_API_BASE_URL=http://127.0.0.1:9321
DANMU_API_TOKEN=87654321
```

## 目录结构

```text
.
├── apps/
│   └── player_flutter/
├── crates/
│   └── player_core/
└── docs/
```

