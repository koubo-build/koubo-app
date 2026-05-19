import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/audit_result.dart';
import '../services/legal_audit_service.dart';

/// 审核状态管理 Provider
/// 管理法务合规审核的过程和结果状态

/// 审核状态
class AuditState {
  final String text;                        // 待审核文案
  final AuditResult? result;                // 审核结果
  final bool isKeywordLoading;              // 关键词过滤中
  final bool isLlmLoading;                  // 大模型审核中
  final String? error;                      // 错误信息
  final String? fixedText;                  // 一键修正后的文案
  final bool isFixing;                      // 正在修正

  const AuditState({
    this.text = '',
    this.result,
    this.isKeywordLoading = false,
    this.isLlmLoading = false,
    this.error,
    this.fixedText,
    this.isFixing = false,
  });

  bool get isLoading => isKeywordLoading || isLlmLoading;

  AuditState copyWith({
    String? text,
    AuditResult? result,
    bool? isKeywordLoading,
    bool? isLlmLoading,
    String? error,
    String? fixedText,
    bool? isFixing,
  }) {
    return AuditState(
      text: text ?? this.text,
      result: result ?? this.result,
      isKeywordLoading: isKeywordLoading ?? this.isKeywordLoading,
      isLlmLoading: isLlmLoading ?? this.isLlmLoading,
      error: error,
      fixedText: fixedText,
      isFixing: isFixing ?? this.isFixing,
    );
  }
}

/// 审核状态Notifier
class AuditNotifier extends StateNotifier<AuditState> {
  final LegalAuditService _auditService;

  AuditNotifier(this._auditService) : super(const AuditState());

  /// 设置待审核文案
  void setText(String text) {
    state = state.copyWith(text: text);
  }

  /// 开始双重审核
  Future<void> startAudit({String? industry}) async {
    if (state.text.isEmpty) return;

    state = state.copyWith(
      isKeywordLoading: true,
      isLlmLoading: true,
      error: null,
    );

    try {
      // 执行双重审核
      final result = await _auditService.audit(
        text: state.text,
        auditType: '原始文案',
        industry: industry,
      );

      state = state.copyWith(
        result: result,
        isKeywordLoading: false,
        isLlmLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isKeywordLoading: false,
        isLlmLoading: false,
        error: e.toString(),
      );
    }
  }

  /// 快速审核（仅关键词过滤）
  void quickAudit() {
    if (state.text.isEmpty) return;
    final issues = _auditService.quickAudit(state.text);
    final riskLevel = issues.isEmpty
        ? '安全'
        : issues.any((i) => i.riskLevel == '高风险')
            ? '高风险'
            : issues.any((i) => i.riskLevel == '中风险')
                ? '中风险'
                : '低风险';

    state = state.copyWith(
      result: AuditResult(
        auditType: '快速审核',
        riskLevel: riskLevel,
        issues: issues,
        overallAssessment: '关键词快速过滤结果，建议进行大模型深度审核',
        safeToPublish: riskLevel == '安全' || riskLevel == '低风险',
        createdAt: DateTime.now(),
      ),
    );
  }

  /// 一键修正
  Future<void> autoFix() async {
    if (state.result == null) return;

    state = state.copyWith(isFixing: true);
    try {
      final fixResult = await _auditService.autoFix(
        state.text,
        state.result!.issues,
      );
      state = state.copyWith(
        fixedText: fixResult['fixed_text'] as String,
        isFixing: false,
      );
    } catch (e) {
      state = state.copyWith(
        isFixing: false,
        error: '修正失败：$e',
      );
    }
  }

  /// 一键修正并复审
  Future<void> autoFixAndReAudit() async {
    if (state.result == null) return;

    state = state.copyWith(isFixing: true);
    try {
      final result = await _auditService.autoFixAndReAudit(
        state.text,
        state.result!.issues,
        state.result!.auditType,
      );
      state = state.copyWith(
        result: result,
        isFixing: false,
      );
    } catch (e) {
      state = state.copyWith(
        isFixing: false,
        error: '修正复审失败：$e',
      );
    }
  }

  /// 获取规避词列表
  List<String> getAvoidWords() {
    if (state.result == null) return [];
    return _auditService.getAvoidWords(state.result!.issues);
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(error: null);
  }

  /// 重置状态
  void reset() {
    state = const AuditState();
  }
}

/// 审核Provider
final auditProvider = StateNotifierProvider<AuditNotifier, AuditState>((ref) {
  return AuditNotifier(ref.read(legalAuditServiceProvider));
});
