import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/ip_auto_package.dart';
import '../services/ip_auto_service.dart';

/// IP口播全自动生成 - 页面状态
class IpAutoState {
  /// 行业关键词输入
  final String keyword;

  /// 参考文案/复刻指令输入
  final String referenceText;

  /// 选题卡片列表
  final List<TopicCard> topics;

  /// 是否正在生成选题卡片
  final bool loadingTopics;

  /// 是否正在执行全自动一条龙
  final bool generating;

  /// 全自动生成产物
  final IpAutoPackage? package;

  /// 当前进度提示文案
  final String statusText;

  /// 错误信息
  final String? error;

  /// 当前选择的模型
  final String selectedModel;

  const IpAutoState({
    this.keyword = '',
    this.referenceText = '',
    this.topics = const [],
    this.loadingTopics = false,
    this.generating = false,
    this.package,
    this.statusText = '',
    this.error,
    this.selectedModel = '自动选择',
  });

  IpAutoState copyWith({
    String? keyword,
    String? referenceText,
    List<TopicCard>? topics,
    bool? loadingTopics,
    bool? generating,
    IpAutoPackage? package,
    String? statusText,
    String? error,
    String? selectedModel,
  }) {
    return IpAutoState(
      keyword: keyword ?? this.keyword,
      referenceText: referenceText ?? this.referenceText,
      topics: topics ?? this.topics,
      loadingTopics: loadingTopics ?? this.loadingTopics,
      generating: generating ?? this.generating,
      package: package ?? this.package,
      statusText: statusText ?? this.statusText,
      error: error,
      selectedModel: selectedModel ?? this.selectedModel,
    );
  }
}

/// IP口播全自动状态 Notifier
class IpAutoNotifier extends StateNotifier<IpAutoState> {
  final IpAutoService _service;

  IpAutoNotifier(this._service) : super(const IpAutoState()) {
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final model = await _service.getSelectedModel();
      state = state.copyWith(selectedModel: model);
    } catch (_) {}
  }

  void setKeyword(String v) => state = state.copyWith(keyword: v);
  void setReferenceText(String v) =>
      state = state.copyWith(referenceText: v);

  /// 切换模型并持久化
  Future<void> changeModel(String value) async {
    state = state.copyWith(selectedModel: value);
    await _service.setSelectedModel(value);
  }

  /// 步骤1：根据行业关键词生成5条选题卡片
  Future<void> loadTopics() async {
    final kw = state.keyword.trim();
    if (kw.isEmpty || state.loadingTopics) return;
    state = state.copyWith(
      loadingTopics: true,
      error: null,
      statusText: '正在检索高流量痛点选题…',
    );
    try {
      final cards = await _service.generateTopicCards(kw);
      state = state.copyWith(
        topics: cards,
        loadingTopics: false,
        statusText: '已生成 ${cards.length} 条选题，点【复刻它】开始全自动',
      );
    } catch (e) {
      state = state.copyWith(
        loadingTopics: false,
        statusText: '',
        error: _friendlyError(e),
      );
    }
  }

  /// 步骤2：点【复刻它】，用复刻指令触发全自动一条龙
  Future<void> replicate(String command) async {
    await _runFullPackage(input: command, mode: 'replicate');
  }

  /// 直接用关键词/选题全自动（不经过卡片）
  Future<void> generateFromKeyword() async {
    final kw = state.keyword.trim();
    if (kw.isEmpty) return;
    await _runFullPackage(input: kw, mode: 'keyword');
  }

  /// 用粘贴的参考文案提取框架并全自动
  Future<void> generateFromReference() async {
    final ref = state.referenceText.trim();
    if (ref.isEmpty) return;
    await _runFullPackage(input: ref, mode: 'reference');
  }

  Future<void> _runFullPackage({
    required String input,
    required String mode,
  }) async {
    if (state.generating) return;
    state = state.copyWith(
      generating: true,
      error: null,
      package: null,
      statusText: '自动模式：正在生成脚本→字幕→动效→BGM→封面→发布文案…',
    );
    try {
      final pkg = await _service.generateFullPackage(input: input, mode: mode);
      state = state.copyWith(
        generating: false,
        package: pkg,
        statusText: '已完成全套创作包，可逐张复制使用',
      );
    } catch (e) {
      state = state.copyWith(
        generating: false,
        statusText: '',
        error: _friendlyError(e),
      );
    }
  }

  /// 清空当前结果
  void clearResult() {
    state = state.copyWith(package: null, statusText: '', error: null);
  }

  String _friendlyError(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    if (msg.contains('所有AI服务均不可用') || msg.contains('未配置')) {
      return '$msg\n可到「设置」检查API Key，或把模型切到「自动选择」。';
    }
    return msg;
  }
}

/// 页面级 StateNotifierProvider
final ipAutoProvider =
    StateNotifierProvider<IpAutoNotifier, IpAutoState>((ref) {
  return IpAutoNotifier(ref.read(ipAutoServiceProvider));
});
