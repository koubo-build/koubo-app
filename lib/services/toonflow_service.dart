import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';
import 'tts_service.dart';

/// ToonFlow短剧流水线服务
/// 完整工作流：输入剧本文本 → 导演Agent(集纲+角色) → 分镜Agent → 批量生成视频+配音 → 返回完整短剧
/// 严格对标Coze工作流规范
class ToonFlowService {
  final ApiClient _apiClient;
  final TtsService _ttsService;

  ToonFlowService(this._apiClient, this._ttsService);

  // ==================== 全局变量配置 ====================

  /// 默认视频模型
  static const String defaultVideoModel = 'Agnes-2.5-Flash';

  /// 默认画面比例
  static const String defaultAspectRatio = '9:16';

  /// 默认画风描述
  static const String defaultBaseStyle =
      '3D写实，柔和电影光影，高清细节，竖屏画面，自然渲染，人物皮肤质感真实';

  /// 获取Agnes API Key（优先从StorageUtil读取，否则使用内置默认Key）
  Future<String> _getAgnesApiKey() async {
    final saved = await StorageUtil.getSecure(ApiConfig.agnesApiKeyKey);
    if (saved != null && saved.isNotEmpty) return saved;
    return 'sk-7910JE6f3qpCtYchwYPgzPdpFC2X99chkCNExCvTmvLObACo';
  }

  // ==================== 角色音色池 ====================

  /// 可用音色池，包含男声和女声
  /// 每个音色包含：id、name、gender（male/female）、style描述
  static const List<Map<String, String>> voicePool = [
    {'id': 'longanhuan', 'name': '龙安欢', 'gender': 'female', 'style': '元气女声'},
    {'id': 'longxiaochun', 'name': '龙小淳', 'gender': 'female', 'style': '知性女声'},
    {'id': 'longyue', 'name': '龙悦', 'gender': 'female', 'style': '温柔女声'},
    {'id': 'longmiao', 'name': '龙喵', 'gender': 'female', 'style': '甜美女声'},
    {'id': 'loongbella', 'name': '龙贝拉', 'gender': 'female', 'style': '优雅女声'},
    {'id': 'loongstella', 'name': '龙思黛拉', 'gender': 'female', 'style': '成熟女声'},
    {'id': 'longshuo', 'name': '龙硕', 'gender': 'male', 'style': '沉稳男声'},
    {'id': 'longanyang', 'name': '龙安洋', 'gender': 'male', 'style': '阳光男声'},
    {'id': 'longxiang', 'name': '龙翔', 'gender': 'male', 'style': '磁性男声'},
    {'id': 'longtong', 'name': '龙彤', 'gender': 'male', 'style': '少年男声'},
  ];

  /// 根据角色描述自动为角色分配不同音色
  /// 根据角色名字或描述中的性别关键词匹配男/女声，未匹配到则交替分配
  static void autoAssignVoices(List<ToonCharacter> characters) {
    final femaleVoices = voicePool.where((v) => v['gender'] == 'male' ? false : true).toList();
    final maleVoices = voicePool.where((v) => v['gender'] == 'male').toList();
    int femaleIdx = 0;
    int maleIdx = 0;

    for (final char in characters) {
      // 根据角色描述判断性别
      final desc = (char.name + ' ' + char.desc).toLowerCase();
      bool? isMale;

      // 中文性别关键词
      if (desc.contains('男') || desc.contains('先生') || desc.contains('哥') ||
          desc.contains('爷') || desc.contains('叔') || desc.contains('少年')) {
        isMale = true;
      } else if (desc.contains('女') || desc.contains('小姐') || desc.contains('姐') ||
          desc.contains('娘') || desc.contains('婆') || desc.contains('少女')) {
        isMale = false;
      }
      // 英文性别关键词
      else if (desc.contains('boy') || desc.contains('man') || desc.contains('mr') ||
          desc.contains('male') || desc.contains('king') || desc.contains('uncle')) {
        isMale = true;
      } else if (desc.contains('girl') || desc.contains('woman') || desc.contains('mrs') ||
          desc.contains('ms') || desc.contains('female') || desc.contains('queen')) {
        isMale = false;
      }

      // 分配音色
      if (isMale == true && maleVoices.isNotEmpty) {
        char.voiceId = maleVoices[maleIdx % maleVoices.length]['id']!;
        maleIdx++;
      } else if (isMale == false && femaleVoices.isNotEmpty) {
        char.voiceId = femaleVoices[femaleIdx % femaleVoices.length]['id']!;
        femaleIdx++;
      } else {
        // 无法判断性别，交替分配所有音色
        final allIdx = femaleIdx + maleIdx;
        char.voiceId = voicePool[allIdx % voicePool.length]['id']!;
        femaleIdx++;
      }
    }
  }

  /// 根据角色名获取对应音色ID
  static String _getVoiceForSpeaker(String speaker, List<ToonCharacter> characters) {
    if (speaker.isEmpty) return 'longanhuan'; // 旁白默认用龙安欢
    for (final char in characters) {
      if (char.name == speaker && char.voiceId.isNotEmpty) {
        return char.voiceId;
      }
    }
    // 模糊匹配：角色名包含speaker或speaker包含角色名
    for (final char in characters) {
      if (speaker.contains(char.name) || char.name.contains(speaker)) {
        if (char.voiceId.isNotEmpty) return char.voiceId;
      }
    }
    return 'longanhuan'; // 未找到匹配角色，使用默认音色
  }

  // ==================== 节点1：LLM 导演Agent ====================

  static const String _directorSystemPrompt =
      '你是专业短剧导演。\n输入：短剧原文剧本\n要求输出标准JSON，禁止多余解释、禁止markdown。\n任务：\n1.梳理完整分集大纲，单集3分钟，每集结尾预留悬念钩子；\n2.提取所有登场人物，为每个人物生成固定外貌描述（用于AI视频统一形象，杜绝变脸）；\nJSON固定结构：\n{\n  "outline": [\n    {"episode": "第1集","content": "剧情简述","hook":"结尾悬念"}\n  ],\n  "characters": [\n    {"name":"角色名","desc":"年龄、发型、穿搭、五官特征、气质，详细画面描述"}\n  ]\n}';

  /// 导演Agent：输入剧本，输出集纲+角色
  Future<DirectorResult> runDirectorAgent({
    required String userInput,
    void Function(String stage, int progress)? onProgress,
  }) async {
    onProgress?.call('导演Agent分析剧本...', 5);

    final response = await _apiClient.chatSmart(
      messages: [
        {'role': 'system', 'content': _directorSystemPrompt},
        {'role': 'user', 'content': userInput},
      ],
      temperature: 0.4,
      maxTokens: 8192,
    );

    onProgress?.call('解析导演输出...', 15);

    // JSON文本清洗：截取{}之间内容
    final jsonStr = _extractJson(response);
    if (jsonStr == null) {
      throw Exception('导演Agent输出无法解析为JSON');
    }

    final data = jsonDecode(jsonStr) as Map<String, dynamic>;

    // 解析分集大纲
    final outlineJson = data['outline'] as List<dynamic>? ?? [];
    final outline = outlineJson
        .map((e) => OutlineItem.fromJson(e as Map<String, dynamic>))
        .toList();

    // 解析角色
    final charactersJson = data['characters'] as List<dynamic>? ?? [];
    final characters = charactersJson
        .map((e) => ToonCharacter.fromJson(e as Map<String, dynamic>))
        .toList();

    onProgress?.call('导演Agent完成，${outline.length}集 ${characters.length}角色', 20);

    return DirectorResult(outline: outline, characters: characters);
  }

  // ==================== 节点3：LLM 分镜Agent ====================

  static const String _storyboardSystemPrompt =
      '你是影视分镜师。\n输入：标准化剧本 + 全部角色外貌档案\n输出JSON数组，一条数据=一个镜头。\n强制规则：\n1.每一条分镜画面描述，自动拼接对应角色固定外貌信息，保证人物统一；\n2.标注景别：特写/近景/中景/全景；增加运镜：缓慢推进、固定镜头、轻微平移；\n3.画风统一，竖屏9:16，高清，电影级光影；\n4.控制镜头时长，单镜头2～8秒；\n5.每个镜头必须标注说话角色名（speaker），旁白填"旁白"；\nJSON结构：\n{\n  "shot_list":[\n    {\n      "scene_desc":"完整画面提示词",\n      "camera":"景别+运镜",\n      "audio_text":"当前镜头需要配音的旁白/台词",\n      "speaker":"说话角色名（对应角色档案中的name，旁白填\'旁白\'）",\n      "duration":"镜头时长(数字，单位秒)"\n    }\n  ]\n}';

  /// 分镜Agent：输入剧本+角色，输出分镜列表
  Future<List<ShotItem>> runStoryboardAgent({
    required DirectorResult scriptResult,
    required List<ToonCharacter> characters,
    void Function(String stage, int progress)? onProgress,
  }) async {
    onProgress?.call('分镜Agent生成镜头...', 22);

    // 构建角色信息文本
    final charInfo = characters
        .map((c) => '${c.name}: ${c.desc}')
        .join('\n');

    // 构建剧本大纲文本
    final outlineText = scriptResult.outline
        .map((o) => '${o.episode}: ${o.content}（悬念：${o.hook}）')
        .join('\n');

    final userInput = '剧本大纲：\n$outlineText\n\n角色外貌档案：\n$charInfo';

    final response = await _apiClient.chatSmart(
      messages: [
        {'role': 'system', 'content': _storyboardSystemPrompt},
        {'role': 'user', 'content': userInput},
      ],
      temperature: 0.3,
      maxTokens: 16384,
    );

    onProgress?.call('解析分镜数据...', 30);

    // JSON文本清洗
    final jsonStr = _extractJson(response);
    if (jsonStr == null) {
      throw Exception('分镜Agent输出无法解析为JSON');
    }

    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    final shotListJson = data['shot_list'] as List<dynamic>? ?? [];

    final shots = shotListJson
        .map((e) => ShotItem.fromJson(e as Map<String, dynamic>))
        .toList();

    onProgress?.call('分镜生成完成，共${shots.length}个镜头', 35);

    return shots;
  }

  // ==================== 节点4：循环生成视频+配音 ====================

  /// 提交Agnes文生视频任务
  Future<String> _submitVideoTask({
    required String prompt,
    required String apiKey,
    required String videoModel,
    required String aspectRatio,
    required int duration,
    String? imageRef,
  }) async {
    final body = <String, dynamic>{
      'model': videoModel,
      'prompt': prompt,
      'ratio': aspectRatio,
      'duration': duration,
      'cfg_scale': 7,
      'motion_bucket_id': 120,
    };

    // 支持image_ref参数（角色参考图URL）
    if (imageRef != null && imageRef.isNotEmpty) {
      body['image_ref'] = imageRef;
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ));

    final response = await dio.post(
      '${ApiConfig.agnesBaseUrl}/video/generations',
      data: jsonEncode(body),
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
    );

    final data = response.data as Map<String, dynamic>;
    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw Exception('Agnes视频任务提交失败，未返回task_id');
    }
    return taskId;
  }

  /// 轮询查询Agnes视频任务状态
  /// 返回 (status, videoUrl)
  Future<VideoPollResult> _pollVideoTask({
    required String taskId,
    required String apiKey,
    int maxPolls = 120, // 最多轮询120次（10分钟）
  }) async {
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));

    for (int i = 0; i < maxPolls; i++) {
      await Future.delayed(const Duration(seconds: 5)); // 轮询间隔不低于5秒

      try {
        final response = await dio.get(
          '${ApiConfig.agnesBaseUrl}/video/generations/$taskId',
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
          }),
        );

        final data = response.data as Map<String, dynamic>;
        final status = data['status'] as String? ?? '';

        if (status == 'success') {
          final videoUrl = data['video_url'] as String? ?? '';
          return VideoPollResult(status: 'success', videoUrl: videoUrl);
        } else if (status == 'failed') {
          final errorMsg = data['error'] as String? ?? '视频生成失败';
          return VideoPollResult(status: 'failed', videoUrl: '', error: errorMsg);
        }
        // pending / running → 继续轮询
      } on DioException catch (e) {
        // 网络错误，继续轮询
        debugPrint('[ToonFlow] 轮询网络错误: ${e.message}');
      }
    }

    return VideoPollResult(status: 'failed', videoUrl: '', error: '视频生成超时');
  }

  /// TTS配音：为单个镜头生成音频
  Future<String?> _generateAudioForShot({
    required String audioText,
    required String voiceId,
  }) async {
    if (audioText.trim().isEmpty) return null;

    try {
      final audioPath = await _ttsService.synthesize(
        text: audioText,
        voiceId: voiceId,
        provider: 'cosyvoice',
      );
      return audioPath;
    } catch (e) {
      debugPrint('[ToonFlow] TTS配音失败: $e');
      return null;
    }
  }

  // ==================== 角色定妆照生成 ====================

  /// 为所有角色生成定妆照（角色参考图）
  /// 使用 Agnes AI 图像生成 API，生成统一风格的角色肖像
  /// 返回成功生成的角色数
  Future<int> generateCharacterPortraits({
    required List<ToonCharacter> characters,
    required String baseStyle,
    required String aspectRatio,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await _getAgnesApiKey();
    int successCount = 0;

    for (int i = 0; i < characters.length; i++) {
      final char = characters[i];
      // 进度映射：30%~45%之间分配
      final progressVal = 30 + ((i / characters.length) * 15).round();
      onProgress?.call('生成角色定妆照 ${i + 1}/${characters.length}: ${char.name}', progressVal);

      try {
        final portraitUrl = await _generatePortrait(
          apiKey: apiKey,
          characterName: char.name,
          characterDesc: char.desc,
          baseStyle: baseStyle,
          aspectRatio: aspectRatio,
        );
        char.portraitUrl = portraitUrl;
        successCount++;
        debugPrint('[ToonFlow] 角色 ${char.name} 定妆照生成成功: $portraitUrl');
      } catch (e) {
        debugPrint('[ToonFlow] 角色 ${char.name} 定妆照生成失败: $e');
        // 不影响其他角色，继续
      }
    }

    onProgress?.call('定妆照生成完成，成功$successCount/${characters.length}', 45);
    return successCount;
  }

  /// 生成单个角色的定妆照
  Future<String> _generatePortrait({
    required String apiKey,
    required String characterName,
    required String characterDesc,
    required String baseStyle,
    required String aspectRatio,
  }) async {
    // 构造角色定妆照专用prompt
    // 关键：角色肖像照，正面或3/4侧面，纯色背景，清晰展现角色外貌特征
    final prompt = '角色设定照，$characterName，$characterDesc，正面或微侧面半身像，中性灰色纯色背景，柔和均匀灯光，$baseStyle，高清细节，角色一致性参考图';

    // 确定图片尺寸
    // aspectRatio 9:16 -> 1024x1792, 16:9 -> 1792x1024, 1:1 -> 1024x1024
    String size = '1024x1792'; // 默认竖屏
    if (aspectRatio == '16:9') {
      size = '1792x1024';
    } else if (aspectRatio == '1:1') {
      size = '1024x1024';
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(minutes: 5),
    ));

    final response = await dio.post(
      '${ApiConfig.agnesBaseUrl}/images/generations',
      data: jsonEncode({
        'model': 'agnes-image-2.1-flash',
        'prompt': prompt,
        'size': size,
        'n': 1,
      }),
      options: Options(headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
      }),
    );

    final data = response.data as Map<String, dynamic>;
    final imageData = data['data'] as List<dynamic>?;
    if (imageData == null || imageData.isEmpty) {
      throw Exception('定妆照生成未返回图片');
    }

    final imageUrl = imageData[0]['url'] as String?;
    if (imageUrl == null || imageUrl.isEmpty) {
      // 尝试b64_json
      final b64 = imageData[0]['b64_json'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        // base64 无法直接作为 image_ref，需要URL
        throw Exception('定妆照返回base64格式，无法用作参考图');
      }
      throw Exception('定妆照生成失败：未返回图片URL');
    }

    return imageUrl;
  }

  /// 第一步+：在导演分析完成后，生成角色定妆照
  /// 返回成功生成的定妆照数量
  Future<int> runPortraitGeneration({
    required List<ToonCharacter> characters,
    required String baseStyle,
    required String aspectRatio,
    void Function(String stage, int progress)? onProgress,
  }) async {
    return generateCharacterPortraits(
      characters: characters,
      baseStyle: baseStyle,
      aspectRatio: aspectRatio,
      onProgress: onProgress,
    );
  }

  // ==================== 主流程：一键生成完整短剧 ====================

  /// 一键执行ToonFlow全流程
  /// 返回ToonFlowResult（包含所有视频/音频链接和结尾悬念）
  /// [characterVoiceMap] 可选，手动指定角色音色映射 {角色名: voiceId}
  /// [existingCharacters] 可选，传入已有角色（含定妆照和音色），跳过导演Agent的角色分析
  /// 若未提供，则自动根据角色性别分配音色
  Future<ToonFlowResult> runFullPipeline({
    required String userInput,
    String videoModel = defaultVideoModel,
    String aspectRatio = defaultAspectRatio,
    String baseStyle = defaultBaseStyle,
    Map<String, String>? characterVoiceMap,
    List<ToonCharacter>? existingCharacters,
    bool enableTts = true,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 获取API Key
    final apiKey = await _getAgnesApiKey();

    DirectorResult directorResult;

    if (existingCharacters != null && existingCharacters.isNotEmpty) {
      // 使用已有角色，但仍执行导演Agent获取outline
      // 合并：用existingCharacters的voiceId和portraitUrl覆盖freshResult的characters
      final freshResult = await runDirectorAgent(
        userInput: userInput,
        onProgress: onProgress,
      );

      for (final existingChar in existingCharacters) {
        for (final freshChar in freshResult.characters) {
          if (freshChar.name == existingChar.name) {
            freshChar.voiceId = existingChar.voiceId;
            freshChar.portraitUrl = existingChar.portraitUrl;
            break;
          }
        }
      }

      directorResult = DirectorResult(
        outline: freshResult.outline,
        characters: freshResult.characters,
      );
    } else {
      // ====== 节点1：导演Agent ======
      directorResult = await runDirectorAgent(
        userInput: userInput,
        onProgress: onProgress,
      );

      // 自动为角色分配音色
      if (characterVoiceMap != null && characterVoiceMap.isNotEmpty) {
        // 用户手动指定了角色音色映射
        for (final char in directorResult.characters) {
          if (characterVoiceMap.containsKey(char.name)) {
            char.voiceId = characterVoiceMap[char.name]!;
          }
        }
      } else {
        // 自动分配音色
        autoAssignVoices(directorResult.characters);
      }
    }

    // 获取结尾悬念
    final episodeHook = directorResult.outline.isNotEmpty
        ? directorResult.outline.last.hook
        : '';

    // ====== 节点3：分镜Agent ======
    final allShots = await runStoryboardAgent(
      scriptResult: directorResult,
      characters: directorResult.characters,
      onProgress: onProgress,
    );

    // ====== 新增：角色定妆照生成 ======
    // 仅在角色还没有定妆照时生成
    final needsPortraits = directorResult.characters.any((c) => c.portraitUrl.isEmpty);
    if (needsPortraits) {
      onProgress?.call('生成角色定妆照...', 30);
      await generateCharacterPortraits(
        characters: directorResult.characters,
        baseStyle: baseStyle,
        aspectRatio: aspectRatio,
        onProgress: onProgress,
      );
    }

    // 构建角色名→定妆照URL映射
    final characterPortraitMap = <String, String>{};
    for (final char in directorResult.characters) {
      if (char.portraitUrl.isNotEmpty) {
        characterPortraitMap[char.name] = char.portraitUrl;
      }
    }

    // ====== 节点4：遍历所有分镜，生成视频+配音 ======
    final videoList = <VideoSegment>[];
    final audioList = <AudioSegment>[];
    final totalShots = allShots.length;
    int failedCount = 0;

    for (int i = 0; i < totalShots; i++) {
      final shot = allShots[i];
      // 进度调整：定妆照占30-45%，视频占45-100%
      final shotProgress = 45 + ((i / totalShots) * 50).round();
      onProgress?.call(
        '生成镜头 ${i + 1}/$totalShots: ${shot.camera}',
        shotProgress,
      );

      // 根据speaker查找对应角色的定妆照URL
      String? shotImageRef;
      if (shot.speaker.isNotEmpty && shot.speaker != '旁白') {
        // 精确匹配
        if (characterPortraitMap.containsKey(shot.speaker)) {
          shotImageRef = characterPortraitMap[shot.speaker];
        } else {
          // 模糊匹配
          for (final entry in characterPortraitMap.entries) {
            if (shot.speaker.contains(entry.key) || entry.key.contains(shot.speaker)) {
              shotImageRef = entry.value;
              break;
            }
          }
        }
      }
      // 如果speaker是旁白或没匹配到，尝试使用第一个有定妆照的角色
      if (shotImageRef == null && characterPortraitMap.isNotEmpty) {
        shotImageRef = characterPortraitMap.values.first;
      }

      // 4-1: 提交Agnes视频任务
      String? taskId;
      try {
        final prompt = '${shot.scene_desc},$baseStyle';
        final duration = shot.durationInt;

        taskId = await _submitVideoTask(
          prompt: prompt,
          apiKey: apiKey,
          videoModel: videoModel,
          aspectRatio: aspectRatio,
          duration: duration,
          imageRef: shotImageRef,
        );
      } catch (e) {
        debugPrint('[ToonFlow] 镜头${i + 1}提交失败: $e');
        failedCount++;
        videoList.add(VideoSegment(
          index: i,
          videoUrl: '',
          status: 'failed',
          error: e.toString(),
        ));
        continue;
      }

      // 4-2: 轮询查询任务状态
      onProgress?.call(
        '镜头 ${i + 1}/$totalShots 视频生成中...',
        shotProgress + 2,
      );

      final pollResult = await _pollVideoTask(
        taskId: taskId,
        apiKey: apiKey,
      );

      if (pollResult.status == 'success') {
        videoList.add(VideoSegment(
          index: i,
          videoUrl: pollResult.videoUrl,
          status: 'success',
        ));
      } else {
        failedCount++;
        videoList.add(VideoSegment(
          index: i,
          videoUrl: '',
          status: 'failed',
          error: pollResult.error,
        ));
      }

      // 4-3: TTS配音（可选）- 根据角色分配不同音色
      if (enableTts && shot.audio_text.isNotEmpty) {
        onProgress?.call(
          '镜头 ${i + 1}/$totalShots 生成配音...',
          shotProgress + 5,
        );

        // 根据说话角色获取对应音色
        final voiceId = _getVoiceForSpeaker(shot.speaker, directorResult.characters);

        final audioPath = await _generateAudioForShot(
          audioText: shot.audio_text,
          voiceId: voiceId,
        );

        audioList.add(AudioSegment(
          index: i,
          audioPath: audioPath ?? '',
          audioText: shot.audio_text,
          status: audioPath != null ? 'success' : 'failed',
        ));
      }
    }

    onProgress?.call(
      '完成！成功${videoList.where((v) => v.status == 'success').length}个视频，失败$failedCount个',
      100,
    );

    // ====== 返回节点 ======
    return ToonFlowResult(
      videoSegments: videoList,
      audioSegments: audioList,
      endingHook: episodeHook,
      characters: directorResult.characters,
      outline: directorResult.outline,
      shots: allShots,
    );
  }

  // ==================== JSON清洗工具 ====================

  /// 从文本中提取JSON字符串
  /// 截取第一个{到对应的}之间的内容
  String? _extractJson(String text) {
    // 先尝试直接解析
    try {
      jsonDecode(text);
      return text;
    } catch (_) {}

    // 去除markdown代码块
    var cleaned = text.trim();
    if (cleaned.startsWith('```')) {
      final firstNewline = cleaned.indexOf('\n');
      if (firstNewline != -1) {
        cleaned = cleaned.substring(firstNewline + 1);
      }
      if (cleaned.endsWith('```')) {
        cleaned = cleaned.substring(0, cleaned.length - 3);
      }
      cleaned = cleaned.trim();
      try {
        jsonDecode(cleaned);
        return cleaned;
      } catch (_) {}
    }

    // 截取{}之间内容
    final startIdx = cleaned.indexOf('{');
    if (startIdx == -1) return null;

    int depth = 0;
    for (int i = startIdx; i < cleaned.length; i++) {
      if (cleaned[i] == '{') {
        depth++;
      } else if (cleaned[i] == '}') {
        depth--;
        if (depth == 0) {
          final jsonStr = cleaned.substring(startIdx, i + 1);
          try {
            jsonDecode(jsonStr);
            return jsonStr;
          } catch (_) {
            // 继续找下一个
          }
        }
      }
    }

    // 尝试截取到最后一个}
    final lastBrace = cleaned.lastIndexOf('}');
    if (lastBrace > startIdx) {
      final jsonStr = cleaned.substring(startIdx, lastBrace + 1);
      try {
        jsonDecode(jsonStr);
        return jsonStr;
      } catch (_) {}
    }

    return null;
  }
}

// ==================== 数据模型 ====================

/// 导演Agent输出结果
class DirectorResult {
  final List<OutlineItem> outline;
  final List<ToonCharacter> characters;

  DirectorResult({required this.outline, required this.characters});
}

/// 分集大纲项
class OutlineItem {
  final String episode;
  final String content;
  final String hook;

  OutlineItem({
    required this.episode,
    required this.content,
    required this.hook,
  });

  factory OutlineItem.fromJson(Map<String, dynamic> json) {
    return OutlineItem(
      episode: json['episode'] as String? ?? '',
      content: json['content'] as String? ?? '',
      hook: json['hook'] as String? ?? '',
    );
  }
}

/// ToonFlow角色
class ToonCharacter {
  final String name;
  final String desc;
  String voiceId; // 分配给该角色的TTS音色ID
  String portraitUrl; // 角色定妆照URL（用于视频生成时的角色参考）

  ToonCharacter({
    required this.name,
    required this.desc,
    this.voiceId = '',
    this.portraitUrl = '',
  });

  factory ToonCharacter.fromJson(Map<String, dynamic> json) {
    return ToonCharacter(
      name: json['name'] as String? ?? '',
      desc: json['desc'] as String? ?? '',
      portraitUrl: json['portraitUrl'] as String? ?? '',
    );
  }
}

/// 分镜镜头项
class ShotItem {
  final String scene_desc;
  final String camera;
  final String audio_text;
  final String duration; // 原始值，可能是字符串
  final String speaker; // 说话角色名

  ShotItem({
    required this.scene_desc,
    required this.camera,
    required this.audio_text,
    required this.duration,
    this.speaker = '',
  });

  /// 获取整数时长（秒），默认5
  int get durationInt {
    final d = int.tryParse(duration.replaceAll(RegExp(r'[^\d]'), ''));
    if (d != null && d >= 2 && d <= 8) return d;
    return 5;
  }

  factory ShotItem.fromJson(Map<String, dynamic> json) {
    return ShotItem(
      scene_desc: json['scene_desc'] as String? ?? '',
      camera: json['camera'] as String? ?? '',
      audio_text: json['audio_text'] as String? ?? '',
      duration: (json['duration'] ?? 5).toString(),
      speaker: json['speaker'] as String? ?? '',
    );
  }
}

/// 视频轮询结果
class VideoPollResult {
  final String status; // success / failed / pending / running
  final String videoUrl;
  final String? error;

  VideoPollResult({
    required this.status,
    required this.videoUrl,
    this.error,
  });
}

/// 视频片段
class VideoSegment {
  final int index;
  final String videoUrl;
  final String status; // success / failed
  final String? error;

  VideoSegment({
    required this.index,
    required this.videoUrl,
    required this.status,
    this.error,
  });
}

/// 音频片段
class AudioSegment {
  final int index;
  final String audioPath;
  final String audioText;
  final String status; // success / failed

  AudioSegment({
    required this.index,
    required this.audioPath,
    required this.audioText,
    required this.status,
  });
}

/// ToonFlow完整输出结果
class ToonFlowResult {
  final List<VideoSegment> videoSegments;
  final List<AudioSegment> audioSegments;
  final String endingHook;
  final List<ToonCharacter> characters;
  final List<OutlineItem> outline;
  final List<ShotItem> shots;

  ToonFlowResult({
    required this.videoSegments,
    required this.audioSegments,
    required this.endingHook,
    required this.characters,
    required this.outline,
    required this.shots,
  });

  /// 成功视频数
  int get successCount =>
      videoSegments.where((v) => v.status == 'success').length;

  /// 总视频数
  int get totalCount => videoSegments.length;

  /// 是否全部成功
  bool get isAllSuccess => successCount == totalCount && totalCount > 0;
}

/// ToonFlowService的Riverpod Provider
final toonFlowServiceProvider = Provider<ToonFlowService>((ref) {
  return ToonFlowService(
    ref.read(apiClientProvider),
    ref.read(ttsServiceProvider),
  );
});
