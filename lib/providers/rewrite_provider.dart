import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/rewrite_version.dart';
import '../services/ai_rewrite_service.dart';

/// 改写状态管理 Provider
/// 管理AI改写的过程和结果状态

/// 改写状态
class RewriteState {
  final String sourceText;            // 原始文案
  final String? selectedMode;          // 选中的改写模式
  final String? selectedStyle;         // 选中的风格
  final int? targetLength;             // 目标字数
  final List<RewriteVersion> versions; // 改写版本列表
  final bool isLoading;                // 是否正在改写
  final String? error;                 // 错误信息
  final String? streamingText;         // 流式输出的当前文本

  const RewriteState({
    this.sourceText = '',
    this.selectedMode,
    this.selectedStyle,
    this.targetLength,
    this.versions = const [],
    this.isLoading = false,
    this.error,
    this.streamingText,
  });

  RewriteState copyWith({
    String? sourceText,
    String? selectedMode,
    String? selectedStyle,
    int? targetLength,
    List<RewriteVersion>? versions,
    bool? isLoading,
    String? error,
    String? streamingText,
  }) {
    return RewriteState(
      sourceText: sourceText ?? this.sourceText,
      selectedMode: selectedMode ?? this.selectedMode,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      targetLength: targetLength ?? this.targetLength,
      versions: versions ?? this.versions,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      streamingText: streamingText,
    );
  }

  /// 获取选中的版本
  RewriteVersion? get selectedVersion =>
      versions.where((v) => v.isSelected).firstOrNull;

  /// 获取最高分版本
  RewriteVersion? get bestVersion =>
      versions.isEmpty ? null : versions.reduce((a, b) => a.score > b.score ? a : b);
}

/// 改写状态Notifier
class RewriteNotifier extends StateNotifier<RewriteState> {
  final AiRewriteService _rewriteService;

  RewriteNotifier(this._rewriteService) : super(const RewriteState());

  /// 设置原始文案
  void setSourceText(String text) {
    state = state.copyWith(sourceText: text);
  }

  /// 选择改写模式
  void selectMode(String mode) {
    state = state.copyWith(selectedMode: mode);
  }

  /// 选择风格
  void selectStyle(String style) {
    state = state.copyWith(selectedStyle: style);
  }

  /// 设置目标字数
  void setTargetLength(int length) {
    state = state.copyWith(targetLength: length);
  }

  /// 开始改写
  Future<void> startRewrite() async {
    if (state.sourceText.isEmpty || state.selectedMode == null) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final versions = await _rewriteService.rewrite(
        sourceText: state.sourceText,
        mode: state.selectedMode!,
        style: state.selectedStyle,
        targetLength: state.targetLength,
      );
      state = state.copyWith(versions: versions, isLoading: false);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 选择某个版本
  void selectVersion(int versionNumber) {
    final updatedVersions = state.versions.map((v) {
      return RewriteVersion(
        id: v.id,
        scriptId: v.scriptId,
        versionNumber: v.versionNumber,
        rewrittenText: v.rewrittenText,
        score: v.score,
        scoreDetails: v.scoreDetails,
        similarity: v.similarity,
        isSelected: v.versionNumber == versionNumber,
        createdAt: v.createdAt,
      );
    }).toList();
    state = state.copyWith(versions: updatedVersions);
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 重置状态
  void reset() {
    state = const RewriteState();
  }
}

/// 改写Provider
final rewriteProvider = StateNotifierProvider<RewriteNotifier, RewriteState>((ref) {
  return RewriteNotifier(ref.read(aiRewriteServiceProvider));
});
