import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/monitor_provider.dart';
import '../../services/monitor_service.dart';

/// 监控台页面 - 真实检测App各功能可用性
/// 不再显示模拟数据，直接检查API Key配置和接口状态
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
      ref.read(monitorProvider).init();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.watch(monitorProvider);

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('监控台'),
        backgroundColor: AppTheme.darkSurface,
        actions: [
          // 一键检测按钮
          TextButton.icon(
            onPressed: ctrl.isLoading ? null : () => ctrl.refreshStatus(),
            icon: Icon(
              Icons.refresh,
              size: 18,
              color: ctrl.isLoading
                  ? AppTheme.textHint
                  : AppTheme.primaryColor,
            ),
            label: Text(
              ctrl.isLoading ? '检测中...' : '一键检测',
              style: TextStyle(
                color: ctrl.isLoading
                    ? AppTheme.textHint
                    : AppTheme.primaryColor,
                fontSize: 13,
              ),
            ),
          ),
          // 自动刷新开关
          Padding(
            padding: const EdgeInsets.only(right: AppTheme.spacingSmall),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  '自动',
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
                Switch(
                  value: ctrl.autoRefresh,
                  onChanged: (_) => ctrl.toggleAutoRefresh(),
                  activeColor: AppTheme.primaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: ctrl.refreshStatus,
        color: AppTheme.primaryColor,
        child: ListView(
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          children: [
            // 顶部总览卡片
            _buildOverviewCard(ctrl),
            const SizedBox(height: AppTheme.spacingLarge),

            // 功能状态区
            _buildSectionTitle('功能状态'),
            const SizedBox(height: AppTheme.spacingSmall),
            if (ctrl.isLoading && ctrl.services.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(),
                ),
              )
            else
              ...ctrl.services.map((s) => Padding(
                    padding:
                        const EdgeInsets.only(bottom: AppTheme.spacingSmall),
                    child: _buildServiceCard(s),
                  )),

            const SizedBox(height: AppTheme.spacingLarge),

            // API Key配置区
            _buildSectionTitle('API Key 配置'),
            const SizedBox(height: AppTheme.spacingSmall),
            ...ctrl.apiKeys.map((k) => Padding(
                  padding:
                      const EdgeInsets.only(bottom: AppTheme.spacingSmall),
                  child: _buildApiKeyCard(k),
                )),

            // 底部提示
            const SizedBox(height: AppTheme.spacingLarge),
            _buildTipCard(),
            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  /// 顶部总览卡片
  Widget _buildOverviewCard(MonitorNotifier ctrl) {
    final total = ctrl.services.length;
    final available = ctrl.availableCount;
    final hasError = ctrl.errorCount > 0;
    final hasUnconfigured = ctrl.unconfiguredCount > 0;

    // 主色调
    Color mainColor;
    String summaryText;
    IconData summaryIcon;
    if (total == 0) {
      mainColor = AppTheme.textHint;
      summaryText = '正在检测...';
      summaryIcon = Icons.hourglass_empty;
    } else if (available == total) {
      mainColor = AppTheme.safeColor;
      summaryText = '全部功能正常';
      summaryIcon = Icons.check_circle;
    } else if (hasError) {
      mainColor = AppTheme.highRiskColor;
      summaryText = '$available/$total 功能可用，${ctrl.errorCount} 个异常';
      summaryIcon = Icons.error;
    } else {
      mainColor = AppTheme.accentColor;
      summaryText = '$available/$total 功能可用，$hasUnconfigured 个未配置';
      summaryIcon = Icons.info;
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            mainColor.withOpacity(0.15),
            mainColor.withOpacity(0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(color: mainColor.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(summaryIcon, color: mainColor, size: 36),
          const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summaryText,
                  style: TextStyle(
                    color: mainColor,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '已配置 ${ctrl.apiKeys.where((k) => k.configured).length}/${ctrl.apiKeys.length} 个API Key',
                  style: const TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 大数字
          if (total > 0)
            Text(
              '$available',
              style: TextStyle(
                color: mainColor,
                fontSize: 42,
                fontWeight: FontWeight.bold,
                height: 1,
              ),
            ),
        ],
      ),
    );
  }

  /// 分区标题
  Widget _buildSectionTitle(String title) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textPrimary,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Divider(color: Color(0xFF2A2A4A), thickness: 1),
        ),
      ],
    );
  }

  /// 功能服务卡片 - 核心展示
  Widget _buildServiceCard(ServiceStatus service) {
    // 状态颜色和文本
    Color statusColor;
    String statusText;
    IconData statusIcon;
    Color bgColor;

    switch (service.status) {
      case 'available':
        statusColor = AppTheme.safeColor;
        statusText = '可用';
        statusIcon = Icons.check_circle;
        bgColor = AppTheme.safeColor.withOpacity(0.06);
        break;
      case 'unconfigured':
        statusColor = AppTheme.accentColor;
        statusText = '未配置';
        statusIcon = Icons.warning_amber;
        bgColor = AppTheme.accentColor.withOpacity(0.06);
        break;
      case 'error':
        statusColor = AppTheme.highRiskColor;
        statusText = '异常';
        statusIcon = Icons.error;
        bgColor = AppTheme.highRiskColor.withOpacity(0.06);
        break;
      case 'checking':
        statusColor = AppTheme.primaryColor;
        statusText = '检测中';
        statusIcon = Icons.hourglass_top;
        bgColor = AppTheme.primaryColor.withOpacity(0.06);
        break;
      default:
        statusColor = AppTheme.textHint;
        statusText = '未知';
        statusIcon = Icons.help;
        bgColor = Colors.transparent;
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: statusColor.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 第一行：图标+名称+状态标签
          Row(
            children: [
              // emoji图标
              Text(
                service.icon,
                style: const TextStyle(fontSize: 24),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              // 名称
              Expanded(
                child: Text(
                  service.name,
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              // 延迟（仅可用时显示）
              if (service.status == 'available' && service.latencyMs > 0)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    '${service.latencyMs}ms',
                    style: TextStyle(
                      color: service.latencyMs > 3000
                          ? AppTheme.highRiskColor
                          : service.latencyMs > 1000
                              ? AppTheme.accentColor
                              : AppTheme.textHint,
                      fontSize: 11,
                    ),
                  ),
                ),
              // 状态标签
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 13, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      statusText,
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          // 第二行：功能描述
          Padding(
            padding: const EdgeInsets.only(left: 36, top: 4),
            child: Text(
              service.description,
              style: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 12,
              ),
            ),
          ),
          // 第三行：详情/错误信息
          if (service.detail != null && service.detail!.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(left: 36, top: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFF0A0A1A).withOpacity(0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(
                    service.status == 'available'
                        ? Icons.check
                        : service.status == 'error'
                            ? Icons.bug_report
                            : Icons.key,
                    size: 14,
                    color: statusColor.withOpacity(0.8),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      service.detail!,
                      style: TextStyle(
                        color: statusColor.withOpacity(0.9),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// API Key配置卡片
  Widget _buildApiKeyCard(ApiKeyInfo keyInfo) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall + 2,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          // 配置状态图标
          Icon(
            keyInfo.configured ? Icons.verified : Icons.key_off,
            size: 18,
            color: keyInfo.configured ? AppTheme.safeColor : AppTheme.textHint,
          ),
          const SizedBox(width: AppTheme.spacingSmall),
          // 供应商名
          SizedBox(
            width: 72,
            child: Text(
              keyInfo.displayName,
              style: TextStyle(
                color: keyInfo.configured
                    ? AppTheme.textPrimary
                    : AppTheme.textHint,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          // 用途
          Expanded(
            child: Text(
              keyInfo.usedFor,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 11,
              ),
            ),
          ),
          // 必需标记
          if (keyInfo.required)
            Container(
              margin: const EdgeInsets.only(right: 6),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.highRiskColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '重要',
                style: TextStyle(
                  color: AppTheme.highRiskColor,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          // 状态文字
          Text(
            keyInfo.configured ? '已配置' : '未配置',
            style: TextStyle(
              color: keyInfo.configured ? AppTheme.safeColor : AppTheme.accentColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  /// 底部提示卡片
  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A1A).withOpacity(0.5),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: const Color(0xFF1A1A3A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.lightbulb_outline, size: 16, color: AppTheme.accentColor),
              SizedBox(width: 6),
              Text(
                '配置提示',
                style: TextStyle(
                  color: AppTheme.accentColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildTipItem('阿里百炼', '语音合成和声音克隆必需，改写/审核也可用'),
          _buildTipItem('智谱AI', '免费模型，配置后即可使用改写/审核'),
          _buildTipItem('硅基流动', '免费备选，改写/审核的第三路由'),
          _buildTipItem('TikHub', '仅抖音解析需要，不用抖音可不配'),
        ],
      ),
    );
  }

  Widget _buildTipItem(String name, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(
              name,
              style: const TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(
                color: AppTheme.textHint,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
