import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import '../utils/retry_util.dart';

/// 动作迁移生成状态
enum MotionTransferStatus {
  idle,          // 空闲
  uploading,     // 上传素材中
  submitting,    // 提交任务中
  processing,    // 处理中（轮询）
  downloading,   // 下载视频中
  completed,     // 完成
  failed,        // 失败
}

/// 动作迁移任务结果
class MotionTransferResult {
  final String taskId;
  final String? videoUrl;        // 在线视频URL（24小时有效）
  final String? localVideoPath;  // 本地保存路径
  final double? duration;        // 视频时长（秒）
  final String? modelName;       // 使用的模型
  final String? serviceMode;     // 服务模式（std/pro 或 分辨率）

  const MotionTransferResult({
    required this.taskId,
    this.videoUrl,
    this.localVideoPath,
    this.duration,
    this.modelName,
    this.serviceMode,
  });
}

/// 动作迁移服务 - 支持多种动作迁移模型
///
/// 支持的模型：
/// - wan2.2-animate-move: 万相图生动作（阿里百炼，支持std/pro两档）
/// - pixverse-motioncontrol: PixVerse动作模仿（爱诗科技，支持360P/540P/720P）
///
/// 通用流程：
/// 1. 上传人物图片到百炼OSS获取临时URL
/// 2. 上传动作视频到百炼OSS获取临时URL
/// 3. 提交动作迁移任务（异步）
/// 4. 轮询任务状态直到完成
/// 5. 下载生成的视频到本地
class MotionTransferService {
  final Dio _dio;

  MotionTransferService()
      : _dio = Dio(BaseOptions(
          connectTimeout: const Duration(seconds: 60),
          receiveTimeout: const Duration(minutes: 15),
          sendTimeout: const Duration(minutes: 10),
        ));

  // ==================== 公共工具方法 ====================

  /// 获取百炼API Key
  Future<String> _getApiKey() async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    final trimmedKey = apiKey?.trim() ?? '';
    if (trimmedKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key（设置页面）');
    }
    return trimmedKey;
  }

  /// 下载视频到本地缓存
  Future<String> downloadVideo(String videoUrl) async {
    final videoDir = await StorageUtil.getVideoDirectory();
    final fileName = 'motion_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filePath = '$videoDir/$fileName';

    try {
      final response = await retryOnNetworkError(() => _dio.get(
        videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 20),
        ),
      ));

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      throw Exception('视频下载失败：${e.toString().replaceAll('DioException ', '')}');
    }
  }

  // ==================== 百炼OSS上传（复用数字人服务的上传逻辑） ====================

  /// 获取OSS上传凭证
  Future<Map<String, dynamic>> _getOssUploadPolicy(String modelName) async {
    final apiKey = await _getApiKey();

    final response = await retryOnNetworkError(() => _dio.get(
      '${ApiConfig.bailianUploadUrl}?action=getPolicy&model=$modelName',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    ));

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
  /// 返回 oss:// 格式的URL，百炼API内部可解析访问
  Future<String> uploadFileToBailian(String localFilePath, String modelName) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('文件不存在：$localFilePath');
    }

    final fileName = '${DateTime.now().millisecondsSinceEpoch}_${localFilePath.split('/').last}';
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

    await retryOnNetworkError(() => _dio.post(
      policy['upload_host'] as String,
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        sendTimeout: const Duration(minutes: 10),
      ),
    ));

    return 'oss://$ossKey';
  }

  // ==================== 模型1：万相 wan2.2-animate-move ====================

  /// 提交万相动作迁移任务
  ///
  /// [imageUrl] 人物图片URL（oss:// 或公网URL）
  /// [videoUrl] 动作参考视频URL（oss:// 或公网URL）
  /// [mode] 服务模式：wan-std（标准）或 wan-pro（专业）
  /// [watermark] 是否添加水印
  /// 返回 task_id
  Future<String> submitWanAnimateMoveTask({
    required String imageUrl,
    required String videoUrl,
    String mode = 'wan-std',
    bool watermark = false,
  }) async {
    final apiKey = await _getApiKey();

    final requestBody = {
      'model': ApiConfig.wanAnimateMoveModel,
      'input': {
        'image_url': imageUrl,
        'video_url': videoUrl,
        'watermark': watermark,
      },
      'parameters': {
        'mode': mode,
      },
    };

    try {
      final response = await retryOnNetworkError(() => _dio.post(
        ApiConfig.wanAnimateMoveSubmitUrl,
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
      ));

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      final taskId = output?['task_id'] as String?;

      if (taskId == null || taskId.isEmpty) {
        final msg = data['message'] ?? output?['message'] ?? '未返回task_id';
        throw Exception('提交任务失败：$msg');
      }

      return taskId;
    } on DioException catch (e) {
      final detail = _extractErrorDetail(e);
      throw Exception('提交万相动作迁移任务失败：$detail');
    }
  }

  /// 查询万相动作迁移任务状态
  ///
  /// 返回 {
  ///   'status': 'PENDING'|'RUNNING'|'SUCCEEDED'|'FAILED',
  ///   'video_url': '...',     // 成功时返回
  ///   'duration': 5.2,         // 成功时返回（秒）
  ///   'error': '...',          // 失败时返回
  /// }
  Future<Map<String, dynamic>> queryWanAnimateMoveTask(String taskId) async {
    final apiKey = await _getApiKey();

    try {
      final response = await _dio.get(
        '${ApiConfig.wanAnimateMoveTaskQueryUrl}$taskId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>? ?? {};
      final status = output['task_status'] as String? ?? 'UNKNOWN';
      final usage = data['usage'] as Map<String, dynamic>?;

      final result = <String, dynamic>{
        'status': status,
      };

      if (status == 'SUCCEEDED') {
        final results = output['results'] as Map<String, dynamic>?;
        result['video_url'] = results?['video_url'] as String?;
        result['duration'] = (usage?['video_duration'] as num?)?.toDouble();
      } else if (status == 'FAILED') {
        final code = output['code']?.toString() ?? '';
        final message = output['message']?.toString() ?? '未知错误';
        result['error'] = code.isNotEmpty ? '($code) $message' : message;
      }

      return result;
    } on DioException catch (e) {
      final detail = _extractErrorDetail(e);
      throw Exception('查询任务状态失败：$detail');
    }
  }

  // ==================== 模型2：PixVerse Motion Control ====================

  /// 提交PixVerse动作模仿任务（百炼平台）
  ///
  /// [imageUrl] 人物图片URL
  /// [videoUrl] 动作参考视频URL
  /// [resolution] 输出分辨率：360P、540P、720P
  /// [watermark] 是否添加水印
  /// 返回 task_id
  Future<String> submitPixverseMotionControlTask({
    required String imageUrl,
    required String videoUrl,
    String resolution = '540P',
    bool watermark = false,
  }) async {
    final apiKey = await _getApiKey();

    final requestBody = {
      'model': ApiConfig.pixverseMotionControlModel,
      'input': {
        'media': [
          {'type': 'image_url', 'url': imageUrl},
          {'type': 'video_url', 'url': videoUrl},
        ],
      },
      'parameters': {
        'resolution': resolution,
        'watermark': watermark,
      },
    };

    try {
      final response = await retryOnNetworkError(() => _dio.post(
        ApiConfig.pixverseMotionControlSubmitUrl,
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
      ));

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      final taskId = output?['task_id'] as String?;

      if (taskId == null || taskId.isEmpty) {
        final msg = data['message'] ?? output?['message'] ?? '未返回task_id';
        throw Exception('提交任务失败：$msg');
      }

      return taskId;
    } on DioException catch (e) {
      final detail = _extractErrorDetail(e);
      throw Exception('提交PixVerse动作迁移任务失败：$detail');
    }
  }

  /// 查询PixVerse动作模仿任务状态
  Future<Map<String, dynamic>> queryPixverseMotionControlTask(String taskId) async {
    final apiKey = await _getApiKey();

    try {
      final response = await _dio.get(
        '${ApiConfig.pixverseMotionControlTaskQueryUrl}$taskId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>? ?? {};
      final status = output['task_status'] as String? ?? 'UNKNOWN';

      final result = <String, dynamic>{
        'status': status,
      };

      if (status == 'SUCCEEDED') {
        final results = output['results'] as Map<String, dynamic>?;
        result['video_url'] = results?['video_url'] as String?;
        final usage = data['usage'] as Map<String, dynamic>?;
        result['duration'] = (usage?['video_duration'] as num?)?.toDouble();
      } else if (status == 'FAILED') {
        final code = output['code']?.toString() ?? '';
        final message = output['message']?.toString() ?? '未知错误';
        result['error'] = code.isNotEmpty ? '($code) $message' : message;
      }

      return result;
    } on DioException catch (e) {
      final detail = _extractErrorDetail(e);
      throw Exception('查询任务状态失败：$detail');
    }
  }

  // ==================== 统一入口：生成动作迁移视频 ====================

  /// 生成动作迁移视频（完整流程，支持进度回调）
  ///
  /// [modelId] 模型ID：wan2.2-animate-move / pixverse-motioncontrol
  /// [imagePath] 本地人物图片路径
  /// [videoPath] 本地动作视频路径
  /// [quality] 质量参数：万相用 wan-std/wan-pro，PixVerse用 360P/540P/720P
  /// [onProgress] 进度回调 (status, progressPercent, message)
  /// 返回本地视频路径
  Future<MotionTransferResult> generateMotionTransferVideo({
    required String modelId,
    required String imagePath,
    required String videoPath,
    String quality = 'wan-std',
    bool watermark = false,
    void Function(MotionTransferStatus status, int progress, String message)? onProgress,
  }) async {
    void report(MotionTransferStatus s, int p, String m) {
      onProgress?.call(s, p, m);
    }

    try {
      // ---- 阶段1：上传/准备图片 ----
      report(MotionTransferStatus.uploading, 5, '正在准备人物图片...');
      final imageUrl = await _prepareMediaUrl(imagePath, modelId);
      report(MotionTransferStatus.uploading, 25, '人物图片准备完成');

      // ---- 阶段2：上传/准备视频 ----
      report(MotionTransferStatus.uploading, 30, '正在准备动作视频...');
      final videoUrl = await _prepareMediaUrl(videoPath, modelId);
      report(MotionTransferStatus.uploading, 45, '动作视频准备完成');

      // ---- 阶段3：提交任务 ----
      report(MotionTransferStatus.submitting, 50, '正在提交生成任务...');
      String taskId;
      if (modelId == 'wan2.2-animate-move') {
        taskId = await submitWanAnimateMoveTask(
          imageUrl: imageUrl,
          videoUrl: videoUrl,
          mode: quality,
          watermark: watermark,
        );
      } else if (modelId == 'pixverse-motioncontrol') {
        taskId = await submitPixverseMotionControlTask(
          imageUrl: imageUrl,
          videoUrl: videoUrl,
          resolution: quality,
          watermark: watermark,
        );
      } else {
        throw Exception('不支持的动作迁移模型：$modelId');
      }
      report(MotionTransferStatus.processing, 55, '任务已提交，等待处理...');

      // ---- 阶段4：轮询任务状态 ----
      final onlineVideoUrl = await _pollTaskStatus(
        modelId: modelId,
        taskId: taskId,
        onProgress: (progress, message) {
          report(MotionTransferStatus.processing, 55 + (progress * 0.35).toInt(), message);
        },
      );

      // ---- 阶段5：下载视频 ----
      report(MotionTransferStatus.downloading, 92, '正在下载生成的视频...');
      final localPath = await downloadVideo(onlineVideoUrl);
      report(MotionTransferStatus.completed, 100, '生成完成！');

      return MotionTransferResult(
        taskId: taskId,
        videoUrl: onlineVideoUrl,
        localVideoPath: localPath,
        modelName: modelId,
        serviceMode: quality,
      );
    } catch (e) {
      report(MotionTransferStatus.failed, 0, e.toString().replaceAll('Exception: ', ''));
      rethrow;
    }
  }

  /// 轮询任务状态直到完成或失败
  Future<String> _pollTaskStatus({
    required String modelId,
    required String taskId,
    required void Function(int progress, String message) onProgress,
  }) async {
    const maxAttempts = 120; // 最多轮询120次（每次15秒=30分钟）
    const pollInterval = Duration(seconds: 15);
    int attempts = 0;

    while (attempts < maxAttempts) {
      attempts++;
      await Future.delayed(pollInterval);

      Map<String, dynamic> statusResult;
      if (modelId == 'wan2.2-animate-move') {
        statusResult = await queryWanAnimateMoveTask(taskId);
      } else {
        statusResult = await queryPixverseMotionControlTask(taskId);
      }

      final status = statusResult['status'] as String;

      switch (status) {
        case 'SUCCEEDED':
          onProgress(100, '生成成功，准备下载...');
          final videoUrl = statusResult['video_url'] as String?;
          if (videoUrl == null || videoUrl.isEmpty) {
            throw Exception('任务成功但未返回视频URL');
          }
          return videoUrl;

        case 'FAILED':
          final error = statusResult['error']?.toString() ?? '任务失败';
          throw Exception('生成失败：$error');

        case 'PENDING':
          onProgress(attempts * 2, '任务排队中...（$attempts/${maxAttempts ~/ 4}）');
          break;

        case 'RUNNING':
          final progress = (attempts * 4).clamp(5, 90);
          onProgress(progress, '视频生成中，请耐心等待...');
          break;

        case 'CANCELED':
          throw Exception('任务已取消');

        default:
          onProgress(attempts * 2, '任务状态：$status');
          break;
      }
    }

    throw Exception('生成超时，请稍后在历史记录中查看结果');
  }

  /// 根据模型ID获取用于上传的模型名称
  String _getUploadModelName(String modelId) {
    if (modelId == 'wan2.2-animate-move') {
      return ApiConfig.wanAnimateMoveModel;
    } else if (modelId == 'pixverse-motioncontrol') {
      // PixVerse上传模型名
      return 'pixverse-motioncontrol';
    }
    return modelId;
  }

  /// 准备媒体URL
  /// - 如果是网络URL（http/https开头），直接返回
  /// - 如果是本地文件路径，上传到百炼OSS并返回oss:// URL
  Future<String> _prepareMediaUrl(String pathOrUrl, String modelId) async {
    if (pathOrUrl.startsWith('http://') || pathOrUrl.startsWith('https://')) {
      // 网络URL直接使用
      return pathOrUrl;
    }
    // 本地文件上传到百炼
    return await uploadFileToBailian(pathOrUrl, _getUploadModelName(modelId));
  }

  /// 从Dio异常中提取错误详情
  String _extractErrorDetail(DioException e) {
    final statusCode = e.response?.statusCode;
    final responseData = e.response?.data;
    String detail = '';

    if (responseData is Map<String, dynamic>) {
      final code = responseData['code']?.toString() ?? '';
      final message = responseData['message']?.toString() ?? '';
      final outputMsg = responseData['output']?['message']?.toString() ?? '';
      if (message.isNotEmpty) {
        detail = code.isNotEmpty ? '($code) $message' : message;
      } else if (outputMsg.isNotEmpty) {
        detail = outputMsg;
      }
    } else if (responseData is String && responseData.isNotEmpty) {
      detail = responseData.length > 150
          ? '${responseData.substring(0, 150)}...'
          : responseData;
    }

    if (detail.isEmpty) {
      detail = e.error?.toString() ?? e.message ?? '网络请求失败';
    }

    return 'HTTP $statusCode：$detail';
  }

  /// 获取模型的质量选项列表
  static List<Map<String, String>> getQualityOptions(String modelId) {
    if (modelId == 'wan2.2-animate-move') {
      return const [
        {'value': 'wan-std', 'label': '标准模式', 'desc': '速度快，性价比高'},
        {'value': 'wan-pro', 'label': '专业模式', 'desc': '画质更佳，费用更高'},
      ];
    } else if (modelId == 'pixverse-motioncontrol') {
      return const [
        {'value': '360P', 'label': '360P', 'desc': '最快，体积小'},
        {'value': '540P', 'label': '540P', 'desc': '平衡推荐'},
        {'value': '720P', 'label': '720P', 'desc': '高清，效果好'},
      ];
    }
    return [];
  }

  /// 估算消耗费用（元），按秒计费
  static double estimateCost(String modelId, String quality, int estimatedSeconds) {
    if (modelId == 'wan2.2-animate-move') {
      // 万相：std 0.4元/秒，pro 0.6元/秒
      final rate = quality == 'wan-pro' ? 0.6 : 0.4;
      return rate * estimatedSeconds;
    } else if (modelId == 'pixverse-motioncontrol') {
      // PixVerse：360P 0.27, 540P 0.3, 720P 0.36 元/秒
      double rate = 0.3;
      if (quality == '360P') rate = 0.27;
      if (quality == '720P') rate = 0.36;
      return rate * estimatedSeconds;
    }
    return 0;
  }
}
