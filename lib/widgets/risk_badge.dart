import 'package:flutter/material.dart';
import '../../config/theme.dart';

/// 风险等级徽章组件
/// 安全(绿) / 低风险(黄) / 中风险(橙) / 高风险(红)
class RiskBadge extends StatelessWidget {
  final String riskLevel;  // 安全/低风险/中风险/高风险
  final double fontSize;
  final bool showIcon;
  final bool compact;  // 紧凑模式（更小的尺寸）

  const RiskBadge({
    super.key,
    required this.riskLevel,
    this.fontSize = 12,
    this.showIcon = true,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final config = _getConfig();

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 10,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: config.backgroundColor,
        borderRadius: BorderRadius.circular(compact ? 4 : AppTheme.radiusSmall),
        border: Border.all(
          color: config.borderColor,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              config.icon,
              size: compact ? 12 : 14,
              color: config.textColor,
            ),
            const SizedBox(width: 4),
          ],
          Text(
            riskLevel,
            style: TextStyle(
              fontSize: compact ? 10 : fontSize,
              fontWeight: FontWeight.w600,
              color: config.textColor,
            ),
          ),
        ],
      ),
    );
  }

  /// 获取风险等级对应的配置
  _RiskBadgeConfig _getConfig() {
    switch (riskLevel) {
      case '安全':
        return _RiskBadgeConfig(
          icon: Icons.check_circle,
          backgroundColor: AppTheme.safeColor.withOpacity(0.15),
          borderColor: AppTheme.safeColor.withOpacity(0.3),
          textColor: AppTheme.safeColor,
        );
      case '低风险':
        return _RiskBadgeConfig(
          icon: Icons.warning,
          backgroundColor: AppTheme.lowRiskColor.withOpacity(0.15),
          borderColor: AppTheme.lowRiskColor.withOpacity(0.3),
          textColor: AppTheme.lowRiskColor,
        );
      case '中风险':
        return _RiskBadgeConfig(
          icon: Icons.error_outline,
          backgroundColor: AppTheme.mediumRiskColor.withOpacity(0.15),
          borderColor: AppTheme.mediumRiskColor.withOpacity(0.3),
          textColor: AppTheme.mediumRiskColor,
        );
      case '高风险':
        return _RiskBadgeConfig(
          icon: Icons.dangerous,
          backgroundColor: AppTheme.highRiskColor.withOpacity(0.15),
          borderColor: AppTheme.highRiskColor.withOpacity(0.3),
          textColor: AppTheme.highRiskColor,
        );
      default:
        return _RiskBadgeConfig(
          icon: Icons.help_outline,
          backgroundColor: AppTheme.textHint.withOpacity(0.15),
          borderColor: AppTheme.textHint.withOpacity(0.3),
          textColor: AppTheme.textHint,
        );
    }
  }
}

/// 风险等级配置
class _RiskBadgeConfig {
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color textColor;

  const _RiskBadgeConfig({
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.textColor,
  });
}

/// 审核维度状态徽章（如"广告法违禁词 🚫 2处"）
class AuditDimensionBadge extends StatelessWidget {
  final String label;       // 维度名称
  final int count;          // 问题数量
  final String riskLevel;   // 风险等级

  const AuditDimensionBadge({
    super.key,
    required this.label,
    required this.count,
    required this.riskLevel,
  });

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.getRiskColor(riskLevel);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          // 维度名称
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          // 问题数量
          if (count > 0) ...[
            Icon(
              Icons.cancel,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 4),
            Text(
              '$count处',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ] else ...[
            const Icon(
              Icons.check_circle,
              size: 16,
              color: AppTheme.safeColor,
            ),
            const SizedBox(width: 4),
            const Text(
              '0处',
              style: TextStyle(
                fontSize: 14,
                color: AppTheme.safeColor,
              ),
            ),
          ],
          const Spacer(),
          // 风险等级标签
          RiskBadge(riskLevel: count > 0 ? riskLevel : '安全', compact: true),
        ],
      ),
    );
  }
}
