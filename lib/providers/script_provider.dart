import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';
import '../services/api_client.dart';
import '../services/douyin_service.dart';

/// 文案状态管理 Provider
/// 管理文案的提取、编辑、存储等状态

/// 当前文案状态
class ScriptState {
  final Script? currentScript;
  final bool isLoading;
  final String? error;
  final List<Script> history;

  const ScriptState({
    this.currentScript,
    this.isLoading = false,
    this.error,
    this.history = const [],
  });

  ScriptState copyWith({
    Script? currentScript,
    bool? isLoading,
    String? error,
    List<Script>? history,
  }) {
    return ScriptState(
      currentScript: currentScript ?? this.currentScript,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      history: history ?? this.history,
    );
  }
}

/// 文案状态Notifier
class ScriptNotifier extends StateNotifier<ScriptState> {
  final DouyinService _douyinService;

  ScriptNotifier(this._douyinService) : super(const ScriptState());

  /// 从抖音链接提取文案
  Future<void> extractFromUrl(String url) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final text = await _douyinService.extractScript(url);
      final script = Script(
        sourceUrl: url,
        sourceText: text,
        createdAt: DateTime.now(),
      );
      state = state.copyWith(
        currentScript: script,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 设置当前文案
  void setCurrentScript(Script script) {
    state = state.copyWith(currentScript: script);
  }

  /// 手动输入文案
  void setSourceText(String text) {
    final script = state.currentScript?.copyWith(
      sourceText: text,
      updatedAt: DateTime.now(),
    ) ?? Script(sourceText: text, createdAt: DateTime.now());
    state = state.copyWith(currentScript: script);
  }

  /// 更新改写后的文案
  void setRewrittenText(String text) {
    if (state.currentScript != null) {
      final updated = state.currentScript!.copyWith(
        rewrittenText: text,
        updatedAt: DateTime.now(),
      );
      state = state.copyWith(currentScript: updated);
    }
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(error: null);
  }
}

/// 文案Provider
final scriptProvider = StateNotifierProvider<ScriptNotifier, ScriptState>((ref) {
  return ScriptNotifier(ref.read(douyinServiceProvider));
});
