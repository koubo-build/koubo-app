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
      '你是影视分镜师。\n输入：标准化剧本 + 全部角色外貌档案\n输出JSON数组，一条数据=一个镜头。\n强制规则：\n1.每一条分镜画面描述，自动拼接对应角色固定外貌信息，保证人物统一；\n2.标注景别：特写/近景/中景/全景；增加运镜：缓慢推进、固定镜头、轻微平移；\n3.画风统一，竖屏9:16，高清，电影级光影；\n4.控制镜头时长，单镜头2～8秒；\nJSON结构：\n{\n  "shot_list":[\n    {\n      "scene_desc":"完整画面提示词",\n      "camera":"景别+运镜",\n      "audio_text":"当前镜头需要配音的旁白/台词",\n      "duration":"镜头时长(数字，单位秒)"\n    }\n  ]\n}';

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

  // ==================== 主流程：一键生成完整短剧 ====================

  /// 一键执行ToonFlow全流程
  /// 返回ToonFlowResult（包含所有视频/音频链接和结尾悬念）
  Future<ToonFlowResult> runFullPipeline({
    required String userInput,
    String videoModel = defaultVideoModel,
    String aspectRatio = defaultAspectRatio,
    String baseStyle = defaultBaseStyle,
    String ttsVoiceId = 'longanhuan',
    bool enableTts = true,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 获取API Key
    final apiKey = await _getAgnesApiKey();

    // ====== 节点1：导演Agent ======
    final directorResult = await runDirectorAgent(
      userInput: userInput,
      onProgress: onProgress,
    );

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

    // ====== 节点4：遍历所有分镜，生成视频+配音 ======
    final videoList = <VideoSegment>[];
    final audioList = <AudioSegment>[];
    final totalShots = allShots.length;
    int failedCount = 0;

    for (int i = 0; i < totalShots; i++) {
      final shot = allShots[i];
      final shotProgress = 35 + ((i / totalShots) * 60).round();
      onProgress?.call(
        '生成镜头 ${i + 1}/$totalShots: ${shot.camera}',
        shotProgress,
      );

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

      // 4-3: TTS配音（可选）
      if (enableTts && shot.audio_text.isNotEmpty) {
        onProgress?.call(
          '镜头 ${i + 1}/$totalShots 生成配音...',
          shotProgress + 5,
        );

        final audioPath = await _generateAudioForShot(
          audioText: shot.audio_text,
          voiceId: ttsVoiceId,
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

  ToonCharacter({required this.name, required this.desc});

  factory ToonCharacter.fromJson(Map<String, dynamic> json) {
    return ToonCharacter(
      name: json['name'] as String? ?? '',
      desc: json['desc'] as String? ?? '',
    );
  }
}

/// 分镜镜头项
class ShotItem {
  final String scene_desc;
  final String camera;
  final String audio_text;
  final String duration; // 原始值，可能是字符串

  ShotItem({
    required this.scene_desc,
    required this.camera,
    required this.audio_text,
    required this.duration,
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
