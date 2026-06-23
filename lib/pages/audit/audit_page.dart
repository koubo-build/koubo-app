import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../models/audit_result.dart';
import '../../services/legal_audit_service.dart';
import '../../services/api_client.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_input.dart';
import '../../widgets/common/api_config_indicator.dart';
import '../../widgets/risk_badge.dart';

/// 法务审核页 - 双重审核机制 + 风险标注 + 一键修正
class AuditPage extends ConsumerStatefulWidget {
  const AuditPage({super.key});

  @override
  ConsumerState<AuditPage> createState() => _AuditPageState();
}

class _AuditPageState extends ConsumerState<AuditPage> {
  final _textController = TextEditingController();
  bool _isAuditing = false;
  Map<String, dynamic>? _auditResult;
  AuditResult? _realAuditResult; // 真实审核结果

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
            // API配置指示器
            ApiConfigIndicator(
              type: ApiConfigIndicatorType.audit,
              onConfigChanged: () {
                ref.read(apiConfigProvider.notifier).refresh();
              },
            ),
            const SizedBox(height: AppTheme.spacingSmall),

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

  /// 开始审核（调用真实AI双重审核）
  Future<void> _startAudit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showSnackBar('请先输入要审核的文案');
      return;
    }

    setState(() => _isAuditing = true);

    try {
      final auditService = ref.read(legalAuditServiceProvider);

      // 调用真实双重审核（关键词快速过滤 + 大模型深度审核）
      final result = await auditService.audit(
        text: text,
        auditType: '法务合规审核',
      );

      // 将审核结果转为UI展示格式
      final issues = result.issues.map((issue) {
        return {
          'type': issue.type,
          'risk_level': issue.riskLevel,
          'original_text': issue.originalText,
          'reason': issue.reason,
          'suggestion': issue.suggestion,
        };
      }).toList();

      // 统计各维度问题数
      int adLawCount = result.issues.where((i) => i.type == '广告法违禁词').length;
      int sensitiveCount = result.issues.where((i) => i.type == '敏感词').length;
      int platformCount = result.issues.where((i) => i.type == '平台违规').length;

      setState(() {
        _realAuditResult = result;
        _auditResult = {
          'risk_level': result.riskLevel,
          'ad_law_count': adLawCount,
          'sensitive_count': sensitiveCount,
          'platform_count': platformCount,
          'safe_to_publish': result.safeToPublish,
          'issues': issues,
        };
      });
    } catch (e) {
      _showSnackBar('审核失败：$e');
    } finally {
      setState(() => _isAuditing = false);
    }
  }

  /// 一键修正（调用真实AI修正 + 自动复审）
  Future<void> _autoFix() async {
    if (_realAuditResult == null || _realAuditResult!.issues.isEmpty) {
      _showSnackBar('没有需要修正的问题');
      return;
    }

    setState(() => _isAuditing = true);

    try {
      final auditService = ref.read(legalAuditServiceProvider);
      final text = _textController.text.trim();

      // 调用真实一键修正（规则修正 + 大模型修正）
      final fixResult = await auditService.autoFix(text, _realAuditResult!.issues);

      final fixedText = fixResult['fixed_text'] as String;
      final changeCount = fixResult['change_count'] as int;

      // 更新文案为修正后的版本
      _textController.text = fixedText;

      // 如果需要复审，自动触发
      if (fixResult['need_re_review'] as bool) {
        _showSnackBar('已修正$changeCount处问题，正在自动复审...');
        // 自动复审
        final reAuditResult = await auditService.audit(
          text: fixedText,
          auditType: '修正后复审',
        );
        _realAuditResult = reAuditResult;

        // 更新UI
        final issues = reAuditResult.issues.map((issue) {
          return {
            'type': issue.type,
            'risk_level': issue.riskLevel,
            'original_text': issue.originalText,
            'reason': issue.reason,
            'suggestion': issue.suggestion,
          };
        }).toList();

        setState(() {
          _auditResult = {
            'risk_level': reAuditResult.riskLevel,
            'ad_law_count': reAuditResult.issues.where((i) => i.type == '广告法违禁词').length,
            'sensitive_count': reAuditResult.issues.where((i) => i.type == '敏感词').length,
            'platform_count': reAuditResult.issues.where((i) => i.type == '平台违规').length,
            'safe_to_publish': reAuditResult.safeToPublish,
            'issues': issues,
          };
        });

        _showSnackBar('复审完成：${reAuditResult.riskLevel}，${reAuditResult.issues.length}处残留问题');
      } else {
        _showSnackBar('已修正$changeCount处问题，文案可安全发布');
        setState(() {
          _auditResult = {
            'risk_level': '安全',
            'ad_law_count': 0,
            'sensitive_count': 0,
            'platform_count': 0,
            'safe_to_publish': true,
            'issues': [],
          };
        });
      }
    } catch (e) {
      _showSnackBar('修正失败：$e');
    } finally {
      setState(() => _isAuditing = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
