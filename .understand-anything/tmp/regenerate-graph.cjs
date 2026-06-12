const fs = require("fs");
const path = require("path");
const cp = require("child_process");

const root = path.resolve(__dirname, "../..");
const outDir = path.join(root, ".understand-anything");
const intermediateDir = path.join(outDir, "intermediate");

function fileLines(filePath) {
  try {
    return fs.readFileSync(path.join(root, filePath), "utf8").split(/\r?\n/).length;
  } catch {
    return 1;
  }
}

function node(id, type, name, filePath, summary, tags, complexity = "moderate", lineRange) {
  return {
    id,
    type,
    name,
    filePath,
    lineRange: lineRange || (filePath ? [1, fileLines(filePath)] : undefined),
    summary,
    tags,
    complexity,
    languageNotes:
      "本节点由 /understand --language zh 生成。描述使用中文，必要的技术名词保留英文。",
  };
}

function edge(source, target, type, description, weight = 0.8, direction = "forward") {
  return { source, target, type, direction, description, weight };
}

fs.mkdirSync(outDir, { recursive: true });
fs.mkdirSync(intermediateDir, { recursive: true });

let gitCommitHash = "unknown";
try {
  gitCommitHash = cp.execSync("git rev-parse HEAD", { cwd: root, encoding: "utf8" }).trim();
} catch {}

let sourceFiles = [];
try {
  sourceFiles = cp
    .execSync('rg --files -g "!target/**" -g "!third_party/**" -g "!Cargo.lock"', {
      cwd: root,
      encoding: "utf8",
    })
    .trim()
    .split(/\r?\n/)
    .filter(Boolean)
    .map((value) => value.replaceAll("\\", "/"));
} catch {}

const nodes = [
  node(
    "project:player",
    "module",
    "Player 播放器工作区",
    "Cargo.toml",
    "跨平台视频播放器工作区，组合 Flutter 前端、Rust player_core 动态库、Android 平台通道和架构文档。",
    ["workspace", "player", "flutter", "rust"],
  ),
  node(
    "app:flutter",
    "module",
    "Flutter 前端应用",
    "apps/player_flutter/lib/main.dart",
    "Flutter 应用入口。通过 part 文件组织页面、状态、服务、模型和工具，并初始化 media_kit 后运行 PlayerApp。",
    ["flutter", "frontend", "media_kit"],
    "complex",
  ),
  node(
    "core:rust",
    "module",
    "Rust player_core",
    "crates/player_core/src/lib.rs",
    "Rust 核心库，导出本地扫描、媒体识别、WebDAV 解析、TMDB 请求和 SQLite 元数据缓存的 C ABI。",
    ["rust", "ffi", "core"],
    "complex",
  ),
  node(
    "platform:android",
    "module",
    "Android 平台桥",
    "apps/player_flutter/android/app/src/main/kotlin/com/example/player_flutter/MainActivity.kt",
    "Android FlutterActivity 注册 popcorn_player/app MethodChannel，提供应用文件目录、电池、网络和流量等原生能力。",
    ["android", "methodchannel", "kotlin"],
  ),
  node(
    "doc:architecture",
    "document",
    "架构设计",
    "docs/architecture.md",
    "项目分层文档，定义 Flutter UI、Bridge、Rust Core、Native，以及 media、tmdb、webdav、danmu、subtitle、playback 的职责边界。",
    ["docs", "architecture"],
    "simple",
  ),
  node(
    "doc:api",
    "document",
    "API 契约",
    "docs/api-contracts.md",
    "记录 Flutter 调 Rust、TMDB 和 danmu_api 的目标接口形态，是后续桥接和服务实现的契约来源。",
    ["docs", "api"],
    "simple",
  ),
  node(
    "doc:roadmap",
    "document",
    "开发路线",
    "docs/roadmap.md",
    "按 M1 到 M7 规划媒体库、TMDB、libmpv、字幕、WebDAV、弹幕和移动端发布。",
    ["docs", "roadmap"],
    "simple",
  ),
  node(
    "config:flutter-pubspec",
    "config",
    "Flutter 依赖配置",
    "apps/player_flutter/pubspec.yaml",
    "声明 Flutter SDK、file_picker、ffi、http、shared_preferences、xml、media_kit、permission_handler 和本地 Android media_kit libs。",
    ["config", "flutter", "dependencies"],
    "simple",
  ),
  node(
    "config:rust-cargo",
    "config",
    "Rust crate 配置",
    "crates/player_core/Cargo.toml",
    "声明 player_core crate 类型为 rlib 和 cdylib，依赖 reqwest、rusqlite、serde、tokio、roxmltree 等。",
    ["config", "rust", "cdylib"],
    "simple",
  ),
  node(
    "store:app-store",
    "class",
    "AppStore",
    "apps/player_flutter/lib/store/app_store.dart",
    "前端中心状态容器，管理媒体源、媒体项、播放进度、TMDB 配置、同步配置、元数据缓存和诊断日志。",
    ["state", "changenotifier", "persistence"],
    "complex",
  ),
  node(
    "model:media-models",
    "schema",
    "媒体模型",
    "apps/player_flutter/lib/models/media_models.dart",
    "定义 MediaSourceConfig、MediaItem、MediaFolderGroup、TmdbConfig、MediaMetadata、SyncConfig、WebdavEntry、LocalEntry 等前端领域模型。",
    ["models", "domain", "serialization"],
    "complex",
  ),
  node(
    "service:rust-core",
    "service",
    "RustCoreService",
    "apps/player_flutter/lib/services/rust_core_service.dart",
    "Dart FFI 封装层，动态加载 player_core 动态库，绑定 C ABI 函数并把 JSON 响应转换成 Dart 模型。",
    ["ffi", "service", "rust-bridge"],
    "complex",
  ),
  node(
    "service:media-scan",
    "service",
    "MediaScanService",
    "apps/player_flutter/lib/services/media_scan_service.dart",
    "根据来源类型扫描本地目录或 WebDAV 选择项。本地目录优先调用 RustCoreService 异步扫描。",
    ["scanner", "local", "webdav"],
  ),
  node(
    "service:tmdb",
    "service",
    "TmdbMetadataService",
    "apps/player_flutter/lib/services/tmdb_metadata_service.dart",
    "前端 TMDB 元数据匹配服务，按 MediaItem 或 MediaFolderGroup 搜索电影/剧集并生成 MediaMetadata。",
    ["tmdb", "metadata", "http"],
    "complex",
  ),
  node(
    "service:webdav",
    "service",
    "WebdavClient",
    "apps/player_flutter/lib/services/webdav_client.dart",
    "Dart WebDAV 客户端，执行目录遍历、文件查找、文本/字节上传下载，并可调用 Rust 解析 PROPFIND XML。",
    ["webdav", "network"],
  ),
  node(
    "service:sync",
    "service",
    "同步服务",
    "apps/player_flutter/lib/services/sync_service.dart",
    "提供 WebDAV 同步配置、上传状态和下载状态的 UI/服务流程。",
    ["sync", "webdav", "state"],
  ),
  node(
    "ui:shell",
    "class",
    "PlayerShell",
    "apps/player_flutter/lib/app/player_shell.dart",
    "应用主壳层，组织媒体库、来源、设置等主导航视图。",
    ["ui", "navigation"],
  ),
  node(
    "ui:library",
    "class",
    "MediaLibraryPage",
    "apps/player_flutter/lib/pages/media_library_page.dart",
    "媒体库和分组详情页面，展示海报墙、剧集组、元数据和播放入口。",
    ["ui", "library", "metadata"],
    "complex",
  ),
  node(
    "ui:source",
    "class",
    "SourceLibraryPage",
    "apps/player_flutter/lib/pages/source_library_page.dart",
    "媒体来源管理页面，展示本地和 WebDAV 来源，并触发扫描或选择。",
    ["ui", "sources"],
  ),
  node(
    "ui:add-source",
    "class",
    "AddSourcePage / WebDAV 表单",
    "apps/player_flutter/lib/pages/add_source_page.dart",
    "新增来源入口，包含 WebDAV 表单和远程目录浏览/选择流程。",
    ["ui", "webdav", "forms"],
  ),
  node(
    "ui:local-browser",
    "class",
    "LocalBrowserPage",
    "apps/player_flutter/lib/pages/local_browser_page.dart",
    "本地目录浏览器，调用 RustCoreService 列目录并添加或移除本地选择。",
    ["ui", "local-files"],
  ),
  node(
    "ui:profile",
    "class",
    "ProfilePage",
    "apps/player_flutter/lib/pages/profile_page.dart",
    "设置页，管理 TMDB、同步配置和诊断日志。",
    ["ui", "settings"],
  ),
  node(
    "ui:video-player",
    "class",
    "VideoPlayerPage",
    "apps/player_flutter/lib/pages/video_player_page.dart",
    "播放器页面，使用 media_kit/media_kit_video 控制播放、进度、全屏、横竖屏、音轨和字幕轨。",
    ["ui", "playback", "media_kit"],
    "complex",
  ),
  node(
    "core:lib-ffi",
    "file",
    "Rust FFI 导出层",
    "crates/player_core/src/lib.rs",
    "通过 extern C 函数统一返回 {ok,data,error} JSON 字符串，并提供 player_core_free_string 释放内存。",
    ["rust", "ffi", "c-abi"],
    "complex",
  ),
  node(
    "core:scanner",
    "file",
    "本地扫描模块",
    "crates/player_core/src/scanner.rs",
    "递归扫描本地视频文件、列目录并按扩展名判断视频文件。",
    ["rust", "scanner", "filesystem"],
  ),
  node(
    "core:media",
    "file",
    "媒体识别模块",
    "crates/player_core/src/media.rs",
    "从父目录名和文件名解析标题、年份、季集、媒体类型，并去除分辨率和编码等噪声 token。",
    ["rust", "parser", "metadata"],
  ),
  node(
    "core:webdav",
    "file",
    "Rust WebDAV 解析模块",
    "crates/player_core/src/webdav.rs",
    "解析 WebDAV PROPFIND XML/JSON，规范化远程路径和 URL，并提供 reqwest WebdavClient。",
    ["rust", "webdav", "xml"],
    "complex",
  ),
  node(
    "core:tmdb",
    "file",
    "Rust TMDB 客户端",
    "crates/player_core/src/tmdb.rs",
    "封装 TMDB 请求、Bearer token、代理 URL 和 movie/tv 搜索/详情 JSON 获取。",
    ["rust", "tmdb", "http"],
  ),
  node(
    "core:danmu",
    "file",
    "Rust 弹幕客户端",
    "crates/player_core/src/danmu.rs",
    "封装 danmu_api 匹配和弹幕事件结构，规范化弹幕时间、模式、颜色和文本。",
    ["rust", "danmu", "http"],
  ),
  node(
    "core:metadata-cache",
    "file",
    "SQLite 元数据缓存",
    "crates/player_core/src/metadata_cache.rs",
    "用 rusqlite 存储 TMDB 元数据、迁移旧结构、缓存图片数据并批量替换元数据。",
    ["rust", "sqlite", "cache"],
    "complex",
  ),
  node(
    "flow:media-library",
    "flow",
    "媒体库扫描与展示流程",
    undefined,
    "用户添加本地或 WebDAV 来源后，AppStore 调用 MediaScanService 扫描，生成 MediaItem，随后刷新 TMDB 元数据并在媒体库页面展示。",
    ["flow", "media-library"],
    "complex",
  ),
  node(
    "flow:metadata",
    "flow",
    "TMDB 元数据刷新流程",
    undefined,
    "AppStore 按媒体分组并发调用 TmdbMetadataService，匹配结果写入内存状态和 Rust SQLite 缓存。",
    ["flow", "tmdb", "cache"],
    "complex",
  ),
  node(
    "flow:playback",
    "flow",
    "播放流程",
    undefined,
    "MediaLibraryPage 进入 VideoPlayerPage，media_kit 负责播放，本地或远程 URL 和播放进度由前端状态与页面逻辑管理。",
    ["flow", "playback"],
  ),
];

const edges = [
  edge("project:player", "app:flutter", "contains", "工作区包含 Flutter 前端应用。"),
  edge("project:player", "core:rust", "contains", "工作区包含 Rust player_core crate。"),
  edge("project:player", "doc:architecture", "documents", "架构文档描述项目分层。"),
  edge("doc:api", "app:flutter", "documents", "API 契约约束 Flutter 到 Rust 的调用边界。"),
  edge("doc:api", "core:rust", "documents", "API 契约约束 Rust core 对外能力。"),
  edge("doc:roadmap", "project:player", "documents", "路线图记录功能迭代阶段。"),
  edge("config:flutter-pubspec", "app:flutter", "configures", "pubspec 配置 Flutter 依赖。"),
  edge("config:rust-cargo", "core:rust", "configures", "Cargo.toml 配置 Rust 动态库和依赖。"),
  edge("app:flutter", "store:app-store", "contains", "main.dart 通过 part 引入 AppStore。"),
  edge("app:flutter", "ui:shell", "contains", "main.dart 通过 part 引入主壳层。"),
  edge("app:flutter", "model:media-models", "contains", "main.dart 通过 part 引入媒体模型。"),
  edge("app:flutter", "service:rust-core", "contains", "main.dart 通过 part 引入 Rust FFI 服务。"),
  edge("app:flutter", "service:webdav", "contains", "main.dart 通过 part 引入 WebDAV 客户端。"),
  edge("ui:shell", "ui:library", "contains", "主壳层组织媒体库页面。"),
  edge("ui:shell", "ui:source", "contains", "主壳层组织来源页面。"),
  edge("ui:shell", "ui:profile", "contains", "主壳层组织设置页面。"),
  edge("ui:source", "ui:add-source", "routes", "来源页进入新增来源和 WebDAV 浏览流程。"),
  edge("ui:add-source", "service:webdav", "calls", "WebDAV 表单和浏览页调用 WebdavClient。"),
  edge("ui:local-browser", "service:rust-core", "calls", "本地浏览页通过 FFI 列目录。"),
  edge("ui:library", "ui:video-player", "routes", "媒体库选择媒体后进入播放器页。"),
  edge("ui:video-player", "store:app-store", "calls", "播放器页写入进度、时长和方向偏好。"),
  edge("ui:video-player", "model:media-models", "depends_on", "播放器页读取 MediaItem、MediaMetadata 等模型。"),
  edge("store:app-store", "service:media-scan", "calls", "AppStore 调用扫描服务刷新媒体项。"),
  edge("store:app-store", "service:tmdb", "calls", "AppStore 调用 TMDB 服务刷新缺失元数据。"),
  edge("store:app-store", "service:rust-core", "calls", "AppStore 通过 RustCoreService 读写 SQLite 元数据缓存。"),
  edge("store:app-store", "service:webdav", "calls", "AppStore 在 WebDAV 选择目录时直接扫描远程视频。"),
  edge("store:app-store", "model:media-models", "writes_to", "AppStore 持有并序列化媒体源、媒体项、配置和元数据。"),
  edge("service:media-scan", "service:rust-core", "calls", "本地目录扫描委托给 Rust 动态库。"),
  edge("service:media-scan", "service:webdav", "calls", "WebDAV 来源扫描委托给 WebdavClient。"),
  edge("service:tmdb", "service:rust-core", "calls", "TMDB 请求可经 RustCoreService tmdb_get_json 代理执行。"),
  edge("service:webdav", "service:rust-core", "calls", "WebDAV PROPFIND 响应可交由 Rust 解析器解析。"),
  edge("service:sync", "service:webdav", "calls", "同步服务使用 WebDAV 上传和下载应用状态。"),
  edge("service:rust-core", "core:lib-ffi", "calls", "Dart FFI lookupFunction 绑定 Rust extern C 导出。"),
  edge("core:lib-ffi", "core:scanner", "calls", "FFI 导出本地扫描和列目录。"),
  edge("core:lib-ffi", "core:media", "calls", "FFI 导出媒体身份解析。"),
  edge("core:lib-ffi", "core:webdav", "calls", "FFI 导出 WebDAV XML 解析。"),
  edge("core:lib-ffi", "core:tmdb", "calls", "FFI 导出 TMDB JSON 获取。"),
  edge("core:lib-ffi", "core:metadata-cache", "calls", "FFI 导出 SQLite 元数据读写和图片缓存。"),
  edge("core:scanner", "core:media", "depends_on", "扫描结果由前端模型进一步调用媒体身份解析。"),
  edge("core:webdav", "core:danmu", "related", "两者都是远程 HTTP/XML/JSON 数据适配模块。", 0.45),
  edge("platform:android", "app:flutter", "serves", "Android MethodChannel 为 Flutter 提供 appFilesDir、电池和网络数据。"),
  edge("flow:media-library", "store:app-store", "flow_step", "AppStore 是媒体库扫描流程的编排者。"),
  edge("flow:media-library", "service:media-scan", "flow_step", "扫描服务把来源转换为媒体项。"),
  edge("flow:media-library", "ui:library", "flow_step", "媒体库页面展示扫描结果。"),
  edge("flow:metadata", "store:app-store", "flow_step", "AppStore 控制刷新状态和并发 worker。"),
  edge("flow:metadata", "service:tmdb", "flow_step", "TMDB 服务完成搜索与详情匹配。"),
  edge("flow:metadata", "core:metadata-cache", "writes_to", "匹配结果最终落到 SQLite 缓存。"),
  edge("flow:playback", "ui:library", "flow_step", "用户从媒体库选择播放条目。"),
  edge("flow:playback", "ui:video-player", "flow_step", "播放器页使用 media_kit 执行播放控制。"),
  edge("flow:playback", "store:app-store", "writes_to", "播放进度和时长写回状态。"),
];

const analyzedAt = new Date().toISOString();
const graph = {
  version: "1.0.0",
  kind: "codebase",
  project: {
    name: "player",
    languages: ["Dart", "Rust", "Markdown", "TOML", "YAML", "Kotlin", "XML"],
    frameworks: ["Flutter", "media_kit", "Rust FFI", "Android MethodChannel", "SQLite"],
    description:
      "跨平台视频播放器：Flutter 前端负责媒体库、设置和播放界面，Rust player_core 负责本地扫描、媒体识别、WebDAV/TMDB/danmu 适配和元数据缓存。",
    analyzedAt,
    gitCommitHash,
  },
  nodes,
  edges,
  layers: [
    {
      id: "layer:frontend",
      name: "Flutter 前端",
      description: "页面、状态、模型和服务层，负责用户体验和播放控制。",
      nodeIds: [
        "app:flutter",
        "store:app-store",
        "model:media-models",
        "service:rust-core",
        "service:media-scan",
        "service:tmdb",
        "service:webdav",
        "service:sync",
        "ui:shell",
        "ui:library",
        "ui:source",
        "ui:add-source",
        "ui:local-browser",
        "ui:profile",
        "ui:video-player",
        "config:flutter-pubspec",
      ],
    },
    {
      id: "layer:rust-core",
      name: "Rust 核心",
      description: "动态库和业务模块，承接扫描、解析、网络适配和 SQLite 缓存。",
      nodeIds: [
        "core:rust",
        "core:lib-ffi",
        "core:scanner",
        "core:media",
        "core:webdav",
        "core:tmdb",
        "core:danmu",
        "core:metadata-cache",
        "config:rust-cargo",
      ],
    },
    {
      id: "layer:platform",
      name: "平台集成",
      description: "Android 原生桥和 Flutter/Rust 动态库加载边界。",
      nodeIds: ["platform:android"],
    },
    {
      id: "layer:docs",
      name: "文档和规划",
      description: "架构、API 契约和路线图。",
      nodeIds: ["doc:architecture", "doc:api", "doc:roadmap"],
    },
    {
      id: "layer:flows",
      name: "核心业务流程",
      description: "媒体库扫描、元数据刷新和播放流程。",
      nodeIds: ["flow:media-library", "flow:metadata", "flow:playback"],
    },
  ],
  tour: [
    {
      order: 1,
      title: "从工作区开始",
      description: "先看 Player 工作区，理解 Flutter 前端和 Rust core 的双层结构。",
      nodeIds: ["project:player", "app:flutter", "core:rust"],
      languageLesson: "Rust cdylib 让 Flutter 可以通过 FFI 直接调用核心能力。",
    },
    {
      order: 2,
      title: "理解前端状态中枢",
      description: "AppStore 是来源、媒体项、进度、TMDB 配置和缓存写入的中心。",
      nodeIds: ["store:app-store", "model:media-models"],
      languageLesson: "ChangeNotifier 模式把状态变更广播给 Flutter UI。",
    },
    {
      order: 3,
      title: "看 Flutter 到 Rust 的桥",
      description: "RustCoreService 动态加载 player_core，并用 JSON 字符串作为跨语言返回格式。",
      nodeIds: ["service:rust-core", "core:lib-ffi"],
      languageLesson: "FFI 边界要显式释放 Rust 分配的字符串，项目通过 player_core_free_string 完成。",
    },
    {
      order: 4,
      title: "跟踪媒体库扫描",
      description: "AppStore 调用 MediaScanService，本地目录走 Rust 扫描，WebDAV 走 Dart 客户端递归扫描。",
      nodeIds: ["flow:media-library", "service:media-scan", "core:scanner", "service:webdav"],
      languageLesson: "本地文件系统扫描放到 Rust，远程源遍历保留在 Dart 服务层。",
    },
    {
      order: 5,
      title: "跟踪元数据刷新",
      description: "TMDB 匹配结果进入内存状态并写入 Rust SQLite 缓存。",
      nodeIds: ["flow:metadata", "service:tmdb", "core:metadata-cache"],
      languageLesson: "缓存层把 UI 状态持久化，减少重复网络匹配。",
    },
    {
      order: 6,
      title: "跟踪播放入口",
      description: "媒体库进入 VideoPlayerPage，media_kit 负责播放控制，AppStore 记录进度和方向。",
      nodeIds: ["flow:playback", "ui:library", "ui:video-player", "store:app-store"],
      languageLesson: "当前播放核心主要在 Flutter/media_kit，文档中规划的 libmpv Rust playback 仍是后续阶段。",
    },
  ],
};

const configPath = path.join(outDir, "config.json");
let config = { autoUpdate: false };
if (fs.existsSync(configPath)) {
  try {
    config = { ...config, ...JSON.parse(fs.readFileSync(configPath, "utf8")) };
  } catch {}
}
config.outputLanguage = "zh";

fs.writeFileSync(configPath, JSON.stringify(config, null, 2), "utf8");
fs.writeFileSync(path.join(intermediateDir, "assembled-graph.json"), JSON.stringify(graph, null, 2), "utf8");
fs.writeFileSync(path.join(outDir, "knowledge-graph.json"), JSON.stringify(graph, null, 2), "utf8");
fs.writeFileSync(
  path.join(outDir, "meta.json"),
  JSON.stringify(
    {
      lastAnalyzedAt: analyzedAt,
      gitCommitHash,
      version: graph.version,
      analyzedFiles: sourceFiles.length,
    },
    null,
    2,
  ),
  "utf8",
);
fs.writeFileSync(
  path.join(intermediateDir, "scan-result.json"),
  JSON.stringify(
    {
      files: sourceFiles,
      languages: graph.project.languages,
      frameworks: graph.project.frameworks,
      generatedAt: analyzedAt,
    },
    null,
    2,
  ),
  "utf8",
);

console.log(JSON.stringify({ nodes: nodes.length, edges: edges.length, files: sourceFiles.length }, null, 2));
