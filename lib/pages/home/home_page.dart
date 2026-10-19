import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../utils/storage_util.dart';
import '../../widgets/common/app_card.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  bool _hasApiKey = false;
  List<Map<String, dynamic>> _recentRecords = [];
  bool _isLoading = true;
  String? _loadError;
  Map<String, dynamic> _stats = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      bool hasKey = false;
      List<Map<String, dynamic>> records = [];
      Map<String, dynamic> stats = {};

      try { hasKey = await StorageUtil.hasAnyApiKey(); } catch (e) { debugPrint('hasAnyApiKey: $e'); }
      try { records = await StorageUtil.getRecentRecords(limit: 3); } catch (e) { debugPrint('getRecentRecords: $e'); }
      try { stats = await StorageUtil.getDashboardStats(); } catch (e) { debugPrint('getDashboardStats: $e'); }

      if (mounted) {
        setState(() {
          _hasApiKey = hasKey;
          _recentRecords = records;
          _stats = stats;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _isLoading = false; _loadError = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    try {
      return Scaffold(
        body: SafeArea(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    children: [
                      _buildHeader(),
                      if (_loadError != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.red.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                            child: Text(_loadError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                          ),
                        ),
                      if (!_hasApiKey) _buildSetupGuide(),
                      // 工作台数据概览（临时注释，排查Stack Overflow）
                      // Padding(
                      //   padding: const EdgeInsets.fromLTRB(AppTheme.spacingMedium, 8, AppTheme.spacingMedium, AppTheme.spacingMedium),
                      //   child: _buildStatsOverview(),
                      // ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppTheme.spacingMedium, 0, AppTheme.spacingMedium, 4),
                        child: const Text(
                          '创作工具',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
                        child: _buildGrid(),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                        child: Row(
                          children: [
                            const Text('最近创作', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppTheme.textPrimary)),
                            const Spacer(),
                            TextButton(onPressed: () => Navigator.pushNamed(context, AppRoutes.history), child: const Text('查看全部')),
                          ],
                        ),
                      ),
                      if (_recentRecords.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(children: const [
                              Icon(Icons.create_outlined, size: 48, color: AppTheme.textHint),
                              SizedBox(height: 8),
                              Text('还没有创作记录', style: TextStyle(fontSize: 14, color: AppTheme.textHint)),
                            ]),
                          ),
                        ),
                      for (final r in _recentRecords) _buildRecentItem(r),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
        ),
      );
    } catch (e) {
      // If build itself throws, show error
      return Scaffold(
        backgroundColor: const Color(0xFF1A1A2E),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              const Text('首页渲染失败', style: TextStyle(color: Colors.white, fontSize: 18)),
              const SizedBox(height: 8),
              Text(e.toString(), style: const TextStyle(color: Colors.orange, fontSize: 12), textAlign: TextAlign.center),
            ]),
          ),
        ),
      );
    }
  }

  Widget _buildHeader() {
    final now = DateTime.now();
    final hour = now.hour;
    String greeting = '早上好';
    if (hour >= 12 && hour < 14) greeting = '中午好';
    else if (hour >= 14 && hour < 18) greeting = '下午好';
    else if (hour >= 18 && hour < 24) greeting = '晚上好';
    else if (hour >= 0 && hour < 5) greeting = '深夜了';

    final dateStr = '${now.month}月${now.day}日 ${['一','二','三','四','五','六','日'][now.weekday-1]}';

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFF0F3460), Color(0xFF1A1A2E)],
        ),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: const Color(0xFF1A73E8).withOpacity(0.2), borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.smart_display, color: Color(0xFF1A73E8), size: 28),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Text(greeting, style: const TextStyle(fontSize: 14, color: Color(0xFFB0BEC5))),
            const SizedBox(width: 8),
            Text('👋', style: const TextStyle(fontSize: 14)),
          ]),
          const SizedBox(height: 2),
          const Text('口播智能体', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          const SizedBox(height: 2),
          Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF90A4AE))),
        ])),
        SizedBox(
          width: 40, height: 40,
          child: IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings, color: Color(0xFFB0BEC5), size: 22),
          ),
        ),
      ]),
    );
  }

  Widget _buildSetupGuide() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A73E8).withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF1A73E8).withOpacity(0.3)),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline, color: Color(0xFF1A73E8), size: 22),
          const SizedBox(width: 12),
          const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('快速配置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Color(0xFF1A73E8))),
            SizedBox(height: 2),
            Text('请先在设置页配置API Key', style: TextStyle(fontSize: 13, color: Color(0xFFB0BEC5))),
          ])),
          ElevatedButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A73E8), foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
            child: const Text('去配置', style: TextStyle(fontSize: 13)),
          ),
        ]),
      ),
    );
  }

  /// 工作台数据概览卡片
  Widget _buildStatsOverview() {
    final totalScripts = _stats['totalScripts'] ?? 0;
    final totalAudios = _stats['totalAudios'] ?? 0;
    final totalVideos = _stats['totalVideos'] ?? 0;
    final todayScripts = _stats['todayScripts'] ?? 0;
    final todayWords = _stats['todayWords'] ?? 0;
    final totalWords = _stats['totalWords'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '数据概览',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _buildStatCard(
              '今日文案',
              todayScripts.toString(),
              Icons.description,
              const Color(0xFF1A73E8),
              subtitle: '总${totalScripts}篇',
            )),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(
              '今日字数',
              _formatNumber(todayWords),
              Icons.text_fields,
              const Color(0xFF81C784),
              subtitle: '总${_formatNumber(totalWords)}字',
            )),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(
              '音频作品',
              totalAudios.toString(),
              Icons.mic,
              const Color(0xFFE57373),
              subtitle: '已生成',
            )),
            const SizedBox(width: 10),
            Expanded(child: _buildStatCard(
              '视频作品',
              totalVideos.toString(),
              Icons.movie,
              const Color(0xFFBA68C8),
              subtitle: '已生成',
            )),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, {String subtitle = ''}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0F3460),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: AppTheme.textHint),
            ),
          ],
        ],
      ),
    );
  }

  String _formatNumber(int num) {
    if (num >= 10000) {
      return '${(num / 10000).toStringAsFixed(1)}w';
    } else if (num >= 1000) {
      return '${(num / 1000).toStringAsFixed(1)}k';
    }
    return num.toString();
  }

  Widget _buildGrid() {
    final items = [
      (Icons.content_paste, '文案提取', const Color(0xFF1A73E8), AppRoutes.extract),
      (Icons.edit_note, 'AI改写', const Color(0xFF81C784), AppRoutes.rewrite),
      (Icons.shield_outlined, '法务审核', const Color(0xFFFFB74D), AppRoutes.audit),
      (Icons.record_voice_over, '语音合成', const Color(0xFFE57373), AppRoutes.voice),
      (Icons.smart_toy_outlined, '数字人', const Color(0xFFBA68C8), AppRoutes.digitalHuman),
      (Icons.directions_run, '动作迁移', const Color(0xFFFF6B6B), AppRoutes.motionTransfer),
      (Icons.movie_edit, '视频混剪', const Color(0xFF26C6DA), AppRoutes.videoEdit),
      (Icons.theaters, 'AI短剧', const Color(0xFFFF6B9D), AppRoutes.dramaList),
      (Icons.auto_awesome, 'ToonFlow', const Color(0xFF7C4DFF), AppRoutes.toonFlow),
      (Icons.publish, '一键发布', const Color(0xFFFF8A65), AppRoutes.publish),
      (Icons.task_alt, '任务进度', const Color(0xFFFF9800), AppRoutes.taskLog),
      (Icons.dashboard, '监控台', const Color(0xFF7E57C2), AppRoutes.monitor),
      (Icons.history, '历史记录', const Color(0xFF4DD0E1), AppRoutes.history),
    ];

    return GridView.count(
      crossAxisCount: 3,
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 0.85,
      children: items.map((item) {
        return Material(
          color: const Color(0xFF0F3460),
          borderRadius: BorderRadius.circular(12),
          elevation: 2,
          child: InkWell(
            onTap: () => Navigator.pushNamed(context, item.$4),
            borderRadius: BorderRadius.circular(12),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: item.$3.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
                child: Icon(item.$1, color: item.$3, size: 22),
              ),
              const SizedBox(height: 6),
              Text(item.$2, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white), textAlign: TextAlign.center),
            ]),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRecentItem(Map<String, dynamic> record) {
    return ListTile(
      leading: const Icon(Icons.description, color: Color(0xFF1A73E8)),
      title: Text(record['title']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(record['time']?.toString() ?? '', style: const TextStyle(color: Color(0xFF607D8B), fontSize: 11)),
      trailing: const Icon(Icons.chevron_right, color: Color(0xFF607D8B)),
      onTap: () => Navigator.pushNamed(context, AppRoutes.history),
    );
  }
}
