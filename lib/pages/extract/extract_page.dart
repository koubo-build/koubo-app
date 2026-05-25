import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/workflow_provider.dart';
import '../../models/rewrite_version.dart';
import '../../models/audit_result.dart';
import '../../services/ai_rewrite_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/risk_badge.dart';

/// 创作工作台 - 一站式：粘贴链接 → 提取文案 → AI改写 → 法务审核 → 定稿
class ExtractPage extends ConsumerStatefulWidget {
  const ExtractPage({super.key});

  @override
  ConsumerState<ExtractPage> createState() => _ExtractPageState();
}

class _ExtractPageState extends ConsumerState<ExtractPage>
    with TickerProviderStateMixin {
  final _urlController = TextEditingController();
  final _sourceTextController = TextEditingController();
  final _scrollController = ScrollController();

  // 动画控制器
  late AnimationController _fadeAnimController;
  late AnimationController _pulseAnimController;

  // 输入模式：链接提取 / 手动输入
  bool _isManualInput = false;

  // 改写模式和风格列表（引用Service常量）
  static const _rewriteModes = AiRewriteService.rewriteModes;
  static const _styleList = AiRewriteService.styleList;

  @override
  void initState() {
    super.initState();
    _fadeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimController.forward();

    // 脉冲动画（用于审核通过等场景）
    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // 监听URL输入，自动识别平台
    _urlController.addListener(() {
      ref.read(workflowProvider.notifier).setVideoUrl(_urlController.text);
    });
  }

  @override
  void dispose() {
    _urlController.dispose();
    _sourceTextController.dispose();
    _scrollController.dispose();
    _fadeAnimController.dispose();
    _pulseAnimController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(workflowProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('创作工作台'),
        leading: workflow.canGoBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => ref.read(workflowProvider.notifier).goBack(),
              )
            : null,
        actions: [
          // 重置按钮
          if (workflow.currentStep != WorkflowStep.input)
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 22),
              tooltip: '重新开始',
              onPressed: _showResetDialog,
            ),
        ],
      ),
      body: Column(
        children: [
          // 步骤指示器
          _buildStepIndicator(workflow.currentStep),

          // 主内容区域
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingSmall,
              ),
              child: AnimatedSize(
                duration: const Duration(milliseconds: 400),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Step1：视频链接输入区
                    _buildStepInput(workflow),

                    // Step2：提取结果展示区
                    if (workflow.currentStep.index >= WorkflowStep.extracted.index)
                      _buildStepExtracted(workflow),

                    // Step3：AI改写区
                    if (workflow.currentStep.index >= WorkflowStep.rewriting.index)
                      _buildStepRewriting(workflow),

                    // Step4：法务审核区
                    if (workflow.currentStep.index >= WorkflowStep.auditing.index)
                      _buildStepAuditing(workflow),

                    // Step5：定稿区
                    if (workflow.currentStep == WorkflowStep.finalized)
                      _buildStepFinalized(workflow),

                    const SizedBox(height: AppTheme.spacingXLarge),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 步骤指示器 ====================

  Widget _buildStepIndicator(WorkflowStep currentStep) {
    final steps = [
      _StepData('粘贴链接', Icons.link),
      _StepData('提取文案', Icons.description_outlined),
      _StepData('AI改写', Icons.auto_fix_high),
      _StepData('法务审核', Icons.shield_outlined),
      _StepData('定稿', Icons.check_circle),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSmall,
        vertical: AppTheme.spacingSmall,
      ),
      color: AppTheme.darkSurface,
      child: Row(
        children: List.generate(steps.length, (index) {
          final stepIndex = index;
          final isActive = stepIndex == currentStep.index;
          final isCompleted = stepIndex < currentStep.index;
          final step = steps[stepIndex];

          return Expanded(
            child: GestureDetector(
              // 点击已完成的步骤可以跳回
              onTap: isCompleted
                  ? () => ref.read(workflowProvider.notifier).goToStep(
                        WorkflowStep.values[stepIndex],
                      )
                  : null,
              child: Tooltip(
                message: isCompleted ? '点击返回此步骤' : '',
                child: Row(
                  children: [
                    // 步骤圆点+标签
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            width: isActive ? 32 : 26,
                            height: isActive ? 32 : 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isCompleted
                                  ? AppTheme.safeColor
                                  : isActive
                                      ? AppTheme.primaryColor
                                      : AppTheme.darkCard,
                              border: Border.all(
                                color: isActive
                                    ? AppTheme.primaryColor
                                    : isCompleted
                                        ? AppTheme.safeColor
                                        : AppTheme.textHint.withOpacity(0.3),
                                width: 2,
                              ),
                              boxShadow: isActive
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.primaryColor.withOpacity(0.4),
                                        blurRadius: 8,
                                        spreadRadius: 1,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Center(
                              child: isCompleted
                                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                                  : Icon(
                                      step.icon,
                                      size: isActive ? 16 : 12,
                                      color: isActive
                                          ? Colors.white
                                          : AppTheme.textHint,
                                    ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            step.label,
                            style: TextStyle(
                              fontSize: 10,
                              color: isActive
                                  ? AppTheme.primaryColor
                                  : isCompleted
                                      ? AppTheme.safeColor
                                      : AppTheme.textHint,
                              fontWeight:
                                  isActive ? FontWeight.w600 : FontWeight.normal,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                    // 连接线
                    if (stepIndex < steps.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          width: 16,
                          height: 2,
                          color: isCompleted
                              ? AppTheme.safeColor
                              : AppTheme.textHint.withOpacity(0.2),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ==================== Step1：视频链接输入区 ====================

  Widget _buildStepInput(WorkflowState workflow) {
    return FadeTransition(
      opacity: _fadeAnimController,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题
            Row(
              children: [
                _buildStepIcon(_isManualInput ? Icons.edit_note : Icons.link, AppTheme.primaryColor),
                const SizedBox(width: 10),
                Text(
                  _isManualInput ? '手动输入文案' : '粘贴视频链接',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // 输入模式切换
                GestureDetector(
                  onTap: () => setState(() {
                    _isManualInput = !_isManualInput;
                    if (_isManualInput) _urlController.clear();
                  }),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppTheme.primaryColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3), width: 1),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isManualInput ? Icons.link : Icons.edit_note,
                          size: 14,
                          color: AppTheme.primaryColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _isManualInput ? '改用链接' : '手动输入',
                          style: const TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                // 平台识别标签
                if (!_isManualInput && workflow.platformType != null)
                  _buildPlatformBadge(workflow.platformType!),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            if (_isManualInput) ...[
              // 手动输入文案模式
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.darkSurface,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: TextField(
                  controller: _sourceTextController,
                  maxLines: 8,
                  style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, height: 1.5),
                  decoration: InputDecoration(
                    hintText: '请直接粘贴或输入口播文案...\n\n也可以从抖音评论区、其他App复制文案后粘贴到这里',
                    hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 14),
                    filled: true,
                    fillColor: Colors.transparent,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                    ),
                  ),
                  onChanged: (text) {
                    ref.read(workflowProvider.notifier).updateSourceText(text);
                  },
                ),
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.safeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 14, color: AppTheme.safeColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '手动输入文案可直接跳过链接提取，进入AI改写步骤',
                        style: const TextStyle(fontSize: 12, color: AppTheme.safeColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              // 确认输入按钮
              AppButton(
                text: '确认文案，开始改写',
                icon: Icons.arrow_forward,
                onPressed: _sourceTextController.text.trim().isNotEmpty
                    ? () {
                        ref.read(workflowProvider.notifier).setManualText(_sourceTextController.text.trim());
                        _scrollToBottom();
                      }
                    : null,
              ),
            ] else ...[
              // 链接输入模式（原有逻辑）

            // 链接输入框
            Container(
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: workflow.platformType != null
                      ? AppTheme.safeColor.withOpacity(0.3)
                      : Colors.transparent,
                  width: 1,
                ),
              ),
              child: TextField(
                controller: _urlController,
                maxLines: 2,
                keyboardType: TextInputType.url,
                style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '请粘贴抖音/快手分享链接或口令\n如：https://v.douyin.com/xxx/ 或分享口令',
                  hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 14),
                  filled: true,
                  fillColor: Colors.transparent,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 粘贴按钮
                      IconButton(
                        icon: const Icon(Icons.paste, size: 20, color: AppTheme.textHint),
                        tooltip: '粘贴',
                        onPressed: _pasteFromClipboard,
                      ),
                      // 清空按钮
                      if (_urlController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: AppTheme.textHint),
                          tooltip: '清空',
                          onPressed: () {
                            _urlController.clear();
                            ref.read(workflowProvider.notifier).setVideoUrl('');
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ),

            // 平台识别成功提示
            if (workflow.platformType != null)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: AppTheme.safeColor),
                    const SizedBox(width: 6),
                    Text(
                      '已识别${workflow.platformType}链接',
                      style: const TextStyle(fontSize: 12, color: AppTheme.safeColor),
                    ),
                  ],
                ),
              ),

            // 错误提示
            if (workflow.extractError != null)
              _buildErrorBanner(workflow.extractError!),

            const SizedBox(height: AppTheme.spacingMedium),

            // 提取按钮
            AppButton(
              text: '提取文案',
              icon: Icons.download_outlined,
              isLoading: workflow.isExtracting,
              onPressed: workflow.isExtracting
                  ? null
                  : () => ref.read(workflowProvider.notifier).extractScript(),
            ),

            // 使用提示
            const SizedBox(height: AppTheme.spacingSmall),
            _buildUsageTips(),
            ], // end of else (链接输入模式)
          ],
        ),
      ),
    );
  }

  // ==================== Step2：提取结果展示区 ====================

  Widget _buildStepExtracted(WorkflowState workflow) {
    // 同步原文到编辑器
    if (_sourceTextController.text != workflow.sourceText) {
      _sourceTextController.text = workflow.sourceText;
    }

    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _buildStepIcon(Icons.description_outlined, AppTheme.safeColor),
                const SizedBox(width: 10),
                const Text(
                  '提取结果',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // 字数统计
                _buildWordCountBadge(_sourceTextController.text.length),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            // 完成状态提示
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.safeColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle_outline, size: 14, color: AppTheme.safeColor),
                  const SizedBox(width: 6),
                  const Text(
                    '文案提取成功，您可以在下方微调',
                    style: TextStyle(fontSize: 12, color: AppTheme.safeColor),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            // 文案内容（可编辑）
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 120, maxHeight: 250),
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: TextField(
                controller: _sourceTextController,
                maxLines: null,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  height: 1.6,
                ),
                decoration: const InputDecoration(
                  hintText: '文案内容...',
                  hintStyle: TextStyle(color: AppTheme.textHint),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (text) {
                  ref.read(workflowProvider.notifier).updateSourceText(text);
                },
              ),
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // AI改写按钮
            AppButton(
              text: 'AI改写',
              icon: Icons.auto_fix_high,
              backgroundColor: AppTheme.accentColor,
              onPressed: () {
                ref.read(workflowProvider.notifier).selectRewriteMode('同义改写');
                _scrollToBottom();
              },
            ),
          ],
        ),
      ),
    );
  }

  // ==================== Step3：AI改写区 ====================

  Widget _buildStepRewriting(WorkflowState workflow) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _buildStepIcon(Icons.auto_fix_high, AppTheme.accentColor),
                const SizedBox(width: 10),
                const Text(
                  'AI改写',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                // 改写进度
                if (workflow.isRewriting)
                  _buildProgressIndicator(workflow.rewriteProgress),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            // 改写模式选择
            const Text(
              '改写模式',
              style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _rewriteModes.map((mode) {
                final isSelected = workflow.selectedMode == mode['key'];
                return ChoiceChip(
                  label: Text(mode['label']!),
                  selected: isSelected,
                  onSelected: (selected) {
                    ref.read(workflowProvider.notifier).selectRewriteMode(
                      selected ? mode['key']! : '同义改写',
                    );
                  },
                  selectedColor: AppTheme.primaryColor.withOpacity(0.3),
                  backgroundColor: AppTheme.darkSurface,
                  side: BorderSide(
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                  ),
                  labelStyle: TextStyle(
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 13,
                  ),
                );
              }).toList(),
            ),

            // 模式说明
            if (workflow.selectedMode != null)
              Padding(
                padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
                child: Text(
                  _rewriteModes.firstWhere(
                    (m) => m['key'] == workflow.selectedMode,
                    orElse: () => {'desc': ''},
                  )['desc'] ?? '',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                ),
              ),

            // 风格选择（仅风格转换模式）
            if (workflow.selectedMode == '风格转换') ...[
              const SizedBox(height: AppTheme.spacingMedium),
              const Text(
                '选择风格',
                style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _styleList.map((style) {
                  final isSelected = workflow.selectedStyle == style;
                  return ChoiceChip(
                    label: Text(style),
                    selected: isSelected,
                    onSelected: (selected) {
                      ref.read(workflowProvider.notifier).selectRewriteStyle(
                        selected ? style : null,
                      );
                    },
                    selectedColor: AppTheme.accentColor.withOpacity(0.3),
                    backgroundColor: AppTheme.darkSurface,
                    side: BorderSide(
                      color: isSelected ? AppTheme.accentColor : Colors.transparent,
                    ),
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.accentColor : AppTheme.textSecondary,
                      fontSize: 13,
                    ),
                  );
                }).toList(),
              ),
            ],

            // 目标字数（仅缩写精简模式）
            if (workflow.selectedMode == '缩写精简') ...[
              const SizedBox(height: AppTheme.spacingMedium),
              Row(
                children: [
                  const Text(
                    '目标字数：',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 80,
                    child: TextFormField(
                      keyboardType: TextInputType.number,
                      initialValue: '${workflow.targetLength ?? 100}',
                      style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        filled: true,
                        fillColor: AppTheme.darkSurface,
                      ),
                      onChanged: (value) {
                        final length = int.tryParse(value) ?? 100;
                        ref.read(workflowProvider.notifier).setTargetLength(length);
                      },
                    ),
                  ),
                  const Text(' 字', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                ],
              ),
            ],

            const SizedBox(height: AppTheme.spacingMedium),

            // 开始改写按钮
            if (!workflow.isRewriting && workflow.versions.isEmpty)
              AppButton(
                text: '开始改写',
                icon: Icons.auto_fix_high,
                isLoading: false,
                onPressed: () {
                  ref.read(workflowProvider.notifier).startRewrite();
                  _scrollToBottom();
                },
              ),

            // 流式输出展示
            if (workflow.isRewriting && workflow.streamingText.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              _buildStreamingBox(workflow.streamingText),
            ],

            // 改写中loading（还没开始输出）
            if (workflow.isRewriting && workflow.streamingText.isEmpty) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              _buildLoadingBox('AI正在思考改写方案...'),
            ],

            // 改写错误提示
            if (workflow.rewriteError != null) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              _buildErrorBanner(workflow.rewriteError!),
              const SizedBox(height: AppTheme.spacingSmall),
              AppButton(
                text: '重新改写',
                icon: Icons.refresh,
                isOutlined: true,
                onPressed: () {
                  ref.read(workflowProvider.notifier).startRewrite();
                  _scrollToBottom();
                },
              ),
            ],

            // 改写版本列表
            if (workflow.versions.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              Row(
                children: [
                  const Text(
                    '改写版本',
                    style: TextStyle(fontSize: 14, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  Text(
                    '共${workflow.versions.length}个版本',
                    style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              ...workflow.versions.map((version) => _buildVersionCard(
                version: version,
                sourceText: workflow.sourceText,
                isSelected: version.versionNumber == workflow.selectedVersionNumber,
                onTap: () => ref.read(workflowProvider.notifier).selectVersion(version.versionNumber),
              )),

              const SizedBox(height: AppTheme.spacingMedium),

              // 确认选用按钮
              AppButton(
                text: '确认选用',
                icon: Icons.check_circle_outline,
                onPressed: workflow.selectedVersionNumber != null
                    ? () {
                        ref.read(workflowProvider.notifier).confirmRewriteVersion();
                        _scrollToBottom();
                      }
                    : null,
              ),
              // 跳过改写按钮
              if (workflow.rewriteError != null || workflow.versions.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
                  child: AppButton(
                    text: '跳过改写，直接审核',
                    icon: Icons.skip_next,
                    isOutlined: true,
                    onPressed: () {
                      ref.read(workflowProvider.notifier).skipRewrite();
                      _scrollToBottom();
                    },
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== Step4：法务审核区 ====================

  Widget _buildStepAuditing(WorkflowState workflow) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _buildStepIcon(Icons.shield_outlined, AppTheme.primaryColor),
                const SizedBox(width: 10),
                const Text(
                  '法务审核',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                if (workflow.isAuditing || workflow.isFixing)
                  _buildProgressIndicator(workflow.auditProgress),
              ],
            ),

            // 审核中loading
            if (workflow.isAuditing || workflow.isFixing) ...[
              const SizedBox(height: AppTheme.spacingLarge),
              _buildLoadingBox(
                workflow.isFixing ? '正在一键修正...' : '正在进行法务审核...',
              ),
            ],

            // 审核错误提示
            if (workflow.auditError != null) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              _buildErrorBanner(workflow.auditError!),
              const SizedBox(height: AppTheme.spacingSmall),
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: '重新审核',
                      icon: Icons.refresh,
                      isOutlined: true,
                      onPressed: () => ref.read(workflowProvider.notifier).startAudit(),
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Expanded(
                    child: AppButton(
                      text: '跳过审核',
                      icon: Icons.skip_next,
                      isOutlined: true,
                      onPressed: () => ref.read(workflowProvider.notifier).skipAudit(),
                    ),
                  ),
                ],
              ),
            ],

            // 审核结果展示
            if (workflow.effectiveAuditResult != null && !workflow.isAuditing) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              _buildAuditResult(workflow.effectiveAuditResult!, workflow),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== Step5：定稿区 ====================

  Widget _buildStepFinalized(WorkflowState workflow) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 标题行
            Row(
              children: [
                _buildStepIcon(Icons.check_circle, AppTheme.safeColor),
                const SizedBox(width: 10),
                const Text(
                  '文案定稿',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                RiskBadge(
                  riskLevel: workflow.effectiveAuditResult?.riskLevel ?? '安全',
                ),
              ],
            ),

            // 完成提示
            const SizedBox(height: AppTheme.spacingSmall),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppTheme.safeColor.withOpacity(0.1),
                    AppTheme.safeColor.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: AppTheme.safeColor.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppTheme.safeColor.withOpacity(0.15),
                    ),
                    child: const Icon(Icons.check_circle, color: AppTheme.safeColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '文案创作完成！',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.safeColor,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '可以保存文案，或继续配音/生成视频',
                          style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 定稿文案内容
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                border: Border.all(
                  color: AppTheme.safeColor.withOpacity(0.3),
                  width: 1,
                ),
              ),
              child: Text(
                workflow.finalText,
                style: const TextStyle(
                  fontSize: 15,
                  color: AppTheme.textPrimary,
                  height: 1.6,
                ),
              ),
            ),

            const SizedBox(height: AppTheme.spacingSmall),
            // 字数统计
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text(
                  '${workflow.finalText.length} 字',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 操作按钮
            AppButton(
              text: '保存文案',
              icon: Icons.save_outlined,
              onPressed: () => _saveScript(workflow),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: '去配音',
                    icon: Icons.record_voice_over,
                    isOutlined: true,
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.voice,
                        arguments: {'text': workflow.finalText},
                      );
                    },
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                Expanded(
                  child: AppButton(
                    text: '去生成视频',
                    icon: Icons.smart_toy_outlined,
                    isOutlined: true,
                    backgroundColor: AppTheme.accentColor,
                    onPressed: () {
                      Navigator.pushNamed(
                        context,
                        AppRoutes.digitalHuman,
                        arguments: {'text': workflow.finalText},
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 审核结果展示 ====================

  Widget _buildAuditResult(AuditResult result, WorkflowState workflow) {
    final isSafe = result.safeToPublish && result.issues.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 总体风险等级大号徽章
        Center(
          child: Column(
            children: [
              // 复审标记
              if (workflow.reAuditResult != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.autorenew, size: 12, color: AppTheme.primaryColor),
                      const SizedBox(width: 4),
                      const Text(
                        '修正后复审',
                        style: TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              // 风险等级大图标
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.getRiskColor(result.riskLevel).withOpacity(0.12),
                  border: Border.all(
                    color: AppTheme.getRiskColor(result.riskLevel).withOpacity(0.3),
                    width: 2,
                  ),
                ),
                child: Icon(
                  isSafe ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 40,
                  color: AppTheme.getRiskColor(result.riskLevel),
                ),
              ),
              const SizedBox(height: 10),
              RiskBadge(riskLevel: result.riskLevel, fontSize: 16),
              if (isSafe) ...[
                const SizedBox(height: 10),
                const Text(
                  '文案已通过审核！',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppTheme.safeColor,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (!isSafe && result.overallAssessment != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    result.overallAssessment!,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: AppTheme.spacingMedium),

        // 5个维度审核结果
        ..._buildAuditDimensions(result),

        // 问题详情（有高亮标注）
        if (result.issues.isNotEmpty) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          const Text(
            '问题详情',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          // 文案高亮展示
          _buildHighlightedText(workflow.currentRewrittenText, result.issues),
          const SizedBox(height: AppTheme.spacingSmall),
          // 问题列表
          ...result.issues.map((issue) => _buildIssueCard(issue)),

          // 操作按钮
          const SizedBox(height: AppTheme.spacingMedium),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: '一键修正',
                  icon: Icons.auto_fix_high,
                  backgroundColor: AppTheme.accentColor,
                  isLoading: workflow.isFixing,
                  onPressed: () => ref.read(workflowProvider.notifier).autoFix(),
                ),
              ),
            ],
          ),
          // 即使有风险，也允许用户强制定稿
          if (!isSafe) ...[
            const SizedBox(height: AppTheme.spacingSmall),
            AppButton(
              text: '仍然使用（风险自担）',
              icon: Icons.warning_amber,
              isOutlined: true,
              onPressed: () => ref.read(workflowProvider.notifier).confirmFinalize(),
            ),
          ],
        ],
      ],
    );
  }

  /// 构建5个审核维度
  List<Widget> _buildAuditDimensions(AuditResult result) {
    final dimensions = [
      _AuditDimension('广告法违禁词', '广告法违禁词', result),
      _AuditDimension('敏感词检测', '敏感词', result),
      _AuditDimension('平台规则', '平台违规', result),
      _AuditDimension('侵权风险', '侵权风险', result),
      _AuditDimension('虚假宣传', '虚假宣传', result),
    ];

    return dimensions.map((dim) {
      final count = result.issues.where((i) => i.type == dim.type).length;
      final hasHighRisk = result.issues.any(
        (i) => i.type == dim.type && i.riskLevel == '高风险',
      );
      final hasMediumRisk = result.issues.any(
        (i) => i.type == dim.type && i.riskLevel == '中风险',
      );
      final riskLevel = count == 0
          ? '安全'
          : hasHighRisk
              ? '高风险'
              : hasMediumRisk
                  ? '中风险'
                  : '低风险';

      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                dim.label,
                style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            if (count > 0) ...[
              Icon(Icons.cancel, size: 14, color: AppTheme.getRiskColor(riskLevel)),
              const SizedBox(width: 3),
              Text(
                '$count处',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.getRiskColor(riskLevel),
                ),
              ),
            ] else ...[
              const Icon(Icons.check_circle, size: 14, color: AppTheme.safeColor),
              const SizedBox(width: 3),
              const Text('0处', style: TextStyle(fontSize: 13, color: AppTheme.safeColor)),
            ],
            const Spacer(),
            RiskBadge(riskLevel: riskLevel, compact: true),
          ],
        ),
      );
    }).toList();
  }

  /// 构建问题高亮文本
  Widget _buildHighlightedText(String text, List<AuditIssue> issues) {
    if (issues.isEmpty) {
      return Text(text, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6));
    }

    // 收集所有问题词的位置
    final spans = <TextSpan>[];
    int currentPos = 0;

    // 按位置排序的问题列表（根据在文本中的出现顺序）
    final sortedIssues = List<AuditIssue>.from(issues)
      ..sort((a, b) {
        final posA = text.indexOf(a.originalText);
        final posB = text.indexOf(b.originalText);
        return posA.compareTo(posB);
      });

    for (final issue in sortedIssues) {
      final pos = text.indexOf(issue.originalText, currentPos);
      if (pos == -1) continue;

      // 添加问题词之前的文本
      if (pos > currentPos) {
        spans.add(TextSpan(text: text.substring(currentPos, pos)));
      }

      // 添加高亮的问题词
      final riskColor = AppTheme.getRiskColor(issue.riskLevel);
      spans.add(TextSpan(
        text: issue.originalText,
        style: TextStyle(
          backgroundColor: riskColor.withOpacity(0.3),
          color: riskColor,
          fontWeight: FontWeight.w600,
        ),
      ));

      currentPos = pos + issue.originalText.length;
    }

    // 添加剩余文本
    if (currentPos < text.length) {
      spans.add(TextSpan(text: text.substring(currentPos)));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6),
          children: spans,
        ),
      ),
    );
  }

  /// 构建问题卡片
  Widget _buildIssueCard(AuditIssue issue) {
    final riskColor = AppTheme.getRiskColor(issue.riskLevel);

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.all(AppTheme.spacingSmall),
      decoration: BoxDecoration(
        color: riskColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: riskColor.withOpacity(0.2), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // 问题类型
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: riskColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  issue.type,
                  style: TextStyle(fontSize: 10, color: riskColor, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              RiskBadge(riskLevel: issue.riskLevel, compact: true),
            ],
          ),
          const SizedBox(height: 6),
          // 原文词句
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('原句：', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: riskColor.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    issue.originalText,
                    style: TextStyle(fontSize: 12, color: riskColor, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // 原因
          if (issue.reason.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('原因：', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
                Expanded(
                  child: Text(issue.reason, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                ),
              ],
            ),
          const SizedBox(height: 4),
          // 建议
          if (issue.suggestion.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('建议：', style: TextStyle(fontSize: 12, color: AppTheme.safeColor)),
                Expanded(
                  child: Text(
                    issue.suggestion,
                    style: const TextStyle(fontSize: 12, color: AppTheme.safeColor, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  // ==================== 改写版本卡片 ====================

  Widget _buildVersionCard({
    required RewriteVersion version,
    required String sourceText,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.1)
              : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.textHint.withOpacity(0.1),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                // 选中指示器
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                    border: Border.all(
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                      width: 1.5,
                    ),
                  ),
                  child: isSelected
                      ? const Icon(Icons.check, size: 12, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 10),
                Text(
                  '版本${version.versionNumber}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                // 评分标签
                if (version.score > 0)
                  _buildScoreBadge(version.score),
                const SizedBox(width: 6),
                Text(
                  '${version.rewrittenText.length}字',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // 改写内容预览
            Text(
              version.rewrittenText.length > 150
                  ? '${version.rewrittenText.substring(0, 150)}...'
                  : version.rewrittenText,
              style: TextStyle(
                fontSize: 13,
                color: isSelected ? AppTheme.textPrimary : AppTheme.textSecondary,
                height: 1.5,
              ),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
            ),

            // 选中时展示原文vs改写对比
            if (isSelected) ...[
              const SizedBox(height: AppTheme.spacingSmall),
              _buildDiffView(sourceText, version.rewrittenText),
            ],
          ],
        ),
      ),
    );
  }

  /// 评分标签
  Widget _buildScoreBadge(int score) {
    Color color;
    String label;
    if (score >= 80) {
      color = AppTheme.safeColor;
      label = '优秀';
    } else if (score >= 60) {
      color = AppTheme.lowRiskColor;
      label = '良好';
    } else {
      color = AppTheme.mediumRiskColor;
      label = '一般';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$score分',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: color.withOpacity(0.8),
            ),
          ),
        ],
      ),
    );
  }

  /// 原文vs改写对比（diff高亮）
  Widget _buildDiffView(String sourceText, String rewrittenText) {
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingSmall),
      decoration: BoxDecoration(
        color: AppTheme.darkBackground,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 原文
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.textHint,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '原文',
                style: TextStyle(fontSize: 11, color: AppTheme.textHint, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${sourceText.length}字',
                style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            sourceText.length > 120 ? '${sourceText.substring(0, 120)}...' : sourceText,
            style: const TextStyle(fontSize: 12, color: AppTheme.textHint, height: 1.4),
          ),
          // 分隔线
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(
              height: 1,
              color: AppTheme.textHint.withOpacity(0.15),
            ),
          ),
          // 改写
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.accentColor,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                '改写',
                style: TextStyle(fontSize: 11, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${rewrittenText.length}字',
                style: TextStyle(fontSize: 10, color: AppTheme.accentColor.withOpacity(0.7)),
              ),
              const SizedBox(width: 4),
              // 字数变化标签
              _buildWordChangeBadge(sourceText.length, rewrittenText.length),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            rewrittenText.length > 120 ? '${rewrittenText.substring(0, 120)}...' : rewrittenText,
            style: const TextStyle(fontSize: 12, color: AppTheme.accentColor, height: 1.4),
          ),
        ],
      ),
    );
  }

  /// 字数变化标签
  Widget _buildWordChangeBadge(int sourceLen, int rewriteLen) {
    final diff = rewriteLen - sourceLen;
    if (diff == 0) return const SizedBox.shrink();

    final isIncrease = diff > 0;
    final color = isIncrease ? AppTheme.lowRiskColor : AppTheme.primaryColor;
    final text = isIncrease ? '+$diff' : '$diff';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 9, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }

  // ==================== 通用UI组件 ====================

  /// 步骤图标
  Widget _buildStepIcon(IconData icon, Color color) {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }

  /// 平台识别徽章
  Widget _buildPlatformBadge(String platform) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.accentColor.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            platform == '抖音' ? Icons.music_note : Icons.play_circle_outline,
            size: 12,
            color: AppTheme.accentColor,
          ),
          const SizedBox(width: 3),
          Text(
            platform,
            style: const TextStyle(
              fontSize: 11,
              color: AppTheme.accentColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// 字数统计徽章
  Widget _buildWordCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$count 字',
        style: const TextStyle(
          fontSize: 11,
          color: AppTheme.textSecondary,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  /// 进度指示器
  Widget _buildProgressIndicator(int progress) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 60,
          height: 4,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress / 100.0,
              backgroundColor: AppTheme.textHint.withOpacity(0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$progress%',
          style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
        ),
      ],
    );
  }

  /// 流式输出展示框
  Widget _buildStreamingBox(String streamingText) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(
          color: AppTheme.accentColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppTheme.accentColor.withOpacity(0.7),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '正在生成版本1...',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.accentColor.withOpacity(0.8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            streamingText,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textPrimary,
              height: 1.6,
            ),
          ),
          // 光标闪烁效果
          _buildBlinkingCursor(),
        ],
      ),
    );
  }

  /// 加载中提示框
  Widget _buildLoadingBox(String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppTheme.spacingLarge),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  /// 错误提示横幅
  Widget _buildErrorBanner(String error) {
    return Padding(
      padding: const EdgeInsets.only(top: AppTheme.spacingSmall),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.highRiskColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: AppTheme.highRiskColor),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                error,
                style: const TextStyle(fontSize: 13, color: AppTheme.highRiskColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 闪烁光标
  Widget _buildBlinkingCursor() {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 500),
      builder: (context, value, child) {
        return Opacity(
          opacity: value > 0.5 ? 1.0 : 0.0,
          child: child,
        );
      },
      child: Container(
        width: 2,
        height: 16,
        color: AppTheme.accentColor,
      ),
    );
  }

  /// 使用提示
  Widget _buildUsageTips() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '使用说明',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          _buildTipItem('1. 打开抖音/快手App，点击分享复制链接或口令'),
          _buildTipItem('2. 粘贴到上方输入框，自动识别平台'),
          _buildTipItem('3. 含链接的文本会自动提取，点击"提取文案"获取'),
          _buildTipItem('4. 只有口令无链接时，请点「手动输入」直接输入文案'),
        ],
      ),
    );
  }

  /// 提示项
  Widget _buildTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 辅助方法 ====================

  /// 从剪贴板粘贴
  Future<void> _pasteFromClipboard() async {
    try {
      final clipboardData = await Clipboard.getData(Clipboard.kTextPlain);
      if (clipboardData != null && clipboardData.text != null) {
        _urlController.text = clipboardData.text!;
        ref.read(workflowProvider.notifier).setVideoUrl(clipboardData.text!);
      }
    } catch (_) {
      // 剪贴板访问失败
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法访问剪贴板'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// 滚动到底部
  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// 保存文案
  void _saveScript(WorkflowState workflow) {
    final script = ref.read(workflowProvider.notifier).buildScript();
    // TODO: 实现保存到本地数据库
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('文案已保存'),
        backgroundColor: AppTheme.safeColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
      ),
    );
  }

  /// 重置确认弹窗
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('重新开始'),
        content: const Text('确定要重置当前工作流吗？所有进度将会丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(workflowProvider.notifier).reset();
              _urlController.clear();
              _sourceTextController.clear();
            },
            child: const Text('确定', style: TextStyle(color: AppTheme.highRiskColor)),
          ),
        ],
      ),
    );
  }
}

// ==================== 数据类 ====================

/// 步骤指示器数据
class _StepData {
  final String label;
  final IconData icon;
  const _StepData(this.label, this.icon);
}

/// 审核维度数据
class _AuditDimension {
  final String label;
  final String type;
  final AuditResult result;
  const _AuditDimension(this.label, this.type, this.result);
}
