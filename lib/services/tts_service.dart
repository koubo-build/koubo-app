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

  /// Edge-TTS音色ID → CosyVoice音色名 的映射
  /// 用户选的是Edge-TTS音色名，实际合成时自动转为CosyVoice对应音色
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

  // ==================== 统一合成接口 ====================

  /// 统一语音合成接口
  /// 策略：阿里百炼CosyVoice优先（你有Key），Edge-TTS为备选
  Future<String> synthesize({
    required String text,
    required String voiceId,
    String provider = 'cosyvoice',
    double speed = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    String? emotion,
  }) async {
    // 先尝试阿里百炼CosyVoice（用户有Key且已验证可用）
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
      // CosyVoice失败，尝试Edge-TTS
      try {
        return await synthesizeEdgeTts(
          text: text,
          voiceId: voiceId,
          rate: speed == 1.0 ? '+0%' : '${speed > 1.0 ? '+' : '-'}${((speed - 1.0) * 100).abs().round()}%',
          pitch: pitch == 1.0 ? '+0Hz' : '${pitch > 1.0 ? '+' : '-'}${((pitch - 1.0) * 10).abs().round()}Hz',
          volume: volume == 1.0 ? '+0%' : '${volume > 1.0 ? '+' : '-'}${((volume - 1.0) * 100).abs().round()}%',
        );
      } catch (e2) {
        throw Exception('语音合成失败：\nCosyVoice: ${e.toString().replaceAll("Exception: ", "")}\nEdge-TTS: ${e2.toString().replaceAll("Exception: ", "")}');
      }
    }
  }

  /// 将Edge-TTS音色ID映射为CosyVoice音色名
  String _mapToCosyVoiceId(String voiceId) {
    // 如果已经是CosyVoice格式的音色ID，直接返回
    if (!voiceId.contains('-')) return voiceId;
    return _edgeToCosyVoiceMap[voiceId] ?? 'longanhuan';
  }

  // ==================== 阿里百炼 CosyVoice（主力方案） ====================

  /// CosyVoice模型优先级列表（自动降级）
  static const List<String> _cosyVoiceModels = [
    'cosyvoice-v2',
    'cosyvoice-v3-flash',
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
    final input = <String, dynamic>{
      'text': text,
      'voice': voiceId,
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

    // 方式1：响应直接包含audio_url
    final output = data['output'] as Map<String, dynamic>?;
    if (output != null) {
      // 非流式模式：返回audio_url
      final audioUrl = output['audio_url'] as String?;
      if (audioUrl != null && audioUrl.isNotEmpty) {
        return await _downloadAudioFromUrl(audioUrl, filePath);
      }

      // 可能直接返回base64音频
      final audioBase64 = output['audio'] as String?;
      if (audioBase64 != null && audioBase64.isNotEmpty) {
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
        final audioUrl = output['audio_url'] as String?;
        if (audioUrl != null) {
          return await _downloadAudioFromUrl(audioUrl, filePath);
        }
        final audioBase64 = output['audio'] as String?;
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
