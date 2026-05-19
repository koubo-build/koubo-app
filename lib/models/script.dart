/// 文案模型 - 表示一条口播文案的完整数据
class Script {
  final int? id;
  final String? sourceUrl;         // 原始抖音链接
  final String sourceText;         // 提取的原始文案
  String? rewrittenText;           // AI改写后的文案（最终选定的版本）
  String? rewriteMode;             // 改写模式
  String? rewriteStyle;            // 风格（风格转换模式使用）
  String? modelName;               // 使用的模型
  String? riskLevel;               // 最终风险等级
  final DateTime? createdAt;
  DateTime? updatedAt;

  Script({
    this.id,
    this.sourceUrl,
    required this.sourceText,
    this.rewrittenText,
    this.rewriteMode,
    this.rewriteStyle,
    this.modelName,
    this.riskLevel,
    this.createdAt,
    this.updatedAt,
  });

  /// 从数据库Map创建
  factory Script.fromMap(Map<String, dynamic> map) {
    return Script(
      id: map['id'] as int?,
      sourceUrl: map['source_url'] as String?,
      sourceText: map['source_text'] as String? ?? '',
      rewrittenText: map['rewritten_text'] as String?,
      rewriteMode: map['rewrite_mode'] as String?,
      rewriteStyle: map['rewrite_style'] as String?,
      modelName: map['model_name'] as String?,
      riskLevel: map['risk_level'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'source_url': sourceUrl,
      'source_text': sourceText,
      'rewritten_text': rewrittenText,
      'rewrite_mode': rewriteMode,
      'rewrite_style': rewriteStyle,
      'model_name': modelName,
      'risk_level': riskLevel,
      'created_at': createdAt?.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
    };
  }

  /// 复制并修改部分字段
  Script copyWith({
    int? id,
    String? sourceUrl,
    String? sourceText,
    String? rewrittenText,
    String? rewriteMode,
    String? rewriteStyle,
    String? modelName,
    String? riskLevel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Script(
      id: id ?? this.id,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceText: sourceText ?? this.sourceText,
      rewrittenText: rewrittenText ?? this.rewrittenText,
      rewriteMode: rewriteMode ?? this.rewriteMode,
      rewriteStyle: rewriteStyle ?? this.rewriteStyle,
      modelName: modelName ?? this.modelName,
      riskLevel: riskLevel ?? this.riskLevel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
