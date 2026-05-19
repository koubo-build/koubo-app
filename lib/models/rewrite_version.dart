/// 改写版本模型 - 表示AI改写生成的一个版本
class RewriteVersion {
  final int? id;
  final int? scriptId;              // 关联文案ID
  final int versionNumber;          // 版本号(1/2/3)
  final String rewrittenText;       // 改写文本
  final int score;                  // 评分(0-100)
  final String? scoreDetails;       // 评分详情(JSON字符串)
  final double? similarity;         // 与原文相似度(%)
  bool isSelected;                  // 是否被用户选中
  final DateTime? createdAt;

  RewriteVersion({
    this.id,
    this.scriptId,
    required this.versionNumber,
    required this.rewrittenText,
    this.score = 0,
    this.scoreDetails,
    this.similarity,
    this.isSelected = false,
    this.createdAt,
  });

  /// 从数据库Map创建
  factory RewriteVersion.fromMap(Map<String, dynamic> map) {
    return RewriteVersion(
      id: map['id'] as int?,
      scriptId: map['script_id'] as int?,
      versionNumber: map['version_number'] as int? ?? 1,
      rewrittenText: map['rewritten_text'] as String? ?? '',
      score: map['score'] as int? ?? 0,
      scoreDetails: map['score_details'] as String?,
      similarity: (map['similarity'] as num?)?.toDouble(),
      isSelected: (map['is_selected'] as int?) == 1,
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
      'version_number': versionNumber,
      'rewritten_text': rewrittenText,
      'score': score,
      'score_details': scoreDetails,
      'similarity': similarity,
      'is_selected': isSelected ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// 解析评分详情
  Map<String, dynamic>? get scoreDetailsMap {
    if (scoreDetails == null) return null;
    try {
      // 简单JSON解析（不引入dart:convert以减少依赖说明）
      // 实际使用时通过dart:convert
      return null; // 由Service层负责解析
    } catch (_) {
      return null;
    }
  }

  /// 获取评分等级描述
  String get scoreLevel {
    if (score >= 80) return '优秀';
    if (score >= 60) return '良好';
    if (score >= 40) return '一般';
    return '需改进';
  }
}
