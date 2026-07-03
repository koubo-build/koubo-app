import 'dart:convert';

/// 项目级模型配置（Drama维度，覆盖全局设置）
class DramaModelConfig {
  final String textModel;      // 文本模型：auto/qwen-plus/glm-4.7-flash/agnes-2.0-flash/custom
  final String textApiKey;     // 自定义文本模型的API Key
  final String textBaseUrl;    // 自定义文本模型的Base URL
  final String imageModel;     // 图像模型：wanx/local_sd/custom
  final String imageApiKey;    // 自定义图像模型的API Key
  final String imageBaseUrl;   // 自定义图像模型的Base URL
  final String videoModel;     // 视频模型：happyhorse/wanx-s2v/custom
  final String videoApiKey;    // 自定义视频模型的API Key
  final String videoBaseUrl;   // 自定义视频模型的Base URL

  DramaModelConfig({
    this.textModel = 'auto',
    this.textApiKey = '',
    this.textBaseUrl = '',
    this.imageModel = 'wanx',
    this.imageApiKey = '',
    this.imageBaseUrl = '',
    this.videoModel = 'happyhorse',
    this.videoApiKey = '',
    this.videoBaseUrl = '',
  });

  factory DramaModelConfig.fromJson(Map<String, dynamic> json) {
    return DramaModelConfig(
      textModel: json['text_model'] as String? ?? 'auto',
      textApiKey: json['text_api_key'] as String? ?? '',
      textBaseUrl: json['text_base_url'] as String? ?? '',
      imageModel: json['image_model'] as String? ?? 'wanx',
      imageApiKey: json['image_api_key'] as String? ?? '',
      imageBaseUrl: json['image_base_url'] as String? ?? '',
      videoModel: json['video_model'] as String? ?? 'happyhorse',
      videoApiKey: json['video_api_key'] as String? ?? '',
      videoBaseUrl: json['video_base_url'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'text_model': textModel,
      'text_api_key': textApiKey,
      'text_base_url': textBaseUrl,
      'image_model': imageModel,
      'image_api_key': imageApiKey,
      'image_base_url': imageBaseUrl,
      'video_model': videoModel,
      'video_api_key': videoApiKey,
      'video_base_url': videoBaseUrl,
    };
  }

  DramaModelConfig copyWith({
    String? textModel,
    String? textApiKey,
    String? textBaseUrl,
    String? imageModel,
    String? imageApiKey,
    String? imageBaseUrl,
    String? videoModel,
    String? videoApiKey,
    String? videoBaseUrl,
  }) {
    return DramaModelConfig(
      textModel: textModel ?? this.textModel,
      textApiKey: textApiKey ?? this.textApiKey,
      textBaseUrl: textBaseUrl ?? this.textBaseUrl,
      imageModel: imageModel ?? this.imageModel,
      imageApiKey: imageApiKey ?? this.imageApiKey,
      imageBaseUrl: imageBaseUrl ?? this.imageBaseUrl,
      videoModel: videoModel ?? this.videoModel,
      videoApiKey: videoApiKey ?? this.videoApiKey,
      videoBaseUrl: videoBaseUrl ?? this.videoBaseUrl,
    );
  }

  /// 是否为自定义文本模型
  bool get isCustomTextModel => textModel == 'custom';

  /// 是否为自定义图像模型
  bool get isCustomImageModel => imageModel == 'custom';

  /// 是否为自定义视频模型
  bool get isCustomVideoModel => videoModel == 'custom';
}

/// 短剧项目
class Drama {
  final int? id;
  final String title;           // 短剧名称
  final String description;     // 故事梗概
  final String style;           // 画风：anime/realistic/3d/watercolor 等
  final String genre;           // 类型：romance/sci-fi/comedy/thriller 等
  final String aspectRatio;     // 画面比例：16:9 / 9:16 / 1:1
  final String modelConfig;     // JSON字符串，存储项目级模型配置
  final String sourceText;      // 用户输入的原始剧本/小说文本
  final DateTime createdAt;
  final DateTime? updatedAt;

  // 统计字段（从数据库查询时计算）
  int episodeCount;
  int totalShots;
  int completedShots;  // 已生成视频的镜头数

  Drama({
    this.id,
    required this.title,
    this.description = '',
    this.style = 'anime',
    this.genre = '',
    this.aspectRatio = '16:9',
    this.modelConfig = '{}',
    this.sourceText = '',
    DateTime? createdAt,
    this.updatedAt,
    this.episodeCount = 0,
    this.totalShots = 0,
    this.completedShots = 0,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从数据库Map创建
  factory Drama.fromMap(Map<String, dynamic> map) {
    return Drama(
      id: map['id'] as int?,
      title: map['title'] as String? ?? '',
      description: map['description'] as String? ?? '',
      style: map['style'] as String? ?? 'anime',
      genre: map['genre'] as String? ?? '',
      aspectRatio: map['aspect_ratio'] as String? ?? '16:9',
      modelConfig: map['model_config'] as String? ?? '{}',
      sourceText: map['source_text'] as String? ?? '',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      updatedAt: map['updated_at'] != null
          ? DateTime.parse(map['updated_at'] as String)
          : null,
      episodeCount: map['episode_count'] as int? ?? 0,
      totalShots: map['total_shots'] as int? ?? 0,
      completedShots: map['completed_shots'] as int? ?? 0,
    );
  }

  /// 从JSON创建（用于AI生成的剧本解析）
  factory Drama.fromJson(Map<String, dynamic> json) {
    return Drama(
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      style: json['style'] as String? ?? 'anime',
      genre: json['genre'] as String? ?? '',
      aspectRatio: json['aspect_ratio'] as String? ?? '16:9',
      modelConfig: json['model_config'] as String? ?? '{}',
      sourceText: json['source_text'] as String? ?? '',
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'title': title,
      'description': description,
      'style': style,
      'genre': genre,
      'aspect_ratio': aspectRatio,
      'model_config': modelConfig,
      'source_text': sourceText,
      'created_at': createdAt.toIso8601String(),
      if (updatedAt != null) 'updated_at': updatedAt!.toIso8601String(),
    };
  }

  /// 转为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'style': style,
      'genre': genre,
      'aspect_ratio': aspectRatio,
      'model_config': modelConfig,
      'source_text': sourceText,
    };
  }

  /// 复制并修改字段
  Drama copyWith({
    int? id,
    String? title,
    String? description,
    String? style,
    String? genre,
    String? aspectRatio,
    String? modelConfig,
    String? sourceText,
    DateTime? createdAt,
    DateTime? updatedAt,
    int? episodeCount,
    int? totalShots,
    int? completedShots,
  }) {
    return Drama(
      id: id ?? this.id,
      title: title ?? this.title,
      description: description ?? this.description,
      style: style ?? this.style,
      genre: genre ?? this.genre,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      modelConfig: modelConfig ?? this.modelConfig,
      sourceText: sourceText ?? this.sourceText,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      episodeCount: episodeCount ?? this.episodeCount,
      totalShots: totalShots ?? this.totalShots,
      completedShots: completedShots ?? this.completedShots,
    );
  }

  /// 获取解析后的模型配置
  DramaModelConfig get parsedModelConfig {
    try {
      return DramaModelConfig.fromJson(jsonDecode(modelConfig));
    } catch (_) {
      return DramaModelConfig();
    }
  }

  /// 获取画风显示名称
  String get styleDisplayName {
    switch (style) {
      case 'anime':
        return '动漫';
      case 'realistic':
        return '写实';
      case '3d':
        return '3D';
      case 'watercolor':
        return '水彩';
      case 'cartoon':
        return '卡通';
      case 'comic':
        return '漫画';
      default:
        return style;
    }
  }

  /// 获取类型显示名称
  String get genreDisplayName {
    switch (genre) {
      case 'romance':
        return '爱情';
      case 'sci-fi':
        return '科幻';
      case 'comedy':
        return '喜剧';
      case 'thriller':
        return '悬疑';
      case 'horror':
        return '恐怖';
      case 'fantasy':
        return '奇幻';
      case 'action':
        return '动作';
      case 'drama':
        return '剧情';
      default:
        return genre.isEmpty ? '其他' : genre;
    }
  }

  /// 获取进度百分比
  double get progressPercent {
    if (totalShots == 0) return 0;
    return completedShots / totalShots;
  }
}

/// 剧集（一集短剧）
class DramaEpisode {
  final int? id;
  final int dramaId;
  final String title;          // 集标题
  final int episodeNumber;     // 第几集
  final String? summary;       // 本集概要
  final List<DramaShot> shots; // 镜头列表

  DramaEpisode({
    this.id,
    required this.dramaId,
    required this.title,
    required this.episodeNumber,
    this.summary,
    List<DramaShot>? shots,
  }) : shots = shots ?? [];

  /// 从数据库Map创建
  factory DramaEpisode.fromMap(Map<String, dynamic> map) {
    return DramaEpisode(
      id: map['id'] as int?,
      dramaId: map['drama_id'] as int? ?? 0,
      title: map['title'] as String? ?? '',
      episodeNumber: map['episode_number'] as int? ?? 1,
      summary: map['summary'] as String?,
    );
  }

  /// 从JSON创建（用于AI生成的剧本解析）
  factory DramaEpisode.fromJson(Map<String, dynamic> json, int dramaId) {
    final shotsJson = json['shots'] as List<dynamic>? ?? [];
    return DramaEpisode(
      dramaId: dramaId,
      title: json['title'] as String? ?? '',
      episodeNumber: json['episode_number'] as int? ?? 1,
      summary: json['summary'] as String?,
      shots: shotsJson
          .map((s) => DramaShot.fromJson(s as Map<String, dynamic>, 0))
          .toList(),
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'drama_id': dramaId,
      'title': title,
      'episode_number': episodeNumber,
      if (summary != null) 'summary': summary,
    };
  }

  /// 转为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'episode_number': episodeNumber,
      'summary': summary,
      'shots': shots.map((s) => s.toJson()).toList(),
    };
  }

  /// 复制并修改字段
  DramaEpisode copyWith({
    int? id,
    int? dramaId,
    String? title,
    int? episodeNumber,
    String? summary,
    List<DramaShot>? shots,
  }) {
    return DramaEpisode(
      id: id ?? this.id,
      dramaId: dramaId ?? this.dramaId,
      title: title ?? this.title,
      episodeNumber: episodeNumber ?? this.episodeNumber,
      summary: summary ?? this.summary,
      shots: shots ?? List.from(this.shots),
    );
  }
}

/// 镜头（最小制作单元）
class DramaShot {
  final int? id;
  final int episodeId;
  final int shotNumber;        // 镜头序号
  final String visualDescription;  // 画面描述（用于AI出图）
  final String dialogue;       // 台词/旁白
  final String? characterDesc; // 角色描述（帮助保持角色一致性）
  final String? cameraDirection; // 运镜指示（特写/远景/推拉等）
  final int duration;          // 时长（秒），默认5
  final String imageModel;     // 图像模型（wanx/local_sd 等）
  final String? promptEnhanced; // AI增强后的出图prompt
  final String? imagePath;     // 生成的图片本地路径
  final String? audioPath;     // 生成的音频本地路径
  final String? videoPath;     // 生成的视频本地路径
  final String status;         // pending → image_ready → audio_ready → video_ready
  final DateTime createdAt;
  final String characterIds;  // 关联角色ID列表（逗号分隔）

  DramaShot({
    this.id,
    required this.episodeId,
    required this.shotNumber,
    required this.visualDescription,
    this.dialogue = '',
    this.characterDesc,
    this.cameraDirection,
    this.duration = 5,
    this.imageModel = 'wanx',
    this.promptEnhanced,
    this.imagePath,
    this.audioPath,
    this.videoPath,
    this.status = 'pending',
    DateTime? createdAt,
    this.characterIds = '',
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从数据库Map创建
  factory DramaShot.fromMap(Map<String, dynamic> map) {
    return DramaShot(
      id: map['id'] as int?,
      episodeId: map['episode_id'] as int? ?? 0,
      shotNumber: map['shot_number'] as int? ?? 1,
      visualDescription: map['visual_description'] as String? ?? '',
      dialogue: map['dialogue'] as String? ?? '',
      characterDesc: map['character_desc'] as String?,
      cameraDirection: map['camera_direction'] as String?,
      duration: map['duration'] as int? ?? 5,
      imageModel: map['image_model'] as String? ?? 'wanx',
      promptEnhanced: map['prompt_enhanced'] as String?,
      imagePath: map['image_path'] as String?,
      audioPath: map['audio_path'] as String?,
      videoPath: map['video_path'] as String?,
      status: map['status'] as String? ?? 'pending',
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      characterIds: map['character_ids'] as String? ?? '',
    );
  }

  /// 从JSON创建（用于AI生成的剧本解析）
  factory DramaShot.fromJson(Map<String, dynamic> json, int episodeId) {
    return DramaShot(
      episodeId: episodeId,
      shotNumber: json['shot_number'] as int? ?? 1,
      visualDescription: json['visual_description'] as String? ?? json['visual'] as String? ?? '',
      dialogue: json['dialogue'] as String? ?? json['text'] as String? ?? '',
      characterDesc: json['character_desc'] as String? ?? json['character'] as String?,
      cameraDirection: json['camera_direction'] as String? ?? json['camera'] as String?,
      duration: json['duration'] as int? ?? 5,
      characterIds: (json['character_ids'] as List<dynamic>?)?.map((e) => e.toString()).join(',') ?? 
                   (json['character_ids'] as String?) ?? '',
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'episode_id': episodeId,
      'shot_number': shotNumber,
      'visual_description': visualDescription,
      'dialogue': dialogue,
      'character_desc': characterDesc,
      'camera_direction': cameraDirection,
      'duration': duration,
      'image_model': imageModel,
      'prompt_enhanced': promptEnhanced,
      'image_path': imagePath,
      'audio_path': audioPath,
      'video_path': videoPath,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'character_ids': characterIds,
    };
  }

  /// 转为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'shot_number': shotNumber,
      'visual_description': visualDescription,
      'dialogue': dialogue,
      'character_desc': characterDesc,
      'camera_direction': cameraDirection,
      'duration': duration,
      'character_ids': characterIds,
    };
  }

  /// 复制并修改字段
  DramaShot copyWith({
    int? id,
    int? episodeId,
    int? shotNumber,
    String? visualDescription,
    String? dialogue,
    String? characterDesc,
    String? cameraDirection,
    int? duration,
    String? imageModel,
    String? promptEnhanced,
    String? imagePath,
    String? audioPath,
    String? videoPath,
    String? status,
    DateTime? createdAt,
    String? characterIds,
  }) {
    return DramaShot(
      id: id ?? this.id,
      episodeId: episodeId ?? this.episodeId,
      shotNumber: shotNumber ?? this.shotNumber,
      visualDescription: visualDescription ?? this.visualDescription,
      dialogue: dialogue ?? this.dialogue,
      characterDesc: characterDesc ?? this.characterDesc,
      cameraDirection: cameraDirection ?? this.cameraDirection,
      duration: duration ?? this.duration,
      imageModel: imageModel ?? this.imageModel,
      promptEnhanced: promptEnhanced ?? this.promptEnhanced,
      imagePath: imagePath ?? this.imagePath,
      audioPath: audioPath ?? this.audioPath,
      videoPath: videoPath ?? this.videoPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      characterIds: characterIds ?? this.characterIds,
    );
  }

  /// 获取状态显示名称
  String get statusDisplayName {
    switch (status) {
      case 'pending':
        return '待生成';
      case 'image_ready':
        return '图片就绪';
      case 'audio_ready':
        return '音频就绪';
      case 'video_ready':
        return '完成';
      case 'failed':
        return '失败';
      default:
        return status;
    }
  }

  /// 是否已完成视频生成
  bool get isVideoReady => status == 'video_ready';

  /// 是否已开始处理
  bool get isStarted => status != 'pending';

  /// 获取关联的角色ID列表
  List<int> get characterIdList {
    if (characterIds.isEmpty) return [];
    return characterIds.split(',').where((s) => s.isNotEmpty).map((s) => int.tryParse(s) ?? 0).where((i) => i > 0).toList();
  }
}

/// 短剧角色（用于保持角色一致性）
class DramaCharacter {
  final int? id;
  final int dramaId;          // 所属短剧
  final String name;          // 角色名
  final String description;   // 外貌描述（用于AI出图时保持一致性）
  final String? personality;  // 性格特征
  final String? referenceImage; // 参考图路径（本地存储）
  final String? promptTemplate; // AI出图时的角色prompt模板
  final DateTime createdAt;

  DramaCharacter({
    this.id,
    required this.dramaId,
    required this.name,
    this.description = '',
    this.personality,
    this.referenceImage,
    this.promptTemplate,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  /// 从数据库Map创建
  factory DramaCharacter.fromMap(Map<String, dynamic> map) {
    return DramaCharacter(
      id: map['id'] as int?,
      dramaId: map['drama_id'] as int? ?? 0,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      personality: map['personality'] as String?,
      referenceImage: map['reference_image'] as String?,
      promptTemplate: map['prompt_template'] as String?,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// 从JSON创建（用于AI生成的剧本解析）
  factory DramaCharacter.fromJson(Map<String, dynamic> json, int dramaId) {
    return DramaCharacter(
      dramaId: dramaId,
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? json['appearance'] as String? ?? '',
      personality: json['personality'] as String?,
      promptTemplate: json['prompt_template'] as String?,
    );
  }

  /// 转为数据库Map
  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'drama_id': dramaId,
      'name': name,
      'description': description,
      'personality': personality,
      'reference_image': referenceImage,
      'prompt_template': promptTemplate,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// 转为JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'drama_id': dramaId,
      'name': name,
      'description': description,
      'personality': personality,
      'reference_image': referenceImage,
      'prompt_template': promptTemplate,
    };
  }

  /// 复制并修改字段
  DramaCharacter copyWith({
    int? id,
    int? dramaId,
    String? name,
    String? description,
    String? personality,
    String? referenceImage,
    String? promptTemplate,
    DateTime? createdAt,
  }) {
    return DramaCharacter(
      id: id ?? this.id,
      dramaId: dramaId ?? this.dramaId,
      name: name ?? this.name,
      description: description ?? this.description,
      personality: personality ?? this.personality,
      referenceImage: referenceImage ?? this.referenceImage,
      promptTemplate: promptTemplate ?? this.promptTemplate,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  /// 获取完整描述（包含外貌和性格）
  String get fullDescription {
    final parts = <String>[];
    if (description.isNotEmpty) parts.add(description);
    if (personality != null && personality!.isNotEmpty) {
      parts.add('性格：$personality');
    }
    return parts.join('；');
  }
}

/// AI生成的剧本结果（包含角色、剧集和镜头）
class DramaScriptResult {
  final List<DramaCharacter> characters;
  final List<DramaEpisode> episodes;

  DramaScriptResult({
    required this.characters,
    required this.episodes,
  });

  /// 从JSON创建
  factory DramaScriptResult.fromJson(Map<String, dynamic> json, int dramaId) {
    final charactersJson = json['characters'] as List<dynamic>? ?? [];
    final episodesJson = json['episodes'] as List<dynamic>? ?? [];

    return DramaScriptResult(
      characters: charactersJson
          .map((c) => DramaCharacter.fromJson(c as Map<String, dynamic>, dramaId))
          .toList(),
      episodes: episodesJson
          .map((e) => DramaEpisode.fromJson(e as Map<String, dynamic>, dramaId))
          .toList(),
    );
  }
}
