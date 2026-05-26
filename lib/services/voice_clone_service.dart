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
        'target_model': ApiConfig.aliQwenTtsVcModel,
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

  /// 使用克隆音色合成语音 - 通过 multimodal-generation 接口
  /// [voiceId] 克隆音色ID（注册后返回的voice_id或customization_id）
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

    // 构建情感指令
    String? instruction;
    if (emotion != null && emotion.isNotEmpty) {
      instruction = '请用$emotion的语气朗读';
    }

    final requestBody = <String, dynamic>{
      'model': ApiConfig.aliQwenTtsVcModel,
      'input': {
        'text': text,
        'voice_setting': {
          'voice_id': voiceId,
        },
        'audio_setting': {
          'sample_rate': 22050,
          'format': 'mp3',
        },
      },
    };

    // 添加指令（如果有）
    if (instruction != null) {
      (requestBody['input'] as Map<String, dynamic>)['instruction'] = instruction;
    }

    final response = await _apiClient.post(
      '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliMultimodalGenerationEndpoint}',
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
      return await _pollSynthesisTask(taskId, apiKey);
    }

    // 同步返回 - 可能直接包含音频数据
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

    // 尝试获取 audio_url
    final audioUrl = output['audio_url'] as String?;
    if (audioUrl != null && audioUrl.isNotEmpty) {
      return await _downloadAudio(audioUrl);
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
          // 优先获取 base64 音频
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

          // 备选下载 URL
          final audioUrl = output['audio_url'] as String?;
          if (audioUrl != null) {
            return await _downloadAudio(audioUrl);
          }

          throw Exception('合成完成但未返回音频数据');
        } else if (taskStatus == 'FAILED') {
          final message = output['message'] as String? ?? '未知错误';
          throw Exception('合成失败：$message');
        }
      } catch (e) {
        if (e.toString().contains('404') || e.toString().contains('Not Found')) {
          retryCount++;
          continue;
        }
        rethrow;
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
