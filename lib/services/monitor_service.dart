import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import '../utils/storage_util.dart';

/// 模型运行状态
class ModelStatus {
  final String name;
  final String status; // running / stopped / error
  final int latencyMs;
  final DateTime lastCheck;

  const ModelStatus({
    required this.name,
    required this.status,
    this.latencyMs = 0,
    required this.lastCheck,
  });

  ModelStatus copyWith({
    String? name,
    String? status,
    int? latencyMs,
    DateTime? lastCheck,
  }) {
    return ModelStatus(
      name: name ?? this.name,
      status: status ?? this.status,
      latencyMs: latencyMs ?? this.latencyMs,
      lastCheck: lastCheck ?? this.lastCheck,
    );
  }
}

/// 监控服务 - 模型状态查询、重启、日志
class MonitorService {
  final ApiClient _apiClient;

  MonitorService(this._apiClient);

  /// 获取所有模型运行状态
  Future<List<ModelStatus>> getModelsStatus() async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) {
      // 未配置后端地址时返回模拟数据
      return _getMockModelsStatus();
    }

    try {
      final response = await _apiClient.get(
        '$baseUrl/api/monitor/models/status',
      );

      final data = response.data as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.map((item) {
        final m = item as Map<String, dynamic>;
        return ModelStatus(
          name: m['name'] ?? '',
          status: m['status'] ?? 'stopped',
          latencyMs: m['latency_ms'] ?? 0,
          lastCheck: DateTime.now(),
        );
      }).toList();
    } catch (e) {
      // 接口异常时返回模拟数据
      return _getMockModelsStatus();
    }
  }

  /// 重启指定模型
  Future<void> restartModel(String name) async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) {
      throw Exception('请先在设置页配置后端地址');
    }

    try {
      await _apiClient.post(
        '$baseUrl/api/monitor/models/restart',
        data: {'name': name},
      );
    } catch (e) {
      throw Exception('重启模型失败：$e');
    }
  }

  /// 获取最近日志
  Future<List<String>> getLogs() async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) {
      return _getMockLogs();
    }

    try {
      final response = await _apiClient.get(
        '$baseUrl/api/monitor/logs',
      );

      final data = response.data as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.map((item) => item.toString()).toList();
    } catch (e) {
      return _getMockLogs();
    }
  }

  /// 获取后端基础地址
  Future<String?> _getBackendBaseUrl() async {
    try {
      final url = StorageUtil.getString('backend_base_url');
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// 模拟模型状态数据
  List<ModelStatus> _getMockModelsStatus() {
    final now = DateTime.now();
    return [
      ModelStatus(name: 'OpenAI', status: 'running', latencyMs: 320, lastCheck: now),
      ModelStatus(name: 'Ollama', status: 'running', latencyMs: 150, lastCheck: now),
      ModelStatus(name: 'Edge-TTS', status: 'running', latencyMs: 80, lastCheck: now),
      ModelStatus(name: 'ElevenLabs', status: 'stopped', latencyMs: 0, lastCheck: now),
      ModelStatus(name: 'Wav2Lip', status: 'running', latencyMs: 450, lastCheck: now),
      ModelStatus(name: 'RVC', status: 'error', latencyMs: 0, lastCheck: now),
      ModelStatus(name: '飞影API', status: 'running', latencyMs: 280, lastCheck: now),
      ModelStatus(name: 'Pexels API', status: 'running', latencyMs: 200, lastCheck: now),
    ];
  }

  /// 模拟日志数据
  List<String> _getMockLogs() {
    final now = DateTime.now();
    final fmt = (DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:${t.second.toString().padLeft(2, '0')}';
    return [
      '[${fmt(now)}] OpenAI GPT-4o 响应正常，延迟 320ms',
      '[${fmt(now.subtract(const Duration(seconds: 5)))}] Ollama LLaMA3 模型加载完成',
      '[${fmt(now.subtract(const Duration(seconds: 10)))}] Edge-TTS 合成完成，耗时 1.2s',
      '[${fmt(now.subtract(const Duration(seconds: 15)))}] ElevenLabs API 连接超时',
      '[${fmt(now.subtract(const Duration(seconds: 20)))}] Wav2Lip 渲染队列: 3 个任务',
      '[${fmt(now.subtract(const Duration(seconds: 25)))}] RVC 声音克隆服务异常退出',
      '[${fmt(now.subtract(const Duration(seconds: 30)))}] 飞影API 创建视频任务成功',
      '[${fmt(now.subtract(const Duration(seconds: 35)))}] Pexels 搜索返回 12 个结果',
      '[${fmt(now.subtract(const Duration(seconds: 40)))}] 系统健康检查通过',
      '[${fmt(now.subtract(const Duration(seconds: 45)))}] OpenAI 请求频率: 15 req/min',
      '[${fmt(now.subtract(const Duration(seconds: 50)))}] Ollama GPU 显存占用: 6.2GB / 8GB',
      '[${fmt(now.subtract(const Duration(seconds: 55)))}] Edge-TTS 音色切换: 晓晓 -> 云健',
      '[${fmt(now.subtract(const Duration(seconds: 60)))}] Wav2Lip 视频渲染完成，分辨率 1080p',
      '[${fmt(now.subtract(const Duration(seconds: 65)))}] 飞影API 轮询状态: 处理中 (60%)',
      '[${fmt(now.subtract(const Duration(seconds: 70)))}] 系统内存占用: 12.3GB / 16GB',
    ];
  }
}

/// MonitorService的Riverpod Provider
final monitorServiceProvider = Provider<MonitorService>((ref) {
  return MonitorService(ref.read(apiClientProvider));
});
