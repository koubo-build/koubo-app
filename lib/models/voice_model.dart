/// 音色模型 - 表示TTS语音合成的一种音色
class VoiceModel {
  final int? id;
  final String voiceName;          // 音色名称
  final String voiceId;            // 音色唯一标识
  final String provider;           // 提供商（edge_tts/cosyvoice/hifly/custom）
  final String? samplePath;        // 音色样本文件路径
  final String? language;          // 语言（zh-CN/en-US等）
  final String? gender;            // 性别（male/female）
  final String? style;             // 风格描述
  final bool isCloned;             // 是否为克隆音色
  final DateTime? createdAt;

  VoiceModel({
    this.id,
    required this.voiceName,
    required this.voiceId,
    required this.provider,
    this.samplePath,
    this.language = 'zh-CN',
    this.gender,
    this.style,
    this.isCloned = false,
    this.createdAt,
  });

  /// 从数据库Map创建
  factory VoiceModel.fromMap(Map<String, dynamic> map) {
    return VoiceModel(
      id: map['id'] as int?,
      voiceName: map['voice_name'] as String? ?? '',
      voiceId: map['voice_id'] as String? ?? '',
      provider: map['provider'] as String? ?? 'edge_tts',
      samplePath: map['sample_path'] as String?,
      language: map['language'] as String? ?? 'zh-CN',
      gender: map['gender'] as String?,
      style: map['style'] as String?,
      isCloned: (map['is_cloned'] as int?) == 1,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : null,
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'voice_name': voiceName,
      'voice_id': voiceId,
      'provider': provider,
      'sample_path': samplePath,
      'language': language,
      'gender': gender,
      'style': style,
      'is_cloned': isCloned ? 1 : 0,
      'created_at': createdAt?.toIso8601String(),
    };
  }

  /// 获取提供商显示名称
  String get providerDisplayName {
    switch (provider) {
      case 'edge_tts':
        return 'Edge-TTS';
      case 'cosyvoice':
        return 'CosyVoice';
      case 'hifly':
        return '飞影数字人';
      case 'custom':
        return '自定义';
      default:
        return provider;
    }
  }

  /// 获取音色标签
  String get displayTag {
    final parts = <String>[];
    if (gender != null) {
      parts.add(gender == 'male' ? '男声' : '女声');
    }
    if (isCloned) {
      parts.add('克隆');
    }
    parts.add(providerDisplayName);
    return parts.join(' · ');
  }
}
