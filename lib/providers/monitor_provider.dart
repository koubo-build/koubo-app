import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/monitor_service.dart';

/// 监控台页面状态
class MonitorState {
  /// 模型列表
  final List<ModelStatus> models;

  /// 日志列表
  final List<String> logs;

  /// 是否正在加载
  final bool isLoading;

  /// 是否自动刷新
  final bool autoRefresh;

  /// 错误信息
  final String? errorMessage;

  const MonitorState({
    this.models = const [],
    this.logs = const [],
    this.isLoading = false,
    this.autoRefresh = false,
    this.errorMessage,
  });

  MonitorState copyWith({
    List<ModelStatus>? models,
    List<String>? logs,
    bool? isLoading,
    bool? autoRefresh,
    String? errorMessage,
    bool clearError = false,
  }) {
    return MonitorState(
      models: models ?? this.models,
      logs: logs ?? this.logs,
      isLoading: isLoading ?? this.isLoading,
      autoRefresh: autoRefresh ?? this.autoRefresh,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// 运行中模型数量
  int get runningCount => models.where((m) => m.status == 'running').length;

  /// 异常模型数量
  int get errorCount => models.where((m) => m.status == 'error').length;
}

/// 监控台状态管理
class MonitorNotifier extends ChangeNotifier {
  final MonitorService _monitorService;

  MonitorState _state = const MonitorState();
  MonitorState get state => _state;

  Timer? _refreshTimer;

  MonitorNotifier(this._monitorService);

  /// 初始化加载数据
  Future<void> init() async {
    await refreshStatus();
  }

  /// 刷新模型状态和日志
  Future<void> refreshStatus() async {
    _state = _state.copyWith(isLoading: true, clearError: true);
    notifyListeners();

    try {
      final results = await Future.wait([
        _monitorService.getModelsStatus(),
        _monitorService.getLogs(),
      ]);

      _state = _state.copyWith(
        models: results[0] as List<ModelStatus>,
        logs: results[1] as List<String>,
        isLoading: false,
      );
    } catch (e) {
      _state = _state.copyWith(
        isLoading: false,
        errorMessage: '刷新状态失败：$e',
      );
    }
    notifyListeners();
  }

  /// 重启指定模型
  Future<void> restartModel(String name) async {
    try {
      await _monitorService.restartModel(name);
      // 重启后刷新状态
      await refreshStatus();
    } catch (e) {
      _state = _state.copyWith(errorMessage: '重启 $name 失败：$e');
      notifyListeners();
    }
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

  /// 启动自动刷新定时器（5秒）
  void _startAutoRefresh() {
    _stopAutoRefresh();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      refreshStatus();
    });
  }

  /// 停止自动刷新
  void _stopAutoRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }

  /// 清除错误
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
