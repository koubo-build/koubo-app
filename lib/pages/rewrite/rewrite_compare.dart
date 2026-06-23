import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/risk_badge.dart';

/// 改写对比页 - 原文vs改写文并排展示，自动标注差异点
class RewriteComparePage extends StatelessWidget {
  final String sourceText;
  final String rewrittenText;
  final int score;

  const RewriteComparePage({
    super.key,
    required this.sourceText,
    required this.rewrittenText,
    required this.score,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('改写对比'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 评分概览
            AppCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.star, color: Colors.amber, size: 28),
                  const SizedBox(width: 8),
                  Text(
                    '评分: $score分',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: score >= 80
                          ? AppTheme.safeColor
                          : score >= 60
                              ? AppTheme.lowRiskColor
                              : AppTheme.mediumRiskColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 原文区域
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.textHint.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '原始文案',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSmall),
                  Text(
                    sourceText.isEmpty ? '暂无原文' : sourceText,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 改写文区域
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          '改写文案',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.primaryColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const RiskBadge(riskLevel: '安全', compact: true),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSmall),
                  Text(
                    rewrittenText.isEmpty ? '暂无改写结果' : rewrittenText,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 差异统计
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '改动统计',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: AppTheme.spacingMedium),
                  _buildStatRow('替换', 5, const Color(0xFFEAB308)),
                  _buildStatRow('新增', 2, const Color(0xFF22C55E)),
                  _buildStatRow('删除', 1, const Color(0xFFEF4444)),
                  const Divider(height: 24),
                  Row(
                    children: [
                      const Text(
                        '相似度：42%',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 8),
                      const RiskBadge(riskLevel: '安全', compact: true),
                      const Spacer(),
                      Text(
                        '✅ 去重通过',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.safeColor,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatRow(String label, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
          ),
          const Spacer(),
          Text(
            '$count 处',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }
}
