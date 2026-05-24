import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../providers/publish_provider.dart';

/// 一键发布页面 - 封面生成 + 多平台发布
class PublishPage extends ConsumerStatefulWidget {
  final String? videoPath;
  final String? coverPath;
  final String? title;

  const PublishPage({
    super.key,
    this.videoPath,
    this.coverPath,
    this.title,
  });

  @override
  ConsumerState<PublishPage> createState() => _PublishPageState();
}

class _PublishPageState extends ConsumerState<PublishPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _titleController = TextEditingController();
  final _keywordController = TextEditingController();
  final _descController = TextEditingController();
  final _tagsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(publishProvider.notifier).init(
            videoPath: widget.videoPath,
            coverPath: widget.coverPath,
            title: widget.title,
          );
      if (widget.title != null) {
        _titleController.text = widget.title!;
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _titleController.dispose();
    _keywordController.dispose();
    _descController.dispose();
    _tagsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(publishProvider);
    final notifier = ref.read(publishProvider.notifier);

    // 监听错误
    ref.listen<PublishState>(publishProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.errorMessage!),
            backgroundColor: AppTheme.highRiskColor,
          ),
        );
        notifier.clearError();
      }
    });

    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('一键发布'),
        backgroundColor: AppTheme.darkSurface,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '封面生成'),
            Tab(text: '发布配置'),
          ],
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textHint,
          indicatorColor: AppTheme.primaryColor,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCoverTab(state, notifier),
          _buildPublishTab(state, notifier),
        ],
      ),
    );
  }

  /// 封面生成Tab
  Widget _buildCoverTab(PublishState state, PublishNotifier notifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题输入
          const Text(
            '封面标题',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          TextField(
            controller: _titleController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '输入封面标题',
              hintStyle: const TextStyle(color: AppTheme.textHint),
              filled: true,
              fillColor: AppTheme.darkSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => notifier.setTitle(value),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 关键词
          const Text(
            '关键词',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keywordController,
                  style: const TextStyle(color: AppTheme.textPrimary),
                  decoration: InputDecoration(
                    hintText: '输入关键词后添加',
                    hintStyle: const TextStyle(color: AppTheme.textHint),
                    filled: true,
                    fillColor: AppTheme.darkSurface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (value) {
                    if (value.trim().isNotEmpty) {
                      notifier.addKeyword(value.trim());
                      _keywordController.clear();
                    }
                  },
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              ElevatedButton(
                onPressed: () {
                  final text = _keywordController.text.trim();
                  if (text.isNotEmpty) {
                    notifier.addKeyword(text);
                    _keywordController.clear();
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppTheme.spacingMedium,
                    vertical: AppTheme.spacingMedium,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                child: const Text('添加'),
              ),
            ],
          ),
          // 关键词Tag列表
          if (state.keywords.isNotEmpty) ...[
            const SizedBox(height: AppTheme.spacingSmall),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: state.keywords.map((keyword) {
                return Chip(
                  label: Text(keyword),
                  deleteIcon: const Icon(Icons.close, size: 16),
                  onDeleted: () => notifier.removeKeyword(keyword),
                  backgroundColor: AppTheme.darkSurface,
                  labelStyle: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                  deleteIconColor: AppTheme.textHint,
                  side: BorderSide(color: AppTheme.textHint.withOpacity(0.3)),
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: AppTheme.spacingLarge),

          // 风格选择
          const Text(
            '封面风格',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Row(
            children: [
              _buildStyleCard('科技感', 'tech', const Color(0xFF26C6DA), Icons.science, state, notifier),
              const SizedBox(width: AppTheme.spacingSmall),
              _buildStyleCard('情感', 'emotional', const Color(0xFFF48FB1), Icons.favorite, state, notifier),
              const SizedBox(width: AppTheme.spacingSmall),
              _buildStyleCard('悬疑', 'suspense', const Color(0xFFBA68C8), Icons.auto_fix_high, state, notifier),
            ],
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 生成封面按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.isGeneratingCover ? null : notifier.generateCover,
              icon: state.isGeneratingCover
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 20),
              label: Text(state.isGeneratingCover ? '生成中...' : '生成封面'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
              ),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 封面预览
          if (state.selectedCoverPath != null) ...[
            const Text(
              '封面预览',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Container(
              width: double.infinity,
              height: 200,
              decoration: BoxDecoration(
                color: AppTheme.darkCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(color: AppTheme.safeColor.withOpacity(0.5)),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.image, color: AppTheme.safeColor, size: 48),
                  const SizedBox(height: 8),
                  Text(
                    '封面已生成',
                    style: TextStyle(
                      color: AppTheme.safeColor,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    state.selectedCoverPath!,
                    style: const TextStyle(color: AppTheme.textHint, fontSize: 11),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 风格选择卡片
  Widget _buildStyleCard(
    String label,
    String key,
    Color color,
    IconData icon,
    PublishState state,
    PublishNotifier notifier,
  ) {
    final isSelected = state.style == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => notifier.setStyle(key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(isSelected ? 0.2 : 0.08),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? color : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 发布配置Tab
  Widget _buildPublishTab(PublishState state, PublishNotifier notifier) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 视频选择
          const Text(
            '视频',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: AppTheme.primaryColor, size: 28),
                const SizedBox(width: AppTheme.spacingMedium),
                Expanded(
                  child: state.selectedVideoPath != null &&
                          state.selectedVideoPath!.isNotEmpty
                      ? Text(
                          state.selectedVideoPath!,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        )
                      : const Text(
                          '未选择视频',
                          style: TextStyle(
                            color: AppTheme.textHint,
                            fontSize: 13,
                          ),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 封面预览
          const Text(
            '封面',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          Container(
            width: double.infinity,
            height: 120,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: state.selectedCoverPath != null
                ? Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.image, color: AppTheme.safeColor, size: 36),
                      const SizedBox(height: 4),
                      Text(
                        '封面已就绪',
                        style: TextStyle(
                          color: AppTheme.safeColor,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  )
                : const Center(
                    child: Text(
                      '请先在"封面生成"Tab生成封面',
                      style: TextStyle(color: AppTheme.textHint, fontSize: 12),
                    ),
                  ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 描述输入
          const Text(
            '描述',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          TextField(
            controller: _descController,
            maxLines: 3,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '输入视频描述...',
              hintStyle: const TextStyle(color: AppTheme.textHint),
              filled: true,
              fillColor: AppTheme.darkSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => notifier.setDescription(value),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 标签输入
          const Text(
            '标签',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          TextField(
            controller: _tagsController,
            style: const TextStyle(color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '输入标签，逗号分隔',
              hintStyle: const TextStyle(color: AppTheme.textHint),
              filled: true,
              fillColor: AppTheme.darkSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (value) => notifier.setTags(value),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 平台选择
          const Text(
            '发布平台',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          _buildPlatformCheckbox(
            '抖音',
            'douyin',
            Icons.tiktok,
            const Color(0xFFFE2C55),
            state,
            notifier,
          ),
          _buildPlatformCheckbox(
            '小红书',
            'xiaohongshu',
            Icons.book_outlined,
            const Color(0xFFFF2442),
            state,
            notifier,
          ),
          _buildPlatformCheckbox(
            'B站',
            'bilibili',
            Icons.play_circle_outline,
            const Color(0xFF00A1D6),
            state,
            notifier,
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 发布按钮
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: state.isPublishing ? null : notifier.publish,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                ),
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              child: state.isPublishing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text('发布中...'),
                      ],
                    )
                  : const Text('一键发布'),
            ),
          ),
          const SizedBox(height: AppTheme.spacingLarge),

          // 发布结果
          if (state.publishResults.isNotEmpty) ...[
            const Text(
              '发布结果',
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            ...state.publishResults.entries.map((entry) {
              final platformName = {
                'douyin': '抖音',
                'xiaohongshu': '小红书',
                'bilibili': 'B站',
              }[entry.key] ?? entry.key;
              final success = entry.value;
              return Container(
                margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                decoration: BoxDecoration(
                  color: AppTheme.darkCard,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    Icon(
                      success ? Icons.check_circle : Icons.cancel,
                      color: success ? AppTheme.safeColor : AppTheme.highRiskColor,
                      size: 22,
                    ),
                    const SizedBox(width: AppTheme.spacingMedium),
                    Expanded(
                      child: Text(
                        platformName,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Text(
                      success ? '发布成功' : '发布失败',
                      style: TextStyle(
                        color: success ? AppTheme.safeColor : AppTheme.highRiskColor,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// 平台选择Checkbox
  Widget _buildPlatformCheckbox(
    String label,
    String platformKey,
    IconData icon,
    Color color,
    PublishState state,
    PublishNotifier notifier,
  ) {
    final isChecked = state.platforms.contains(platformKey);
    return Container(
      margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: isChecked
            ? Border.all(color: color.withOpacity(0.5))
            : null,
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: isChecked ? AppTheme.textPrimary : AppTheme.textSecondary,
                fontSize: 14,
                fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          Checkbox(
            value: isChecked,
            onChanged: (_) => notifier.togglePlatform(platformKey),
            activeColor: color,
            checkColor: Colors.white,
          ),
        ],
      ),
    );
  }
}
