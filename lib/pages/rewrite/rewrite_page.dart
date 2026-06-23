import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../services/ai_rewrite_service.dart';
import '../../services/api_client.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/loading_widget.dart';
import '../../widgets/risk_badge.dart';

/// AI改写工作台 - 多种改写模式 + 多版本生成 + 对比展示
class RewritePage extends ConsumerStatefulWidget {
  const RewritePage({super.key});

  @override
  ConsumerState<RewritePage> createState() => _RewritePageState();
}

class _RewritePageState extends ConsumerState<RewritePage> {
  final _sourceController = TextEditingController();
  String? _selectedMode;
  String? _selectedStyle;
  int? _targetLength;
  bool _isRewriting = false;

  // 改写结果
  List<Map<String, dynamic>> _versions = [];

  @override
  void dispose() {
    _sourceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI改写工作台'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 原始文案区域
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.description_outlined, color: AppTheme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      const Text('原始文案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingSmall),
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(minHeight: 100),
                    padding: const EdgeInsets.all(AppTheme.spacingMedium),
                    decoration: BoxDecoration(
                      color: AppTheme.darkSurface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                    child: TextField(
                      controller: _sourceController,
                      maxLines: null,
                      style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary, height: 1.6),
                      decoration: const InputDecoration(
                        hintText: '请输入或粘贴要改写的口播文案...',
                        hintStyle: TextStyle(color: AppTheme.textHint),
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingSmall),
                  // 审核状态（占位）
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.safeColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_outlined, size: 14, color: AppTheme.safeColor),
                        const SizedBox(width: 4),
                        Text(
                          '审核: 未审核',
                          style: TextStyle(fontSize: 12, color: AppTheme.safeColor.withOpacity(0.8)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 改写模式选择
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, color: AppTheme.accentColor, size: 20),
                      const SizedBox(width: 8),
                      const Text('改写模式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: AppTheme.spacingMedium),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: AiRewriteService.rewriteModes.map((mode) {
                      final isSelected = _selectedMode == mode['key'];
                      return ChoiceChip(
                        label: Text(mode['label']!),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedMode = selected ? mode['key'] : null;
                          });
                        },
                        selectedColor: AppTheme.primaryColor.withOpacity(0.3),
                        backgroundColor: AppTheme.darkSurface,
                        side: BorderSide(
                          color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                        ),
                      );
                    }).toList(),
                  ),

                  // 风格选择（仅风格转换模式显示）
                  if (_selectedMode == '风格转换') ...[
                    const SizedBox(height: AppTheme.spacingMedium),
                    const Text('选择风格：', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                    const SizedBox(height: AppTheme.spacingSmall),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AiRewriteService.styleList.map((style) {
                        final isSelected = _selectedStyle == style;
                        return ChoiceChip(
                          label: Text(style),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedStyle = selected ? style : null;
                            });
                          },
                          selectedColor: AppTheme.accentColor.withOpacity(0.3),
                          backgroundColor: AppTheme.darkSurface,
                        );
                      }).toList(),
                    ),
                  ],

                  // 目标字数（仅缩写精简模式显示）
                  if (_selectedMode == '缩写精简') ...[
                    const SizedBox(height: AppTheme.spacingMedium),
                    Row(
                      children: [
                        const Text('目标字数：', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextFormField(
                            keyboardType: TextInputType.number,
                            initialValue: '100',
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
                              _targetLength = int.tryParse(value);
                            },
                          ),
                        ),
                        const Text(' 字', style: TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
                      ],
                    ),
                  ],

                  const SizedBox(height: AppTheme.spacingMedium),
                  AppButton(
                    text: '开始改写',
                    icon: Icons.auto_fix_high,
                    isLoading: _isRewriting,
                    onPressed: _startRewrite,
                  ),
                ],
              ),
            ),

            // 改写结果
            if (_versions.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.assessment_outlined, color: AppTheme.primaryColor, size: 20),
                        const SizedBox(width: 8),
                        const Text('改写结果', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text(
                          '${_versions.length}个版本',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppTheme.spacingMedium),
                    // 版本卡片列表
                    ..._versions.asMap().entries.map((entry) {
                      final index = entry.key;
                      final version = entry.value;
                      return _buildVersionCard(index + 1, version);
                    }),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppTheme.spacingMedium),

            // 开始改写按钮
            AppButton(
              text: '开始改写',
              icon: Icons.auto_fix_high,
              isLoading: _isRewriting,
              onPressed: _startRewrite,
            ),

            // 改写后法务审核
            if (_versions.isNotEmpty) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              AppCard(
                child: Row(
                  children: [
                    const Icon(Icons.shield_outlined, color: AppTheme.safeColor, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '改写后法务审核',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
                      ),
                    ),
                    AppButton(
                      text: '去审核',
                      fontSize: 13,
                      height: 36,
                      borderRadius: AppTheme.radiusSmall,
                      onPressed: () {
                        Navigator.pushNamed(context, AppRoutes.audit);
                      },
                    ),
                  ],
                ),
              ),

              // 下一步
              const SizedBox(height: AppTheme.spacingMedium),
              AppButton(
                text: '下一步：语音合成 →',
                icon: Icons.record_voice_over,
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.voice);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建版本卡片
  Widget _buildVersionCard(int versionNum, Map<String, dynamic> version) {
    final score = version['score'] as int? ?? 0;
    final text = version['text'] as String? ?? '';
    final isSelected = version['is_selected'] as bool? ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: isSelected ? AppTheme.primaryColor.withOpacity(0.1) : AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: isSelected
            ? Border.all(color: AppTheme.primaryColor, width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'v$versionNum',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.primaryColor,
                ),
              ),
              const SizedBox(width: 8),
              if (score > 0) ...[
                const Icon(Icons.star, size: 16, color: Colors.amber),
                const SizedBox(width: 4),
                Text(
                  '$score分',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: score >= 80 ? AppTheme.safeColor
                        : score >= 60 ? AppTheme.lowRiskColor
                        : AppTheme.mediumRiskColor,
                  ),
                ),
              ],
              const Spacer(),
              if (isSelected)
                const Icon(Icons.check_circle, color: AppTheme.primaryColor, size: 18),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              AppButton(
                text: '对比',
                fontSize: 12,
                height: 30,
                borderRadius: AppTheme.radiusSmall,
                isOutlined: true,
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.rewriteCompare,
                    arguments: {
                      'sourceText': _sourceController.text,
                      'rewrittenText': text,
                      'score': score,
                    },
                  );
                },
              ),
              const SizedBox(width: 8),
              AppButton(
                text: isSelected ? '已选择' : '选择',
                fontSize: 12,
                height: 30,
                borderRadius: AppTheme.radiusSmall,
                onPressed: () {
                  setState(() {
                    for (final v in _versions) {
                      v['is_selected'] = false;
                    }
                    version['is_selected'] = true;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 开始改写（调用真实AI API）
  Future<void> _startRewrite() async {
    if (_selectedMode == null) {
      _showSnackBar('请先选择改写模式');
      return;
    }

    final sourceText = _sourceController.text.trim();
    if (sourceText.isEmpty) {
      _showSnackBar('请先输入原始文案');
      return;
    }

    setState(() => _isRewriting = true);

    try {
      final rewriteService = AiRewriteService(
        ref.read(apiClientProvider),
      );

      // 调用真实AI改写API，并行生成3个版本
      final results = await rewriteService.rewrite(
        sourceText: sourceText,
        mode: _selectedMode!,
        style: _selectedStyle,
        targetLength: _targetLength,
        versionCount: 3,
      );

      setState(() {
        _versions = results.map((v) {
          return {
            'text': v.rewrittenText,
            'score': v.score,
            'is_selected': v.isSelected,
          };
        }).toList();
      });
    } catch (e) {
      _showSnackBar('改写失败：$e');
    } finally {
      setState(() => _isRewriting = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}
