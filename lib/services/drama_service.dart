import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/drama.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';
import 'image_gen_service.dart';

/// 短剧脚本服务 - 用AI从故事梗概生成分镜脚本
class DramaService {
  final ApiClient _apiClient;

  DramaService(this._apiClient);

  // ==================== 系统Prompt ====================

  static const String _systemPrompt = '''你是一位专业的短剧分镜脚本创作师。你擅长创作短视频短剧剧本，能够将一个故事前提拆解为专业的分镜脚本。

请根据用户提供的故事前提，生成完整的短剧剧本。剧本必须包含：
1. 角色列表（主要角色的外貌描述和性格特征，用于AI出图时保持角色一致性）
2. 分集剧情（每集包含多镜头）
3. 每个镜头的详细描述（画面、台词、运镜、角色等）

输出格式必须是标准JSON，结构如下：
{
  "characters": [
    {
      "name": "角色名",
      "description": "外貌描述，如：年轻女性，黑色长发，白色连衣裙",
      "personality": "性格特征，如：独立、坚强、有点傲娇"
    }
  ],
  "episodes": [
    {
      "title": "第一集 相遇",
      "episode_number": 1,
      "summary": "本集概要",
      "shots": [
        {
          "shot_number": 1,
          "visual_description": "画面描述（用于AI出图，要具体、生动、有画面感）",
          "dialogue": "台词或旁白",
          "character_desc": "该镜头涉及的角色描述",
          "camera_direction": "运镜指示，如：特写、中景、远景、推近、拉远、跟拍",
          "duration": 5,
          "character_ids": []
        }
      ]
    }
  ]
}

请确保：
1. 每个镜头的 visual_description 要有画面感，描述要具体生动
2. 台词要符合角色性格和剧情发展
3. 角色描述要保持一致性，方便AI出图时保持角色形象
4. JSON格式必须完全正确，不要有语法错误''';

  // ==================== 核心方法 ====================

  /// 从故事梗概生成完整剧本
  /// [premise] 故事前提/梗概
  /// [style] 画风
  /// [genre] 类型
  /// [episodeCount] 集数
  /// [shotsPerEpisode] 每集镜头数（默认8-12）
  /// 返回 DramaScriptResult（包含characters和episodes）
  Future<DramaScriptResult> generateScript({
    required String premise,
    required String style,
    required String genre,
    int episodeCount = 1,
    int shotsPerEpisode = 10,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 构建用户Prompt
    final userPrompt = _buildUserPrompt(
      premise: premise,
      style: style,
      genre: genre,
      episodeCount: episodeCount,
      shotsPerEpisode: shotsPerEpisode,
    );

    onProgress?.call('AI构思剧本...', 10);

    // 2. 调用AI生成剧本
    final aiResponse = await _apiClient.chatSmart(
      messages: [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.8,
    );

    onProgress?.call('解析剧本结构...', 70);

    // 3. 解析JSON响应
    final result = _parseScriptResponse(aiResponse);

    onProgress?.call('剧本生成完成！', 100);
    return result;
  }

  /// 生成剧本并保存到数据库
  /// 返回创建的Drama对象
  Future<Drama> createDramaWithScript({
    required String title,
    required String premise,
    required String style,
    required String genre,
    String aspectRatio = '16:9',
    int episodeCount = 1,
    int shotsPerEpisode = 10,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 创建Drama记录
    final drama = Drama(
      title: title,
      description: premise,
      style: style,
      genre: genre,
      aspectRatio: aspectRatio,
    );

    final dramaId = await StorageUtil.insertDrama(drama);
    final savedDrama = drama.copyWith(id: dramaId);

    onProgress?.call('剧本生成中...', 20);

    // 2. 生成脚本
    final scriptResult = await generateScript(
      premise: premise,
      style: style,
      genre: genre,
      episodeCount: episodeCount,
      shotsPerEpisode: shotsPerEpisode,
      onProgress: (stage, progress) {
        // 映射进度：20-80%给剧本生成
        onProgress?.call(stage, 20 + (progress * 0.6).round());
      },
    );

    onProgress?.call('保存角色...', 85);

    // 3. 保存角色
    for (final character in scriptResult.characters) {
      await StorageUtil.insertCharacter(character.copyWith(dramaId: dramaId));
    }

    onProgress?.call('保存剧集...', 90);

    // 4. 保存剧集和镜头
    await StorageUtil.insertEpisodesWithShots(scriptResult.episodes);

    onProgress?.call('完成！', 100);

    // 5. 返回更新后的Drama（包含统计）
    return (await StorageUtil.getDrama(dramaId))!;
  }

  // ==================== 辅助方法 ====================

  /// 构建用户Prompt
  String _buildUserPrompt({
    required String premise,
    required String style,
    required String genre,
    required int episodeCount,
    required int shotsPerEpisode,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('请为以下故事创作短剧剧本：');
    buffer.writeln();
    buffer.writeln('故事前提：$premise');
    buffer.writeln();
    buffer.writeln('画风要求：${_getStyleDesc(style)}');
    buffer.writeln('类型：${_getGenreDesc(genre)}');
    buffer.writeln('集数：$episodeCount 集');
    buffer.writeln('每集镜头数：$shotsPerEpisode-$shotsPerEpisode 个');
    buffer.writeln();
    buffer.writeln('请生成完整的剧本，包括角色设定和分镜脚本。');

    return buffer.toString();
  }

  /// 获取画风描述
  String _getStyleDesc(String style) {
    switch (style) {
      case 'anime':
        return '动漫风格，色彩鲜艳，线条流畅';
      case 'realistic':
        return '写实风格，接近真人，质感真实';
      case '3d':
        return '3D动画风格，皮克斯/迪士尼风格';
      case 'watercolor':
        return '水彩手绘风格，柔和淡雅';
      case 'cartoon':
        return '卡通风格，夸张可爱';
      case 'comic':
        return '漫画风格，强烈对比色';
      default:
        return '通用风格';
    }
  }

  /// 获取类型描述
  String _getGenreDesc(String genre) {
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
        return genre;
    }
  }

  /// 解析AI返回的剧本
  DramaScriptResult _parseScriptResponse(String response) {
    try {
      // 提取JSON
      final jsonStr = _extractJson(response);
      if (jsonStr == null) {
        throw Exception('无法解析剧本格式');
      }

      final data = jsonDecode(jsonStr) as Map<String, dynamic>;

      // 解析角色
      final characters = <DramaCharacter>[];
      final charactersJson = data['characters'] as List<dynamic>? ?? [];
      for (final c in charactersJson) {
        characters.add(DramaCharacter.fromJson(c as Map<String, dynamic>, 0));
      }

      // 解析剧集
      final episodes = <DramaEpisode>[];
      final episodesJson = data['episodes'] as List<dynamic>? ?? [];
      for (final e in episodesJson) {
        episodes.add(DramaEpisode.fromJson(e as Map<String, dynamic>, 0));
      }

      return DramaScriptResult(
        characters: characters,
        episodes: episodes,
      );
    } catch (e) {
      throw Exception('剧本解析失败：$e');
    }
  }

  /// 从文本中提取JSON字符串
  String? _extractJson(String text) {
    // 清理可能的markdown代码块
    var cleanedText = text.trim();
    
    // 移除可能的```json 或 ``` 标记
    if (cleanedText.startsWith('```json')) {
      cleanedText = cleanedText.substring(7);
    } else if (cleanedText.startsWith('```')) {
      cleanedText = cleanedText.substring(3);
    }
    if (cleanedText.endsWith('```')) {
      cleanedText = cleanedText.substring(0, cleanedText.length - 3);
    }
    cleanedText = cleanedText.trim();

    // 尝试直接解析
    try {
      jsonDecode(cleanedText);
      return cleanedText;
    } catch (_) {
      // 尝试匹配{ ... }格式
    }

    // 尝试在文本中查找JSON
    final braceRegex = RegExp(r'\{[\s\S]*\}');
    final match = braceRegex.firstMatch(text);
    if (match != null) {
      final candidate = match.group(0);
      try {
        jsonDecode(candidate!);
        return candidate;
      } catch (_) {
        // 继续尝试
      }
    }

    return null;
  }

  // ==================== 剧本增强 ====================

  /// 增强镜头Prompt（注入角色描述）
  /// 根据镜头的character_ids，从角色列表中获取描述并注入到prompt中
  static String enhanceShotPrompt({
    required DramaShot shot,
    required List<DramaCharacter> characters,
    required String style,
  }) {
    final buffer = StringBuffer(shot.visualDescription);

    // 如果镜头有关联的角色，注入角色描述
    if (shot.characterIds.isNotEmpty) {
      final charIds = shot.characterIdList;
      for (final charId in charIds) {
        final character = characters.firstWhere(
          (c) => c.id == charId,
          orElse: () => DramaCharacter(dramaId: 0, name: '', description: ''),
        );
        if (character.description.isNotEmpty) {
          buffer.write('; ${character.name}: ${character.description}');
        }
      }
    }

    // 增强画风相关描述
    buffer.write('; ${ImageGenService.enhancePrompt('', style, null)}');

    return buffer.toString();
  }
}

/// DramaService的Riverpod Provider
final dramaServiceProvider = Provider<DramaService>((ref) {
  return DramaService(ref.read(apiClientProvider));
});
