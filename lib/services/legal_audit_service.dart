import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/audit_result.dart';
import '../utils/word_filter.dart';
import 'api_client.dart';

/// 法务合规审核服务 - 关键词快速过滤 + 大模型深度审核双重机制
/// 优化版：确保一键修正逻辑完整、修正后自动复审、审核结果更加精确
class LegalAuditService {
  final ApiClient _apiClient;
  final WordFilterEngine _wordFilter;

  LegalAuditService(this._apiClient) : _wordFilter = WordFilterEngine();

  // ==================== 审核Prompt模板 ====================

  /// 通用法务审核Prompt
  static const String _legalReviewPrompt = '''你是一位资深的互联网内容法务审核专家，精通《中华人民共和国广告法》、抖音社区规范以及各行业合规要求。

请对以下口播文案进行全面法务合规审核，按以下维度逐一分析：

【审核维度】
1. 广告法合规：是否包含绝对化用语（最、第一、国家级等）、虚假承诺、权威暗示
2. 敏感词检测：是否包含政治敏感、色情低俗、暴力恐怖、歧视性内容
3. 平台规则：是否符合抖音社区规范，是否存在引流、虚假互动等违规行为
4. 侵权风险：是否涉及他人商标、著作权、肖像权等侵权风险
5. 虚假宣传：是否存在医疗、金融等特殊行业的违规宣传

【特别注意】
- 识别谐音规避（如"醉好"→"最好"）
- 识别拆词规避（如"最/好"→"最好"）
- 识别符号规避（如"最✅好"→"最好"）
- 区分合理使用和违规使用（上下文判断）
- 标注具体风险词句及其在文案中的位置

【待审核文案】
{text}

请按以下JSON格式输出审核结果：
{{
  "risk_level": "安全|低风险|中风险|高风险",
  "issues": [
    {{
      "type": "广告法违禁词|敏感词|平台违规|侵权风险|虚假宣传",
      "risk_level": "低风险|中风险|高风险",
      "original_text": "文案中的原词原句",
      "position": "起始位置-结束位置",
      "reason": "违规原因说明",
      "suggestion": "修改建议或替换方案"
    }}
  ],
  "overall_assessment": "整体评估说明",
  "safe_to_publish": true/false
}}''';

  /// 行业专项审核Prompt
  static const String _industryReviewPrompt = '''你是一位{industry}行业的合规审核专家。

请针对{industry}行业的特殊合规要求，对以下文案进行专业审核：

行业特规要点：
{industry_rules}

待审核文案：
{text}

请重点关注：
1. 是否存在行业特有违规用语
2. 是否需要特殊资质才能发布此类内容
3. 是否存在误导消费者的风险
4. 是否符合行业监管部门的最新要求

请按以下JSON格式输出：
{{
  "industry": "{industry}",
  "qualification_required": true/false,
  "issues": [
    {{
      "type": "违规类型",
      "risk_level": "低风险|中风险|高风险",
      "original_text": "原词原句",
      "reason": "违规原因",
      "suggestion": "替换建议"
    }}
  ],
  "safe_to_publish": true/false
}}''';

  /// 行业特规要点
  static const Map<String, String> _industryRules = {
    '医疗健康': '禁止使用治愈率、有效率等数据；禁止处方药推广；偏方/秘方/祖传/神药为高风险词；医疗建议需执业资质',
    '金融理财': '禁止保本保息、零风险、稳赚等承诺；荐股需证券投资咨询资质；内幕消息/庄家/割韭菜为高风险词',
    '教育培训': '禁止保过/包过承诺；禁止考前押题宣传；速成/零基础包就业/月薪XX万为风险词',
  };

  /// 一键修正Prompt
  static const String _autoFixPrompt = '''你是一位专业的口播文案合规修正专家。请对以下文案中的违规内容进行修正，要求：
1. 仅修正标注的违规内容，其他内容保持不变
2. 修正后的文案应保持口播风格的自然流畅
3. 每处修正应使用最合适的替换词
4. 不要添加任何解释说明，只输出修正后的完整文案

原文：
{original_text}

需要修正的问题：
{issues_description}

请直接输出修正后的完整文案：''';

  // ==================== 核心审核方法 ====================

  /// 双重审核（核心方法）
  /// [text] 待审核文案
  /// [auditType] 审核类型：原始文案/改写后文案
  /// [industry] 行业类型（可选，用于行业专项审核）
  /// 返回完整的审核结果
  Future<AuditResult> audit({
    required String text,
    required String auditType,
    String? industry,
  }) async {
    // ========== 第一层：关键词快速过滤（毫秒级） ==========
    final keywordResults = _wordFilter.filter(text);

    // ========== 第二层：大模型深度审核（秒级） ==========
    AuditResult? llmResult;
    try {
      llmResult = await _llmAudit(text, industry);
    } catch (e) {
      // 大模型审核失败时，仅使用关键词过滤结果
      llmResult = null;
    }

    // ========== 审核结果合并：取两层审核中风险等级更高的结果 ==========
    return _mergeResults(
      text: text,
      auditType: auditType,
      keywordResults: keywordResults,
      llmResult: llmResult,
    );
  }

  /// 大模型深度审核
  Future<AuditResult> _llmAudit(String text, String? industry) async {
    String prompt;
    if (industry != null && _industryRules.containsKey(industry)) {
      // 行业专项审核
      prompt = _industryReviewPrompt
          .replaceAll('{industry}', industry)
          .replaceAll('{industry_rules}', _industryRules[industry]!)
          .replaceAll('{text}', text);
    } else {
      // 通用法务审核
      prompt = _legalReviewPrompt.replaceAll('{text}', text);
    }

    // 调用智能路由进行法务审核（推理场景优先阿里百炼qwen-plus，其次智谱GLM-4）
    final result = await _apiClient.chatSmart(
      messages: [
        {
          'role': 'system',
          'content': '你是一位资深的互联网内容法务审核专家，请严格按照要求输出JSON格式的审核结果。'
        },
        {'role': 'user', 'content': prompt},
      ],
      temperature: 0.3,
      preferReasoning: true,
    );

    // 解析大模型返回的JSON
    return _parseLlmResult(result, text);
  }

  /// 解析大模型返回的审核结果
  AuditResult _parseLlmResult(String result, String text) {
    try {
      final jsonStr = _extractJson(result);
      if (jsonStr != null) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;

        // 解析问题列表
        final issues = <AuditIssue>[];
        final issuesData = data['issues'] as List<dynamic>? ?? [];
        for (final item in issuesData) {
          issues.add(AuditIssue.fromMap(item as Map<String, dynamic>));
        }

        // 按风险等级排序：高风险 → 中风险 → 低风险
        issues.sort((a, b) {
          final riskOrder = {'高风险': 3, '中风险': 2, '低风险': 1};
          return (riskOrder[b.riskLevel] ?? 0).compareTo(riskOrder[a.riskLevel] ?? 0);
        });

        return AuditResult(
          auditType: '大模型审核',
          riskLevel: data['risk_level'] as String? ?? '安全',
          issues: issues,
          overallAssessment: data['overall_assessment'] as String?,
          safeToPublish: data['safe_to_publish'] as bool? ?? true,
          createdAt: DateTime.now(),
        );
      }
    } catch (_) {
      // JSON解析失败
    }

    // 解析失败返回默认安全结果
    return AuditResult(
      auditType: '大模型审核',
      riskLevel: '安全',
      issues: [],
      overallAssessment: '大模型审核结果解析失败，建议重新审核',
      safeToPublish: true,
      createdAt: DateTime.now(),
    );
  }

  /// 合并两层审核结果
  AuditResult _mergeResults({
    required String text,
    required String auditType,
    required List<AuditIssue> keywordResults,
    required AuditResult? llmResult,
  }) {
    // 收集所有问题
    final allIssues = <AuditIssue>[];

    // 添加关键词过滤发现的问题
    allIssues.addAll(keywordResults);

    // 添加大模型审核发现的问题（去重）
    if (llmResult != null) {
      for (final issue in llmResult.issues) {
        // 检查是否与关键词过滤结果重复
        final isDuplicate = keywordResults.any(
          (k) => k.originalText == issue.originalText && k.type == issue.type,
        );
        if (!isDuplicate) {
          allIssues.add(issue);
        }
      }
    }

    // 按风险等级排序
    allIssues.sort((a, b) {
      final riskOrder = {'高风险': 3, '中风险': 2, '低风险': 1};
      return (riskOrder[b.riskLevel] ?? 0).compareTo(riskOrder[a.riskLevel] ?? 0);
    });

    // 计算综合风险等级（取最高风险）
    final riskLevel = _calculateRiskLevel(allIssues);

    // 判断是否可发布
    final safeToPublish = riskLevel == '安全' || riskLevel == '低风险';

    // 生成整体评估
    final assessment = _generateAssessment(allIssues, riskLevel, llmResult);

    return AuditResult(
      auditType: auditType,
      riskLevel: riskLevel,
      issues: allIssues,
      overallAssessment: assessment,
      safeToPublish: safeToPublish,
      createdAt: DateTime.now(),
    );
  }

  /// 计算综合风险等级
  String _calculateRiskLevel(List<AuditIssue> issues) {
    if (issues.isEmpty) return '安全';

    bool hasHighRisk = issues.any((i) => i.riskLevel == '高风险');
    bool hasMediumRisk = issues.any((i) => i.riskLevel == '中风险');
    bool hasLowRisk = issues.any((i) => i.riskLevel == '低风险');

    if (hasHighRisk) return '高风险';
    if (hasMediumRisk) return '中风险';
    if (hasLowRisk) return '低风险';
    return '安全';
  }

  /// 生成整体评估说明
  String _generateAssessment(
    List<AuditIssue> issues,
    String riskLevel,
    AuditResult? llmResult,
  ) {
    final buffer = StringBuffer();
    buffer.write('综合风险等级：$riskLevel。');

    if (issues.isEmpty) {
      buffer.write('未发现合规风险，文案可安全发布。');
    } else {
      final grouped = <String, int>{};
      for (final issue in issues) {
        grouped[issue.type] = (grouped[issue.type] ?? 0) + 1;
      }
      buffer.write('共发现${issues.length}处问题：');
      grouped.forEach((type, count) {
        buffer.write('$type${count}处、');
      });
      // 移除最后的顿号
      final str = buffer.toString();
      if (str.endsWith('、')) {
        buffer.clear();
        buffer.write(str.substring(0, str.length - 1));
      }
      buffer.write('。');
    }

    // 追加大模型的评估
    if (llmResult?.overallAssessment != null) {
      buffer.write(llmResult!.overallAssessment);
    }

    return buffer.toString();
  }

  // ==================== 一键修正（优化版） ====================

  /// 一键修正 - 根据审核建议自动修改文案
  /// [text] 原始文案
  /// [issues] 审核发现的问题列表
  /// 返回修正结果，包含修正后的文案和变更详情
  Future<Map<String, dynamic>> autoFix(String text, List<AuditIssue> issues) async {
    String fixedText = text;
    final changes = <Map<String, String>>[];

    // 按风险等级从高到低排序处理，确保高风险先替换
    final sortedIssues = List<AuditIssue>.from(issues)
      ..sort((a, b) {
        final riskOrder = {'高风险': 3, '中风险': 2, '低风险': 1};
        return (riskOrder[b.riskLevel] ?? 0).compareTo(riskOrder[a.riskLevel] ?? 0);
      });

    // 遍历所有问题，按建议替换
    for (final issue in sortedIssues) {
      if (issue.suggestion.isNotEmpty && issue.originalText.isNotEmpty) {
        // 检查原文中是否包含问题词汇
        if (fixedText.contains(issue.originalText)) {
          final replacement = issue.firstSuggestion;
          if (replacement.isNotEmpty && replacement != issue.originalText) {
            fixedText = fixedText.replaceFirst(issue.originalText, replacement);
            changes.add({
              'original': issue.originalText,
              'fixed': replacement,
              'type': issue.type,
              'risk_level': issue.riskLevel,
            });
          }
        }
      }
    }

    // 如果没有通过规则修正任何内容，但有高风险/中风险问题，尝试用大模型修正
    if (changes.isEmpty && issues.any((i) => i.riskLevel == '高风险' || i.riskLevel == '中风险')) {
      try {
        final llmFixedText = await _llmAutoFix(text, issues);
        if (llmFixedText.isNotEmpty && llmFixedText != text) {
          fixedText = llmFixedText;
          changes.add({
            'original': '(大模型自动修正)',
            'fixed': '(大模型自动修正)',
            'type': '大模型修正',
            'risk_level': '综合修正',
          });
        }
      } catch (_) {
        // 大模型修正失败，使用规则修正结果
      }
    }

    // 如果只修正了部分问题但仍有中高风险残留，也尝试大模型修正
    final remainingHighOrMedium = sortedIssues.where((i) =>
      i.riskLevel == '高风险' || i.riskLevel == '中风险'
    ).where((i) =>
      !changes.any((c) => c['original'] == i.originalText)
    ).toList();

    if (remainingHighOrMedium.isNotEmpty && changes.isNotEmpty) {
      try {
        // 对修正后的文案再做大模型深度修正
        final llmFixedText = await _llmAutoFix(fixedText, remainingHighOrMedium);
        if (llmFixedText.isNotEmpty && llmFixedText != fixedText) {
          fixedText = llmFixedText;
          changes.add({
            'original': '(大模型深度修正)',
            'fixed': '(大模型深度修正)',
            'type': '大模型修正',
            'risk_level': '综合修正',
          });
        }
      } catch (_) {
        // 大模型修正失败，使用当前修正结果
      }
    }

    // 判断是否需要复审
    final hasHighRisk = issues.any((i) => i.riskLevel == '高风险');
    final hasMediumRisk = issues.any((i) => i.riskLevel == '中风险');
    final needReReview = hasHighRisk || hasMediumRisk;

    return {
      'fixed_text': fixedText,
      'changes': changes,
      'change_count': changes.length,
      'need_re_review': needReReview,
    };
  }

  /// 大模型一键修正（用于规则修正无法处理的复杂情况）
  Future<String> _llmAutoFix(String text, List<AuditIssue> issues) async {
    final issueDesc = issues.map((i) =>
      '- "${i.originalText}"（${i.type}，${i.riskLevel}）：${i.reason}，建议改为"${i.suggestion}"'
    ).join('\n');

    final prompt = _autoFixPrompt
        .replaceAll('{original_text}', text)
        .replaceAll('{issues_description}', issueDesc);

    final result = await _apiClient.chatSmart(
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      temperature: 0.3, // 低temperature确保修正稳定
    );

    return result.trim();
  }

  /// 一键修正后自动触发复审
  /// 确保修正后自动复审逻辑完整
  Future<AuditResult> autoFixAndReAudit(
    String text,
    List<AuditIssue> issues,
    String auditType,
  ) async {
    // 1. 先执行一键修正
    final fixResult = await autoFix(text, issues);
    final fixedText = fixResult['fixed_text'] as String;
    final needReReview = fixResult['need_re_review'] as bool;

    // 2. 如果需要复审，重新执行双重审核
    if (needReReview) {
      return audit(text: fixedText, auditType: '$auditType(修正后复审)');
    }

    // 3. 不需要复审，直接返回安全结果
    return AuditResult(
      auditType: '$auditType(修正后)',
      riskLevel: '安全',
      issues: [],
      overallAssessment: '修正后无需复审，文案可安全发布。',
      safeToPublish: true,
      createdAt: DateTime.now(),
    );
  }

  // ==================== 辅助方法 ====================

  /// 从文本中提取JSON字符串
  String? _extractJson(String text) {
    // 尝试匹配```json ... ```格式
    final jsonBlockRegex = RegExp(r'```json\s*([\s\S]*?)\s*```');
    final blockMatch = jsonBlockRegex.firstMatch(text);
    if (blockMatch != null) {
      return blockMatch.group(1);
    }

    // 尝试匹配{ ... }格式
    final braceRegex = RegExp(r'\{[\s\S]*\}');
    final braceMatch = braceRegex.firstMatch(text);
    if (braceMatch != null) {
      return braceMatch.group(0);
    }

    return null;
  }

  /// 快速预审核（仅关键词过滤，毫秒级）
  List<AuditIssue> quickAudit(String text) {
    return _wordFilter.filter(text);
  }

  /// 获取风险规避词列表（用于注入改写Prompt）
  List<String> getAvoidWords(List<AuditIssue> issues) {
    return issues
        .where((i) => i.originalText.isNotEmpty)
        .map((i) => i.originalText)
        .toList();
  }
}

/// LegalAuditService的Riverpod Provider
final legalAuditServiceProvider = Provider<LegalAuditService>((ref) {
  return LegalAuditService(ref.read(apiClientProvider));
});
