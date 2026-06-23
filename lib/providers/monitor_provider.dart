import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/monitor_service.dart';

/// 监控台页面状态
class MonitorState {
  /// 功能服务列表
  final List<ServiceStatus> services;

  /// API Key配置列表
  final List<ApiKeyInfo> apiKeys;

  /// 是否正在加载
  final bool isLoading;

  /// 是否自动刷新
  final bool autoRefresh;

  /// 错误信息
  final String? errorMessage;

  const MonitorState({
    this.services = const [],
    this.apiKeys = const [],
    this.isLoading = false,
    this.autoRefresh = false,
    this.errorMessage,
  });

  MonitorState copyWith({
    List<ServiceStatus>? services,
    List<ApiKeyInfo>? apiKeys,
    bool? isLoading,
    bool? autoRefresh,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MonitorState(
      services: services ?? this.services,
      apiKeys: apiKeys ?? this.apiKeys,
      isLoading: isLoading ?? this.isLoading,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// 可用功能数量
  int get availableCount =>
      services.where((s) => s.status == 'available').length;

  /// 未配置功能数量
  int get unconfiguredCount =>
      services.where((s) => s.status == 'unconfigured').length;

  /// 异常功能数量
  int get errorCount => services.where((s) => s.status == 'error').length;

  /// 已配置Key数量
  int get configuredKeyCount =>
      apiKeys.where((k) => k.configured).length;
}

/// 监控台状态管理
class MonitorNotifier extends ChangeNotifier {
  final MonitorService _monitorService;

  MonitorState _state = const MonitorState();
  MonitorState get state => _state;

  // 便捷getter
  List<ServiceStatus> get services => _state.services;
  List<ApiKeyInfo> get apiKeys => _state.apiKeys;
  bool get isLoading => _state.isLoading;
  bool get autoRefresh => _state.autoRefresh;
  int get availableCount => _state.availableCount;
  int get unconfiguredCount => _state.unconfiguredCount;
  int get errorCount => _state.errorCount;
  String? get errorMessage => _state.errorMessage;

  Timer? _refreshTimer;

  MonitorNotifier(this._monitorService);

  /// 初始化加载数据
  Future<void> init() async {
    await refreshStatus();
  }

  /// 刷新所有状态
  Future<void> refreshStatus() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();

    try {
      final results = await Future.wait([
        _monitorService.checkAllServices(),
        _monitorService.getApiKeyInfo(),
      ]);

      _state = _state.copyWith(
        services: results[0] as List<ServiceStatus>,
        apiKeys: results[1] as List<ApiKeyInfo>,
        isLoading: false,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '检测失败：$e',
      );
    }
    notifyListeners();
  }

  /// 切换自动刷新
  void toggleAutoRefresh() {
    final newValue = !_state.autoRefresh;
    _state = _state.copyWith(autoRefresh: newValue);
    notifyListeners();

    if (newValue) {
      _startAutoRefresh();
    } else {
      _stopAutoRefresh();
    }
  }

  /// 自动刷新间隔改为30秒（检测API调用较重，不宜太频繁）
  void _startAutoRefresh() {
    _stopAutoRefresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshStatus();
    });
  }

  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  void clearError() {
    _state = _state.copyWith(clearError: true);
    notifyListeners();
  }

  @override
  void dispose() {
    _stopAutoRefresh();
    super.dispose();
  }
}

/// Monitor Provider
final monitorProvider = ChangeNotifierProvider<MonitorNotifier>((ref) {
  return MonitorNotifier(ref.read(monitorServiceProvider));
});
