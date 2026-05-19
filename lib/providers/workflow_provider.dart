import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/script.dart';
import '../models/rewrite_version.dart';
import '../models/audit_result.dart';
import '../services/douyin_service.dart';
import '../services/ai_rewrite_service.dart';
import '../services/legal_audit_service.dart';
import '../services/api_client.dart';

/// 工作流步骤枚举
enum WorkflowStep {
  input,       // Step1：视频链接输入
  extracted,   // Step2：提取结果展示
  rewriting,   // Step3：AI改写
  auditing,    // Step4：法务审核
  finalized,   // Step5：定稿
}

/// 一站式创作工作流状态管理
/// 管理整个 提取→改写→审核→定稿 的流程状态
class WorkflowState {
  /// 当前步骤
  final WorkflowStep currentStep;

  /// Step1：视频链接
  final String videoUrl;
  /// 链接平台类型（抖音/快手）
  final String? platformType;

  /// Step2：提取的原文
  final String sourceText;
  /// 提取中
  final bool isExtracting;
  /// 提取错误信息
  final String? extractError;

  /// Step3：改写相关
  final String? selectedMode;          // 选中的改写模式
  final String? selectedStyle;         // 选中的风格
  final int? targetLength;             // 目标字数
  final List<RewriteVersion> versions; // 改写版本列表
  final bool isRewriting;              // 正在改写
  final String? rewriteError;          // 改写错误
  final String streamingText;          // 流式输出当前文本
  final int? selectedVersionNumber;    // 用户选中的版本号
  final int rewriteProgress;           // 改写进度（0-100）

  /// Step4：法务审核相关
  final AuditResult? auditResult;      // 审核结果
  final bool isAuditing;               // 正在审核
  final String? auditError;            // 审核错误
  final bool isFixing;                 // 正在一键修正
  final String? fixedText;             // 修正后的文案
  final AuditResult? reAuditResult;    // 复审结果
  final int auditProgress;             // 审核进度（0-100）

  /// Step5：定稿文案
  final String finalText;

  /// 步骤历史（用于回退）
  final List<WorkflowStep> stepHistory;

  /// 是否可以回退到上一步
  bool get canGoBack => currentStep != WorkflowStep.input;

  const WorkflowState({
    this.currentStep = WorkflowStep.input,
    this.videoUrl = '',
    this.platformType,
    this.sourceText = '',
    this.isExtracting = false,
    this.extractError,
    this.selectedMode,
    this.selectedStyle,
    this.targetLength,
    this.versions = const [],
    this.isRewriting = false,
    this.rewriteError,
    this.streamingText = '',
    this.selectedVersionNumber,
    this.rewriteProgress = 0,
    this.auditResult,
    this.isAuditing = false,
    this.auditError,
    this.isFixing = false,
    this.fixedText,
    this.reAuditResult,
    this.auditProgress = 0,
    this.finalText = '',
    this.stepHistory = const [],
  });

  WorkflowState copyWith({
    WorkflowStep? currentStep,
    String? videoUrl,
    String? platformType,
    bool clearPlatformType = false,
    String? sourceText,
    bool? isExtracting,
    String? extractError,
    bool clearExtractError = false,
    String? selectedMode,
    String? selectedStyle,
    bool clearSelectedStyle = false,
    int? targetLength,
    List<RewriteVersion>? versions,
    bool? isRewriting,
    String? rewriteError,
    bool clearRewriteError = false,
    String? streamingText,
    int? selectedVersionNumber,
    bool clearSelectedVersionNumber = false,
    int? rewriteProgress,
    AuditResult? auditResult,
    bool clearAuditResult = false,
    bool? isAuditing,
    String? auditError,
    bool clearAuditError = false,
    bool? isFixing,
    String? fixedText,
    bool clearFixedText = false,
    AuditResult? reAuditResult,
    bool clearReAuditResult = false,
    int? auditProgress,
    String? finalText,
    List<WorkflowStep>? stepHistory,
  }) {
    return WorkflowState(
      currentStep: currentStep ?? this.currentStep,
      videoUrl: videoUrl ?? this.videoUrl,
      platformType: clearPlatformType ? null : (platformType ?? this.platformType),
      sourceText: sourceText ?? this.sourceText,
      isExtracting: isExtracting ?? this.isExtracting,
      extractError: clearExtractError ? null : (extractError ?? this.extractError),
      selectedMode: selectedMode ?? this.selectedMode,
      selectedStyle: clearSelectedStyle ? null : (selectedStyle ?? this.selectedStyle),
      targetLength: targetLength ?? this.targetLength,
      versions: versions ?? this.versions,
      isRewriting: isRewriting ?? this.isRewriting,
      rewriteError: clearRewriteError ? null : (rewriteError ?? this.rewriteError),
      streamingText: streamingText ?? this.streamingText,
      selectedVersionNumber: clearSelectedVersionNumber ? null : (selectedVersionNumber ?? this.selectedVersionNumber),
      rewriteProgress: rewriteProgress ?? this.rewriteProgress,
      auditResult: clearAuditResult ? null : (auditResult ?? this.auditResult),
      isAuditing: isAuditing ?? this.isAuditing,
      auditError: clearAuditError ? null : (auditError ?? this.auditError),
      isFixing: isFixing ?? this.isFixing,
      fixedText: clearFixedText ? null : (fixedText ?? this.fixedText),
      reAuditResult: clearReAuditResult ? null : (reAuditResult ?? this.reAuditResult),
      auditProgress: auditProgress ?? this.auditProgress,
      finalText: finalText ?? this.finalText,
      stepHistory: stepHistory ?? this.stepHistory,
    );
  }

  /// 获取选中的改写版本
  RewriteVersion? get selectedVersion {
    if (selectedVersionNumber == null) return null;
    try {
      return versions.firstWhere((v) => v.versionNumber == selectedVersionNumber);
    } catch (_) {
      return null;
    }
  }

  /// 获取当前用于审核/定稿的文案
  String get currentRewrittenText {
    if (fixedText != null && fixedText!.isNotEmpty) return fixedText!;
    if (reAuditResult != null) {
      return fixedText ?? selectedVersion?.rewrittenText ?? sourceText;
    }
    return selectedVersion?.rewrittenText ?? sourceText;
  }

  /// 获取当前有效的审核结果（复审优先）
  AuditResult? get effectiveAuditResult => reAuditResult ?? auditResult;
}

/// 工作流状态Notifier
class WorkflowNotifier extends StateNotifier<WorkflowState> {
  final DouyinService _douyinService;
  final AiRewriteService _rewriteService;
  final LegalAuditService _auditService;

  // 流式订阅取消器
  StreamSubscription? _streamSubscription;

  WorkflowNotifier(this._douyinService, this._rewriteService, this._auditService)
      : super(const WorkflowState());

  // ==================== Step1：链接输入 ====================

  /// 设置视频链接
  void setVideoUrl(String url) {
    // 自动识别平台
    final platform = _douyinService.identifyPlatform(url.trim());
    state = state.copyWith(
      videoUrl: url,
      platformType: platform,
      clearExtractError: true,
    );
  }

  // ==================== Step2：提取文案 ====================

  /// 提取文案
  Future<void> extractScript() async {
    if (state.videoUrl.trim().isEmpty) {
      state = state.copyWith(extractError: '请先粘贴视频链接');
      return;
    }

    // 验证链接格式
    if (!_douyinService.isValidUrl(state.videoUrl.trim())) {
      state = state.copyWith(extractError: '链接格式不正确，目前支持抖音和快手链接');
      return;
    }

    state = state.copyWith(isExtracting: true, clearExtractError: true);

    try {
      final text = await _douyinService.extractScript(state.videoUrl.trim());
      if (text.isEmpty) {
        state = state.copyWith(
          isExtracting: false,
          extractError: '提取结果为空，请检查链接是否正确或视频是否包含语音',
        );
        return;
      }
      state = state.copyWith(
        sourceText: text,
        isExtracting: false,
        currentStep: WorkflowStep.extracted,
        stepHistory: [...state.stepHistory, WorkflowStep.input],
      );
    } catch (e) {
      state = state.copyWith(
        isExtracting: false,
        extractError: _friendlyError(e.toString()),
      );
    }
  }

  /// 更新原文（用户手动微调）
  void updateSourceText(String text) {
    state = state.copyWith(sourceText: text);
  }

  // ==================== Step3：AI改写 ====================

  /// 选择改写模式
  void selectRewriteMode(String mode) {
    state = state.copyWith(
      selectedMode: mode,
      // 切换模式时清除风格选择（除非是风格转换）
      clearSelectedStyle: mode != '风格转换',
    );
  }

  /// 选择风格
  void selectRewriteStyle(String? style) {
    if (style == null) {
      state = state.copyWith(clearSelectedStyle: true);
    } else {
      state = state.copyWith(selectedStyle: style);
    }
  }

  /// 设置目标字数
  void setTargetLength(int length) {
    state = state.copyWith(targetLength: length);
  }

  /// 开始流式改写（先流式展示一个版本，然后并行生成其他版本）
  Future<void> startRewrite() async {
    if (state.sourceText.isEmpty || state.selectedMode == null) return;

    // 取消之前的流式订阅
    _streamSubscription?.cancel();

    state = state.copyWith(
      isRewriting: true,
      clearRewriteError: true,
      streamingText: '',
      versions: [],
      currentStep: WorkflowStep.rewriting,
      stepHistory: [...state.stepHistory, WorkflowStep.extracted],
      rewriteProgress: 10,
    );

    // 收集审核发现的风险词（如果之前有审核结果）
    List<String>? avoidWords;
    if (state.auditResult != null && state.auditResult!.issues.isNotEmpty) {
      avoidWords = _auditService.getAvoidWords(state.auditResult!.issues);
    }

    // Step1：先流式展示第一个版本
    try {
      final stream = _rewriteService.rewriteStream(
        sourceText: state.sourceText,
        mode: state.selectedMode!,
        style: state.selectedStyle,
        targetLength: state.targetLength,
        avoidWords: avoidWords,
      );

      final buffer = StringBuffer();
      _streamSubscription = stream.listen(
        (chunk) {
          buffer.write(chunk);
          state = state.copyWith(
            streamingText: buffer.toString(),
            rewriteProgress: 30, // 流式输出中，表示有进度
          );
        },
        onDone: () {
          // 流式输出完成，开始并行生成其他版本
          state = state.copyWith(rewriteProgress: 50);
          _generateRemainingVersions(buffer.toString(), avoidWords);
        },
        onError: (e) {
          state = state.copyWith(
            isRewriting: false,
            rewriteError: '改写出错：${_friendlyError(e.toString())}',
            rewriteProgress: 0,
          );
        },
        cancelOnError: true,
      );
    } catch (e) {
      state = state.copyWith(
        isRewriting: false,
        rewriteError: '改写出错：${_friendlyError(e.toString())}',
        rewriteProgress: 0,
      );
    }
  }

  /// 并行生成剩余版本（第一个版本已通过流式获得）
  Future<void> _generateRemainingVersions(
    String firstVersionText,
    List<String>? avoidWords,
  ) async {
    try {
      // 用第一个版本创建版本1
      final version1 = RewriteVersion(
        versionNumber: 1,
        rewrittenText: firstVersionText.trim(),
        score: 0,
        isSelected: true,
        createdAt: DateTime.now(),
      );

      // 并行生成版本2和版本3
      final futures = <Future<RewriteVersion>>[];
      for (int i = 2; i <= 3; i++) {
        final temperature = 0.7 + i * 0.1;
        futures.add(
          _generateSingleVersion(
            sourceText: state.sourceText,
            mode: state.selectedMode!,
            style: state.selectedStyle,
            targetLength: state.targetLength,
            versionNumber: i,
            temperature: temperature,
            avoidWords: avoidWords,
          ),
        );
      }

      final extraVersions = await Future.wait(futures);
      state = state.copyWith(rewriteProgress: 70);

      // 合并所有版本
      final allVersions = [version1, ...extraVersions];

      // 对所有版本评分
      final scoredVersions = <RewriteVersion>[];
      for (int i = 0; i < allVersions.length; i++) {
        final v = allVersions[i];
        int score = 0;
        try {
          final scoreResult = await _rewriteService.scoreVersion(
            sourceText: state.sourceText,
            rewrittenText: v.rewrittenText,
            mode: state.selectedMode!,
          );
          score = scoreResult;
        } catch (_) {
          score = 60;
        }
        scoredVersions.add(RewriteVersion(
          id: v.id,
          scriptId: v.scriptId,
          versionNumber: v.versionNumber,
          rewrittenText: v.rewrittenText,
          score: score,
          scoreDetails: v.scoreDetails,
          similarity: v.similarity,
          isSelected: v.versionNumber == 1,
          createdAt: v.createdAt,
        ));
        // 更新进度
        state = state.copyWith(rewriteProgress: 70 + ((i + 1) / allVersions.length * 30).round());
      }

      // 按评分排序
      scoredVersions.sort((a, b) => b.score.compareTo(a.score));

      state = state.copyWith(
        versions: scoredVersions,
        isRewriting: false,
        streamingText: '',
        selectedVersionNumber: scoredVersions.first.versionNumber,
        rewriteProgress: 100,
      );
    } catch (e) {
      // 即使并行生成失败，第一个版本仍然可用
      state = state.copyWith(
        versions: [
          RewriteVersion(
            versionNumber: 1,
            rewrittenText: firstVersionText.trim(),
            score: 0,
            isSelected: true,
            createdAt: DateTime.now(),
          ),
        ],
        isRewriting: false,
        streamingText: '',
        selectedVersionNumber: 1,
        rewriteProgress: 100,
      );
    }
  }

  /// 生成单个版本（内部方法）
  Future<RewriteVersion> _generateSingleVersion({
    required String sourceText,
    required String mode,
    String? style,
    int? targetLength,
    required int versionNumber,
    required double temperature,
    List<String>? avoidWords,
  }) async {
    final rewrittenText = await _rewriteService.rewriteSingle(
      sourceText: sourceText,
      mode: mode,
      style: style,
      targetLength: targetLength,
      temperature: temperature,
      avoidWords: avoidWords,
    );

    return RewriteVersion(
      versionNumber: versionNumber,
      rewrittenText: rewrittenText.trim(),
      score: 0,
      isSelected: false,
      createdAt: DateTime.now(),
    );
  }

  /// 选择某个改写版本
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
    state = state.copyWith(
      versions: updatedVersions,
      selectedVersionNumber: versionNumber,
    );
  }

  /// 确认选用改写版本，进入审核步骤
  Future<void> confirmRewriteVersion() async {
    if (state.selectedVersion == null) return;

    // 清除之前的审核结果，进入审核步骤
    state = state.copyWith(
      currentStep: WorkflowStep.auditing,
      stepHistory: [...state.stepHistory, WorkflowStep.rewriting],
      clearAuditResult: true,
      clearAuditError: true,
      clearFixedText: true,
      clearReAuditResult: true,
    );

    // 自动触发法务审核
    await startAudit();
  }

  // ==================== Step4：法务审核 ====================

  /// 开始法务审核
  Future<void> startAudit() async {
    final textToAudit = state.fixedText ?? state.selectedVersion?.rewrittenText ?? state.sourceText;
    if (textToAudit.isEmpty) return;

    state = state.copyWith(
      isAuditing: true,
      clearAuditError: true,
      auditProgress: 20,
    );

    try {
      // 模拟审核进度（关键词过滤很快，大模型审核较慢）
      state = state.copyWith(auditProgress: 40);

      final result = await _auditService.audit(
        text: textToAudit,
        auditType: '改写后文案',
      );

      state = state.copyWith(
        auditResult: result,
        isAuditing: false,
        auditProgress: 100,
      );

      // 如果审核全部安全，自动进入定稿步骤
      if (result.safeToPublish && result.issues.isEmpty) {
        state = state.copyWith(
          currentStep: WorkflowStep.finalized,
          stepHistory: [...state.stepHistory, WorkflowStep.auditing],
          finalText: textToAudit,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isAuditing: false,
        auditError: '审核出错：${_friendlyError(e.toString())}',
        auditProgress: 0,
      );
    }
  }

  /// 一键修正
  Future<void> autoFix() async {
    final effectiveResult = state.effectiveAuditResult;
    if (effectiveResult == null || effectiveResult.issues.isEmpty) return;

    final textToFix = state.fixedText ?? state.selectedVersion?.rewrittenText ?? state.sourceText;
    state = state.copyWith(isFixing: true);

    try {
      final fixResult = await _auditService.autoFix(
        textToFix,
        effectiveResult.issues,
      );
      final fixedText = fixResult['fixed_text'] as String;
      final needReReview = fixResult['need_re_review'] as bool;

      if (needReReview) {
        // 修正后自动触发复审
        state = state.copyWith(fixedText: fixedText, isFixing: false);
        await _reAudit(fixedText);
      } else {
        // 无需复审，直接标记安全并进入定稿
        state = state.copyWith(
          fixedText: fixedText,
          isFixing: false,
          reAuditResult: AuditResult(
            auditType: '修正后复审',
            riskLevel: '安全',
            issues: [],
            overallAssessment: '修正后无需复审，文案可安全发布。',
            safeToPublish: true,
            createdAt: DateTime.now(),
          ),
          currentStep: WorkflowStep.finalized,
          stepHistory: [...state.stepHistory, WorkflowStep.auditing],
          finalText: fixedText,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isFixing: false,
        auditError: '修正失败：${_friendlyError(e.toString())}',
      );
    }
  }

  /// 修正后复审
  Future<void> _reAudit(String text) async {
    state = state.copyWith(
      isAuditing: true,
      auditProgress: 30,
    );

    try {
      final result = await _auditService.audit(
        text: text,
        auditType: '修正后复审',
      );
      state = state.copyWith(
        reAuditResult: result,
        isAuditing: false,
        auditProgress: 100,
      );

      // 如果复审安全，自动进入定稿
      if (result.safeToPublish) {
        state = state.copyWith(
          currentStep: WorkflowStep.finalized,
          stepHistory: [...state.stepHistory, WorkflowStep.auditing],
          finalText: text,
        );
      }
    } catch (e) {
      state = state.copyWith(
        isAuditing: false,
        auditError: '复审出错：${_friendlyError(e.toString())}',
        auditProgress: 0,
      );
    }
  }

  // ==================== Step5：定稿 ====================

  /// 确认定稿（有风险但用户仍想使用）
  void confirmFinalize() {
    final text = state.fixedText ?? state.selectedVersion?.rewrittenText ?? state.sourceText;
    state = state.copyWith(
      currentStep: WorkflowStep.finalized,
      stepHistory: [...state.stepHistory, WorkflowStep.auditing],
      finalText: text,
    );
  }

  /// 保存文案到本地数据库（返回Script对象）
  Script buildScript() {
    return Script(
      sourceUrl: state.videoUrl,
      sourceText: state.sourceText,
      rewrittenText: state.finalText,
      rewriteMode: state.selectedMode,
      rewriteStyle: state.selectedStyle,
      riskLevel: state.effectiveAuditResult?.riskLevel ?? '安全',
      createdAt: DateTime.now(),
    );
  }

  // ==================== 回退操作 ====================

  /// 回退到上一步
  void goBack() {
    // 取消正在进行的操作
    _streamSubscription?.cancel();

    switch (state.currentStep) {
      case WorkflowStep.input:
        break; // 已是第一步
      case WorkflowStep.extracted:
        state = state.copyWith(
          currentStep: WorkflowStep.input,
          sourceText: '',
          clearExtractError: true,
        );
        break;
      case WorkflowStep.rewriting:
        state = state.copyWith(
          currentStep: WorkflowStep.extracted,
          isRewriting: false,
          streamingText: '',
          versions: [],
          clearRewriteError: true,
          rewriteProgress: 0,
        );
        break;
      case WorkflowStep.auditing:
        state = state.copyWith(
          currentStep: WorkflowStep.rewriting,
          clearAuditResult: true,
          clearAuditError: true,
          clearFixedText: true,
          clearReAuditResult: true,
          isAuditing: false,
          isFixing: false,
          auditProgress: 0,
        );
        break;
      case WorkflowStep.finalized:
        state = state.copyWith(
          currentStep: WorkflowStep.auditing,
          finalText: '',
        );
        break;
    }
  }

  /// 跳转到指定步骤（仅限已完成的步骤）
  void goToStep(WorkflowStep step) {
    // 只能跳转到当前步骤之前的步骤
    if (step.index >= state.currentStep.index) return;
    _streamSubscription?.cancel();

    // 根据目标步骤清理后续状态
    switch (step) {
      case WorkflowStep.input:
        state = state.copyWith(
          currentStep: WorkflowStep.input,
          sourceText: '',
          clearExtractError: true,
          isRewriting: false,
          streamingText: '',
          versions: [],
          clearRewriteError: true,
          rewriteProgress: 0,
          clearAuditResult: true,
          clearAuditError: true,
          clearFixedText: true,
          clearReAuditResult: true,
          isAuditing: false,
          isFixing: false,
          auditProgress: 0,
          finalText: '',
        );
        break;
      case WorkflowStep.extracted:
        state = state.copyWith(
          currentStep: WorkflowStep.extracted,
          isRewriting: false,
          streamingText: '',
          versions: [],
          clearRewriteError: true,
          rewriteProgress: 0,
          clearAuditResult: true,
          clearAuditError: true,
          clearFixedText: true,
          clearReAuditResult: true,
          isAuditing: false,
          isFixing: false,
          auditProgress: 0,
          finalText: '',
        );
        break;
      case WorkflowStep.rewriting:
        state = state.copyWith(
          currentStep: WorkflowStep.rewriting,
          clearAuditResult: true,
          clearAuditError: true,
          clearFixedText: true,
          clearReAuditResult: true,
          isAuditing: false,
          isFixing: false,
          auditProgress: 0,
          finalText: '',
        );
        break;
      case WorkflowStep.auditing:
        state = state.copyWith(
          currentStep: WorkflowStep.auditing,
          finalText: '',
        );
        break;
      case WorkflowStep.finalized:
        break; // 不能往前跳到定稿
    }
  }

  /// 重置整个工作流
  void reset() {
    _streamSubscription?.cancel();
    state = const WorkflowState();
  }

  /// 友好的错误信息转换
  String _friendlyError(String error) {
    if (error.contains('SocketException') || error.contains('Connection refused')) {
      return '网络连接失败，请检查网络设置';
    }
    if (error.contains('Connection timed out') || error.contains('TimeoutException')) {
      return '网络连接超时，请稍后重试';
    }
    if (error.contains('401')) {
      return 'API Key无效或已过期，请在设置中重新配置';
    }
    if (error.contains('429')) {
      return '请求过于频繁，请稍后再试';
    }
    if (error.contains('500') || error.contains('502') || error.contains('503')) {
      return '服务暂时不可用，请稍后再试';
    }
    // 去掉Exception前缀
    return error.replaceAll('Exception: ', '').replaceAll('Exception', '');
  }

  @override
  void dispose() {
    _streamSubscription?.cancel();
    super.dispose();
  }
}

/// 工作流Provider
final workflowProvider = StateNotifierProvider<WorkflowNotifier, WorkflowState>((ref) {
  return WorkflowNotifier(
    ref.read(douyinServiceProvider),
    ref.read(aiRewriteServiceProvider),
    ref.read(legalAuditServiceProvider),
  );
});
