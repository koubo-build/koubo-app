import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';

/// 实时语音识别服务（fun-asr-realtime WebSocket）
/// 阿里百炼 Fun-ASR-Realtime 模型，WebSocket 双向流式音频识别
/// - 端点：wss://dashscope.aliyuncs.com/api-ws/v1/inference（北京地域）
/// - 音频格式：16kHz PCM mono，每100ms发送一块
/// - 支持：16种方言、30种语言、中英日混合
class AsrRealtimeService {
  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  bool _isRunning = false;
  bool _taskStarted = false;

  // 识别结果回调
  final void Function(String text, bool isFinal) onResult;

  // 状态回调
  final void Function(String status)? onStatus;

  // 错误回调
  final void Function(String error)? onError;

  AsrRealtimeService({
    required this.onResult,
    this.onStatus,
    this.onError,
  });

  /// 启动实时识别会话
  Future<bool> start({
    String format = 'pcm',
    int sampleRate = 16000,
    List<String>? languageHints,
  }) async {
    if (_isRunning) return true;

    final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      _emitError('请先在设置中配置阿里百炼API Key');
      return false;
    }

    try {
      _isRunning = true;
      _taskStarted = false;

      // 1. 建立 WebSocket 连接
      _emitStatus('连接识别服务...');
      _channel = IOWebSocketChannel.connect(
        Uri.parse(ApiConfig.aliAsrRealtimeWsUrl),
        headers: {
          'Authorization': 'Bearer $apiKey',
        },
        pingInterval: const Duration(seconds: 30),
      );

      // 2. 监听服务端事件
      _subscription = _channel!.stream.listen(
        _onMessage,
        onError: (e) {
          _emitError('WebSocket错误：$e');
          stop();
        },
        onDone: () {
          if (_isRunning) {
            _emitStatus('连接已关闭');
            _isRunning = false;
          }
        },
        cancelOnError: true,
      );

      // 3. 发送 run-task 指令启动识别任务
      _emitStatus('启动识别任务...');
      _sendRunTask(format: format, sampleRate: sampleRate, languageHints: languageHints);

      return true;
    } catch (e) {
      _isRunning = false;
      _emitError('启动失败：$e');
      return false;
    }
  }

  /// 发送音频帧（建议每 100ms 一次，每次 1-16KB）
  void sendAudioFrame(List<int> audioData) {
    if (!_isRunning || _channel == null) return;
    if (!_taskStarted) {
      // 任务未启动，丢弃早期帧
      return;
    }
    try {
      _channel!.sink.add(audioData);
    } catch (e) {
      if (kDebugMode) print('发送音频帧失败：$e');
    }
  }

  /// 停止识别会话
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    try {
      if (_channel != null && _taskStarted) {
        // 发送 finish-task 指令
        final finishMsg = {
          'header': {
            'action': 'finish-task',
            'task_id': _taskId,
            'streaming': 'duplex',
          },
          'payload': {'input': {}},
        };
        _channel!.sink.add(jsonEncode(finishMsg));
        // 给服务端一点时间处理最后的识别结果
        await Future.delayed(const Duration(milliseconds: 500));
      }
    } catch (_) {}

    await _subscription?.cancel();
    _subscription = null;
    try {
      await _channel?.sink.close();
    } catch (_) {}
    _channel = null;
    _taskStarted = false;
    _emitStatus('已停止');
  }

  // ==================== 内部方法 ====================

  String _taskId = '';

  void _sendRunTask({
    required String format,
    required int sampleRate,
    List<String>? languageHints,
  }) {
    // 生成 32 位随机 ID
    _taskId = _generateTaskId();

    final runTaskMsg = {
      'header': {
        'action': 'run-task',
        'task_id': _taskId,
        'streaming': 'duplex',
      },
      'payload': {
        'task_group': 'audio',
        'task': 'asr',
        'function': 'recognition',
        'model': 'fun-asr-realtime',
        'parameters': {
          'format': format,
          'sample_rate': sampleRate,
          if (languageHints != null && languageHints.isNotEmpty)
            'language_hints': languageHints,
        },
        'input': {},
      },
    };
    _channel!.sink.add(jsonEncode(runTaskMsg));
  }

  void _onMessage(dynamic data) {
    try {
      final message = data is String ? jsonDecode(data) as Map<String, dynamic> : null;
      if (message == null) return;

      final header = message['header'] as Map<String, dynamic>?;
      final event = header?['event'] as String?;

      switch (event) {
        case 'task-started':
          _taskStarted = true;
          _emitStatus('识别中...');
          break;
        case 'result-generated':
          final payload = message['payload'] as Map<String, dynamic>?;
          final output = payload?['output'] as Map<String, dynamic>?;
          final sentence = output?['sentence'] as Map<String, dynamic>?;
          final text = sentence?['text'] as String?;
          if (text != null && text.isNotEmpty) {
            // sentence_end=true 表示一句话结束
            final isFinal = sentence?['sentence_end'] == true;
            onResult(text, isFinal);
          }
          break;
        case 'task-finished':
          _emitStatus('识别完成');
          stop();
          break;
        case 'task-failed':
          final errMsg = header?['error_message'] as String? ?? '未知错误';
          _emitError('识别失败：$errMsg');
          stop();
          break;
        default:
          if (kDebugMode) print('未知事件：$event');
      }
    } catch (e) {
      if (kDebugMode) print('解析消息失败：$e');
    }
  }

  String _generateTaskId() {
    // 简单 UUID 生成（去掉横线，取前 32 位）
    final now = DateTime.now().millisecondsSinceEpoch.toString();
    final rand = (now.hashCode ^ now).toString().replaceAll('-', '');
    return (now + rand).padRight(32, '0').substring(0, 32);
  }

  void _emitStatus(String s) {
    onStatus?.call(s);
    if (kDebugMode) print('[ASR-Realtime] $s');
  }

  void _emitError(String e) {
    onError?.call(e);
    if (kDebugMode) print('[ASR-Realtime ERROR] $e');
  }

  bool get isRunning => _isRunning;
}
