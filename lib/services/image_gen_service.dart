import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';

/// 图像生成服务 - 支持阿里百炼Wanxiang和本地Stable Diffusion
class ImageGenService {
  final Dio _dio;

  ImageGenService() : _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 15),
    sendTimeout: const Duration(minutes: 5),
  ));

  // ==================== 公共方法 ====================

  /// 根据画面描述生成图片
  /// [prompt] 画面描述
  /// [negativePrompt] 否定提示词
  /// [width] 宽度
  /// [height] 高度
  /// [model] 使用的模型：wanx / local_sd / custom
  /// [customApiKey] 自定义API Key（custom模式时使用）
  /// [customBaseUrl] 自定义Base URL（custom模式时使用）
  /// 返回本地文件路径
  Future<String> generateImage({
    required String prompt,
    String negativePrompt = 'blurry, low quality, deformed, ugly, bad anatomy, extra limbs',
    int width = 1024,
    int height = 576,
    String model = 'wanx',
    String? customApiKey,
    String? customBaseUrl,
    void Function(String stage, int progress)? onProgress,
  }) async {
    if (model == 'custom' && customApiKey != null && customApiKey.isNotEmpty) {
      // 使用自定义配置（兼容OpenAI格式的文生图API）
      return _generateWithCustom(
        prompt: prompt,
        negativePrompt: negativePrompt,
        width: width,
        height: height,
        apiKey: customApiKey,
        baseUrl: customBaseUrl ?? '',
        modelName: 'dall-e-3',
        onProgress: onProgress,
      );
    } else if (model == 'agnes-image') {
      // 使用Agnes AI图像生成（OpenAI兼容格式）
      final agnesKey = (customApiKey?.isNotEmpty ?? false)
          ? customApiKey!
          : 'sk-Rcb7FziWSyPq3cZPEcrHx4Xh4MOte1DlUjuEg6w0TBVvhiub';
      return _generateWithCustom(
        prompt: prompt,
        negativePrompt: negativePrompt,
        width: width,
        height: height,
        apiKey: agnesKey,
        baseUrl: customBaseUrl?.isNotEmpty == true ? customBaseUrl! : 'https://api.agnes-ai.com/v1',
        modelName: 'agnes-image-2.1-flash',
        onProgress: onProgress,
      );
    } else if (model == 'wanx') {
      return _generateWithWanx(
        prompt: prompt,
        negativePrompt: negativePrompt,
        width: width,
        height: height,
        onProgress: onProgress,
      );
    } else {
      return _generateWithLocalSd(
        prompt: prompt,
        negativePrompt: negativePrompt,
        width: width,
        height: height,
        onProgress: onProgress,
      );
    }
  }

  /// 增强prompt（加入画风、质量等修饰词）
  static String enhancePrompt(String description, String style, String? characterDesc) {
    final buffer = StringBuffer(description);

    // 添加角色描述
    if (characterDesc != null && characterDesc.isNotEmpty) {
      buffer.write('; $characterDesc');
    }

    // 根据画风添加修饰词
    switch (style) {
      case 'anime':
        buffer.write(', anime style, high quality, detailed, vibrant colors, professional illustration');
        break;
      case 'realistic':
        buffer.write(', photorealistic, 8k, detailed skin texture, cinematic lighting, professional photography');
        break;
      case '3d':
        buffer.write(', 3D render, Pixar style, high quality, detailed, studio lighting');
        break;
      case 'watercolor':
        buffer.write(', watercolor painting style, soft colors, artistic, delicate brush strokes');
        break;
      case 'cartoon':
        buffer.write(', cartoon style, colorful, fun, clean lines, animated');
        break;
      case 'comic':
        buffer.write(', comic book style, bold outlines, vibrant colors, dynamic composition');
        break;
      default:
        buffer.write(', high quality, detailed, professional');
    }

    return buffer.toString();
  }

  /// 解析aspectRatio为宽高
  static Map<String, int> parseAspectRatio(String ratio, {int defaultWidth = 1024}) {
    switch (ratio) {
      case '16:9':
        return {'width': defaultWidth, 'height': (defaultWidth * 9 / 16).round()};
      case '9:16':
        return {'width': (defaultWidth * 9 / 16).round(), 'height': defaultWidth};
      case '1:1':
        return {'width': defaultWidth, 'height': defaultWidth};
      case '4:3':
        return {'width': defaultWidth, 'height': (defaultWidth * 3 / 4).round()};
      case '3:4':
        return {'width': (defaultWidth * 3 / 4).round(), 'height': defaultWidth};
      default:
        return {'width': defaultWidth, 'height': (defaultWidth * 9 / 16).round()};
    }
  }

  // ==================== 阿里百炼 Wanxiang 文生图 ====================

  /// 获取百炼API Key
  Future<String> _getWanxApiKey() async {
    var apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    apiKey = apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key（设置页面）');
    }
    return apiKey;
  }

  /// 使用阿里百炼Wanxiang生成图片
  Future<String> _generateWithWanx({
    required String prompt,
    required String negativePrompt,
    required int width,
    required int height,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await _getWanxApiKey();

    onProgress?.call('提交文生图任务...', 10);

    // 构建请求体
    final requestBody = {
      'model': ApiConfig.wanxT2IModel,
      'input': {
        'prompt': prompt,
        'negative_prompt': negativePrompt,
      },
      'parameters': {
        'size': '${width}*$height',
        'n': 1,
      },
    };

    try {
      final response = await _dio.post(
        ApiConfig.wanxT2ISubmitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-DashScope-Async': 'enable',
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

      onProgress?.call('等待图片生成...', 30);

      // 轮询任务状态
      final imageUrl = await _pollWanxTask(
        taskId,
        apiKey,
        onProgress: onProgress,
      );

      onProgress?.call('下载图片...', 90);

      // 下载图片
      final localPath = await _downloadImage(imageUrl, 'wanx');

      onProgress?.call('完成！', 100);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? '';
      } else if (responseBody is String) {
        detail = responseBody;
      }

      if (statusCode == 401 || statusCode == 403) {
        throw Exception('鉴权失败($statusCode)：请检查阿里百炼API Key是否正确，并确认已开通Wanxiang文生图服务。$detail');
      }
      if (statusCode == 400) {
        throw Exception('请求参数错误：$detail');
      }
      if (statusCode == 402) {
        throw Exception('账户余额不足：请前往阿里云百炼控制台充值。$detail');
      }

      throw Exception('文生图失败($statusCode)：$detail');
    }
  }

  /// 轮询百炼任务状态
  Future<String> _pollWanxTask(
    String taskId,
    String apiKey, {
    void Function(String stage, int progress)? onProgress,
  }) async {
    const maxRetries = 60;
    const pollInterval = Duration(seconds: 10);

    for (int i = 0; i < maxRetries; i++) {
      try {
        final response = await _dio.get(
          '${ApiConfig.wanxT2ITaskQueryUrl}$taskId',
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

        if (status == 'SUCCEEDED') {
          // 提取图片URL
          final results = output?['results'] as List<dynamic>?;
          if (results != null && results.isNotEmpty) {
            final imageResult = results.first as Map<String, dynamic>;
            final imageUrl = imageResult['url'] as String?;
            if (imageUrl != null && imageUrl.isNotEmpty) {
              return imageUrl;
            }
          }
          throw Exception('图片生成完成但未返回URL');
        } else if (status == 'FAILED') {
          final msg = output?['message'] as String? ?? output?['code'] as String? ?? '生成失败';
          throw Exception('图片生成失败：$msg');
        }

        // 更新进度
        final progress = 30 + ((i + 1) * 60 / maxRetries).round();
        onProgress?.call('生成中（${i + 1}/$maxRetries）...', progress.clamp(30, 90));

        // 等待
        await Future.delayed(pollInterval);
      } on DioException catch (e) {
        // 查询失败，记录错误但继续重试
        if (i == maxRetries - 1) {
          throw Exception('查询任务状态失败：${e.message}');
        }
        await Future.delayed(pollInterval);
      }
    }

    throw Exception('图片生成超时（${maxRetries * 10}秒）');
  }

  // ==================== 本地 Stable Diffusion ====================

  /// 获取本地SD地址
  Future<String> _getLocalSdUrl() async {
    var url = StorageUtil.getString(ApiConfig.localSdUrlKey);
    url = url?.trim() ?? '';
    if (url.isEmpty) {
      return ApiConfig.defaultLocalSdUrl;
    }
    // 确保URL格式正确
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    return url;
  }

  /// 使用本地Stable Diffusion生成图片
  Future<String> _generateWithLocalSd({
    required String prompt,
    required String negativePrompt,
    required int width,
    required int height,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final sdUrl = await _getLocalSdUrl();

    onProgress?.call('连接本地SD...', 10);

    // 构建SD WebUI请求
    final requestBody = {
      'prompt': prompt,
      'negative_prompt': negativePrompt,
      'steps': 20,
      'width': width,
      'height': height,
      'cfg_scale': 7,
      'sampler_index': 'Euler a',
    };

    try {
      onProgress?.call('正在生成...', 30);

      final response = await _dio.post(
        '$sdUrl${ApiConfig.localSdTxt2ImgEndpoint}',
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      final data = response.data as Map<String, dynamic>;

      // SD返回base64编码的图片
      final images = data['images'] as List<dynamic>?;
      if (images == null || images.isEmpty) {
        final error = data['error'] as String? ?? 'SD未返回图片';
        throw Exception('本地SD生成失败：$error');
      }

      final base64Image = images.first as String;

      onProgress?.call('保存图片...', 80);

      // 解码并保存
      final localPath = await _saveBase64Image(base64Image, 'sd');

      onProgress?.call('完成！', 100);
      return localPath;
    } on DioException catch (e) {
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        throw Exception('连接本地SD超时，请检查SD WebUI是否启动');
      }
      if (e.response?.statusCode == 404) {
        throw Exception('本地SD地址不可用，请检查SD WebUI是否启动');
      }
      throw Exception('本地SD生成失败：${e.message}');
    }
  }

  // ==================== 自定义文生图（OpenAI兼容格式） ====================

  /// 使用自定义API生成图片（兼容OpenAI images/generations格式）
  Future<String> _generateWithCustom({
    required String prompt,
    required String negativePrompt,
    required int width,
    required int height,
    required String apiKey,
    required String baseUrl,
    String modelName = 'dall-e-3',
    void Function(String stage, int progress)? onProgress,
  }) async {
    if (baseUrl.isEmpty) {
      throw Exception('自定义图像模型需要配置Base URL');
    }

    onProgress?.call('提交文生图任务...', 10);

    // 确保baseUrl不以/结尾
    final normalizedBaseUrl = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;

    try {
      final response = await _dio.post(
        '$normalizedBaseUrl/images/generations',
        data: jsonEncode({
          'model': modelName,
          'prompt': prompt,
          'size': '${width}x$height',
          'n': 1,
        }),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final imageData = data['data'] as List<dynamic>?;

      if (imageData == null || imageData.isEmpty) {
        throw Exception('自定义文生图未返回结果');
      }

      final imageUrl = imageData[0]['url'] as String?;
      if (imageUrl == null || imageUrl.isEmpty) {
        // 尝试b64_json格式
        final b64 = imageData[0]['b64_json'] as String?;
        if (b64 != null && b64.isNotEmpty) {
          onProgress?.call('保存图片...', 80);
          final localPath = await _saveBase64Image(b64, 'custom');
          onProgress?.call('完成！', 100);
          return localPath;
        }
        throw Exception('自定义文生图返回数据异常');
      }

      onProgress?.call('下载图片...', 80);
      final localPath = await _downloadImage(imageUrl, 'custom');
      onProgress?.call('完成！', 100);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final msg = e.response?.data?.toString() ?? e.message ?? '';
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('自定义图像API鉴权失败：请检查API Key。$msg');
      }
      throw Exception('自定义图像生成失败($statusCode)：$msg');
    }
  }

  // ==================== 辅助方法 ====================

  /// 下载图片
  Future<String> _downloadImage(String imageUrl, String prefix) async {
    final imageDir = await StorageUtil.getDramaImageDirectory();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    final filePath = '$imageDir/$fileName';

    try {
      final response = await _dio.get(
        imageUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      throw Exception('图片下载失败：$e');
    }
  }

  /// 保存Base64图片
  Future<String> _saveBase64Image(String base64Data, String prefix) async {
    final imageDir = await StorageUtil.getDramaImageDirectory();
    final fileName = '${prefix}_${DateTime.now().millisecondsSinceEpoch}.png';
    final filePath = '$imageDir/$fileName';

    try {
      final bytes = base64Decode(base64Data);
      final file = File(filePath);
      await file.writeAsBytes(bytes);
      return filePath;
    } catch (e) {
      throw Exception('图片保存失败：$e');
    }
  }
}
