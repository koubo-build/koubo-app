import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// 声音克隆服务 - 封装CosyVoice声音克隆完整流程
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

    // 1. 上传音频到阿里OSS获取公网URL
    final audioUrl = await _uploadAudio(audioFilePath, apiKey);

    // 2. 注册克隆音色
    final voiceId = await _registerVoice(
      audioUrl: audioUrl,
      refText: refText ?? '',
      voiceName: voiceName,
      apiKey: apiKey,
    );

    return voiceId;
  }

  /// 上传音频文件到阿里OSS
  Future<String> _uploadAudio(String filePath, String apiKey) async {
    try {
      final response = await _apiClient.upload(
        '${ApiConfig.aliBailianBaseUrl}/uploads',
        filePath: filePath,
        fieldName: 'file',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final url = data['url'] as String? ?? '';
      if (url.isEmpty) {
        throw Exception('音频上传失败，未返回文件URL');
      }
      return url;
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('403')) {
        throw Exception('阿里百炼API Key无效或已过期，请重新配置');
      }
      rethrow;
    }
  }

  /// 注册克隆音色
  /// 官方API: POST /api/v1/services/audio/tts/customization
  /// model: "voice-enrollment", input: {action: "create_voice", target_model, prefix, url}
  Future<String> _registerVoice({
    required String audioUrl,
    required String refText,
    required String voiceName,
    required String apiKey,
  }) async {
    // voiceName作为prefix（音色名称前缀），仅支持小写字母和数字
    final prefix = voiceName.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    final requestBody = <String, dynamic>{
      'model': 'voice-enrollment',
      'input': {
        'action': 'create_voice',
        'target_model': 'cosyvoice-v2',
        'prefix': prefix.isNotEmpty ? prefix : 'myvoice',
        'url': audioUrl,
      },
    };

    // 参考文本可提高克隆质量
    if (refText.isNotEmpty) {
      (requestBody['input'] as Map<String, dynamic>)['ref_text'] = refText;
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
    final taskId = output['task_id'] as String?;
    if (taskId != null) {
      // 轮询等待注册完成
      return await _pollRegisterTask(taskId, apiKey);
    }

    // 同步返回
    final voiceId = output['voice_id'] as String?;
    if (voiceId == null || voiceId.isEmpty) {
      throw Exception('声音克隆注册失败');
    }
    return voiceId;
  }

  /// 轮询等待音色注册完成
  Future<String> _pollRegisterTask(String taskId, String apiKey) async {
    final pollUrl = '${ApiConfig.aliBailianBaseUrl}/tasks/$taskId';
    int retryCount = 0;
    const maxRetries = 30; // 最多等待2.5分钟

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
        final voiceId = output['voice_id'] as String?;
        if (voiceId != null && voiceId.isNotEmpty) {
          return voiceId;
        }
        throw Exception('声音克隆注册完成但未返回音色ID');
      } else if (taskStatus == 'FAILED') {
        final message = output['message'] as String? ?? '未知错误';
        throw Exception('声音克隆注册失败：$message');
      }

      retryCount++;
    }

    throw Exception('声音克隆注册超时，请稍后重试');
  }

  /// 使用克隆音色合成语音
  /// [voiceId] 克隆音色ID
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

    final requestBody = <String, dynamic>{
      'model': 'cosyvoice-v2',
      'voice': voiceId,
      'text': text,
      'parameters': {
        'speed': speed,
        'pitch': pitch,
      },
    };

    // 情感控制指令
    if (emotion != null && emotion.isNotEmpty) {
      requestBody['instructions'] = '请用$emotion的语气朗读';
    }

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
    final output = data['output'] as Map<String, dynamic>? ?? data;
    final taskId = output['task_id'] as String?;

    if (taskId != null) {
      return await _pollSynthesisTask(taskId, apiKey);
    }

    // 同步返回
    final audioBase64 = output['audio'] as String?;
    if (audioBase64 != null) {
      final audioDir = await StorageUtil.getAudioDirectory();
      final fileName = 'clone_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final filePath = '$audioDir/$fileName';
      final audioBytes = _decodeBase64(audioBase64);
      final file = File(filePath);
      await file.writeAsBytes(audioBytes);
      return filePath;
    }

    // 字节数据
    if (response.data is List<int>) {
      final audioDir = await StorageUtil.getAudioDirectory();
      final fileName = 'clone_${DateTime.now().millisecondsSinceEpoch}.mp3';
      final filePath = '$audioDir/$fileName';
      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    }

    throw Exception('克隆音色合成返回数据格式异常');
  }

  /// 轮询合成任务
  Future<String> _pollSynthesisTask(String taskId, String apiKey) async {
    final pollUrl = '${ApiConfig.aliBailianBaseUrl}/tasks/$taskId';
    int retryCount = 0;
    const maxRetries = 60;

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
        final audioUrl = output['audio_url'] as String?;
        if (audioUrl != null) {
          return await _downloadAudio(audioUrl);
        }
        final audioBase64 = output['audio'] as String?;
        if (audioBase64 != null) {
          final audioDir = await StorageUtil.getAudioDirectory();
          final fileName = 'clone_${DateTime.now().millisecondsSinceEpoch}.mp3';
          final filePath = '$audioDir/$fileName';
          final audioBytes = _decodeBase64(audioBase64);
          final file = File(filePath);
          await file.writeAsBytes(audioBytes);
          return filePath;
        }
        throw Exception('合成完成但未返回音频数据');
      } else if (taskStatus == 'FAILED') {
        throw Exception('合成失败：${output['message'] ?? '未知错误'}');
      }

      retryCount++;
    }

    throw Exception('合成超时');
  }

  /// 下载音频文件
  Future<String> _downloadAudio(String url) async {
    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'clone_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    final response = await _apiClient.get(
      url,
      options: Options(responseType: ResponseType.bytes),
    );

    final file = File(filePath);
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  /// Base64解码
  List<int> _decodeBase64(String base64Str) {
    return _base64Decode(base64Str);
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

  static final _base64Decoder = _SimpleBase64Decoder();

  /// 查询已注册的克隆音色列表
  Future<List<Map<String, String>>> getClonedVoiceList() async {
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
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 删除克隆音色
  Future<bool> deleteClonedVoice(String voiceId) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return false;

    try {
      await _apiClient.delete(
        '${ApiConfig.aliBailianBaseUrl}/services/aigc/text2audio/voice-delete',
        data: {'voice_id': voiceId},
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
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
