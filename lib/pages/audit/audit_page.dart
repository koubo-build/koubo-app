import 'package:flutter/material.dart';
import '../../config/theme.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_input.dart';
import '../../widgets/risk_badge.dart';

/// 法务审核页 - 双重审核机制 + 风险标注 + 一键修正
class AuditPage extends StatefulWidget {
  const AuditPage({super.key});

  @override
  State<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends State<AuditPage> {
  final _textController = TextEditingController();
  bool _isAuditing = false;
  Map<String, dynamic>? _auditResult;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('法务合规审核'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 文案输入区域
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_snippet_outlined, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text('待审核文案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSmall),
                  AppInput(
                    controller: _textController,
                    hintText: '请输入要审核的口播文案...',
                    maxLines: 6,
                    maxLength: 5000,
                  ),
                  const SizedBox(height: AppTheme.spacingMedium),
                  AppButton(
                    text: '开始审核',
                    icon: Icons.shield_outlined,
                    isLoading: _isAuditing,
                    onPressed: _startAudit,
                  ),
                ],
              ),
            ),

            // 审核结果展示
            if (_auditResult != null) ...[
              const SizedBox(height: AppTheme.spacingMedium),

              // 审核概览
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assessment_outlined, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        const Text('审核概览', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        RiskBadge(riskLevel: _auditResult!['risk_level'] as String),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingMedium),
                    // 各维度审核结果
                    _buildAuditDimension('广告法违禁词', _auditResult!['ad_law_count'] as int, '高风险'),
                    _buildAuditDimension('敏感词检测', _auditResult!['sensitive_count'] as int, '安全'),
                    _buildAuditDimension('平台规则', _auditResult!['platform_count'] as int, '低风险'),
                    _buildAuditDimension('侵权风险', 0, '安全'),
                    _buildAuditDimension('虚假宣传', 0, '安全'),
                  ],
                ),
              ),

              const SizedBox(height: AppTheme.spacingMedium),

              // 问题详情
              if ((_auditResult!['issues'] as List).isNotEmpty)
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                    children: [
                      const Icon(Icons.search, color: AppTheme.mediumRiskColor, size: 20),
                      const SizedBox(width: 8),
                      const Text('问题详情', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingMedium),
                  ...(_auditResult!['issues'] as List<Map<String, dynamic>>).map((issue) {
                    return _buildIssueCard(issue);
                  }),
                ],
              ),
            ),

              // 操作按钮
              const SizedBox(height: AppTheme.spacingMedium),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: '一键全部修正',
                      icon: Icons.auto_fix_high,
                      backgroundColor: AppTheme.accentColor,
                      onPressed: _autoFix,
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Expanded(
                    child: AppButton(
                      text: '重新审核',
                      icon: Icons.refresh,
                      isOutlined: true,
                      onPressed: _startAudit,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: AppTheme.spacingSmall),
              AppButton(
                text: '导出审核报告',
                icon: Icons.file_download_outlined,
                isOutlined: true,
                onPressed: () {
                  // 导出审核报告
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建审核维度行
  Widget _buildAuditDimension(String label, int count, String riskLevel) {
    final color = count > 0 ? AppTheme.getRiskColor(riskLevel) : AppTheme.safeColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 8),
          if (count > 0) ...[
            Icon(count > 0 ? Icons.cancel : Icons.check_circle, size: 16, color: color),
            const SizedBox(width: 4),
            Text('$count处', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
          ] else ...[
            const Icon(Icons.check_circle, size: 16, color: AppTheme.safeColor),
            const SizedBox(width: 4),
            const Text('0处', style: TextStyle(fontSize: 14, color: AppTheme.safeColor)),
          ],
          const Spacer(),
          RiskBadge(riskLevel: count > 0 ? riskLevel : '安全', compact: true),
        ],
      ),
    );
  }

  /// 构建问题详情卡片
  Widget _buildIssueCard(Map<String, dynamic> issue) {
    final riskLevel = issue['risk_level'] as String? ?? '低风险';
    final type = issue['type'] as String? ?? '';
    final originalText = issue['original_text'] as String? ?? '';
    final reason = issue['reason'] as String? ?? '';
    final suggestion = issue['suggestion'] as String? ?? '';
    final riskColor = AppTheme.getRiskColor(riskLevel);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: riskColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问题类型和风险等级
          Row(
            children: [
              Icon(Icons.cancel, size: 16, color: riskColor),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '[$type]',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: riskColor),
                ),
              ),
              const Spacer(),
              RiskBadge(riskLevel: riskLevel, compact: true),
            ],
          ),
          const SizedBox(height: 8),
          // 违规原文
          RichText(
            text: TextSpan(
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5),
              children: [
                const TextSpan(text: '原文：'),
                TextSpan(
                  text: '"$originalText"',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    backgroundColor: riskColor.withOpacity(0.2),
                    color: riskColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          // 违规原因
          Text('原因：$reason', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          if (suggestion.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('建议：→ "$suggestion"', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppTheme.safeColor)),
          ],
          const SizedBox(height: 8),
          // 修正按钮
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                text: '一键修正',
                fontSize: 12,
                height: 30,
                borderRadius: AppTheme.radiusSmall,
                onPressed: () {
                  // 修正单条问题
                },
              ),
              const SizedBox(width: 8),
              AppButton(
                text: '手动修改',
                fontSize: 12,
                height: 30,
                borderRadius: AppTheme.radiusSmall,
                isOutlined: true,
                onPressed: () {
                  // 手动修改
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 开始审核
  Future<void> _startAudit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请先输入要审核的文案');
      return;
    }

    setState(() => _isAuditing = true);

    try {
      // 模拟审核过程（实际调用LegalAuditService）
      await Future.delayed(const Duration(seconds: 2));

      setState(() {
        _auditResult = {
          'risk_level': '中风险',
          'ad_law_count': 2,
          'sensitive_count': 0,
          'platform_count': 1,
          'safe_to_publish': false,
          'issues': [
            {
              'type': '广告法违禁词',
              'risk_level': '高风险',
              'original_text': '最好',
              'reason': '使用了绝对化用语"最好"，违反《广告法》第九条',
              'suggestion': '非常好',
            },
            {
              'type': '广告法违禁词',
              'risk_level': '高风险',
              'original_text': '第一',
              'reason': '使用了绝对化用语"第一"，违反《广告法》第九条',
              'suggestion': '名列前茅',
            },
            {
              'type': '平台违规',
              'risk_level': '低风险',
              'original_text': '加微信',
              'reason': '抖音禁止引流到微信',
              'suggestion': '评论区留言',
            },
          ],
        };
      });
    } catch (e) {
      _showSnackBar('审核失败：$e');
    } finally {
      setState(() => _isAuditing = false);
    }
  }

  /// 一键修正
  Future<void> _autoFix() async {
    _showSnackBar('正在修正所有问题...');
    await Future.delayed(const Duration(seconds: 1));
    _showSnackBar('已修正3处问题，建议重新审核');
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
