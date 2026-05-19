import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';

/// 统一网络请求客户端 - 基于Dio封装
/// 支持拦截器（token注入、错误处理）、流式请求（SSE）
class ApiClient {
  late final Dio _dio;
  final Ref _ref;

  ApiClient(this._ref) {
    _dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      sendTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // 添加拦截器
    _dio.interceptors.addAll([
      _AuthInterceptor(_ref),
      _LogInterceptor(),
      _ErrorInterceptor(),
    ]);
  }

  // ==================== 基础请求方法 ====================

  /// GET请求
  Future<Response<T>> get<T>(
    String url, {
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.get<T>(
      url,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// POST请求
  Future<Response<T>> post<T>(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.post<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// DELETE请求
  Future<Response<T>> delete<T>(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.delete<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// PUT请求
  Future<Response<T>> put<T>(
    String url, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
    CancelToken? cancelToken,
  }) async {
    return _dio.put<T>(
      url,
      data: data,
      queryParameters: queryParameters,
      options: options,
      cancelToken: cancelToken,
    );
  }

  /// 文件上传
  Future<Response<T>> upload<T>(
    String url, {
    required String filePath,
    String fieldName = 'file',
    Map<String, dynamic>? extraFields,
    Options? options,
    ProgressCallback? onSendProgress,
    CancelToken? cancelToken,
  }) async {
    final formData = FormData.fromMap({
      fieldName: await MultipartFile.fromFile(filePath),
      if (extraFields != null) ...extraFields,
    });

    return _dio.post<T>(
      url,
      data: formData,
      options: options ?? Options(contentType: 'multipart/form-data'),
      onSendProgress: onSendProgress,
      cancelToken: cancelToken,
    );
  }

  // ==================== 大模型聊天接口（OpenAI兼容格式） ====================

  /// 调用大模型聊天接口（普通模式）
  /// [baseUrl] API基础地址
  /// [apiKey] API密钥
  /// [model] 模型名称
  /// [messages] 消息列表
  /// [temperature] 温度参数(0.0-1.0)
  Future<String> chatCompletion({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async {
    final response = await _dio.post(
      '$baseUrl/chat/completions',
      data: {
        'model': model,
        'messages': messages,
        'temperature': temperature,
        'max_tokens': maxTokens,
      },
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    // 解析OpenAI兼容格式的响应
    final data = response.data as Map<String, dynamic>;
    final choices = data['choices'] as List<dynamic>;
    if (choices.isNotEmpty) {
      final message = choices[0]['message'] as Map<String, dynamic>;
      return message['content'] as String? ?? '';
    }
    return '';
  }

  /// 流式调用大模型聊天接口（SSE模式，用于大模型流式输出）
  /// 返回Stream，逐块输出文本
  Stream<String> chatCompletionStream({
    required String baseUrl,
    required String apiKey,
    required String model,
    required List<Map<String, String>> messages,
    double temperature = 0.7,
    int maxTokens = 4096,
  }) async* {
    final controller = StreamController<String>();

    try {
      // 使用Dio发送SSE请求
      final response = await _dio.post(
        '$baseUrl/chat/completions',
        data: {
          'model': model,
          'messages': messages,
          'temperature': temperature,
          'max_tokens': maxTokens,
          'stream': true,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'Accept': 'text/event-stream',
          },
          responseType: ResponseType.stream,
        ),
      );

      final stream = response.data as ResponseBody;
      String buffer = '';

      await for (final chunk in stream.stream) {
        buffer += utf8.decode(chunk, allowMalformed: true);
        // 按行解析SSE数据
        final lines = buffer.split('\n');
        buffer = lines.removeLast(); // 保留最后不完整的行

        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('data: ')) {
            final data = trimmed.substring(6);
            if (data == '[DONE]') {
              controller.close();
              return;
            }
            try {
              final json = jsonDecode(data) as Map<String, dynamic>;
              final choices = json['choices'] as List<dynamic>?;
              if (choices != null && choices.isNotEmpty) {
                final delta = choices[0]['delta'] as Map<String, dynamic>?;
                if (delta != null && delta.containsKey('content')) {
                  final content = delta['content'] as String? ?? '';
                  if (content.isNotEmpty) {
                    controller.add(content);
                  }
                }
              }
            } catch (_) {
              // 忽略解析错误
            }
          }
        }
      }
    } catch (e) {
      controller.addError(e);
    } finally {
      if (!controller.isClosed) {
        controller.close();
      }
    }

    yield* controller.stream;
  }

  // ==================== 智谱AI快捷调用 ====================

  /// 调用智谱AI（GLM-4-Flash）
  Future<String> chatZhipu({
    required List<Map<String, String>> messages,
    String model = ApiConfig.zhipuModelFlash,
    double temperature = 0.7,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.zhipuApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置智谱AI的API Key');
    }
    return chatCompletion(
      baseUrl: ApiConfig.zhipuBaseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
    );
  }

  /// 流式调用智谱AI
  Stream<String> chatZhipuStream({
    required List<Map<String, String>> messages,
    String model = ApiConfig.zhipuModelFlash,
    double temperature = 0.7,
  }) async* {
    final apiKey = await StorageUtil.getSecure(ApiConfig.zhipuApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置智谱AI的API Key');
    }
    yield* chatCompletionStream(
      baseUrl: ApiConfig.zhipuBaseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
    );
  }

  // ==================== 硅基流动快捷调用 ====================

  /// 调用硅基流动（Qwen2.5-7B）
  Future<String> chatSiliconFlow({
    required List<Map<String, String>> messages,
    String model = ApiConfig.siliconFlowModelQwen,
    double temperature = 0.7,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.siliconFlowApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置硅基流动的API Key');
    }
    return chatCompletion(
      baseUrl: ApiConfig.siliconFlowBaseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
    );
  }

  // ==================== DeepSeek快捷调用 ====================

  /// 调用DeepSeek（法务审核用，强推理能力）
  Future<String> chatDeepSeek({
    required List<Map<String, String>> messages,
    String model = ApiConfig.deepseekModelV3,
    double temperature = 0.3,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.deepseekApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置DeepSeek的API Key');
    }
    return chatCompletion(
      baseUrl: ApiConfig.deepseekBaseUrl,
      apiKey: apiKey,
      model: model,
      messages: messages,
      temperature: temperature,
    );
  }
}

// ==================== 拦截器 ====================

/// Token注入拦截器 - 根据请求URL自动从SecureStorage读取对应API Key注入Header
class _AuthInterceptor extends Interceptor {
  final Ref _ref;
  _AuthInterceptor(this._ref);

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    // 根据URL自动注入对应的API Key到Header
    final url = options.uri.toString();

    // 如果已有Authorization头，跳过自动注入
    if (options.headers.containsKey('Authorization')) {
      handler.next(options);
      return;
    }

    String? apiKey;
    String? storageKey;

    if (url.contains('bigmodel.cn')) {
      // 智谱AI
      storageKey = ApiConfig.zhipuApiKeyKey;
    } else if (url.contains('siliconflow')) {
      // 硅基流动
      storageKey = ApiConfig.siliconFlowApiKeyKey;
    } else if (url.contains('deepseek')) {
      // DeepSeek
      storageKey = ApiConfig.deepseekApiKeyKey;
    } else if (url.contains('dashscope')) {
      // 阿里百炼
      storageKey = ApiConfig.aliBailianApiKeyKey;
    } else if (url.contains('hifly')) {
      // 飞影数字人
      storageKey = ApiConfig.hiflyApiKeyKey;
    }

    if (storageKey != null) {
      apiKey = await StorageUtil.getSecure(storageKey);
      if (apiKey != null && apiKey.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $apiKey';
      }
    }

    handler.next(options);
  }
}

/// 日志拦截器
class _LogInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    // 请求日志
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    // 响应日志
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 错误日志
    handler.next(err);
  }
}

/// 错误处理拦截器
class _ErrorInterceptor extends Interceptor {
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    // 统一错误处理
    String errorMessage = '网络请求失败';

    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        errorMessage = '网络连接超时，请检查网络设置';
        break;
      case DioExceptionType.badResponse:
        final statusCode = err.response?.statusCode;
        switch (statusCode) {
          case 401:
            errorMessage = 'API Key无效或已过期，请重新配置';
            break;
          case 429:
            errorMessage = '请求过于频繁，请稍后再试';
            break;
          case 500:
            errorMessage = '服务器内部错误，请稍后再试';
            break;
          case 502:
          case 503:
            errorMessage = '服务暂时不可用，请稍后再试';
            break;
          default:
            errorMessage = '请求失败($statusCode)';
        }
        break;
      case DioExceptionType.connectionError:
        errorMessage = '网络连接失败，请检查网络设置';
        break;
      default:
        errorMessage = '未知网络错误';
    }

    handler.next(DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: errorMessage,
    ));
  }
}

/// ApiClient的Riverpod Provider
final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(ref);
});
