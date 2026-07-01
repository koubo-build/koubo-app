import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/workflow_provider.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/api_config_indicator.dart';

/// 文案提取页 - 纯粹的链接提取工具
/// 流程：粘贴链接/口令 → 提取文案 → 选择下一步（AI改写/直接生成视频）
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

  // 输入模式：链接提取 / 手动输入
  bool _isManualInput = false;

  // 提取是否完成（用于显示结果区）
  bool _hasExtracted = false;

  @override
  void initState() {
    super.initState();
    _fadeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimController.forward();

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(workflowProvider);

    // 监听提取状态变化
    final currentStep = workflow.currentStep;
    final wasExtracting = _hasExtracted;
    if (currentStep == WorkflowStep.extracted || currentStep.index >= WorkflowStep.extracted.index) {
      if (!_hasExtracted) {
        _hasExtracted = true;
        // 提取完成后同步文案到编辑器
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('文案提取'),
        leading: _hasExtracted
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: _handleBack,
              )
            : null,
        actions: [
          // 重置按钮
          if (_hasExtracted)
            IconButton(
              icon: const Icon(Icons.restart_alt, size: 22),
              tooltip: '重新提取',
              onPressed: _showResetDialog,
            ),
        ],
      ),
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
          vertical: AppTheme.spacingSmall,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // API配置指示器
            ApiConfigIndicator(
              type: ApiConfigIndicatorType.extract,
              onConfigChanged: () {
                ref.read(apiConfigProvider.notifier).refresh();
              },
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            // 输入区
            _buildStepInput(workflow),

            // 提取结果区（仅提取完成后显示）
            if (_hasExtracted) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              _buildExtractedResult(workflow),
            ],

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  /// 处理返回
  void _handleBack() {
    if (_hasExtracted) {
      // 如果有内容，询问是否放弃
      _showResetDialog();
    } else {
      Navigator.pop(context);
    }
  }

  // ==================== 输入区 ====================

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
                ),
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppTheme.safeColor.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: AppTheme.safeColor),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '手动输入可直接提取文案，然后选择下一步操作',
                        style: TextStyle(fontSize: 12, color: AppTheme.safeColor),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppTheme.spacingMedium),
              // 提取按钮
              AppButton(
                text: '提取文案',
                icon: Icons.download_outlined,
                onPressed: _sourceTextController.text.trim().isNotEmpty
                    ? () => _handleManualExtract()
                    : null,
              ),
            ] else ...[
              // 链接输入模式
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
                    : () => _handleExtract(),
              ),

              // 使用提示
              const SizedBox(height: AppTheme.spacingSmall),
              _buildUsageTips(),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== 提取结果区 ====================

  Widget _buildExtractedResult(WorkflowState workflow) {
    // 同步原文到编辑器
    if (_sourceTextController.text != workflow.sourceText && workflow.sourceText.isNotEmpty) {
      _sourceTextController.text = workflow.sourceText;
    }

    return FadeTransition(
      opacity: _fadeAnimController,
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
              child: const Row(
                children: [
                  Icon(Icons.check_circle_outline, size: 14, color: AppTheme.safeColor),
                  SizedBox(width: 6),
                  Text(
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

            // 两个操作按钮
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: 'AI改写',
                    icon: Icons.auto_fix_high,
                    backgroundColor: AppTheme.accentColor,
                    onPressed: () => _navigateToRewrite(),
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                Expanded(
                  child: AppButton(
                    text: '生成视频',
                    icon: Icons.smart_display,
                    onPressed: () => _navigateToDigitalHuman(),
                  ),
                ),
              ],
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 底部说明
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: const Row(
                children: [
                  Icon(Icons.lightbulb_outline, size: 14, color: AppTheme.textHint),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'AI改写可优化文案表达，直接生成视频将使用当前文案',
                      style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 导航方法 ====================

  /// 处理链接提取
  Future<void> _handleExtract() async {
    await ref.read(workflowProvider.notifier).extractScript();
    // 等待状态更新后，显示结果区
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _hasExtracted = true;
        });
        _scrollToBottom();
      }
    });
  }

  /// 处理手动输入提取
  void _handleManualExtract() {
    final text = _sourceTextController.text.trim();
    if (text.isNotEmpty) {
      ref.read(workflowProvider.notifier).updateSourceText(text);
      setState(() {
        _hasExtracted = true;
      });
      _scrollToBottom();
    }
  }

  /// 跳转到AI改写页
  void _navigateToRewrite() {
    final text = _sourceTextController.text.trim();
    if (text.isNotEmpty) {
      Navigator.pushNamed(
        context,
        AppRoutes.rewrite,
        arguments: {'initialText': text},
      );
    }
  }

  /// 跳转到数字人视频页
  void _navigateToDigitalHuman() {
    final text = _sourceTextController.text.trim();
    if (text.isNotEmpty) {
      Navigator.pushNamed(
        context,
        AppRoutes.digitalHuman,
        arguments: {'initialText': text},
      );
    }
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
      margin: const EdgeInsets.only(left: 8),
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

  /// 使用提示
  Widget _buildUsageTips() {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '使用说明',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textSecondary),
          ),
          SizedBox(height: 4),
          _TipItem('1. 打开抖音/快手App，点击分享复制链接或口令'),
          _TipItem('2. 粘贴到上方输入框，自动识别平台'),
          _TipItem('3. 点击"提取文案"获取视频中的口播内容'),
          _TipItem('4. 只有口令无链接时，请点「手动输入」直接输入文案'),
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

  /// 重置确认弹窗
  void _showResetDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('重新提取'),
        content: const Text('确定要重新提取吗？当前编辑的文案将丢失。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _reset();
            },
            child: const Text('确定', style: TextStyle(color: AppTheme.highRiskColor)),
          ),
        ],
      ),
    );
  }

  /// 重置状态
  void _reset() {
    ref.read(workflowProvider.notifier).reset();
    _urlController.clear();
    _sourceTextController.clear();
    setState(() {
      _hasExtracted = false;
      _isManualInput = false;
    });
  }
}

/// 提示项组件
class _TipItem extends StatelessWidget {
  final String text;
  const _TipItem(this.text);

  @override
  Widget build(BuildContext context) {
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
}
