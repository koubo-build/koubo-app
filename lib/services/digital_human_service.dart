import 'dart:async';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// 数字人视频服务 - 对接飞影数字人API V2完整实现
class DigitalHumanService {
  final ApiClient _apiClient;

  DigitalHumanService(this._apiClient);

  // ==================== 飞影数字人API ====================

  /// 获取公版数字人模板列表
  Future<List<Map<String, dynamic>>> getAvatarTemplates() async {
    final agentToken = await StorageUtil.getSecure(ApiConfig.hiflyApiKeyKey);
    if (agentToken == null || agentToken.isEmpty) return [];

    try {
      final response = await _apiClient.get(
        '${ApiConfig.hiflyBaseUrl}${ApiConfig.hiflyAvatarListEndpoint}',
        queryParameters: {
          'hifly_agent_token': agentToken,
          'type': 'public',
        },
      );

      final data = response.data as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];

      return list.map((item) {
        final t = item as Map<String, dynamic>;
        return {
          'id': t['avatar_id'] as String? ?? t['id'] as String? ?? '',
          'name': t['name'] as String? ?? '',
          'thumbnail_url': t['thumbnail_url'] as String? ?? t['cover_url'] as String? ?? '',
          'video_url': t['video_url'] as String? ?? '',
          'gender': t['gender'] as String? ?? '',
        };
      }).toList();
    } catch (_) {
      // 未配置Token或接口异常时返回空列表
      return [];
    }
  }

  /// 获取平台音色列表
  Future<List<Map<String, String>>> getAvailableVoices() async {
    final agentToken = await StorageUtil.getSecure(ApiConfig.hiflyApiKeyKey);
    if (agentToken == null || agentToken.isEmpty) return [];

    try {
      final response = await _apiClient.get(
        '${ApiConfig.hiflyBaseUrl}${ApiConfig.hiflyVoiceListEndpoint}',
        queryParameters: {
          'hifly_agent_token': agentToken,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final voiceList = data['data'] as List<dynamic>? ?? [];

      return voiceList.map((v) {
        final voice = v as Map<String, dynamic>;
        return {
          'id': voice['speaker_id'] as String? ?? voice['id'] as String? ?? '',
          'name': voice['name'] as String? ?? '',
          'gender': voice['gender'] as String? ?? '',
          'language': voice['language'] as String? ?? 'zh',
          'style': voice['style'] as String? ?? '',
          'sample_url': voice['sample_url'] as String? ?? '',
        };
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 试听平台音色
  /// [sampleUrl] 音色样本URL
  Future<String> previewVoice(String sampleUrl) async {
    if (sampleUrl.isEmpty) throw Exception('音色样本URL为空');

    final audioDir = await StorageUtil.getAudioDirectory();
    final fileName = 'preview_${DateTime.now().millisecondsSinceEpoch}.mp3';
    final filePath = '$audioDir/$fileName';

    final response = await _apiClient.get(
      sampleUrl,
      options: Options(responseType: ResponseType.bytes),
    );

    final file = File(filePath);
    await file.writeAsBytes(response.data as List<int>);
    return filePath;
  }

  /// 创建数字人口播视频
  /// [text] 口播文案
  /// [videoUrl] 数字人视频模板URL（用户上传照片后获得或公版模板URL）
  /// [speakerId] 声音ID（飞影声音市场音色或克隆音色）
  /// [audioUrl] 已合成配音的URL（如果使用已合成配音）
  /// 返回任务jobId
  Future<String> createVideo({
    required String text,
    required String videoUrl,
    required String speakerId,
    String? audioUrl,
  }) async {
    final agentToken = await StorageUtil.getSecure(ApiConfig.hiflyApiKeyKey);
    if (agentToken == null || agentToken.isEmpty) {
      throw Exception('请先配置飞影数字人Agent Token');
    }

    final requestBody = <String, dynamic>{
      'text': text,
      'video_url': videoUrl,
      'hifly_agent_token': agentToken,
    };

    // 声音来源：优先使用已合成配音，否则使用平台音色
    if (audioUrl != null && audioUrl.isNotEmpty) {
      requestBody['audio_url'] = audioUrl;
    } else if (speakerId.isNotEmpty) {
      requestBody['speaker_id'] = speakerId;
    }

    final response = await _apiClient.post(
      '${ApiConfig.hiflyBaseUrl}${ApiConfig.hiflyCreateVideoEndpoint}',
      data: requestBody,
      options: Options(
        headers: {
          'Content-Type': 'application/json',
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final jobId = data['job_id'] as String? ?? data['data']?['job_id'] as String?;

    if (jobId == null || jobId.isEmpty) {
      throw Exception('创建视频任务失败');
    }

    return jobId;
  }

  /// 查询视频生成状态
  /// [jobId] 任务ID
  /// 返回状态信息：{status, video_url, progress, message}
  /// status: 1=等待 2=处理中 3=完成 4=失败
  Future<Map<String, dynamic>> inspectStatus(String jobId) async {
    final agentToken = await StorageUtil.getSecure(ApiConfig.hiflyApiKeyKey);
    if (agentToken == null || agentToken.isEmpty) {
      throw Exception('请先配置飞影数字人Agent Token');
    }

    final response = await _apiClient.get(
      '${ApiConfig.hiflyBaseUrl}${ApiConfig.hiflyInspectStatusEndpoint}',
      queryParameters: {
        'job_id': jobId,
        'hifly_agent_token': agentToken,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final statusData = data['data'] as Map<String, dynamic>? ?? data;

    return {
      'status': statusData['status'] as int? ?? 1,
      'video_url': statusData['video_url'] as String? ?? '',
      'progress': statusData['progress'] as int? ?? 0,
      'message': statusData['message'] as String? ?? '',
    };
  }

  /// 轮询等待视频生成完成
  /// [jobId] 任务ID
  /// [intervalSeconds] 轮询间隔（秒），默认5秒
  /// [timeoutSeconds] 超时时间（秒），默认300秒
  /// [onProgress] 进度回调
  /// 返回视频URL
  Future<String> waitForCompletion({
    required String jobId,
    int intervalSeconds = 5,
    int timeoutSeconds = 300,
    void Function(int status, int progress)? onProgress,
  }) async {
    final startTime = DateTime.now();

    while (true) {
      final statusInfo = await inspectStatus(jobId);
      final status = statusInfo['status'] as int;
      final progress = statusInfo['progress'] as int;

      // 回调进度
      onProgress?.call(status, progress);

      if (status == 3) {
        // 完成
        final videoUrl = statusInfo['video_url'] as String;
        if (videoUrl.isEmpty) {
          throw Exception('视频生成完成但未返回视频URL');
        }
        return videoUrl;
      } else if (status == 4) {
        // 失败
        throw Exception('视频生成失败：${statusInfo['message']}');
      }

      // 检查超时
      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if (elapsed >= timeoutSeconds) {
        throw Exception('视频生成超时（${timeoutSeconds}秒）');
      }

      // 等待下一次轮询
      await Future.delayed(Duration(seconds: intervalSeconds));
    }
  }

  /// 上传照片创建数字人形象
  /// [imagePath] 用户照片文件路径
  /// 返回数字人视频模板URL
  Future<String> uploadAvatarImage(String imagePath) async {
    final agentToken = await StorageUtil.getSecure(ApiConfig.hiflyApiKeyKey);
    if (agentToken == null || agentToken.isEmpty) {
      throw Exception('请先配置飞影数字人Agent Token');
    }

    // 验证图片文件
    final imageFile = File(imagePath);
    if (!await imageFile.exists()) {
      throw Exception('图片文件不存在');
    }

    // 验证文件大小（建议5MB以内）
    final fileSize = await imageFile.length();
    if (fileSize > 10 * 1024 * 1024) {
      throw Exception('图片文件过大，请选择5MB以内的照片');
    }

    // 上传图片到飞影
    try {
      final response = await _apiClient.upload(
        '${ApiConfig.hiflyBaseUrl}/avatar/upload',
        filePath: imagePath,
        fieldName: 'image',
        extraFields: {
          'hifly_agent_token': agentToken,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final avatarData = data['data'] as Map<String, dynamic>? ?? data;
      final videoUrl = avatarData['video_url'] as String?;

      if (videoUrl == null || videoUrl.isEmpty) {
        throw Exception('上传数字人形象失败，未返回视频模板URL');
      }

      return videoUrl;
    } catch (e) {
      if (e.toString().contains('401') || e.toString().contains('403')) {
        throw Exception('飞影Agent Token无效或已过期，请重新配置');
      }
      rethrow;
    }
  }

  /// 上传音频文件到飞影（用于"使用已合成配音"）
  /// [audioFilePath] 本地音频文件路径
  /// 返回音频URL
  Future<String> uploadAudio(String audioFilePath) async {
    final agentToken = await StorageUtil.getSecure(ApiConfig.hiflyApiKeyKey);
    if (agentToken == null || agentToken.isEmpty) {
      throw Exception('请先配置飞影数字人Agent Token');
    }

    final audioFile = File(audioFilePath);
    if (!await audioFile.exists()) {
      throw Exception('音频文件不存在');
    }

    final response = await _apiClient.upload(
      '${ApiConfig.hiflyBaseUrl}/audio/upload',
      filePath: audioFilePath,
      fieldName: 'audio',
      extraFields: {
        'hifly_agent_token': agentToken,
      },
    );

    final data = response.data as Map<String, dynamic>;
    final audioData = data['data'] as Map<String, dynamic>? ?? data;
    final audioUrl = audioData['audio_url'] as String? ?? audioData['url'] as String?;

    if (audioUrl == null || audioUrl.isEmpty) {
      throw Exception('上传音频失败');
    }

    return audioUrl;
  }

  /// 下载视频到本地
  /// [videoUrl] 视频URL
  /// 返回本地文件路径
  Future<String> downloadVideo(String videoUrl) async {
    final videoDir = await StorageUtil.getVideoDirectory();
    final fileName = 'digital_human_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filePath = '$videoDir/$fileName';

    try {
      final response = await _apiClient.get(
        videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      throw Exception('视频下载失败：$e');
    }
  }

  /// 完整流程：上传照片 + 创建视频 + 等待完成 + 下载
  /// [text] 口播文案
  /// [imagePath] 照片路径
  /// [speakerId] 声音ID
  /// [audioUrl] 已合成配音URL（可选）
  /// [onProgress] 进度回调
  Future<String> generateVideoFullPipeline({
    required String text,
    required String imagePath,
    required String speakerId,
    String? audioUrl,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 上传照片创建数字人形象
    onProgress?.call('上传照片中...', 10);
    final videoUrl = await uploadAvatarImage(imagePath);

    // 2. 如果有本地音频，先上传
    String? remoteAudioUrl = audioUrl;
    if (audioUrl == null && speakerId.isEmpty) {
      throw Exception('请选择声音或提供配音音频');
    }

    // 3. 创建口播视频
    onProgress?.call('创建视频中...', 30);
    final jobId = await createVideo(
      text: text,
      videoUrl: videoUrl,
      speakerId: speakerId,
      audioUrl: remoteAudioUrl,
    );

    // 4. 等待视频生成完成
    final resultUrl = await waitForCompletion(
      jobId: jobId,
      onProgress: (status, progress) {
        onProgress?.call('生成视频中...', 30 + (progress * 0.6).round());
      },
    );

    // 5. 下载视频到本地
    onProgress?.call('下载视频中...', 95);
    final localPath = await downloadVideo(resultUrl);

    onProgress?.call('完成！', 100);
    return localPath;
  }

  /// 获取视频文件信息
  /// [filePath] 本地视频文件路径
  /// 返回文件信息：{size, exists}
  Future<Map<String, dynamic>> getVideoInfo(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      return {'exists': false, 'size': 0};
    }

    final size = await file.length();
    return {
      'exists': true,
      'size': size,
      'sizeText': StorageUtil.formatFileSize(size),
    };
  }
}

/// DigitalHumanService的Riverpod Provider
final digitalHumanServiceProvider = Provider<DigitalHumanService>((ref) {
  return DigitalHumanService(ref.read(apiClientProvider));
});
