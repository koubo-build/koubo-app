import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// 功能服务状态
class ServiceStatus {
  final String id;          // 功能标识
  final String name;        // 功能名称
  final String icon;        // emoji图标
  final String description; // 功能描述
  final String status;      // available / unconfigured / error / checking
  final String? detail;     // 状态详情
  final int latencyMs;      // 响应延迟(ms)
  final DateTime lastCheck; // 最后检测时间

  const ServiceStatus({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.status,
    this.detail,
    this.latencyMs = 0,
    required this.lastCheck,
  });

  ServiceStatus copyWith({
    String? status,
    String? detail,
    int? latencyMs,
  }) {
    return ServiceStatus(
      id: id,
      name: name,
      icon: icon,
      description: description,
      status: status ?? this.status,
      detail: detail ?? this.detail,
      latencyMs: latencyMs ?? this.latencyMs,
      lastCheck: DateTime.now(),
    );
  }
}

/// API Key配置信息
class ApiKeyInfo {
  final String keyName;      // 存储键名
  final String displayName;  // 显示名
  final String usedFor;      // 用于什么功能
  final bool configured;     // 是否已配置
  final bool required;       // 是否必需（至少配一个）

  const ApiKeyInfo({
    required this.keyName,
    required this.displayName,
    required this.usedFor,
    required this.configured,
    this.required = false,
  });
}

/// 监控服务 - 真实检测App各功能可用性
/// 不再使用模拟数据，直接检查API Key配置和接口可用性
class MonitorService {
  final ApiClient _apiClient;

  MonitorService(this._apiClient);

  /// 检测所有功能服务状态
  Future<List<ServiceStatus>> checkAllServices() async {
    final now = DateTime.now();

    // 先快速读取所有Key配置状态
    final aliKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    final zhipuKey = await StorageUtil.getSecure(ApiConfig.zhipuApiKeyKey);
    final sfKey = await StorageUtil.getSecure(ApiConfig.siliconFlowApiKeyKey);
    final tikhubKey = await StorageUtil.getSecure(ApiConfig.tikhubApiKeyKey);

    final hasAliKey = aliKey != null && aliKey.isNotEmpty;
    final hasZhipuKey = zhipuKey != null && zhipuKey.isNotEmpty;
    final hasSfKey = sfKey != null && sfKey.isNotEmpty;
    final hasTikhubKey = tikhubKey != null && tikhubKey.isNotEmpty;
    final hasAnyAiKey = hasAliKey || hasZhipuKey || hasSfKey;

    final results = <ServiceStatus>[];

    // 1. AI改写/审核 - 实际调用chatSmart验证（任一AI Key可用即可）
    if (hasAnyAiKey) {
      final providers = <String>[
        if (hasAliKey) '阿里百炼',
        if (hasZhipuKey) '智谱AI',
        if (hasSfKey) '硅基流动',
      ];
      try {
        final sw = Stopwatch()..start();
        await _apiClient.chatSmart(
          messages: [
            {'role': 'user', 'content': '你好'}
          ],
          temperature: 0.1,
        );
        sw.stop();
        results.add(ServiceStatus(
          id: 'ai',
          name: 'AI改写/审核',
          icon: '🤖',
          description: '改写文案、法务审核、质量评分',
          status: 'available',
          detail: '可用: ${providers.join("、")}',
          latencyMs: sw.elapsedMilliseconds,
          lastCheck: now,
        ));
      } catch (e) {
        final msg = e.toString().replaceAll('Exception: ', '');
        results.add(ServiceStatus(
          id: 'ai',
          name: 'AI改写/审核',
          icon: '🤖',
          description: '改写文案、法务审核、质量评分',
          status: 'error',
          detail: msg.length > 60 ? '${msg.substring(0, 60)}...' : msg,
          lastCheck: now,
        ));
      }
    } else {
      results.add(ServiceStatus(
        id: 'ai',
        name: 'AI改写/审核',
        icon: '🤖',
        description: '改写文案、法务审核、质量评分',
        status: 'unconfigured',
        detail: '请配置至少一个AI Key（阿里百炼/智谱/硅基流动）',
        lastCheck: now,
      ));
    }

    // 2. 语音合成 - 需要阿里百炼Key
    results.add(ServiceStatus(
      id: 'tts',
      name: '语音合成',
      icon: '🔊',
      description: 'CosyVoice系统音色配音',
      status: hasAliKey ? 'available' : 'unconfigured',
      detail: hasAliKey ? '阿里百炼Key已配置' : '需要配置阿里百炼API Key',
      lastCheck: now,
    ));

    // 3. 声音克隆 - 需要阿里百炼Key
    results.add(ServiceStatus(
      id: 'voice_clone',
      name: '声音克隆',
      icon: '🎤',
      description: '录制声音克隆+克隆音色合成',
      status: hasAliKey ? 'available' : 'unconfigured',
      detail: hasAliKey ? '阿里百炼Key已配置' : '需要配置阿里百炼API Key',
      lastCheck: now,
    ));

    // 4. 抖音解析 - 需要TikHub Key
    results.add(ServiceStatus(
      id: 'tikhub',
      name: '抖音解析',
      icon: '🎬',
      description: '抖音分享口令视频解析',
      status: hasTikhubKey ? 'available' : 'unconfigured',
      detail: hasTikhubKey ? 'TikHub Key已配置' : '需要配置TikHub API Key',
      lastCheck: now,
    ));

    return results;
  }

  /// 获取所有API Key配置状态
  Future<List<ApiKeyInfo>> getApiKeyInfo() async {
    final keys = [
      (
        ApiConfig.aliBailianApiKeyKey,
        '阿里百炼',
        '改写/审核/语音/克隆',
        true,
      ),
      (
        ApiConfig.zhipuApiKeyKey,
        '智谱AI',
        '改写/审核(免费)',
        false,
      ),
      (
        ApiConfig.siliconFlowApiKeyKey,
        '硅基流动',
        '改写/审核(免费)',
        false,
      ),
      (
        ApiConfig.tikhubApiKeyKey,
        'TikHub',
        '抖音视频解析',
        false,
      ),
    ];

    final results = <ApiKeyInfo>[];
    for (final (keyName, displayName, usedFor, required) in keys) {
      final value = await StorageUtil.getSecure(keyName);
      results.add(ApiKeyInfo(
        keyName: keyName,
        displayName: displayName,
        usedFor: usedFor,
        configured: value != null && value.isNotEmpty,
        required: required,
      ));
    }
    return results;
  }
}

/// MonitorService Provider
final monitorServiceProvider = Provider<MonitorService>((ref) {
  return MonitorService(ref.read(apiClientProvider));
});
