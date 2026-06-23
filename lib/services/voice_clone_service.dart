import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// 声音克隆服务 - 封装Qwen声音复刻完整流程
/// 使用 qwen-voice-enrollment 模型，支持 base64 编码音频直接上传
class VoiceCloneService {
  final ApiClient _apiClient;

  VoiceCloneService(this._apiClient);

  /// 克隆音色完整流程
  /// [audioFilePath] 用户录制的参考音频文件路径（建议3-10秒）
  /// [refText] 参考音频对应的文字内容（可选，提高克隆质量）
  /// [voiceName] 音色名称
  /// 返回克隆后的voiceId
  Future<String> cloneVoice({
    required String audioFilePath,
    String? refText,
    required String voiceName,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key以使用声音克隆功能');
    }

    // 验证音频文件存在
    final audioFile = File(audioFilePath);
    if (!await audioFile.exists()) {
      throw Exception('音频文件不存在');
    }

    // 验证音频文件大小
    final fileSize = await audioFile.length();
    if (fileSize < 1024) {
      throw Exception('音频文件过小，请重新录制（建议3-10秒）');
    }
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('音频文件过大，请控制在10MB以内');
    }

    // 直接使用 base64 编码音频，注册克隆音色
    final voiceId = await _registerVoice(
      audioFilePath: audioFilePath,
      refText: refText ?? '',
      voiceName: voiceName,
      apiKey: apiKey,
    );

    return voiceId;
  }

  /// 注册克隆音色 - 使用 Qwen Voice Enrollment API
  /// 官方API: POST /api/v1/services/audio/tts/customization
  /// model: "qwen-voice-enrollment", input: {action: "create", target_model, preferred_name, audio: {data: "data:audio/mpeg;base64,..."}}
  Future<String> _registerVoice({
    required String audioFilePath,
    required String refText,
    required String voiceName,
    required String apiKey,
  }) async {
    // voiceName作为preferred_name，仅支持小写字母和数字
    final prefix = voiceName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // 读取音频文件并转换为 base64
    final audioFile = File(audioFilePath);
    final audioBytes = await audioFile.readAsBytes();
    final audioBase64 = base64Encode(audioBytes);
    final audioDataUri = 'data:audio/mpeg;base64,$audioBase64';

    final requestBody = <String, dynamic>{
      'model': ApiConfig.aliQwenVoiceEnrollmentModel,
      'input': {
        'action': 'create',
        'target_model': ApiConfig.aliOmniModel,
        'preferred_name': prefix.isNotEmpty ? prefix : 'myvoice',
        'audio': {
          'data': audioDataUri,
        },
      },
    };

    // 参考文本可提高克隆质量（Qwen用text字段）
    if (refText.isNotEmpty) {
      (requestBody['input'] as Map<String, dynamic>)['text'] = refText;
    }

    final response = await _apiClient.post(
      '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliVoiceRegisterEndpoint}',
      data: requestBody,
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final output = data['output'] as Map<String, dynamic>? ?? data;

    // 检查是否为异步任务
    final taskId = data['task_id'] as String? ?? output['task_id'] as String?;
    if (taskId != null) {
      // 轮询等待注册完成
      return await _pollRegisterTask(taskId, apiKey);
    }

    // Qwen voice-enrollment 返回 voice 字段（官方文档确认）
    final voice = output['voice'] as String?;
    if (voice != null && voice.isNotEmpty) {
      return voice;
    }

    // 兼容旧格式
    final voiceId = output['voice_id'] as String?;
    if (voiceId != null && voiceId.isNotEmpty) {
      return voiceId;
    }

    // CosyVoice格式
    final customizationId = output['customization_id'] as String?;
    if (customizationId != null && customizationId.isNotEmpty) {
      return customizationId;
    }

    // 如果返回了status=OK但没voice字段，可能是同步注册还在处理
    final status = output['status'] as String?;
    if (status == 'OK') {
      // 尝试从resource_link或其他字段获取
      final resourceLink = output['resource_link'] as String?;
      if (resourceLink != null && resourceLink.isNotEmpty) {
        // resource_link是音频文件URL，不是voice_id
        // 但说明注册成功了，需要查询音色列表获取voice_id
        final voices = await getClonedVoiceList();
        if (voices.isNotEmpty) {
          return voices.first['voice_id'] ?? voices.first['voice'] ?? '';
        }
      }
    }

    throw Exception('声音克隆注册失败：未返回音色ID\n返回数据：${data.toString().substring(0, (data.toString().length > 200 ? 200 : data.toString().length))}');
  }

  /// 轮询等待音色注册完成
  Future<String> _pollRegisterTask(String taskId, String apiKey) async {
    final pollUrl = '${ApiConfig.aliBailianBaseUrl}/tasks/$taskId';
    int retryCount = 0;
    const maxRetries = 30; // 最多等待2.5分钟

    while (retryCount < maxRetries) {
      await Future.delayed(const Duration(seconds: 5));

      try {
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
          // Qwen voice-enrollment 返回 voice 字段
          final voice = output['voice'] as String?;
          if (voice != null && voice.isNotEmpty) {
            return voice;
          }
          // 兼容 voice_id
          final voiceId = output['voice_id'] as String?;
          if (voiceId != null && voiceId.isNotEmpty) {
            return voiceId;
          }
          // 兼容 customization_id
          final customizationId = output['customization_id'] as String?;
          if (customizationId != null && customizationId.isNotEmpty) {
            return customizationId;
          }
          throw Exception('声音克隆注册完成但未返回音色ID\n返回数据：${output.toString().substring(0, (output.toString().length > 200 ? 200 : output.toString().length))}');
        } else if (taskStatus == 'FAILED') {
          final message = output['message'] as String? ?? '未知错误';
          throw Exception('声音克隆注册失败：$message');
        }
      } catch (e) {
        if (e.toString().contains('404') || e.toString().contains('Not Found')) {
          // 任务还未创建，继续等待
          retryCount++;
          continue;
        }
        rethrow;
      }

      retryCount++;
    }

    throw Exception('声音克隆注册超时，请稍后重试');
  }

  /// 使用克隆音色合成语音 - 通过OpenAI兼容端点流式请求
  /// ⚠️ Qwen-Omni模型输出音频必须使用流式模式(stream=true)
  /// [voiceId] 克隆音色ID（注册后返回的voice字段）
  /// [text] 要合成的文案
  /// [speed] 语速(0.5-2.0)
  /// [pitch] 音调(0.5-2.0)
  /// [emotion] 情感指令（如"用温柔的语气"）
  Future<String> synthesizeWithClonedVoice({
    required String voiceId,
    required String text,
    double speed = 1.0,
    double pitch = 1.0,
    String? emotion,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key');
    }

    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'clone_${DateTime.now().millisecondsSinceEpoch}.wav';
    final filePath = '$audioDir/$fileName';

    // 构建提示词
    String promptText = text;
    if (emotion != null && emotion.isNotEmpty) {
      promptText = '请用$emotion的语气朗读以下内容：\n$text';
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
      throw Exception('克隆音色合成未返回音频数据，请确认：1.API Key已开通${ApiConfig.aliOmniModel} 2.克隆音色与当前模型一致');
    }

    // 合并音频片段并保存
    String fullBase64 = audioBase64Parts.join();
    if (fullBase64.contains(',')) fullBase64 = fullBase64.split(',').last;
    final audioBytes = _decodeBase64(fullBase64);

    final file = File(filePath);
    if (!_hasWavHeader(audioBytes)) {
      final wavBytes = _addWavHeader(audioBytes, 24000);
      await file.writeAsBytes(wavBytes);
    } else {
      await file.writeAsBytes(audioBytes);
    }
    return filePath;
  }

  /// Base64解码
  List<int> _decodeBase64(String base64Str) {
    // 处理 data URI 格式
    String data = base64Str;
    if (base64Str.contains(',')) {
      data = base64Str.split(',').last;
    }
    return _base64Decoder.convert(data);
  }

  /// 安全Base64解码
  static List<int> _base64Decode(String source) {
    // 补齐padding
    String padded = source;
    while (padded.length % 4 != 0) {
      padded += '=';
    }
    return _base64Decoder.convert(padded);
  }

  /// 检查数据是否已有WAV头
  bool _hasWavHeader(List<int> data) {
    if (data.length < 12) return false;
    return data[0] == 0x52 && data[1] == 0x49 &&
           data[2] == 0x46 && data[3] == 0x46;
  }

  /// PCM裸数据添加WAV头
  List<int> _addWavHeader(List<int> pcmData, int sampleRate) {
    final channels = 1;
    final bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataSize = pcmData.length;
    final fileSize = dataSize + 36;

    final header = <int>[];
    header.addAll([0x52, 0x49, 0x46, 0x46]); // RIFF
    header.addAll(_intToBytes(fileSize, 4));
    header.addAll([0x57, 0x41, 0x56, 0x45]); // WAVE
    header.addAll([0x66, 0x6D, 0x74, 0x20]); // fmt
    header.addAll(_intToBytes(16, 4));
    header.addAll(_intToBytes(1, 2)); // PCM
    header.addAll(_intToBytes(channels, 2));
    header.addAll(_intToBytes(sampleRate, 4));
    header.addAll(_intToBytes(byteRate, 4));
    header.addAll(_intToBytes(blockAlign, 2));
    header.addAll(_intToBytes(bitsPerSample, 2));
    header.addAll([0x64, 0x61, 0x74, 0x61]); // data
    header.addAll(_intToBytes(dataSize, 4));

    return [...header, ...pcmData];
  }

  List<int> _intToBytes(int value, int bytes) {
    final result = <int>[];
    for (int i = 0; i < bytes; i++) {
      result.add((value >> (8 * i)) & 0xFF);
    }
    return result;
  }

  static final _base64Decoder = _SimpleBase64Decoder();

  /// 查询已注册的克隆音色列表
  /// 官方API: POST /services/audio/tts/customization
  /// Qwen: model=qwen-voice-enrollment, action=list
  Future<List<Map<String, String>>> getClonedVoiceList() async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return [];

    try {
      final response = await _apiClient.post(
        '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliVoiceRegisterEndpoint}',
        data: {
          'model': ApiConfig.aliQwenVoiceEnrollmentModel,
          'input': {
            'action': 'list',
            'page_size': 50,
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>? ?? {};
      final voices = output['voice_list'] as List<dynamic>? ?? [];
      return voices.map((v) {
        final voice = v as Map<String, dynamic>;
        // Qwen返回voice字段，CosyVoice返回voice_id字段
        final voiceId = voice['voice'] as String? ?? voice['voice_id'] as String? ?? '';
        return {
          'voice_id': voiceId,
          'voice': voiceId,
          'target_model': voice['target_model'] as String? ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 删除克隆音色
  /// Qwen: model=qwen-voice-enrollment, action=delete, voice=音色名称
  Future<bool> deleteClonedVoice(String voiceId) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return false;

    try {
      await _apiClient.post(
        '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliVoiceRegisterEndpoint}',
        data: {
          'model': ApiConfig.aliQwenVoiceEnrollmentModel,
          'input': {
            'action': 'delete',
            'voice': voiceId,
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 试听克隆音色
  /// [voiceId] 音色ID
  /// [sampleText] 试听文本
  Future<String> previewClonedVoice({
    required String voiceId,
    String sampleText = '你好，这是我的声音样本，欢迎使用口播智能体。',
  }) async {
    return synthesizeWithClonedVoice(
      voiceId: voiceId,
      text: sampleText,
    );
  }
}

/// 简单Base64解码器
class _SimpleBase64Decoder {
  static const String _base64Chars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

  List<int> convert(String input) {
    input = input.replaceAll(RegExp(r'\s'), '');
    if (input.isEmpty) return [];

    final outputLength = (input.length * 3) ~/ 4 -
        (input.endsWith('==') ? 2 : input.endsWith('=') ? 1 : 0);
    final output = List<int>.filled(outputLength, 0);

    int buffer = 0;
    int bits = 0;
    int outputIndex = 0;

    for (int i = 0; i < input.length; i++) {
      final char = input[i];
      if (char == '=') break;
      final value = _base64Chars.indexOf(char);
      if (value < 0) continue;
      buffer = (buffer << 6) | value;
      bits += 6;
      if (bits >= 8) {
        bits -= 8;
        if (outputIndex < outputLength) {
          output[outputIndex++] = (buffer >> bits) & 0xFF;
        }
      }
    }

    return output;
  }
}

/// VoiceCloneService的Riverpod Provider
final voiceCloneServiceProvider = Provider<VoiceCloneService>((ref) {
  return VoiceCloneService(ref.read(apiClientProvider));
});
