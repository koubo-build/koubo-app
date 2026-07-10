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
    String template = '',
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 构建用户Prompt
    final userPrompt = _buildUserPrompt(
      premise: premise,
      style: style,
      genre: genre,
      episodeCount: episodeCount,
      shotsPerEpisode: shotsPerEpisode,
      template: template,
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
    String template = '',
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 创建Drama记录
    final drama = Drama(
      title: title,
      description: premise,
      style: style,
      genre: genre,
      aspectRatio: aspectRatio,
      template: template,
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
      template: template,
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
    String template = '',
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

    // 注入模板上下文（非人类角色 / 猎奇风格预设）
    final templateDesc = _getTemplateDesc(template);
    if (templateDesc.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('【特殊风格设定 - 必读】');
      buffer.writeln(templateDesc);
    }

    buffer.writeln();
    buffer.writeln('请生成完整的剧本，包括角色设定和分镜脚本。');

    return buffer.toString();
  }

  /// 获取模板风格描述（非人类角色/猎奇预设）
  String _getTemplateDesc(String template) {
    switch (template) {
      case 'fruit':
        return '主角是【拟人化的水果/蔬菜】：例如番茄公主、香蕉国王、草莓战士、葡萄忍者、辣椒妈妈等。保留水果原本的颜色、形状和质感，但赋予完整的人类形态、表情、服装和性格。画面应色彩鲜艳、果香四溢，符合水果本身特征。剧情围绕水果王国的爱恨情仇、复仇、冒险展开。';
      case 'seahorse':
        return '主角是【拟人化的海洋生物】：海马爸爸、海马妈妈、章鱼老板、水母仙女、螃蟹将军等。保留海洋生物的形态特征（海马的弯曲身体、章鱼的触手、水母的透明感），但有完整的人类表情、对话和社会关系。故事可以围绕怀孕、育儿、家庭、复仇等情感议题展开，画面梦幻、温暖或诡异。';
      case 'animal':
        return '主角是【拟人化的陆地动物】：猫老板、狗警察、狐狸侦探、兔子公主、狼反派等。动物保留各自物种特征（猫的耳朵、狗的尾巴、狐狸的尖嘴），穿着人类衣服，住人类房子，但行为举止完全拟人化。故事轻松幽默、夸张荒诞，配上戏剧化的冲突和反转。';
      case 'monster':
        return '【怪物/克苏鲁风格】：主角是克苏鲁式怪物、异形、外星生物、变异生物等。强调恐怖、诡异、超自然的氛围。画面暗调、阴影、触手、复眼、异形构造。剧情围绕觉醒、吞噬、复仇、异世界入侵展开，制造强烈的不安感和视觉冲击。';
      case 'absurd':
        return '【荒诞讽刺风格】：主角可以是任何东西（家具、电器、食物、抽象概念），剧情完全打破常规逻辑，黑色幽默、荒诞不经、讽刺现实。画面夸张、扭曲、超现实。可以采用定格动画或拼贴风格，每个镜头都充满意外和笑点。';
      case 'horror':
        return '【猎奇恐怖风格】：人物造型诡异、色彩压抑、画面充斥不安元素（血迹、阴影、扭曲人形、恐怖娃娃）。剧情围绕诅咒、复仇、疯狂、超自然事件。画面要营造强烈的恐怖氛围，每个镜头都让观众脊背发凉。';
      default:
        return '';
    }
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

  // ==================== 从剧本文本提取角色 ====================

  static const String _extractCharsSystemPrompt = '''你是一位专业的剧本分析师。请从用户提供的剧本/小说文本中，提取所有出现的角色。

对每个角色，请提供：
1. name：角色名
2. description：外貌描述（如：年轻男性，黑色短发，白色衬衫，身材高大）
3. personality：性格特征（如：勇敢、冲动、重义气）

输出格式必须是标准JSON：
{
  "characters": [
    {
      "name": "角色名",
      "description": "外貌描述",
      "personality": "性格特征"
    }
  ]
}

注意：
1. 只提取有实际戏份的角色，路人/群演不需要
2. 描述要具体生动，方便AI出图时保持角色一致性
3. 如果文本中没有明确的外貌描述，请根据上下文合理推断
4. JSON格式必须完全正确''';

  /// 从剧本文本中自动提取角色
  Future<List<DramaCharacter>> extractCharacters({
    required String scriptText,
    required int dramaId,
    String template = '',
    void Function(String stage, int progress)? onProgress,
  }) async {
    onProgress?.call('AI分析角色...', 10);

    // 截取文本（防止超长）
    final truncatedText = scriptText.length > 15000
        ? '${scriptText.substring(0, 15000)}\n...(文本已截断)'
        : scriptText;

    final templateDesc = _getTemplateDesc(template);
    final userPrompt = templateDesc.isEmpty
        ? '请从以下剧本/小说中提取所有角色：\n\n$truncatedText'
        : '请从以下剧本/小说中提取所有角色：\n\n$truncatedText\n\n【风格设定】\n$templateDesc';

    final aiResponse = await _callAiWithModelConfig(
      dramaId: dramaId,
      messages: [
        {'role': 'system', 'content': _extractCharsSystemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.3,
    );

    onProgress?.call('解析角色数据...', 80);

    // 解析JSON
    final jsonStr = _extractJson(aiResponse);
    if (jsonStr == null) {
      throw Exception('无法解析角色数据');
    }

    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final charactersJson = data['characters'] as List<dynamic>? ?? [];

    final characters = <DramaCharacter>[];
    for (final c in charactersJson) {
      characters.add(DramaCharacter.fromJson(c as Map<String, dynamic>, dramaId));
    }

    onProgress?.call('角色提取完成！', 100);
    return characters;
  }

  // ==================== 从剧本生成分镜 ====================

  static const String _storyboardSystemPrompt = '''你是一位专业的短剧分镜脚本创作师。请根据用户提供的完整剧本/小说文本和角色列表，生成结构化的分镜脚本。

输出格式必须是标准JSON：
{
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
3. 角色描述要保持与提供列表的一致性
4. 合理分配镜头，确保故事节奏流畅
5. JSON格式必须完全正确，不要有语法错误''';

  /// 从剧本自动生成分镜
  Future<DramaScriptResult> generateStoryboardFromScript({
    required String scriptText,
    required List<DramaCharacter> characters,
    required String style,
    required String genre,
    int shotsPerEpisode = 10,
    String template = '',
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 构建角色信息
    final charInfoList = characters.map((c) {
      return '- ${c.name}：${c.description}${c.personality != null && c.personality!.isNotEmpty ? '（${c.personality}）' : ''}';
    }).join('\n');

    final truncatedText = scriptText.length > 15000
        ? '${scriptText.substring(0, 15000)}\n...(文本已截断)'
        : scriptText;

    final templateDesc = _getTemplateDesc(template);
    final userPrompt = '''请根据以下剧本和角色列表，生成结构化的分镜脚本。

画风要求：${_getStyleDesc(style)}
类型：${_getGenreDesc(genre)}
每集镜头数：约${shotsPerEpisode}个
${templateDesc.isNotEmpty ? '\n【特殊风格设定 - 必读】\n$templateDesc\n' : ''}
角色列表：
$charInfoList

剧本文本：
$truncatedText

请生成分镜脚本，角色列表已在上方提供，无需重复提取。''';

    onProgress?.call('AI生成分镜...', 10);

    final aiResponse = await _callAiWithModelConfig(
      dramaId: characters.isNotEmpty ? characters.first.dramaId : 0,
      messages: [
        {'role': 'system', 'content': _storyboardSystemPrompt},
        {'role': 'user', 'content': userPrompt},
      ],
      temperature: 0.8,
    );

    onProgress?.call('解析分镜数据...', 80);

    // 解析JSON
    final jsonStr = _extractJson(aiResponse);
    if (jsonStr == null) {
      throw Exception('无法解析分镜数据');
    }

    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final dramaId = characters.isNotEmpty ? characters.first.dramaId : 0;

    // 解析剧集
    final episodes = <DramaEpisode>[];
    final episodesJson = data['episodes'] as List<dynamic>? ?? [];
    for (final e in episodesJson) {
      episodes.add(DramaEpisode.fromJson(e as Map<String, dynamic>, dramaId));
    }

    onProgress?.call('分镜生成完成！', 100);

    return DramaScriptResult(
      characters: characters,  // 使用传入的角色列表
      episodes: episodes,
    );
  }

  // ==================== 一键从完整剧本创建短剧 ====================

  /// 一键从完整剧本创建短剧（核心入口）
  Future<Drama> createDramaFromFullScript({
    required String title,
    required String scriptText,
    required String style,
    required String genre,
    String aspectRatio = '16:9',
    String modelConfig = '{}',
    int shotsPerEpisode = 10,
    String template = '',
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 创建Drama记录（保存sourceText和modelConfig）
    final drama = Drama(
      title: title,
      description: scriptText.length > 200 ? '${scriptText.substring(0, 200)}...' : scriptText,
      style: style,
      genre: genre,
      aspectRatio: aspectRatio,
      modelConfig: modelConfig,
      sourceText: scriptText,
      template: template,
    );

    final dramaId = await StorageUtil.insertDrama(drama);
    onProgress?.call('项目创建成功，AI分析角色中...', 10);

    // 2. AI自动提取角色（带模板上下文）
    final characters = await extractCharacters(
      scriptText: scriptText,
      dramaId: dramaId,
      template: template,
      onProgress: (stage, progress) {
        onProgress?.call('提取角色：$stage', 10 + (progress * 0.2).round());
      },
    );

    onProgress?.call('保存角色...', 32);

    // 3. 保存角色到DB
    for (final character in characters) {
      await StorageUtil.insertCharacter(character.copyWith(dramaId: dramaId));
    }

    // 4. AI自动生成分镜（带模板上下文）
    final scriptResult = await generateStoryboardFromScript(
      scriptText: scriptText,
      characters: characters,
      style: style,
      genre: genre,
      shotsPerEpisode: shotsPerEpisode,
      template: template,
      onProgress: (stage, progress) {
        onProgress?.call('生成分镜：$stage', 35 + (progress * 0.55).round());
      },
    );

    onProgress?.call('保存剧集和镜头...', 92);

    // 5. 保存剧集和镜头到DB
    await StorageUtil.insertEpisodesWithShots(scriptResult.episodes);

    onProgress?.call('完成！', 100);

    // 6. 返回更新后的Drama
    return (await StorageUtil.getDrama(dramaId))!;
  }

  // ==================== 模型配置调用辅助 ====================

  /// 根据Drama的模型配置调用AI
  /// 如果text_model为auto，走chatSmart默认逻辑
  /// 如果text_model为特定模型，指定provider
  /// 如果text_model为custom且提供了api_key/base_url，直接用自定义配置调用
  /// 自动回退：如果指定模型调用失败（特别是Agnes 502/503等网络问题），自动切到chatSmart
  Future<String> _callAiWithModelConfig({
    required int dramaId,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
  }) async {
    final drama = await StorageUtil.getDrama(dramaId);
    final config = drama?.parsedModelConfig ?? DramaModelConfig();

    // 转换messages为chatCompletion期望的格式
    final List<Map<String, String>> formattedMessages = messages
        .map((m) => {'role': m['role']!, 'content': m['content']!})
        .toList();

    if (config.textModel == 'custom') {
      // 自定义配置
      if (config.textApiKey.isEmpty || config.textBaseUrl.isEmpty) {
        throw Exception('自定义文本模型需要配置API Key和Base URL');
      }
      return _apiClient.chatCompletion(
        baseUrl: config.textBaseUrl,
        apiKey: config.textApiKey,
        model: 'default',
        messages: formattedMessages,
        temperature: temperature,
      );
    } else if (config.textModel != 'auto' && config.textModel.isNotEmpty) {
      // 检查是否有预设的Base URL和用户填的API Key
      final presetUrl = _getPresetBaseUrl(config.textModel);
      final presetKey = _getPresetApiKey(config.textModel);
      final effectiveApiKey = config.textApiKey.isNotEmpty ? config.textApiKey : presetKey;

      if (presetUrl.isNotEmpty && effectiveApiKey.isNotEmpty) {
        // 有预设URL且有API Key：直接调用 + 失败自动回退
        // 解析实际模型名称（32AI前缀需要剥离）
        final actualModel = _resolveActualModelName(config.textModel);
        try {
          return await _apiClient.chatCompletion(
            baseUrl: config.textBaseUrl.isNotEmpty ? config.textBaseUrl : presetUrl,
            apiKey: effectiveApiKey,
            model: actualModel,
            messages: formattedMessages,
            temperature: temperature,
          );
        } catch (e) {
          // 自动回退到chatSmart，避免单个模型抽风卡死整个流程
          // 仅当chatSmart能找到其他可用Provider时才回退
          try {
            return await _apiClient.chatSmart(
              messages: messages,
              temperature: temperature,
            );
          } catch (_) {
            // 回退也失败，抛出原始错误让用户知道是哪个模型失败
            throw Exception('${config.textModel}调用失败且无可用回退模型：$e');
          }
        }
      } else {
        // 没有API Key：尝试走chatSmart
        return _apiClient.chatSmart(
          messages: messages,
          temperature: temperature,
          modelOverride: config.textModel,
        );
      }
    } else {
      // auto
      return _apiClient.chatSmart(
        messages: messages,
        temperature: temperature,
      );
    }
  }

  /// 解析实际模型名称（剥离内部路由前缀）
  static String _resolveActualModelName(String model) {
    if (model.startsWith('ai32-')) {
      final stripped = model.replaceFirst('ai32-', '');
      // ai32-deepseek → deepseek-chat
      return stripped == 'deepseek' ? 'deepseek-chat' : stripped;
    }
    return model;
  }

  /// 获取预设模型的默认Base URL
  static String _getPresetBaseUrl(String model) {
    switch (model) {
      case 'agnes-2.0-flash':
      case 'agnes-image':
      case 'agnes-video':
        return 'https://apihub.agnes-ai.com/v1';
      case 'ai32-qwen-plus':
      case 'ai32-deepseek':
        return 'https://32ai.uk/v1';
      case 'ai32-doubao-pro':
      case 'ai32-seedance':
        return 'https://32ai.uk/volc/v1';
      case 'ai32-image':
        return 'https://32ai.uk/v1';
      case 'deepseek-v4-flash':
      case 'deepseek-v4-pro':
        return 'https://api.deepseek.com';
      case 'doubao-pro':
        return 'https://ark.cn-beijing.volces.com/api/v3';
      default:
        return '';
    }
  }

  /// 获取预设模型的默认API Key（Agnes AI + 32AI 全模型预填，其他需用户自行输入）
  static String _getPresetApiKey(String model) {
    switch (model) {
      case 'agnes-2.0-flash':
      case 'agnes-image':
      case 'agnes-video':
        return 'sk-Rcb7FziWSyPq3cZPEcrHx4Xh4MOte1DlUjuEg6w0TBVvhiub';
      case 'ai32-qwen-plus':
      case 'ai32-deepseek':
      case 'ai32-doubao-pro':
      case 'ai32-seedance':
      case 'ai32-image':
        return 'sk-sMC4yb8EUgS2G6OTlFYVwlqJJ5Pg08NpmbuoTg0Qiceh5uq6';
      default:
        return '';
    }
  }
}

/// DramaService的Riverpod Provider
final dramaServiceProvider = Provider<DramaService>((ref) {
  return DramaService(ref.read(apiClientProvider));
});
