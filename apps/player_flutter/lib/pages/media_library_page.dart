part of 'package:player_flutter/main.dart';

class MediaLibraryPage extends StatelessWidget {
  const MediaLibraryPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final groups =
        mediaFolderGroups(store.items, lastPlayedAt: store.lastPlayedAt);
    final recentItems = store.items
        .where((item) => store.lastPlayedAt.containsKey(item.id))
        .toList()
      ..sort((a, b) => (store.lastPlayedAt[b.id] ?? 0)
          .compareTo(store.lastPlayedAt[a.id] ?? 0));

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
              child: Row(
                children: [
                  const AppBrand(),
                  const Spacer(),
                  IconButton(
                    tooltip: '刷新',
                    onPressed: store.rescanAll,
                    icon: const Icon(Icons.refresh, size: 26),
                  ),
                ],
              ),
            ),
          ),
          if (!store.loaded)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (store.items.isEmpty)
            SliverFillRemaining(
              child: EmptyState(
                icon: Icons.video_library_outlined,
                title: '还没有视频',
                message: '请先到资源库添加本地目录或 WebDAV 目录源。',
                action: FilledButton.icon(
                  onPressed: () => openAddSource(context, store),
                  icon: const Icon(Icons.add),
                  label: const Text('添加源'),
                ),
              ),
            )
          else ...[
            if (recentItems.isNotEmpty) ...[
              SliverToBoxAdapter(
                child: SectionHeader(
                  title: '最近播放',
                  count: recentItems.length,
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 176,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    scrollDirection: Axis.horizontal,
                    itemCount: math.min(recentItems.length, 12),
                    separatorBuilder: (_, __) => const SizedBox(width: 14),
                    itemBuilder: (context, index) {
                      final item = recentItems[index];
                      final group = groups.firstWhere(
                        (group) => group.key == mediaFolderKey(item),
                        orElse: () => MediaFolderGroup(
                          key: mediaFolderKey(item),
                          title: mediaGroupDisplayTitle(item),
                          items: [item],
                          representative: item,
                          latestPlayedAt: store.lastPlayedAt[item.id] ?? 0,
                        ),
                      );
                      final metadata = store.metadata[item.id];
                      return SizedBox(
                        width: 240,
                        child: RecentMediaTile(
                          item: item,
                          metadata: metadata,
                          progressMs: store.progress[item.id] ?? 0,
                          durationMs: store.durations[item.id] ?? 0,
                          displayTitle:
                              recentMediaTitle(item, metadata, group.title),
                          onTap: () => openPlayer(context, store, item),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],
            SliverToBoxAdapter(
              child: SectionHeader(title: '电视剧', count: groups.length),
            ),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverGrid.builder(
                itemCount: groups.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 126,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 22,
                  childAspectRatio: 0.48,
                ),
                itemBuilder: (context, index) {
                  final group = groups[index];
                  final item = group.representative;
                  return MediaTile(
                    item: item,
                    metadata: mediaGroupMetadata(group, store.metadata),
                    progressMs: 0,
                    displayTitle: group.title,
                    itemCount: group.items.length,
                    onTap: () => openMediaGroup(context, store, group),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ],
      ),
    );
  }
}

String recentMediaTitle(
    MediaItem item, MediaMetadata? metadata, String groupTitle) {
  final episode = inferredEpisodeNumber(item);
  final episodeName = metadata?.episodeName;
  if (episode != null && episodeName?.isNotEmpty == true) {
    return '$groupTitle 第 $episode 集 $episodeName';
  }
  if (episode != null) return '$groupTitle 第 $episode 集';
  return item.title;
}

void openMediaGroup(
    BuildContext context, AppStore store, MediaFolderGroup group) {
  Navigator.of(context).push(
    PageRouteBuilder<void>(
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, __, ___) =>
          MediaGroupPage(store: store, groupKey: group.key),
    ),
  );
}

class MediaGroupPage extends StatelessWidget {
  const MediaGroupPage(
      {required this.store, required this.groupKey, super.key});

  final AppStore store;
  final String groupKey;

  @override
  Widget build(BuildContext context) {
    final group = mediaFolderGroups(
      store.items.where((item) => mediaFolderKey(item) == groupKey),
      lastPlayedAt: store.lastPlayedAt,
    ).firstOrNull;

    if (group == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('没有可播放的视频')),
      );
    }

    final representative = group.representative;
    final metadata = mediaGroupMetadata(group, store.metadata);
    final title =
        metadata?.title.isNotEmpty == true ? metadata!.title : group.title;
    final backdropUrl = metadata?.backdropUrl ?? metadata?.posterUrl;
    final posterUrl = metadata?.posterUrl;
    final totalEpisodes = metadata?.totalEpisodes;
    final totalSeasons = metadata?.totalSeasons;
    final releaseDate = metadata?.releaseDate;
    final genres = metadata?.genres ?? const <String>[];
    final castNames = metadata?.castNames ?? const <String>[];
    final firstPlayable = group.items.first;
    final heroHeight =
        (MediaQuery.sizeOf(context).height * 0.48).clamp(360.0, 440.0);

    return Scaffold(
      backgroundColor: const Color(0xFF090B08),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: SizedBox(
              height: heroHeight,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (backdropUrl != null)
                    Image.network(
                      backdropUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => MediaPosterFallback(
                        remote: representative.type == SourceType.webdav,
                      ),
                    )
                  else
                    MediaPosterFallback(
                      remote: representative.type == SourceType.webdav,
                    ),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x66000000),
                          Color(0x33000000),
                          Color(0xFF090B08),
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                      child: Align(
                        alignment: Alignment.topLeft,
                        child: IconButton(
                          color: Colors.white,
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.chevron_left, size: 30),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 18,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (posterUrl != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  posterUrl,
                                  width: 76,
                                  height: 114,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox(),
                                ),
                              ),
                            if (posterUrl != null) const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            if ((metadata?.voteAverage ?? 0) > 0)
                              _DarkMetaChip(
                                icon: Icons.local_movies,
                                label:
                                    metadata!.voteAverage!.toStringAsFixed(1),
                                accent: const Color(0xFF60D264),
                              ),
                            if (releaseDate?.isNotEmpty == true)
                              _DarkMetaChip(
                                icon: Icons.calendar_month_outlined,
                                label: releaseDate!,
                              ),
                            if (totalEpisodes != null)
                              _DarkTextChip(
                                label:
                                    '共 $totalEpisodes 集（库中有 ${group.items.length} 集）',
                              )
                            else
                              _DarkTextChip(
                                  label: '库中 ${group.items.length} 集'),
                          ],
                        ),
                        if (genres.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            genres.join('  '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(28, 0, 28, 34),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: () => openPlayer(context, store, firstPlayable),
                    icon: const Icon(Icons.play_arrow, size: 24),
                    label: Text(
                      '第 ${inferredEpisodeNumber(firstPlayable) ?? 1} 集',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Text(
                      '第 ${totalSeasons == null || totalSeasons <= 1 ? 1 : 1} 季',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Colors.white),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  width: 90,
                  height: 3,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 142,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: group.items.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final item = group.items[index];
                      return SizedBox(
                        width: 176,
                        child: _EpisodeCard(
                          item: item,
                          metadata: store.metadata[item.id] ?? metadata,
                          progressMs: store.progress[item.id] ?? 0,
                          durationMs: store.durations[item.id] ?? 0,
                          onTap: () => openPlayer(context, store, item),
                        ),
                      );
                    },
                  ),
                ),
                if (metadata?.overview?.isNotEmpty == true) ...[
                  const SizedBox(height: 24),
                  const _DarkSectionHeader(title: '剧情简介'),
                  const SizedBox(height: 12),
                  Text(
                    metadata!.overview!,
                    maxLines: 6,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xDDFFFFFF),
                      height: 1.55,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (castNames.isNotEmpty) ...[
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: castNames
                        .take(6)
                        .map((name) => Text(
                              name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ))
                        .toList(),
                  ),
                ],
                const SizedBox(height: 22),
                const Divider(color: Color(0x22FFFFFF)),
                const SizedBox(height: 14),
                Text(
                  group.items.map((item) => item.title).join('\n'),
                  style: const TextStyle(color: Color(0xCCFFFFFF), height: 1.8),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkMetaChip extends StatelessWidget {
  const _DarkMetaChip({
    required this.icon,
    required this.label,
    this.accent = Colors.white,
  });

  final IconData icon;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: accent, size: 15),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _DarkTextChip extends StatelessWidget {
  const _DarkTextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 12,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _DarkSectionHeader extends StatelessWidget {
  const _DarkSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 17,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _EpisodeCard extends StatelessWidget {
  const _EpisodeCard({
    required this.item,
    required this.metadata,
    required this.progressMs,
    required this.durationMs,
    required this.onTap,
  });

  final MediaItem item;
  final MediaMetadata? metadata;
  final int progressMs;
  final int durationMs;
  final VoidCallback onTap;

  double get progressValue {
    if (progressMs <= 0) return 0;
    if (durationMs <= 0) return 0.06;
    return (progressMs / durationMs).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = metadata?.stillUrl ?? metadata?.backdropUrl;
    final episode = inferredEpisodeNumber(item);
    final episodeTitle = metadata?.episodeName?.isNotEmpty == true
        ? metadata!.episodeName!
        : item.title;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (imageUrl != null)
                    Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => MediaPosterFallback(
                          remote: item.type == SourceType.webdav),
                    )
                  else
                    MediaPosterFallback(remote: item.type == SourceType.webdav),
                  const Center(
                    child: CircleAvatar(
                      radius: 15,
                      backgroundColor: Color(0xAA000000),
                      child:
                          Icon(Icons.play_arrow, color: Colors.white, size: 20),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: LinearProgressIndicator(
                      minHeight: 3,
                      value: progressValue,
                      backgroundColor: const Color(0x66FFFFFF),
                      color: const Color(0xFF2E7AF6),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 7),
          Text(
            episode == null ? episodeTitle : '$episode. $episodeTitle',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
