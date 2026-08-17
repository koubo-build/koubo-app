import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import '../utils/retry_util.dart';

/// 飞影数字人服务 - AI数字人视频生成平台
///
/// 支持功能：
/// - 上传文件获取file_id
/// - 音频驱动数字人视频生成
/// - 任务状态轮询
/// - 视频下载到本地
///
/// API文档：https://api.lingverse.co/hifly.html
class FeiyingService {
  final Dio _dio;

  FeiyingService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 15),
          sendTimeout: const Duration(minutes: 5),
        ));

  // ==================== API Key ====================

  /// 获取飞影API Token
  Future<String> _getApiKey() async {
    var apiKey = await StorageUtil.getSecure(ApiConfig.feiyingApiKeyKey);
    apiKey = apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw Exception('请先配置飞影数字人API Token（设置页面）');
    }
    return apiKey;
  }

  // ==================== 文件上传 ====================

  /// 上传本地文件到飞影，返回 file_id
  /// 
  /// 流程：先获取预签名上传URL，再PUT上传文件
  /// [localFilePath] 本地文件路径
  /// [fileExtension] 文件后缀，如 mp3, mp4, wav
  Future<String> uploadFile(String localFilePath, String fileExtension) async {
    final apiKey = await _getApiKey();
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('文件不存在：$localFilePath');
    }

    // 1. 获取上传URL
    final uploadUrlResponse = await retryOnNetworkError(() => _dio.post(
      '${ApiConfig.feiyingBaseUrl}${ApiConfig.feiyingCreateUploadUrl}',
      data: jsonEncode({'file_extension': fileExtension}),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 30),
      ),
    ));

    final uploadData = uploadUrlResponse.data as Map<String, dynamic>;
    if (uploadData['code'] != null && uploadData['code'] != 0) {
      throw Exception('获取上传地址失败：${uploadData['message'] ?? '未知错误'}');
    }

    final uploadUrl = uploadData['upload_url'] as String;
    final fileId = uploadData['file_id'] as String;
    final contentType = uploadData['content_type'] as String? ?? 'application/octet-stream';

    // 2. PUT上传文件
    final fileBytes = await file.readAsBytes();
    await retryOnNetworkError(() => _dio.put(
      uploadUrl,
      data: fileBytes,
      options: Options(
        headers: {
          'Content-Type': contentType,
        },
        sendTimeout: const Duration(minutes: 5),
        receiveTimeout: const Duration(minutes: 5),
      ),
    ));

    return fileId;
  }

  // ==================== 视频生成 ====================

  /// 通过音频驱动生成数字人视频
  /// 
  /// [audioFilePath] 本地音频文件路径（mp3/m4a/wav）
  /// [avatarId] 数字人标识（从飞影平台获取）
  /// [title] 作品名称
  /// [onProgress] 进度回调
  /// 返回本地视频文件路径
  Future<String> generateVideoByAudio({
    required String audioFilePath,
    required String avatarId,
    String title = '数字人视频',
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await _getApiKey();

    // 1. 上传音频文件
    onProgress?.call('上传音频到飞影...', 10);
    final ext = audioFilePath.split('.').last.toLowerCase();
    final fileId = await uploadFile(audioFilePath, ext);

    // 2. 提交视频生成任务
    onProgress?.call('提交数字人视频任务...', 25);
    final requestBody = {
      'audio_file_id': fileId,
      'avatar': avatarId,
      'title': title,
      'aigc_flag': 2, // 关闭水印
    };

    final response = await retryOnNetworkError(() => _dio.post(
      '${ApiConfig.feiyingBaseUrl}${ApiConfig.feiyingVideoCreateByAudio}',
      data: jsonEncode(requestBody),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(minutes: 5),
      ),
    ));

    final data = response.data as Map<String, dynamic>;
    if (data['code'] != null && data['code'] != 0) {
      final msg = data['message'] ?? '提交任务失败';
      // 处理常见错误码
      if (data['code'] == 1002) throw Exception('飞影积分不足，请前往平台充值');
      if (data['code'] == 1001) throw Exception('飞影并发任务已达上限，请稍后重试');
      if (data['code'] == 1006) throw Exception('飞影会员等级不够，请升级后重试');
      throw Exception('飞影提交失败：$msg');
    }

    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw Exception('飞影未返回任务ID');
    }

    // 3. 轮询等待完成
    onProgress?.call('飞影数字人生成中（通常2-5分钟）...', 40);
    final videoUrl = await _pollVideoTask(taskId, apiKey, onProgress: onProgress);

    // 4. 下载视频到本地
    onProgress?.call('下载视频中...', 90);
    final localPath = await _downloadVideo(videoUrl);

    onProgress?.call('完成！', 100);
    return localPath;
  }

  /// 通过文本驱动生成数字人视频（使用飞影内置TTS）
  /// 
  /// [text] 文本内容（不超过10000字）
  /// [avatarId] 数字人标识
  /// [voiceId] 声音标识（从飞影平台获取）
  /// [title] 作品名称
  /// [onProgress] 进度回调
  Future<String> generateVideoByTts({
    required String text,
    required String avatarId,
    required String voiceId,
    String title = '数字人视频',
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await _getApiKey();

    onProgress?.call('提交飞影文本驱动视频任务...', 15);
    final requestBody = {
      'text': text,
      'voice': voiceId,
      'avatar': avatarId,
      'title': title,
      'st_show': 1, // 显示字幕
      'aigc_flag': 2, // 关闭水印
    };

    final response = await retryOnNetworkError(() => _dio.post(
      '${ApiConfig.feiyingBaseUrl}${ApiConfig.feiyingVideoCreateByTts}',
      data: jsonEncode(requestBody),
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        receiveTimeout: const Duration(minutes: 5),
      ),
    ));

    final data = response.data as Map<String, dynamic>;
    if (data['code'] != null && data['code'] != 0) {
      final msg = data['message'] ?? '提交任务失败';
      if (data['code'] == 1002) throw Exception('飞影积分不足，请前往平台充值');
      if (data['code'] == 1001) throw Exception('飞影并发任务已达上限，请稍后重试');
      throw Exception('飞影提交失败：$msg');
    }

    final taskId = data['task_id'] as String?;
    if (taskId == null || taskId.isEmpty) {
      throw Exception('飞影未返回任务ID');
    }

    onProgress?.call('飞影数字人生成中（通常2-5分钟）...', 40);
    final videoUrl = await _pollVideoTask(taskId, apiKey, onProgress: onProgress);

    onProgress?.call('下载视频中...', 90);
    final localPath = await _downloadVideo(videoUrl);

    onProgress?.call('完成！', 100);
    return localPath;
  }

  // ==================== 任务轮询 ====================

  /// 轮询视频任务状态直到完成
  Future<String> _pollVideoTask(
    String taskId,
    String apiKey, {
    void Function(String stage, int progress)? onProgress,
  }) async {
    const maxRetries = 60; // 最多等待10分钟
    const pollInterval = Duration(seconds: 10);

    for (int i = 0; i < maxRetries; i++) {
      try {
        final response = await retryOnNetworkError(() => _dio.get(
          '${ApiConfig.feiyingBaseUrl}${ApiConfig.feiyingVideoTaskQuery}',
          queryParameters: {'task_id': taskId},
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
              'Accept': 'application/json',
            },
            receiveTimeout: const Duration(seconds: 30),
          ),
        ));

        final data = response.data as Map<String, dynamic>;
        final status = data['status'] as int? ?? 0;
        final videoUrl = data['video_Url'] as String? ?? data['video_url'] as String?;

        if (status == 3) {
          // 完成
          if (videoUrl != null && videoUrl.isNotEmpty) {
            return videoUrl;
          }
          throw Exception('飞影视频生成完成但未返回URL');
        } else if (status == 4) {
          // 失败
          final msg = data['message'] ?? '生成失败';
          throw Exception('飞影视频生成失败：$msg');
        }

        // 更新进度（status: 1=等待 2=处理中）
        final progress = 40 + ((i + 1) * 45 / maxRetries).round();
        final stageMsg = status == 1 ? '排队中...' : '生成中（${i + 1}/$maxRetries）...';
        onProgress?.call(stageMsg, progress.clamp(40, 85));

        await Future.delayed(pollInterval);
      } on DioException catch (e) {
        if (i == maxRetries - 1) {
          throw Exception('查询飞影任务状态失败：${e.message}');
        }
        await Future.delayed(pollInterval);
      }
    }

    throw Exception('飞影视频生成超时（${maxRetries * 10}秒）');
  }

  // ==================== 辅助方法 ====================

  /// 下载视频到本地
  Future<String> _downloadVideo(String videoUrl) async {
    final videoDir = await StorageUtil.getDramaVideoDirectory();
    final fileName = 'feiying_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filePath = '$videoDir/$fileName';

    try {
      final response = await retryOnNetworkError(() => _dio.get(
        videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 15),
        ),
      ));

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      throw Exception('飞影视频下载失败：$e');
    }
  }

  /// 查询账户积分
  Future<int> getCreditBalance() async {
    final apiKey = await _getApiKey();

    final response = await retryOnNetworkError(() => _dio.get(
      '${ApiConfig.feiyingBaseUrl}${ApiConfig.feiyingAccountCredit}',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
        receiveTimeout: const Duration(seconds: 15),
      ),
    ));

    final data = response.data as Map<String, dynamic>;
    if (data['code'] != null && data['code'] != 0) {
      throw Exception('查询飞影积分失败：${data['message'] ?? '未知错误'}');
    }
    return data['left'] as int? ?? 0;
  }
}
