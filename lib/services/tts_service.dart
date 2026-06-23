import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// TTS语音合成服务 - 阿里百炼CosyVoice为主 + Edge-TTS为备选
class TtsService {
  final ApiClient _apiClient;

  TtsService(this._apiClient);

  // ==================== CosyVoice 系统音色映射 ====================

  /// Edge-TTS音色ID → CosyVoice基础音色名 的映射
  /// 注意：实际合成时会根据模型版本自动添加后缀（_v3或_v2）
  /// longanyang和longanhuan各版本通用，无需后缀
  static const Map<String, String> _edgeToCosyVoiceMap = {
    'zh-CN-XiaoxiaoNeural': 'longanhuan',   // 晓晓 → 龙安欢（欢脱元气女）
    'zh-CN-XiaoyiNeural': 'longanhuan',     // 晓艺 → 龙安欢
    'zh-CN-XiaohanNeural': 'longxiaochun',  // 晓涵 → 龙小淳（知性女声）
    'zh-CN-XiaomengNeural': 'longanhuan',   // 晓梦 → 龙安欢
    'zh-CN-XiaochenNeural': 'longanhuan',   // 晓辰 → 龙安欢
    'zh-CN-XiaoshuangNeural': 'longhuhu',   // 晓双 → 龙呼呼（童声）
    'zh-CN-YunjianNeural': 'longanyang',    // 云健 → 龙安洋（阳光大男孩）
    'zh-CN-YunxiNeural': 'longanyang',      // 云希 → 龙安洋
    'zh-CN-YunxiaNeural': 'longanyang',     // 云夏 → 龙安洋
    'zh-CN-YunyangNeural': 'longshuo',      // 云扬 → 龙硕（新闻男声）
    'zh-CN-YunzeNeural': 'longshuo',        // 云泽 → 龙硕
    'zh-CN-YunhaoNeural': 'longshuo',       // 云皓 → 龙硕
    'zh-CN-YunfengNeural': 'longshuo',      // 云枫 → 龙硕
    'zh-CN-liaoning-XiaobeiNeural': 'longanhuan', // 小北 → 龙安欢
    'zh-CN-shaanxi-XiaoniNeural': 'longanhuan',   // 小妮 → 龙安欢
  };

  /// 不同模型版本需要不同音色后缀
  /// v3-flash: longshuo → longshuo_v3, longhuhu → longhuhu_v3
  /// v2: longshuo → longshuo_v2, longhuhu → longhuhu_v2
  /// longanyang和longanhuan在所有版本中无后缀
  static const Set<String> _versionNeutralVoices = {
    'longanyang', 'longanhuan',
  };

  /// 根据模型版本返回正确的音色名
  static String _voiceForModel(String baseVoice, String model) {
    if (_versionNeutralVoices.contains(baseVoice)) return baseVoice;
    if (model.contains('v3')) return '${baseVoice}_v3';
    if (model.contains('v2')) return '${baseVoice}_v2';
    return baseVoice;
  }

  /// CosyVoice 可用系统音色列表（用于UI显示）
  static const List<Map<String, String>> cosyVoiceList = [
    {'id': 'longanyang', 'name': '龙安洋', 'gender': 'male', 'style': '阳光大男孩', 'desc': '20-30岁，中英双语'},
    {'id': 'longanhuan', 'name': '龙安欢', 'gender': 'female', 'style': '欢脱元气女', 'desc': '20-30岁，中英双语'},
    {'id': 'longxiaochun', 'name': '龙小淳', 'gender': 'female', 'style': '知性女声', 'desc': '温柔知性'},
    {'id': 'longshuo', 'name': '龙硕', 'gender': 'male', 'style': '沉稳男声', 'desc': '专业播报'},
    {'id': 'longhuhu', 'name': '龙呼呼', 'gender': 'female', 'style': '童声', 'desc': '可爱童声'},
  ];

  /// Edge-TTS 可用中文音色列表（备选方案显示用）
  static const List<Map<String, String>> edgeTtsVoices = [
    {'id': 'zh-CN-XiaoxiaoNeural', 'name': '晓晓', 'gender': 'female', 'style': '温柔女声'},
    {'id': 'zh-CN-XiaoyiNeural', 'name': '晓艺', 'gender': 'female', 'style': '活泼女声'},
    {'id': 'zh-CN-XiaohanNeural', 'name': '晓涵', 'gender': 'female', 'style': '知性女声'},
    {'id': 'zh-CN-XiaomengNeural', 'name': '晓梦', 'gender': 'female', 'style': '甜美女声'},
    {'id': 'zh-CN-XiaochenNeural', 'name': '晓辰', 'gender': 'female', 'style': '活力女声'},
    {'id': 'zh-CN-XiaoshuangNeural', 'name': '晓双', 'gender': 'female', 'style': '儿童音'},
    {'id': 'zh-CN-YunjianNeural', 'name': '云健', 'gender': 'male', 'style': '磁性男声'},
    {'id': 'zh-CN-YunxiNeural', 'name': '云希', 'gender': 'male', 'style': '年轻男声'},
    {'id': 'zh-CN-YunxiaNeural', 'name': '云夏', 'gender': 'male', 'style': '少年音'},
    {'id': 'zh-CN-YunyangNeural', 'name': '云扬', 'gender': 'male', 'style': '新闻男声'},
    {'id': 'zh-CN-YunzeNeural', 'name': '云泽', 'gender': 'male', 'style': '沉稳男声'},
    {'id': 'zh-CN-YunhaoNeural', 'name': '云皓', 'gender': 'male', 'style': '广告男声'},
    {'id': 'zh-CN-YunfengNeural', 'name': '云枫', 'gender': 'male', 'style': '旁白男声'},
    {'id': 'zh-CN-liaoning-XiaobeiNeural', 'name': '小北', 'gender': 'female', 'style': '东北女声'},
    {'id': 'zh-CN-shaanxi-XiaoniNeural', 'name': '小妮', 'gender': 'female', 'style': '陕西女声'},
  ];

  /// Qwen TTS 可用音色列表（克隆音色使用）
  static const List<Map<String, String>> qwenTtsVoices = [
    {'id': 'longanhuan', 'name': '龙安欢', 'gender': 'female', 'style': '欢脱元气女'},
    {'id': 'longanyang', 'name': '龙安洋', 'gender': 'male', 'style': '阳光大男孩'},
    {'id': 'longxiaochun', 'name': '龙小淳', 'gender': 'female', 'style': '知性女声'},
    {'id': 'longshuo', 'name': '龙硕', 'gender': 'male', 'style': '沉稳男声'},
    {'id': 'longhuhu', 'name': '龙呼呼', 'gender': 'female', 'style': '童声'},
  ];

  // ==================== 统一合成接口 ====================

  /// 统一语音合成接口
  /// [provider] 引擎类型: 'cosyvoice' | 'edge_tts' | 'qwen_tts'
  /// 注意：qwen_tts 主要用于克隆音色合成，克隆音色ID会通过voiceId传入
  Future<String> synthesize({
    required String text,
    required String voiceId,
    String provider = 'cosyvoice',
    double speed = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    String? emotion,
  }) async {
    // 根据引擎类型选择合成方式
    switch (provider) {
      case 'qwen_tts':
        // Qwen TTS - 用于克隆音色合成
        return synthesizeQwenTts(
          text: text,
          voiceId: voiceId,
          emotion: emotion,
        );
      case 'edge_tts':
        // Edge-TTS WebSocket在国内被墙，改用qwen3.5-omni-flash（同样支持CosyVoice音色）
        final mappedVoiceId = _mapToCosyVoiceId(voiceId);
        return synthesizeQwenTts(
          text: text,
          voiceId: mappedVoiceId,
          emotion: emotion,
        );
      case 'cosyvoice':
      default:
        // 阿里百炼CosyVoice优先，失败则回退到qwen_tts
        try {
          final cosyVoiceId = _mapToCosyVoiceId(voiceId);
          return await synthesizeCosyVoice(
            text: text,
            voiceId: cosyVoiceId,
            speed: speed,
            pitch: pitch,
            emotion: emotion,
          );
        } catch (e) {
          final msg = e.toString();
          // CosyVoice 403/权限问题，回退到qwen_tts
          if (msg.contains('403') || msg.contains('无权限') || msg.contains('NoPermission')) {
            final cosyVoiceId = _mapToCosyVoiceId(voiceId);
            return synthesizeQwenTts(
              text: text,
              voiceId: cosyVoiceId,
              emotion: emotion,
            );
          }
          throw Exception('语音合成失败：\n${msg.replaceAll("Exception: ", "")}\n\n请检查：1.阿里百炼API Key是否正确 2.是否欠费');
        }
    }
  }

  /// 将Edge-TTS音色ID映射为CosyVoice音色名
  String _mapToCosyVoiceId(String voiceId) {
    // 如果已经是CosyVoice格式的音色名（纯小写字母），直接返回
    if (!voiceId.contains('-') && voiceId.isNotEmpty) return voiceId;
    // Edge-TTS格式（如zh-CN-YunxiaNeural），查映射表
    final mapped = _edgeToCosyVoiceMap[voiceId];
    if (mapped != null) return mapped;
    // 如果映射表找不到，用默认音色
    return 'longanhuan';
  }

  // ==================== 安全解析音频响应 ====================

  /// 安全提取音频URL
  /// DashScope API的audio/audio_url字段可能是String或Map<String,dynamic>
  /// 新版API: audio = {"data": "base64...", "url": "https://...", "id": "...", "expires_at": ...}
  /// 旧版API: audio = "base64string", audio_url = "https://..."
  String? _extractAudioUrl(dynamic audioField) {
    if (audioField == null) return null;
    if (audioField is String) return audioField.isNotEmpty ? audioField : null;
    if (audioField is Map<String, dynamic>) {
      // 新版格式: audio.url
      final url = audioField['url'];
      if (url is String && url.isNotEmpty) return url;
      return null;
    }
    return null;
  }

  /// 安全提取base64音频数据
  /// 返回非空的base64字符串，或null
  String? _extractAudioBase64(dynamic audioField) {
    if (audioField == null) return null;
    if (audioField is String) return audioField.isNotEmpty ? audioField : null;
    if (audioField is Map<String, dynamic>) {
      // 新版格式: audio.data
      final data = audioField['data'];
      if (data is String && data.isNotEmpty) return data;
      return null;
    }
    return null;
  }

  // ==================== 阿里百炼 CosyVoice（主力方案） ====================

  /// CosyVoice模型优先级列表（自动降级）
  /// v3-flash推荐优先（速度快、音色多），v2备选
  static const List<String> _cosyVoiceModels = [
    'cosyvoice-v3-flash',
    'cosyvoice-v2',
  ];

  /// 使用阿里百炼CosyVoice合成语音
  /// 官方API格式：POST /api/v1/services/audio/tts/SpeechSynthesizer
  Future<String> synthesizeCosyVoice({
    required String text,
    required String voiceId,
    double speed = 1.0,
    double pitch = 1.0,
    String? emotion,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置阿里百炼API Key');
    }

    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'cosy_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    // 按优先级尝试不同模型
    Exception? lastError;
    for (final model in _cosyVoiceModels) {
      try {
        return await _callCosyVoiceApi(
          apiKey: apiKey,
          model: model,
          text: text,
          voiceId: voiceId,
          speed: speed,
          pitch: pitch,
          emotion: emotion,
          filePath: filePath,
        );
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        final msg = e.toString();
        // 如果是模型不存在/无权限，尝试下一个模型
        if (msg.contains('ModelNotFound') || msg.contains('model_not_found')
            || msg.contains('NoPermission') || msg.contains('不支持')) {
          continue;
        }
        // 其他错误（参数错误、网络错误等），不重试其他模型
        rethrow;
      }
    }
    throw lastError ?? Exception('所有CosyVoice模型均不可用');
  }

  /// 实际调用CosyVoice API
  Future<String> _callCosyVoiceApi({
    required String apiKey,
    required String model,
    required String text,
    required String voiceId,
    required double speed,
    required double pitch,
    String? emotion,
    required String filePath,
  }) async {
    // 构建请求体（按官方API格式）
    // 关键：不同模型版本需要不同的音色名后缀
    // v3-flash: longshuo → longshuo_v3; v2: longshuo → longshuo_v2
    final baseVoiceId = voiceId.isEmpty ? 'longanhuan' : voiceId;
    final effectiveVoiceId = _voiceForModel(baseVoiceId, model);
    final input = <String, dynamic>{
      'text': text,
      'voice': effectiveVoiceId,
      'format': 'mp3',
      'sample_rate': 24000,
    };
    // 语速和音高只在非默认值时发送（部分旧模型可能不支持）
    if (speed != 1.0) input['rate'] = speed;
    if (pitch != 1.0) input['pitch'] = pitch;

    // 情感控制（Instruct方式，仅部分音色支持）
    if (emotion != null && emotion.isNotEmpty) {
      final emotionMap = {
        '开心': 'happy',
        '悲伤': 'sad',
        '激动': 'surprised',
        '愤怒': 'angry',
        '平静': 'neutral',
      };
      final emotionValue = emotionMap[emotion] ?? 'neutral';
      input['instruction'] = '你说话的情感是$emotionValue。';
    }

    final requestBody = <String, dynamic>{
      'model': model,
      'input': input,
    };

    // 发送请求
    final response = await _apiClient.post(
      '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliCosyvoiceEndpoint}',
      data: requestBody,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.json,
        receiveTimeout: const Duration(seconds: 60),
      ),
    );

    final data = response.data as Map<String, dynamic>;

    // 解析响应 - DashScope API可能返回新版或旧版格式
    final output = data['output'] as Map<String, dynamic>?;
    if (output != null) {
      // 优先提取音频URL（新版: audio.url 或 旧版: audio_url）
      final audioUrl = _extractAudioUrl(output['audio']) ?? _extractAudioUrl(output['audio_url']);
      if (audioUrl != null) {
        return await _downloadAudioFromUrl(audioUrl, filePath);
      }

      // 提取base64音频数据（新版: audio.data 或 旧版: audio）
      final audioBase64 = _extractAudioBase64(output['audio']);
      if (audioBase64 != null) {
        return await _saveBase64Audio(audioBase64, filePath);
      }
    }

    // 方式2：异步任务（返回task_id）
    final requestId = data['request_id'] as String?;
    // 检查是否有task_id在output中
    final taskId = output?['task_id'] as String?;
    if (taskId != null) {
      return await _pollCosyVoiceTask(taskId, apiKey, filePath);
    }

    // 方式3：response直接是bytes
    if (response.data is List<int>) {
      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    }

    throw Exception('CosyVoice返回格式异常：${data.keys.join(", ")}，请检查API Key是否正确');
  }

  /// 轮询CosyVoice异步任务
  Future<String> _pollCosyVoiceTask(String taskId, String apiKey, String filePath) async {
    final pollUrl = '${ApiConfig.aliBailianBaseUrl}/tasks/$taskId';
    int retryCount = 0;
    const maxRetries = 60;

    while (retryCount < maxRetries) {
      await Future.delayed(const Duration(seconds: 3));

      final response = await _apiClient.get(
        pollUrl,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>? ?? {};
      final taskStatus = output['task_status'] as String? ?? '';

      if (taskStatus == 'SUCCEEDED') {
        // 安全提取音频URL或base64（兼容新版Map格式和旧版String格式）
        final audioUrl = _extractAudioUrl(output['audio']) ?? _extractAudioUrl(output['audio_url']);
        if (audioUrl != null) {
          return await _downloadAudioFromUrl(audioUrl, filePath);
        }
        final audioBase64 = _extractAudioBase64(output['audio']);
        if (audioBase64 != null) {
          return await _saveBase64Audio(audioBase64, filePath);
        }
        throw Exception('CosyVoice任务完成但未返回音频');
      } else if (taskStatus == 'FAILED') {
        final message = output['message'] as String? ?? '未知错误';
        final errorCode = output['error_code'] as String?;
        throw Exception('CosyVoice合成失败：$errorCode $message');
      }

      retryCount++;
    }

    throw Exception('CosyVoice合成超时（等待3分钟）');
  }

  /// 从URL下载音频文件
  Future<String> _downloadAudioFromUrl(String url, String filePath) async {
    final response = await _apiClient.get(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final file = File(filePath);
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  /// 保存Base64编码的音频数据
  Future<String> _saveBase64Audio(String base64Audio, String filePath) async {
    final audioBytes = base64Decode(base64Audio);
    final file = File(filePath);
    await file.writeAsBytes(audioBytes);
    return filePath;
  }

  // ==================== 阿里百炼 声音复刻合成（qwen3.5-omni） ====================

  /// 使用阿里百炼 Omni 模型 + 克隆音色合成语音
  /// ⚠️ Qwen-Omni模型输出音频必须使用流式模式(stream=true)
  /// 官方文档: OpenAI兼容端点 /compatible-mode/v1/chat/completions
  /// 音频数据通过SSE流式返回: delta.audio.data (base64片段)
  Future<String> synthesizeQwenTts({
    required String text,
    String voiceId = 'longanhuan',
    String? emotion,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置阿里百炼API Key');
    }

    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'omni_${DateTime.now().millisecondsSinceEpoch}.wav';
    final filePath = '$audioDir/$fileName';

    // Qwen-Omni模型必须用流式请求+OpenAI兼容端点才能返回音频
    return _omniStreamSynthesize(
      voiceId: voiceId,
      text: text,
      apiKey: apiKey,
      filePath: filePath,
      emotion: emotion,
    );
  }

  /// Qwen-Omni流式合成核心方法
  /// 通过OpenAI兼容端点(/compatible-mode/v1/chat/completions)发送SSE流式请求
  /// 逐chunk收集delta.audio.data中的base64音频片段，最后合并保存
  Future<String> _omniStreamSynthesize({
    required String voiceId,
    required String text,
    required String apiKey,
    required String filePath,
    String? emotion,
  }) async {
    // 构建提示词
    String promptText = text;
    if (emotion != null && emotion.isNotEmpty) {
      final emotionMap = {
        '开心': 'happy', '悲伤': 'sad', '激动': 'excited',
        '愤怒': 'angry', '平静': 'neutral',
      };
      final emotionValue = emotionMap[emotion] ?? 'neutral';
      promptText = '请用$emotionValue的语气朗读以下内容：\n$text';
    }

    // OpenAI兼容格式请求体（官方文档确认的格式）
    final requestBody = <String, dynamic>{
      'model': ApiConfig.aliOmniModel,
      'messages': [
        {'role': 'user', 'content': promptText}
      ],
      'modalities': ['text', 'audio'],
      'audio': {'voice': voiceId, 'format': 'wav'},
      'stream': true,  // ⚠️ 必须为true，否则无法返回音频
      'stream_options': {'include_usage': true},
    };

    // 创建独立Dio实例（避免全局拦截器干扰流式响应）
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
      sendTimeout: const Duration(seconds: 30),
    ));

    // 发送SSE流式请求
    final response = await dio.post<ResponseBody>(
      '${ApiConfig.aliBailianCompatUrl}/chat/completions',
      data: requestBody,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        responseType: ResponseType.stream,
      ),
    );

    // 解析SSE流，逐chunk收集音频base64数据
    final audioBase64Parts = <String>[];
    final stream = response.data!.stream;
    String buffer = '';

    await for (final chunk in stream) {
      buffer += utf8.decode(chunk, allowMalformed: true);

      // 按换行分割SSE事件
      while (buffer.contains('\n')) {
        final lineEnd = buffer.indexOf('\n');
        final line = buffer.substring(0, lineEnd).trim();
        buffer = buffer.substring(lineEnd + 1);

        if (!line.startsWith('data: ')) continue;
        final data = line.substring(6).trim();
        if (data == '[DONE]') continue;

        try {
          final json = jsonDecode(data) as Map<String, dynamic>;
          final choices = json['choices'] as List<dynamic>?;
          if (choices == null || choices.isEmpty) continue;

          final delta = choices[0]['delta'] as Map<String, dynamic>?;
          if (delta == null) continue;

          // 提取音频数据: delta.audio.data (base64编码的PCM片段)
          final audio = delta['audio'];
          if (audio is Map<String, dynamic>) {
            final audioData = audio['data'] as String?;
            if (audioData != null && audioData.isNotEmpty) {
              audioBase64Parts.add(audioData);
            }
          }
        } catch (_) {
          // SSE行解析失败，跳过
        }
      }
    }

    if (audioBase64Parts.isEmpty) {
      throw Exception('Qwen-Omni合成未返回音频数据，请确认：1.API Key已开通${ApiConfig.aliOmniModel} 2.克隆音色与当前模型一致');
    }

    // 合并所有音频片段并保存为WAV文件
    _saveBase64AudioToFile(audioBase64Parts.join(), filePath);
    return filePath;
  }

  /// 保存base64音频到文件（支持PCM裸数据转WAV）
  void _saveBase64AudioToFile(String base64Data, String filePath) {
    String data = base64Data;
    if (base64Data.contains(',')) {
      data = base64Data.split(',').last;
    }
    final audioBytes = _safeBase64Decode(data);
    final file = File(filePath);

    // 如果文件路径以.wav结尾且数据是PCM（没有WAV头），添加WAV头
    if (filePath.endsWith('.wav') && !_hasWavHeader(audioBytes)) {
      final wavBytes = _pcmToWav(audioBytes, 24000);
      file.writeAsBytesSync(wavBytes);
    } else {
      file.writeAsBytesSync(audioBytes);
    }
  }

  /// 下载音频URL到文件
  Future<void> _downloadAudioToFile(String url, String filePath) async {
    final response = await _apiClient.get(
      url,
      options: Options(responseType: ResponseType.bytes),
    );
    final file = File(filePath);
    await file.writeAsBytes(response.data as List<int>);
  }

  /// 检查数据是否已有WAV头
  bool _hasWavHeader(List<int> data) {
    if (data.length < 12) return false;
    // RIFF header: "RIFF" + size + "WAVE"
    return data[0] == 0x52 && data[1] == 0x49 &&
           data[2] == 0x46 && data[3] == 0x46;
  }

  /// PCM裸数据转WAV文件（添加44字节头）
  List<int> _pcmToWav(List<int> pcmData, int sampleRate) {
    final channels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;

    final header = <int>[];
    // RIFF
    header.addAll([0x52, 0x49, 0x46, 0x46]);
    header.addAll(_intToBytes(fileSize, 4));
    header.addAll([0x57, 0x41, 0x56, 0x45]); // WAVE
    // fmt
    header.addAll([0x66, 0x6D, 0x74, 0x20]); // fmt
    header.addAll(_intToBytes(16, 4)); // chunk size
    header.addAll(_intToBytes(1, 2));  // PCM format
    header.addAll(_intToBytes(channels, 2));
    header.addAll(_intToBytes(sampleRate, 4));
    header.addAll(_intToBytes(byteRate, 4));
    header.addAll(_intToBytes(blockAlign, 2));
    header.addAll(_intToBytes(bitsPerSample, 2));
    // data
    header.addAll([0x64, 0x61, 0x74, 0x61]); // data
    header.addAll(_intToBytes(dataSize, 4));

    return [...header, ...pcmData];
  }

  /// 整数转小端字节
  List<int> _intToBytes(int value, int bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes; i++) {
      result.add((value >> (8 * i)) & 0xFF);
    }
    return result;
  }

  /// 安全Base64解码
  List<int> _safeBase64Decode(String source) {
    String padded = source.replaceAll(RegExp(r'\s'), '');
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    return base64Decode(padded);
  }

  // ==================== Edge-TTS（免费备选方案） ====================

  /// 使用Edge-TTS合成语音（WebSocket协议）
  /// 注意：在国内网络环境可能连接不稳定，仅作备选
  Future<String> synthesizeEdgeTts({
    required String text,
    String voiceId = 'zh-CN-XiaoxiaoNeural',
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
  }) async {
    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    final requestId = _generateRequestId();
    final ssml = _buildSsml(text, voiceId, rate, pitch, volume);

    final wsUrl = '${ApiConfig.edgeTtsBaseUrl}?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4'
        '&ConnectionId=$requestId';

    // 尝试WebSocket方式
    try {
      final channel = WebSocketChannel.connect(Uri.parse(wsUrl));
      final audioData = <int>[];
      final completer = Completer<void>();

      channel.stream.listen(
        (message) {
          if (message is String) {
            if (message.contains('Path:turn.end')) {
              completer.complete();
            }
          } else if (message is List<int>) {
            if (message.length > 2) {
              audioData.addAll(message.sublist(2));
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
      );

      // 发送配置
      final configMessage = jsonEncode({
        'context': {
          'synthesis': {
            'audio': {
              'metadataoptions': {
                'sentenceBoundaryEnabled': 'false',
                'wordBoundaryEnabled': 'true',
              },
              'outputFormat': 'audio-24khz-48kbitrate-mono-mp3',
            },
          },
        },
      });

      channel.sink.add('X-Timestamp:${DateTime.now().toUtc().toIso8601String()}\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n$configMessage');

      channel.sink.add('X-RequestId:$requestId\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${DateTime.now().toUtc().toIso8601String()}Z\r\n'
          'Path:ssml\r\n\r\n$ssml');

      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Edge-TTS合成超时'),
      );

      await channel.sink.close();

      if (audioData.isEmpty) {
        throw Exception('Edge-TTS未返回音频数据');
      }

      final file = File(filePath);
      await file.writeAsBytes(Uint8List.fromList(audioData));
      return filePath;
    } catch (e) {
      throw Exception('Edge-TTS不可用：${e.toString().replaceAll("Exception: ", "")}，请配置阿里百炼API Key使用CosyVoice');
    }
  }

  /// 生成请求ID
  String _generateRequestId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = StringBuffer();
    for (int i = 0; i < 16; i++) {
      random.write(now.toRadixString(16).substring(i % now.toRadixString(16).length));
    }
    return random.toString().padLeft(32, '0').substring(0, 32);
  }

  /// 构建SSML
  String _buildSsml(String text, String voiceId, String rate, String pitch, String volume) {
    final escapedText = text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');

    return '''
<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='zh-CN'>
  <voice name='$voiceId'>
    <prosody pitch='$pitch' rate='$rate' volume='$volume'>
      $escapedText
    </prosody>
  </voice>
</speak>''';
  }

  /// 试听音色
  Future<String> previewVoice({
    required String voiceId,
    required String provider,
    String sampleText = '你好，这是一段试听音频，欢迎使用口播智能体。',
  }) async {
    return synthesize(
      text: sampleText,
      voiceId: voiceId,
      provider: provider,
    );
  }
}


/// TtsService的Riverpod Provider
final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService(ref.read(apiClientProvider));
});
