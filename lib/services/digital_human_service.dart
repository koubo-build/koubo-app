import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// 数字人视频服务 - 支持多种视频生成模型
/// 
/// 支持的模型：
/// - wan2.2-s2v: 万相数字人（照片+音频→口型视频，百炼直连）
/// - happyhorse-1.0-i2v: HappyHorse图生视频（百炼直连）
/// - ai32-seedance: 豆包Seedance（32AI中转站）
/// 
/// 万相流程：
/// 1. 上传图片到百炼OSS获取oss:// URL
/// 2. 上传音频到百炼OSS获取oss:// URL
/// 3. 调用wan2.2-s2v-detect检测图片是否合规
/// 4. 提交wan2.2-s2v视频生成任务（Bearer token鉴权）
/// 5. 轮询任务状态直到完成
/// 6. 下载视频到本地
class DigitalHumanService {
  final ApiClient _apiClient;
  final Dio _dio;

  DigitalHumanService(this._apiClient)
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 30),
          receiveTimeout: const Duration(minutes: 15),
          sendTimeout: const Duration(minutes: 5),
        ));

  // ==================== 公共方法 ====================

  /// 下载视频到本地
  Future<String> downloadVideo(String videoUrl) async {
    final videoDir = await StorageUtil.getVideoDirectory();
    final fileName = 'wanx_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filePath = '$videoDir/$fileName';

    try {
      final response = await _dio.get(
        videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 15),
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      throw Exception('视频下载失败：$e');
    }
  }

  /// 获取视频文件信息
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

  // ==================== 百炼API Key ====================

  /// 获取百炼API Key
  Future<String> _getApiKey() async {
    var apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    apiKey = apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key（设置页面）');
    }
    return apiKey;
  }

  // ==================== 百炼OSS上传 ====================

  /// 获取OSS上传凭证
  Future<Map<String, dynamic>> _getOssUploadPolicy(String modelName) async {
    final apiKey = await _getApiKey();

    final response = await _dio.get(
      '${ApiConfig.bailianUploadUrl}?action=getPolicy&model=$modelName',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final data = response.data as Map<String, dynamic>;
    final result = data['data'] as Map<String, dynamic>? ?? data;

    return {
      'upload_host': result['upload_host'] as String,
      'upload_dir': result['upload_dir'] as String,
      'oss_access_key_id': result['oss_access_key_id'] as String,
      'signature': result['signature'] as String,
      'policy': result['policy'] as String,
      'x_oss_object_acl': result['x_oss_object_acl'] as String? ?? 'private',
      'x_oss_forbid_overwrite': result['x_oss_forbid_overwrite']?.toString() ?? 'true',
    };
  }

  /// 上传文件到百炼临时存储
  /// 
  /// 返回 oss:// 格式的URL（百炼API内部可访问，有效期48小时）
  /// 调用API时需在请求头添加 X-DashScope-OssResourceResolve: enable
  Future<String> uploadFileToBailian(String localFilePath, String modelName) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('文件不存在：$localFilePath');
    }

    final fileName = localFilePath.split('/').last;
    
    final policy = await _getOssUploadPolicy(modelName);

    final ossKey = '${policy['upload_dir']}/$fileName';

    final formData = FormData.fromMap({
      'OSSAccessKeyId': policy['oss_access_key_id'],
      'Signature': policy['signature'],
      'policy': policy['policy'],
      'x-oss-object-acl': policy['x_oss_object_acl'],
      'x-oss-forbid-overwrite': policy['x_oss_forbid_overwrite'],
      'key': ossKey,
      'success_action_status': '200',
      'file': await MultipartFile.fromFile(localFilePath, filename: fileName),
    });

    await _dio.post(
      policy['upload_host'] as String,
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        sendTimeout: const Duration(minutes: 5),
      ),
    );

    // 返回 oss:// 格式的URL，百炼API内部可解析访问
    return 'oss://$ossKey';
  }

  // ==================== 万相wan2.2-s2v 图像检测 ====================

  /// 检测图片是否满足wan2.2-s2v的输入规范
  /// 
  /// 返回 true 表示图片合规，false 表示不合规
  /// 检测项：清晰度、单人、正面等
  Future<bool> detectImage(String imageUrl) async {
    final apiKey = await _getApiKey();

    final requestBody = {
      'model': ApiConfig.wanxDetectModel,
      'input': {
        'image_url': imageUrl,
      },
    };

    try {
      final response = await _dio.post(
        ApiConfig.wanxDetectUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-DashScope-OssResourceResolve': 'enable',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      final checkPass = output?['check_pass'] as bool? ?? false;

      if (!checkPass) {
        final msg = output?['message'] as String? ?? '图片不满足要求（需清晰、单人、正面）';
        throw Exception('图片检测未通过：$msg');
      }

      return true;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? '';
      }
      throw Exception('图片检测失败($statusCode)：$detail');
    }
  }

  // ==================== 万相wan2.2-s2v 视频生成 ====================

  /// 提交万相数字人视频生成任务
  /// 
  /// [imageUrl] 人像图片URL（oss:// 格式或公网URL）
  /// [audioUrl] 音频URL（oss:// 格式或公网URL）
  /// [resolution] 分辨率：480P 或 720P
  /// 返回task_id
  Future<String> submitVideoTask({
    required String imageUrl,
    required String audioUrl,
    String resolution = '720P',
  }) async {
    final apiKey = await _getApiKey();

    final requestBody = {
      'model': ApiConfig.wanxS2vModel,
      'input': {
        'image_url': imageUrl,
        'audio_url': audioUrl,
      },
      'parameters': {
        'resolution': resolution,
      },
    };

    try {
      final response = await _dio.post(
        ApiConfig.wanxVideoSubmitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-DashScope-Async': 'enable',
            'X-DashScope-OssResourceResolve': 'enable',
          },
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final taskId = data['output']?['task_id'] as String?;

      if (taskId == null || taskId.isEmpty) {
        final msg = data['message'] ?? data['output']?['message'] ?? '未返回task_id';
        throw Exception('提交任务失败：$msg');
      }

      return taskId;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? 
                 responseBody['output']?['message']?.toString() ?? '';
      } else if (responseBody is String) {
        detail = responseBody;
      }
      
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('鉴权失败($statusCode)：请检查阿里百炼API Key是否正确，并确认已开通万相数字人服务。$detail');
      }
      if (statusCode == 400) {
        throw Exception('请求参数错误：$detail');
      }
      
      throw Exception('提交任务失败($statusCode)：$detail');
    }
  }

  /// 查询任务状态
  /// 
  /// 返回：
  /// - status: PENDING / RUNNING / SUCCEEDED / FAILED / UNKNOWN
  /// - video_url: 视频URL（仅SUCCEEDED时返回）
  Future<Map<String, dynamic>> queryTaskStatus(String taskId) async {
    final apiKey = await _getApiKey();

    try {
      final response = await _dio.get(
        '${ApiConfig.wanxTaskQueryUrl}$taskId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      
      final status = output?['task_status'] as String? ?? 'UNKNOWN';
      String? videoUrl;
      
      if (status == 'SUCCEEDED') {
        // 官方文档：output.results.video_url
        final results = output?['results'] as Map<String, dynamic>?;
        videoUrl = results?['video_url'] as String?;
      } else if (status == 'FAILED') {
        final msg = output?['message'] as String? ?? 
                    output?['code'] as String? ?? 
                    '生成失败';
        throw Exception('视频生成失败：$msg');
      }

      return {
        'status': status,
        'video_url': videoUrl,
      };
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? '';
      }
      throw Exception('查询任务失败($statusCode)：$detail');
    }
  }

  /// 轮询等待任务完成
  Future<String> waitForTaskCompletion(
    String taskId, {
    int intervalSeconds = 10,
    int timeoutSeconds = 900,
    void Function(String status, int progress)? onProgress,
  }) async {
    final startTime = DateTime.now();

    while (true) {
      final statusInfo = await queryTaskStatus(taskId);
      final status = statusInfo['status'] as String;
      final videoUrl = statusInfo['video_url'] as String?;

      onProgress?.call(status, _calculateProgress(status));

      if (status == 'SUCCEEDED') {
        if (videoUrl == null || videoUrl.isEmpty) {
          throw Exception('视频生成完成但未返回视频URL');
        }
        return videoUrl;
      } else if (status == 'FAILED') {
        throw Exception('视频生成失败');
      } else if (status == 'UNKNOWN') {
        final elapsed = DateTime.now().difference(startTime).inSeconds;
        if (elapsed > 60) {
          throw Exception('任务状态未知，可能已失效');
        }
      }

      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if (elapsed >= timeoutSeconds) {
        throw Exception('视频生成超时（${timeoutSeconds}秒），万相数字人通常需要5-10分钟');
      }

      await Future.delayed(Duration(seconds: intervalSeconds));
    }
  }

  /// 根据任务状态计算进度百分比
  int _calculateProgress(String status) {
    switch (status) {
      case 'PENDING':
        return 20;
      case 'RUNNING':
        return 60;
      case 'SUCCEEDED':
        return 100;
      case 'FAILED':
        return 0;
      default:
        return 10;
    }
  }

  /// 将分辨率int映射为API参数格式
  String _mapResolution(int resolution) {
    if (resolution <= 480) return '480P';
    return '720P';
  }

  // ==================== 完整流程 ====================

  /// 完整流程：根据设置中的videoModel路由到对应的视频生成后端
  Future<String> generateVideoFullPipeline({
    required String imagePath,
    required String audioPath,
    String? prompt,
    int outputResolution = 720,
    bool fastMode = false,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 读取设置中的视频模型偏好
    final videoModel = StorageUtil.getVideoModel();

    switch (videoModel) {
      case 'ai32-seedance':
        return _generateWith32AISeedance(
          imagePath: imagePath,
          audioPath: audioPath,
          prompt: prompt,
          outputResolution: outputResolution,
          onProgress: onProgress,
        );
      case 'happyhorse-1.0-i2v':
        return _generateWithHappyHorse(
          imagePath: imagePath,
          prompt: prompt,
          outputResolution: outputResolution,
          onProgress: onProgress,
        );
      case 'wan2.2-s2v':
      default:
        return _generateWithWanx(
          imagePath: imagePath,
          audioPath: audioPath,
          prompt: prompt,
          outputResolution: outputResolution,
          onProgress: onProgress,
        );
    }
  }

  /// 万相wan2.2-s2v完整流程：上传图片+音频 → 检测图片 → 生成视频 → 下载
  Future<String> _generateWithWanx({
    required String imagePath,
    required String audioPath,
    String? prompt,
    int outputResolution = 720,
    void Function(String stage, int progress)? onProgress,
  }) async {
    // 1. 上传图片到百炼OSS
    onProgress?.call('上传人像照片中...', 5);
    final imageUrl = await uploadFileToBailian(imagePath, ApiConfig.wanxS2vModel);

    // 2. 上传音频到百炼OSS
    onProgress?.call('上传配音中...', 15);
    final audioUrl = await uploadFileToBailian(audioPath, ApiConfig.wanxS2vModel);

    // 3. 图像检测（官方要求先检测再生成）
    onProgress?.call('检测图片合规性...', 20);
    await detectImage(imageUrl);

    // 4. 提交万相视频生成任务
    onProgress?.call('提交生成任务...', 30);
    final taskId = await submitVideoTask(
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      resolution: _mapResolution(outputResolution),
    );

    // 5. 轮询等待完成
    final videoUrl = await waitForTaskCompletion(
      taskId,
      intervalSeconds: 10,
      timeoutSeconds: 900,
      onProgress: (status, progress) {
        final actualProgress = 30 + (progress * 0.55).round();
        String stageMsg;
        switch (status) {
          case 'PENDING':
            stageMsg = '排队中...';
            break;
          case 'RUNNING':
            stageMsg = '生成中（万相数字人通常5-10分钟）...';
            break;
          case 'SUCCEEDED':
            stageMsg = '生成完成！';
            break;
          default:
            stageMsg = '处理中...';
        }
        onProgress?.call(stageMsg, actualProgress.clamp(30, 85));
      },
    );

    // 6. 下载视频
    onProgress?.call('下载视频中...', 90);
    final localPath = await downloadVideo(videoUrl);

    onProgress?.call('完成！', 100);
    return localPath;
  }

  // ==================== 32AI Seedance 视频生成 ====================

  /// 通过32AI中转站调用豆包Seedance视频生成
  /// Seedance支持图生视频，需先上传图片获取公网URL
  Future<String> _generateWith32AISeedance({
    required String imagePath,
    required String audioPath,
    String? prompt,
    int outputResolution = 720,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.ai32ApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置32AI中转站API Key');
    }

    // 1. 上传图片到百炼OSS获取公网可访问URL
    onProgress?.call('上传人像照片中...', 5);
    final imageUrl = await uploadFileToBailian(imagePath, ApiConfig.wanxS2vModel);

    // 2. 提交Seedance视频生成任务
    onProgress?.call('提交Seedance生成任务...', 20);
    final submitUrl = '${ApiConfig.ai32VolcBaseUrl}${ApiConfig.ai32VideoGenEndpoint}';

    final requestBody = {
      'model': 'seedance-2.0',
      'content': [
        {
          'type': 'image_url',
          'image_url': {'url': imageUrl},
        },
        if (prompt != null && prompt.isNotEmpty)
          {
            'type': 'text',
            'text': prompt,
          },
      ],
    };

    try {
      final response = await _dio.post(
        submitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final taskId = data['id']?.toString() ?? data['task_id']?.toString();

      if (taskId == null || taskId.isEmpty) {
        throw Exception('Seedance提交任务未返回task_id');
      }

      // 3. 轮询等待完成
      final videoUrl = await _poll32AITask(
        taskId,
        apiKey,
        onProgress: onProgress,
      );

      // 4. 下载视频
      onProgress?.call('下载视频中...', 90);
      final localPath = await downloadVideo(videoUrl);
      onProgress?.call('完成！', 100);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['error']?['message']?.toString() ?? 
                 responseBody['message']?.toString() ?? '';
      }
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('32AI API Key无效或无权限：$detail');
      }
      throw Exception('Seedance提交失败($statusCode)：$detail');
    }
  }

  /// 轮询32AI任务状态
  Future<String> _poll32AITask(
    String taskId,
    String apiKey, {
    void Function(String stage, int progress)? onProgress,
  }) async {
    final queryUrl = '${ApiConfig.ai32VolcBaseUrl}${ApiConfig.ai32VideoGenEndpoint}/$taskId';
    final startTime = DateTime.now();

    while (true) {
      try {
        final response = await _dio.get(
          queryUrl,
          options: Options(
            headers: {
              'Authorization': 'Bearer $apiKey',
            },
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        final data = response.data as Map<String, dynamic>;
        final status = data['status']?.toString() ?? data['state']?.toString() ?? '';

        if (status == 'succeeded' || status == 'success' || status == 'complete') {
          // 提取视频URL
          final output = data['output'] ?? data['result'] ?? data;
          String? videoUrl;
          if (output is Map) {
            videoUrl = output['video_url']?.toString() ?? 
                       output['url']?.toString();
          }
          if (output is List && output.isNotEmpty) {
            videoUrl = output[0]['url']?.toString() ?? output[0]['video_url']?.toString();
          }
          if (videoUrl == null || videoUrl.isEmpty) {
            throw Exception('Seedance任务完成但未返回视频URL');
          }
          return videoUrl;
        } else if (status == 'failed' || status == 'error') {
          final errorMsg = data['error']?['message']?.toString() ?? 
                           data['message']?.toString() ?? '生成失败';
          throw Exception('Seedance生成失败：$errorMsg');
        }

        // 仍在处理中
        onProgress?.call('Seedance生成中（通常3-5分钟）...', 50);
      } on DioException catch (_) {
        // 查询失败，继续重试
      }

      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if (elapsed >= 600) {
        throw Exception('Seedance视频生成超时（10分钟）');
      }

      await Future.delayed(const Duration(seconds: 10));
    }
  }

  // ==================== HappyHorse 图生视频 ====================

  /// 通过百炼调用HappyHorse图生视频
  /// 注意：HappyHorse是图生视频（照片→动作视频），不支持口型同步
  Future<String> _generateWithHappyHorse({
    required String imagePath,
    String? prompt,
    int outputResolution = 720,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await _getApiKey();

    // 1. 上传图片到百炼OSS
    onProgress?.call('上传人像照片中...', 5);
    final imageUrl = await uploadFileToBailian(imagePath, ApiConfig.happyHorseI2vModel);

    // 2. 提交HappyHorse图生视频任务
    onProgress?.call('提交HappyHorse任务...', 25);
    final resolution = outputResolution <= 720 ? '720P' : '1080P';

    final requestBody = {
      'model': ApiConfig.happyHorseI2vModel,
      'input': {
        'prompt': prompt ?? '人物自然说话，口型同步',
        'media': [
          {
            'type': 'first_frame',
            'url': imageUrl,
          },
        ],
      },
      'parameters': {
        'resolution': resolution,
        'duration': 5,
      },
    };

    try {
      final response = await _dio.post(
        ApiConfig.happyHorseVideoSubmitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-DashScope-Async': 'enable',
            'X-DashScope-OssResourceResolve': 'enable',
          },
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final taskId = data['output']?['task_id'] as String?;
      if (taskId == null || taskId.isEmpty) {
        throw Exception('HappyHorse提交任务未返回task_id');
      }

      // 3. 轮询等待完成（复用万相查询接口，同一个/tasks/端点）
      final videoUrl = await waitForTaskCompletion(
        taskId,
        intervalSeconds: 10,
        timeoutSeconds: 600,
        onProgress: (status, progress) {
          final actualProgress = 25 + (progress * 0.6).round();
          onProgress?.call(
            status == 'PENDING' ? 'HappyHorse排队中...' :
            status == 'RUNNING' ? 'HappyHorse生成中（通常2-5分钟）...' : '处理中...',
            actualProgress.clamp(25, 85),
          );
        },
      );

      // 4. 下载视频
      onProgress?.call('下载视频中...', 90);
      final localPath = await downloadVideo(videoUrl);
      onProgress?.call('完成！', 100);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('百炼Key无权限，请确认已开通HappyHorse模型服务');
      }
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? '';
      }
      throw Exception('HappyHorse提交失败($statusCode)：$detail');
    }
  }
}

/// DigitalHumanService的Riverpod Provider
final digitalHumanServiceProvider = Provider<DigitalHumanService>((ref) {
  return DigitalHumanService(ref.read(apiClientProvider));
});
