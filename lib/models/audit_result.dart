/// 审核结果模型 - 表示一次法务合规审核的结果
class AuditResult {
  final int? id;
  final int? scriptId;              // 关联文案ID
  final int? rewriteVersionId;      // 关联改写版本ID（审核原始文案时为空）
  final String auditType;           // 审核类型（原始文案/改写后文案）
  final String riskLevel;           // 综合风险等级（安全/低风险/中风险/高风险）
  final List<AuditIssue> issues;    // 审核问题列表
  final String? overallAssessment;  // 整体评估
  final bool safeToPublish;         // 是否可发布
  final String? reportPath;         // 审核报告文件路径
  final DateTime? createdAt;

  AuditResult({
    this.id,
    this.scriptId,
    this.rewriteVersionId,
    required this.auditType,
    required this.riskLevel,
    required this.issues,
    this.overallAssessment,
    required this.safeToPublish,
    this.reportPath,
    this.createdAt,
  });

  /// 从数据库Map创建
  factory AuditResult.fromMap(Map<String, dynamic> map) {
    return AuditResult(
      id: map['id'] as int?,
      scriptId: map['script_id'] as int?,
      rewriteVersionId: map['rewrite_version_id'] as int?,
      auditType: map['audit_type'] as String? ?? '原始文案',
      riskLevel: map['risk_level'] as String? ?? '安全',
      issues: [], // issues需要单独从JSON解析，由Service层处理
      overallAssessment: map['overall_assessment'] as String?,
      safeToPublish: (map['safe_to_publish'] as int?) == 1,
      reportPath: map['report_path'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'script_id': scriptId,
      'rewrite_version_id': rewriteVersionId,
      'audit_type': auditType,
      'risk_level': riskLevel,
      'overall_assessment': overallAssessment,
      'safe_to_publish': safeToPublish ? 1 : 0,
      'report_path': reportPath,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// 获取按类型分组的问题
  Map<String, List<AuditIssue>> get issuesByType {
    final grouped = <String, List<AuditIssue>>{};
    for (final issue in issues) {
      grouped.putIfAbsent(issue.type, () => []).add(issue);
    }
    return grouped;
  }

  /// 获取高风险问题数量
  int get highRiskCount => issues.where((i) => i.riskLevel == '高风险').length;

  /// 获取中风险问题数量
  int get mediumRiskCount => issues.where((i) => i.riskLevel == '中风险').length;

  /// 获取低风险问题数量
  int get lowRiskCount => issues.where((i) => i.riskLevel == '低风险').length;
}

/// 审核问题 - 单个审核发现的问题
class AuditIssue {
  final String type;          // 问题类型：广告法违禁词/敏感词/平台违规/侵权风险/虚假宣传
  final String riskLevel;     // 风险等级：低风险/中风险/高风险
  final String originalText;  // 文案中的原词原句
  final String? position;     // 在文案中的位置
  final String reason;        // 违规原因说明
  final String suggestion;    // 修改建议或替换方案

  AuditIssue({
    required this.type,
    required this.riskLevel,
    required this.originalText,
    this.position,
    required this.reason,
    required this.suggestion,
  });

  /// 从Map创建（大模型返回的JSON解析后）
  factory AuditIssue.fromMap(Map<String, dynamic> map) {
    return AuditIssue(
      type: map['type'] as String? ?? '未知类型',
      riskLevel: map['risk_level'] as String? ?? '低风险',
      originalText: map['original_text'] as String? ?? '',
      position: map['position'] as String?,
      reason: map['reason'] as String? ?? '',
      suggestion: map['suggestion'] as String? ?? '',
    );
  }

  /// 转为Map
  Map<String, dynamic> toMap() {
    return {
      'type': type,
      'risk_level': riskLevel,
      'original_text': originalText,
      'position': position,
      'reason': reason,
      'suggestion': suggestion,
    };
  }

  /// 获取建议中的第一个替换词（用于一键修正）
  String get firstSuggestion {
    if (suggestion.isEmpty) return originalText;
    // 取"或"分隔的第一个建议
    final parts = suggestion.split('或');
    if (parts.isNotEmpty) {
      // 去除引号和空格
      return parts[0].replaceAll('"', '').replaceAll('"', '').replaceAll('"', '').trim();
    }
    return suggestion;
  }
}
