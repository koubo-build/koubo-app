import 'package:dio/dio.dart';

/// 网络重试工具 - 弱网环境下自动重试连接错误（DNS失败、超时等）
/// 最多重试[maxRetries]次，间隔递增（3s → 6s → 9s）
/// 只对网络层错误重试，HTTP状态码错误不重试
Future<T> retryOnNetworkError<T>(
  Future<T> Function() action, {
  int maxRetries = 3,
  int baseDelaySeconds = 3,
}) async {
  for (int attempt = 0; attempt <= maxRetries; attempt++) {
    try {
      return await action();
    } on DioException catch (e) {
      // 只对网络层错误重试（DNS失败、连接错误、超时）
      final isNetworkError = e.type == DioExceptionType.connectionError ||
          e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.sendTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          (e.message != null && e.message!.contains('Failed host lookup'));
      if (!isNetworkError || attempt >= maxRetries) {
        rethrow;
      }
      // 指数退避等待后重试
      await Future.delayed(Duration(seconds: baseDelaySeconds * (attempt + 1)));
    }
  }
  throw Exception('retryOnNetworkError: 不应到达此处');
}
