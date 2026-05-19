import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// TTS语音合成服务 - 支持Edge-TTS(免费基础) + CosyVoice(声音克隆)
class TtsService {
  final ApiClient _apiClient;

  TtsService(this._apiClient);

  // ==================== Edge-TTS 基础配音 ====================

  /// Edge-TTS 可用中文音色列表
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

  /// 使用Edge-TTS合成语音（WebSocket协议完整实现）
  /// [text] 要合成的文案
  /// [voiceId] 音色ID
  /// [rate] 语速调整，如"+20%"或"-10%"
  /// [pitch] 音调调整，如"+10Hz"或"-5Hz"
  /// [volume] 音量调整，如"+50%"或"-20%"
  /// 返回音频文件路径
  Future<String> synthesizeEdgeTts({
    required String text,
    String voiceId = 'zh-CN-XiaoxiaoNeural',
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
  }) async {
    // Edge-TTS通过WebSocket协议实现
    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    // 生成请求ID
    final requestId = _generateRequestId();

    // 构建SSML
    final ssml = _buildSsml(text, voiceId, rate, pitch, volume);

    // 连接WebSocket
    final wsUrl = '${ApiConfig.edgeTtsBaseUrl}?TrustedClientToken=6A5AA1D4EAFF4E9FB37E23D68491D6F4'
        '&ConnectionId=$requestId';

    final channel = WebSocketChannel.connect(Uri.parse(wsUrl));

    try {
      // 收集音频数据
      final audioData = <int>[];
      final completer = Completer<void>();

      // 监听WebSocket消息
      channel.stream.listen(
        (message) {
          if (message is String) {
            // 文本消息 - 检查是否包含音频数据路径标记
            if (message.contains('Path:turn.end')) {
              completer.complete();
            }
          } else if (message is List<int>) {
            // 二进制消息 - 音频数据
            // Edge-TTS的音频数据前2字节为头部标记，需要跳过
            if (message.length > 2) {
              audioData.addAll(message.sublist(2));
            }
          }
        },
        onError: (error) {
          if (!completer.isCompleted) {
            completer.completeError(error);
          }
        },
        onDone: () {
          if (!completer.isCompleted) {
            completer.complete();
          }
        },
      );

      // 发送配置请求
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

      // 发送SSML请求
      channel.sink.add('X-RequestId:$requestId\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${DateTime.now().toUtc().toIso8601String()}Z\r\n'
          'Path:ssml\r\n\r\n$ssml');

      // 等待完成
      await completer.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () => throw Exception('Edge-TTS合成超时'),
      );

      // 关闭WebSocket
      await channel.sink.close();

      // 保存音频文件
      if (audioData.isEmpty) {
        throw Exception('Edge-TTS未返回音频数据');
      }

      final file = File(filePath);
      await file.writeAsBytes(Uint8List.fromList(audioData));

      return filePath;
    } catch (e) {
      await channel.sink.close();
      // 如果WebSocket方式失败，回退到HTTP代理方式
      return await _synthesizeEdgeTtsFallback(
        text: text,
        voiceId: voiceId,
        rate: rate,
        pitch: pitch,
        volume: volume,
      );
    }
  }

  /// Edge-TTS HTTP回退方案（通过第三方代理服务）
  Future<String> _synthesizeEdgeTtsFallback({
    required String text,
    required String voiceId,
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
  }) async {
    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'tts_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    try {
      // 使用本地Edge-TTS HTTP接口或开源代理
      // 注：实际部署时可替换为自建的Edge-TTS HTTP服务
      final response = await _apiClient.post(
        'https://tts.kukuters.com/api/tts',
        data: {
          'text': text,
          'voice': voiceId,
          'rate': rate,
          'pitch': pitch,
          'volume': volume,
        },
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      // 最终兜底：使用本地模拟生成
      // 在实际使用中，用户需要配置可用的TTS服务
      final file = File(filePath);
      // 写入空音频文件占位（实际应由Edge-TTS服务填充）
      await file.writeAsBytes(Uint8List(0));
      throw Exception('语音合成服务暂时不可用，请检查网络或稍后重试');
    }
  }

  /// 生成请求ID（UUID格式，不带连字符）
  String _generateRequestId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = StringBuffer();
    for (int i = 0; i < 16; i++) {
      random.write(now.toRadixString(16).substring(i % now.toRadixString(16).length));
    }
    return random.toString().padLeft(32, '0').substring(0, 32);
  }

  /// 构建SSML（Speech Synthesis Markup Language）
  String _buildSsml(String text, String voiceId, String rate, String pitch, String volume) {
    // 转义XML特殊字符
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

  // ==================== CosyVoice 声音克隆 ====================

  /// 使用CosyVoice克隆音色合成语音
  /// [text] 要合成的文案
  /// [voiceId] 克隆音色ID
  /// [speed] 语速(0.5-2.0)
  /// [pitch] 音调(0.5-2.0)
  /// [emotion] 情感（如"开心"/"悲伤"/"激动"等）
  /// 返回音频文件路径
  Future<String> synthesizeCosyVoice({
    required String text,
    required String voiceId,
    double speed = 1.0,
    double pitch = 1.0,
    String? emotion,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key');
    }

    final requestBody = <String, dynamic>{
      'model': 'cosyvoice-v2',
      'voice': voiceId,
      'text': text,
      'parameters': {
        'speed': speed,
        'pitch': pitch,
      },
    };

    // 情感控制（通过自然语言指令）
    if (emotion != null && emotion.isNotEmpty) {
      requestBody['instructions'] = '请用$emotion的语气朗读';
    }

    // 阿里百炼CosyVoice接口，异步提交任务
    final response = await _apiClient.post(
      '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliCosyvoiceEndpoint}',
      data: requestBody,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'X-DashScope-Async': 'enable',
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;

    // 检查是否为异步任务
    final output = data['output'] as Map<String, dynamic>? ?? data;
    final taskId = output['task_id'] as String?;

    if (taskId != null) {
      // 异步模式：轮询任务状态
      return await _pollCosyVoiceTask(taskId, apiKey);
    }

    // 同步模式：直接获取音频
    final audioData = data['audio'] as String?;
    if (audioData != null) {
      return await _saveBase64Audio(audioData);
    }

    // 如果response是bytes类型
    if (response.data is List<int>) {
      final audioDir = await StorageUtil.getAudioDirectory();
      final fileName = 'cosy_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final filePath = '$audioDir/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    }

    throw Exception('CosyVoice合成返回数据格式异常');
  }

  /// 轮询CosyVoice异步任务
  Future<String> _pollCosyVoiceTask(String taskId, String apiKey) async {
    final pollUrl = '${ApiConfig.aliBailianBaseUrl}/tasks/$taskId';
    int retryCount = 0;
    const maxRetries = 60; // 最多等待5分钟（5秒*60次）

    while (retryCount < maxRetries) {
      await Future.delayed(const Duration(seconds: 5));

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
        final audioUrl = output['audio_url'] as String? ?? output['results']?['audio_url'] as String?;
        if (audioUrl != null) {
          return await _downloadAudioFromUrl(audioUrl);
        }
        final audioBase64 = output['audio'] as String?;
        if (audioBase64 != null) {
          return await _saveBase64Audio(audioBase64);
        }
        throw Exception('CosyVoice任务完成但未返回音频数据');
      } else if (taskStatus == 'FAILED') {
        final message = output['message'] as String? ?? '未知错误';
        throw Exception('CosyVoice合成失败：$message');
      }

      retryCount++;
    }

    throw Exception('CosyVoice合成超时');
  }

  /// 从URL下载音频文件
  Future<String> _downloadAudioFromUrl(String url) async {
    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'cosy_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    final response = await _apiClient.get(
      url,
      options: Options(responseType: ResponseType.bytes),
    );

    final file = File(filePath);
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  /// 保存Base64编码的音频数据
  Future<String> _saveBase64Audio(String base64Audio) async {
    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'cosy_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    final audioBytes = base64Decode(base64Audio);
    final file = File(filePath);
    await file.writeAsBytes(audioBytes);
    return filePath;
  }

  /// 获取CosyVoice已注册音色列表
  Future<List<Map<String, String>>> getCosyVoiceList() async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return [];

    try {
      final response = await _apiClient.get(
        '${ApiConfig.aliBailianBaseUrl}/services/aigc/text2audio/voice-list',
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final voices = data['voices'] as List<dynamic>? ?? [];
      return voices.map((v) {
        final voice = v as Map<String, dynamic>;
        return {
          'voice_id': voice['voice_id'] as String? ?? '',
          'voice_name': voice['voice_name'] as String? ?? '',
          'gender': voice['gender'] as String? ?? '',
          'language': voice['language'] as String? ?? 'zh',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 试听音色（获取预览音频）
  /// [voiceId] 音色ID
  /// [provider] 提供商
  /// [sampleText] 试听文本
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

  // ==================== 统一合成接口 ====================

  /// 统一语音合成接口 - 根据provider自动选择引擎
  /// [text] 要合成的文案
  /// [voiceId] 音色ID
  /// [provider] 提供商：edge_tts / cosyvoice
  /// [speed] 语速
  /// [pitch] 音调
  /// [volume] 音量（0.0-2.0，仅Edge-TTS）
  /// [emotion] 情感（仅CosyVoice支持）
  Future<String> synthesize({
    required String text,
    required String voiceId,
    String provider = 'edge_tts',
    double speed = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
    String? emotion,
  }) async {
    switch (provider) {
      case 'edge_tts':
        // 将speed转换为Edge-TTS格式
        final rateStr = speed == 1.0
            ? '+0%'
            : '${speed > 1.0 ? '+' : '-'}${((speed - 1.0) * 100).abs().round()}%';
        final pitchStr = pitch == 1.0
            ? '+0Hz'
            : '${pitch > 1.0 ? '+' : '-'}${((pitch - 1.0) * 10).abs().round()}Hz';
        final volumeStr = volume == 1.0
            ? '+0%'
            : '${volume > 1.0 ? '+' : '-'}${((volume - 1.0) * 100).abs().round()}%';
        return synthesizeEdgeTts(
          text: text,
          voiceId: voiceId,
          rate: rateStr,
          pitch: pitchStr,
          volume: volumeStr,
        );
      case 'cosyvoice':
        return synthesizeCosyVoice(
          text: text,
          voiceId: voiceId,
          speed: speed,
          pitch: pitch,
          emotion: emotion,
        );
      default:
        throw Exception('不支持的语音合成引擎：$provider');
    }
  }
}

/// TtsService的Riverpod Provider
final ttsServiceProvider = Provider<TtsService>((ref) {
  return TtsService(ref.read(apiClientProvider));
});
