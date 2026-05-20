import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../utils/storage_util.dart';
import '../../widgets/common/app_card.dart';

/// 首页 - 功能入口6宫格 + 最近创作 + 首次引导
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasApiKey = false;
  List<Map<String, dynamic>> _recentRecords = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final hasKey = await StorageUtil.hasAnyApiKey();
      final records = await StorageUtil.getRecentRecords(limit: 3);
      if (mounted) {
        setState(() {
          _hasApiKey = hasKey;
          _recentRecords = records;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
            : RefreshIndicator(
                onRefresh: _loadData,
                color: AppTheme.primaryColor,
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(child: _buildHeader()),
                    if (_error != null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text('加载异常: $_error', style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      ),
                    if (!_hasApiKey)
                      SliverToBoxAdapter(child: _buildSetupGuide()),
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppTheme.spacingMedium,
                        vertical: AppTheme.spacingSmall,
                      ),
                      sliver: SliverGrid(
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: AppTheme.spacingMedium,
                          crossAxisSpacing: AppTheme.spacingMedium,
                          childAspectRatio: 0.82,
                        ),
                        delegate: SliverChildListDelegate(_buildGridItems(context)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppTheme.spacingLarge,
                          AppTheme.spacingLarge,
                          AppTheme.spacingLarge,
                          AppTheme.spacingSmall,
                        ),
                        child: Row(
                          children: [
                            const Text('最近创作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            const Spacer(),
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, AppRoutes.history),
                              child: const Text('查看全部'),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _recentRecords.isEmpty
                        ? SliverToBoxAdapter(child: _buildEmptyRecent())
                        : SliverList(
                            delegate: SliverChildListDelegate(
                              _recentRecords.map((r) => _buildRecentItem(r)).toList(),
                            ),
                          ),
                    const SliverToBoxAdapter(child: SizedBox(height: AppTheme.spacingXLarge)),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppTheme.spacingLarge, AppTheme.spacingMedium,
        AppTheme.spacingLarge, AppTheme.spacingLarge,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F3460), Color(0xFF1A1A2E)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: const Icon(Icons.smart_display, color: AppTheme.primaryColor, size: 28),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('口播智能体', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppTheme.textPrimary)),
                SizedBox(height: 2),
                Text('你的AI口播创作助手', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
              ],
            ),
          ),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppTheme.darkSurface.withOpacity(0.5),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: IconButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
              icon: const Icon(Icons.settings, color: AppTheme.textSecondary, size: 22),
              padding: EdgeInsets.zero,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSetupGuide() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppTheme.spacingMedium, AppTheme.spacingSmall, AppTheme.spacingMedium, 0),
      child: Container(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [AppTheme.primaryColor.withOpacity(0.15), AppTheme.accentColor.withOpacity(0.1)],
          ),
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: const Icon(Icons.info_outline, color: AppTheme.primaryColor, size: 22),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('快速配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                  SizedBox(height: 2),
                  Text('请先在设置页配置API Key，即可开始使用', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
              ),
              child: const Text('去配置', style: TextStyle(fontSize: 13)),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildGridItems(BuildContext context) {
    final items = [
      _GridItem(icon: Icons.auto_awesome, label: '创作工作台', subtitle: '一键创作口播视频', color: AppTheme.primaryColor, isMain: true, onTap: () => Navigator.pushNamed(context, AppRoutes.extract)),
      _GridItem(icon: Icons.edit_note, label: 'AI改写', subtitle: '多种改写模式', color: const Color(0xFF81C784), onTap: () => Navigator.pushNamed(context, AppRoutes.rewrite)),
      _GridItem(icon: Icons.shield_outlined, label: '法务审核', subtitle: '合规风险检测', color: const Color(0xFFFFB74D), onTap: () => Navigator.pushNamed(context, AppRoutes.audit)),
      _GridItem(icon: Icons.record_voice_over, label: '语音合成', subtitle: 'TTS配音', color: const Color(0xFFE57373), onTap: () => Navigator.pushNamed(context, AppRoutes.voice)),
      _GridItem(icon: Icons.smart_toy_outlined, label: '数字人视频', subtitle: '口播视频生成', color: const Color(0xFFBA68C8), onTap: () => Navigator.pushNamed(context, AppRoutes.digitalHuman)),
      _GridItem(icon: Icons.history, label: '历史记录', subtitle: '查看创作记录', color: const Color(0xFF4DD0E1), onTap: () => Navigator.pushNamed(context, AppRoutes.history)),
    ];
    return items.map((item) => _buildGridCard(item)).toList();
  }

  Widget _buildGridCard(_GridItem item) {
    return AppCard(
      onTap: item.onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: item.isMain ? 52 : 44, height: item.isMain ? 52 : 44,
            decoration: BoxDecoration(
              color: item.color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Icon(item.icon, color: item.color, size: item.isMain ? 28 : 24),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Text(item.label, style: TextStyle(fontSize: item.isMain ? 15 : 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary), textAlign: TextAlign.center),
          if (item.subtitle != null) ...[
            const SizedBox(height: 2),
            Text(item.subtitle!, style: TextStyle(fontSize: item.isMain ? 12 : 11, color: AppTheme.textHint), textAlign: TextAlign.center),
          ],
          if (item.isMain) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF1A73E8), Color(0xFF0D47A1)]),
                borderRadius: BorderRadius.circular(3),
              ),
              child: const Text('核心入口', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyRecent() {
    return const SliverToBoxAdapter(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: AppTheme.spacingXLarge),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.create_outlined, size: 48, color: AppTheme.textHint),
              SizedBox(height: AppTheme.spacingSmall),
              Text('还没有创作记录', style: TextStyle(fontSize: 14, color: AppTheme.textHint)),
              SizedBox(height: 4),
              Text('开始你的第一次口播创作吧！', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentItem(Map<String, dynamic> record) {
    final type = record['type'] as String? ?? 'script';
    final title = record['title'] as String? ?? '';
    final time = _formatTime(record['time'] as String?);
    final status = record['status'] as String? ?? '';

    IconData icon;
    Color color;
    switch (type) {
      case 'audio': icon = Icons.audiotrack; color = const Color(0xFFE57373); break;
      case 'video': icon = Icons.videocam; color = const Color(0xFFBA68C8); break;
      default: icon = Icons.description; color = AppTheme.primaryColor;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium, vertical: AppTheme.spacingXS),
      child: AppCard(
        onTap: () => Navigator.pushNamed(context, AppRoutes.history),
        child: Row(
          children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(AppTheme.radiusSmall)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(time, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: AppTheme.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);
      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day}';
    } catch (_) { return ''; }
  }
}

class _GridItem {
  final IconData icon;
  final String label;
  final String? subtitle;
  final Color color;
  final bool isMain;
  final VoidCallback onTap;
  _GridItem({required this.icon, required this.label, this.subtitle, required this.color, this.isMain = false, required this.onTap});
}
