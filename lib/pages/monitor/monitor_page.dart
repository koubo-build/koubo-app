import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/monitor_provider.dart';
import '../../services/monitor_service.dart';

/// 监控台页面 - 模型状态查询、重启、日志
class MonitorPage extends ConsumerStatefulWidget {
  const MonitorPage({super.key});

  @override
  ConsumerState<MonitorPage> createState() => _MonitorPageState();
}

class _MonitorPageState extends ConsumerState<MonitorPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(monitorProvider.notifier).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(monitorProvider);
    

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('监控台'),
        backgroundColor: AppTheme.darkSurface,
        actions: [
          // 自动刷新开关
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingMedium),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '自动刷新',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(width: 4),
                Switch(
                  value: notifier.autoRefresh,
                  onChanged: (_) => notifier.toggleAutoRefresh(),
                  activeColor: AppTheme.primaryColor,
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: notifier.refreshStatus,
        color: AppTheme.primaryColor,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          children: [
            // 统计卡片
            _buildStatCards(state),
            const SizedBox(height: AppTheme.spacingLarge),

            // 模型状态列表
            const Text(
              '模型状态',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            if (notifier.isLoading && notifier.models.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ...notifier.models.map((model) => _buildModelCard(model, notifier)),

            const SizedBox(height: AppTheme.spacingLarge),

            // 日志区
            const Text(
              '运行日志',
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMedium),
            _buildLogArea(state),
            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  /// 顶部3个统计卡片
  Widget _buildStatCards(MonitorState state) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            '模型总数',
            '${notifier.models.length}',
            Colors.white,
            Icons.dns_outlined,
          ),
        ),
        const SizedBox(width: AppTheme.spacingSmall),
        Expanded(
          child: _buildStatCard(
            '运行中',
            '${notifier.runningCount}',
            AppTheme.safeColor,
            Icons.check_circle_outline,
          ),
        ),
        const SizedBox(width: AppTheme.spacingSmall),
        Expanded(
          child: _buildStatCard(
            '异常',
            '${notifier.errorCount}',
            AppTheme.highRiskColor,
            Icons.error_outline,
          ),
        ),
      ],
    );
  }

  /// 单个统计卡片
  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(
        vertical: AppTheme.spacingMedium,
        horizontal: AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        children: [
          Icon(icon, color: color.withOpacity(0.6), size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  /// 模型状态卡片
  Widget _buildModelCard(ModelStatus model, MonitorNotifier notifier) {
    Color statusColor;
    String statusText;
    switch (model.status) {
      case 'running':
        statusColor = AppTheme.safeColor;
        statusText = '运行中';
        break;
      case 'stopped':
        statusColor = AppTheme.textHint;
        statusText = '已停止';
        break;
      case 'error':
        statusColor = AppTheme.highRiskColor;
        statusText = '异常';
        break;
      default:
        statusColor = AppTheme.textHint;
        statusText = '未知';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingMedium,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Row(
        children: [
          // 状态指示灯
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: statusColor,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: statusColor.withOpacity(0.4),
                  blurRadius: 4,
                  spreadRadius: 1,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          // 模型名
          Expanded(
            child: Text(
              model.name,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 延迟
          if (model.status == 'running')
            Padding(
              padding: const EdgeInsets.only(right: AppTheme.spacingMedium),
              child: Text(
                '${model.latencyMs}ms',
                style: TextStyle(
                  color: model.latencyMs > 500
                      ? AppTheme.lowRiskColor
                      : AppTheme.textHint,
                  fontSize: 12,
                ),
              ),
            ),
          // 状态文字
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: statusColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 重启按钮（仅异常时显示）
          if (model.status == 'error') ...[
            const SizedBox(width: AppTheme.spacingSmall),
            GestureDetector(
              onTap: () => _handleRestart(model.name, notifier),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '重启',
                  style: TextStyle(
                    color: AppTheme.accentColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 处理重启操作
  void _handleRestart(String modelName, MonitorNotifier notifier) async {
    // 确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text(
          '确认重启',
          style: TextStyle(color: AppTheme.textPrimary),
        ),
        content: Text(
          '确定要重启 $modelName 吗？',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.accentColor,
            ),
            child: const Text('重启'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('正在重启 $modelName ...'),
          backgroundColor: AppTheme.primaryColor,
        ),
      );
      await notifier.restartModel(modelName);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$modelName 重启指令已发送'),
            backgroundColor: AppTheme.safeColor,
          ),
        );
      }
    }
  }

  /// 日志区
  Widget _buildLogArea(MonitorState state) {
    final logs = notifier.logs.take(15).toList();

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 280),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: const Color(0xFF1A1A3A)),
      ),
      child: logs.isEmpty
          ? const Center(
              child: Text(
                '暂无日志',
                style: TextStyle(
                  color: AppTheme.textHint,
                  fontFamily: 'monospace',
                  fontSize: 13,
                ),
              ),
            )
          : ListView.builder(
              shrinkWrap: true,
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    logs[index],
                    style: const TextStyle(
                      color: Color(0xFF00E676),
                      fontFamily: 'monospace',
                      fontSize: 11,
                      height: 1.4,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
