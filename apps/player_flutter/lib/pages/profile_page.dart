part of 'package:player_flutter/main.dart';

class ProfilePage extends StatelessWidget {
  const ProfilePage({required this.store, super.key});

  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final sync = store.syncConfig;
    return SafeArea(
      bottom: false,
      child: ListView(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(22, 34, 22, 30),
            decoration: const BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFDCEEFF), Colors.white]),
            ),
            child: Column(
              children: [
                const CircleAvatar(
                  radius: 56,
                  backgroundColor: Color(0xFFAFC7F7),
                  child: Icon(Icons.cloud_sync_outlined, color: Colors.white, size: 58),
                ),
                const SizedBox(height: 22),
                const Text('配置同步', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text(sync == null ? '未设置同步 WebDAV' : sync.baseUrl, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              children: [
                ProfileActionCard(
                  icon: Icons.settings_outlined,
                  title: '同步 WebDAV',
                  subtitle: sync == null ? '单独配置用于备份整个 App 状态' : sync.configPath,
                  actionText: sync == null ? '设置' : '编辑',
                  onTap: () => showSyncConfigDialog(context, store),
                ),
                ProfileActionCard(
                  icon: Icons.upload_file,
                  title: '上传配置',
                  subtitle: '上传播放进度、已添加源和设置',
                  actionText: '上传',
                  onTap: () => uploadState(context, store),
                ),
                ProfileActionCard(
                  icon: Icons.download_for_offline_outlined,
                  title: '下载配置',
                  subtitle: '从同步 WebDAV 恢复 App 状态',
                  actionText: '下载',
                  onTap: () => downloadState(context, store),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
