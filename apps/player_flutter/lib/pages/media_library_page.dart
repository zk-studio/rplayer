part of 'package:player_flutter/main.dart';

class MediaLibraryPage extends StatelessWidget {
  const MediaLibraryPage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
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
                  IconButton(tooltip: '刷新', onPressed: store.rescanAll, icon: const Icon(Icons.refresh, size: 30)),
                ],
              ),
            ),
          ),
          if (!store.loaded)
            const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
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
            SliverToBoxAdapter(child: SectionHeader(title: '海报墙', count: store.items.length)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 22),
              sliver: SliverGrid.builder(
                itemCount: store.items.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 18,
                  childAspectRatio: 0.88,
                ),
                itemBuilder: (context, index) {
                  final item = store.items[index];
                  return MediaTile(
                    item: item,
                    progressMs: store.progress[item.id] ?? 0,
                    onTap: () => openPlayer(context, store, item),
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
