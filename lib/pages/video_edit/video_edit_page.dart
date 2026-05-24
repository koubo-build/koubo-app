import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/video_edit_provider.dart';

/// 视频混剪页面 - 6步骤引导式视频合成
class VideoEditPage extends ConsumerStatefulWidget {
  final String? initialScript;
  final String? faceVideoPath;

  const VideoEditPage({
    super.key,
    this.initialScript,
    this.faceVideoPath,
  });

  @override
  ConsumerState<VideoEditPage> createState() => _VideoEditPageState();
}

class _VideoEditPageState extends ConsumerState<VideoEditPage> {
  final _scriptController = TextEditingController();
  final _searchController = TextEditingController();
  final _keywordInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // 延迟初始化，避免在build中触发状态更新
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(videoEditProvider.notifier).init(
            initialScript: widget.initialScript,
            faceVideoPath: widget.faceVideoPath,
          );
      if (widget.initialScript != null) {
        _scriptController.text = widget.initialScript!;
      }
      // 加载默认音乐列表
      ref.read(videoEditProvider.notifier).loadMusicList();
    });
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _searchController.dispose();
    _keywordInputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(videoEditProvider);
    

    // 监听错误
    ref.listen<VideoEditState>(videoEditProvider, (prev, next) {
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
        title: const Text('视频混剪'),
        backgroundColor: AppTheme.darkSurface,
      ),
      body: Column(
        children: [
          // 步骤条
          _buildStepBar(notifier.currentStep),
          // 步骤内容
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: _buildStepContent(notifier.currentStep, notifier),
            ),
          ),
          // 底部操作栏
          _buildBottomBar(state, notifier),
        ],
      ),
    );
  }

  /// 步骤条
  Widget _buildStepBar(int currentStep) {
    const stepLabels = ['文案', '数字人', '风格', '背景', '音乐', '字幕'];
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingSmall,
        vertical: AppTheme.spacingMedium,
      ),
      color: AppTheme.darkSurface,
      child: Row(
        children: List.generate(6, (index) {
          final isCompleted = index < currentStep;
          final isCurrent = index == currentStep;
          Color circleColor;
          Color textColor;
          if (isCompleted) {
            circleColor = AppTheme.safeColor;
            textColor = AppTheme.safeColor;
          } else if (isCurrent) {
            circleColor = AppTheme.primaryColor;
            textColor = AppTheme.primaryColor;
          } else {
            circleColor = AppTheme.textHint;
            textColor = AppTheme.textHint;
          }

          return Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: circleColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: circleColor, width: 2),
                  ),
                  child: Center(
                    child: isCompleted
                        ? Icon(Icons.check, color: circleColor, size: 16)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: circleColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  stepLabels[index],
                  style: TextStyle(
                    color: textColor,
                    fontSize: 11,
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  /// 步骤内容
  Widget _buildStepContent(int step, VideoEditNotifier notifier) {
    switch (step) {
      case 0:
        return _buildScriptStep(notifier);
      case 1:
        return _buildFaceVideoStep(notifier);
      case 2:
        return _buildStyleStep(notifier);
      case 3:
        return _buildBgVideoStep(notifier);
      case 4:
        return _buildMusicStep(notifier);
      case 5:
        return _buildSubtitleStep(notifier);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 步骤1：选择文案
  Widget _buildScriptStep(VideoEditNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '编辑口播文案',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Text(
          '文案将用于生成字幕和视频配音',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        TextField(
          controller: _scriptController,
          maxLines: 12,
          onChanged: (value) => notifier.setScriptText(value),
          style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15),
          decoration: InputDecoration(
            hintText: '请输入口播文案内容...',
            hintStyle: const TextStyle(color: AppTheme.textHint),
            filled: true,
            fillColor: AppTheme.darkSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Text(
          '${notifier.scriptText.length} 字',
          style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
        ),
      ],
    );
  }

  /// 步骤2：选择数字人视频
  Widget _buildFaceVideoStep(VideoEditNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选择数字人视频',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Text(
          '选择一个已生成的数字人视频作为画面主体',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        // 已选择的数字人视频
        if (notifier.faceVideoPath != null && notifier.faceVideoPath!.isNotEmpty)
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              border: Border.all(color: AppTheme.safeColor.withOpacity(0.5)),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, color: AppTheme.safeColor, size: 32),
                const SizedBox(width: AppTheme.spacingMedium),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '已选择数字人视频',
                        style: TextStyle(
                          color: AppTheme.safeColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        notifier.faceVideoPath!,
                        style: const TextStyle(
                          color: AppTheme.textHint,
                          fontSize: 11,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(AppTheme.spacingLarge),
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            ),
            child: Column(
              children: [
                const Icon(Icons.smart_toy_outlined,
                    size: 48, color: AppTheme.textHint),
                const SizedBox(height: AppTheme.spacingMedium),
                const Text(
                  '暂未选择数字人视频',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, AppRoutes.digitalHuman);
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 18),
                  label: const Text('去生成数字人视频'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 步骤3：选择风格
  Widget _buildStyleStep(VideoEditNotifier notifier) {
    final styles = [
      {'key': 'tech', 'label': '科技感', 'color': const Color(0xFF26C6DA), 'icon': Icons.science},
      {'key': 'emotional', 'label': '情感', 'color': const Color(0xFFF48FB1), 'icon': Icons.favorite},
      {'key': 'suspense', 'label': '悬疑', 'color': const Color(0xFFBA68C8), 'icon': Icons.auto_fix_high},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选择视频风格',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Text(
          '不同风格将匹配不同的背景素材和音乐风格',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingLarge),
        Row(
          children: styles.map((s) {
            final isSelected = notifier.selectedStyle == s['key'];
            final color = s['color'] as Color;
            return Expanded(
              child: GestureDetector(
                onTap: () => notifier.selectStyle(s['key'] as String),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    vertical: AppTheme.spacingLarge,
                    horizontal: AppTheme.spacingMedium,
                  ),
                  decoration: BoxDecoration(
                    color: color.withOpacity(isSelected ? 0.2 : 0.08),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    border: Border.all(
                      color: isSelected ? color : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(s['icon'] as IconData,
                          color: color, size: 36),
                      const SizedBox(height: AppTheme.spacingSmall),
                      Text(
                        s['label'] as String,
                        style: TextStyle(
                          color: isSelected ? color : AppTheme.textSecondary,
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  /// 步骤4：背景素材
  Widget _buildBgVideoStep(VideoEditNotifier notifier) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '搜索背景素材',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Text(
          '从Pexels搜索匹配的视频素材作为背景',
          style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        // 搜索框
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '输入关键词搜索素材...',
                  hintStyle: const TextStyle(color: AppTheme.textHint),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textHint),
                  filled: true,
                  fillColor: AppTheme.darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    borderSide: BorderSide.none,
                  ),
                ),
                onSubmitted: (value) => notifier.searchMaterials(value),
              ),
            ),
            const SizedBox(width: AppTheme.spacingSmall),
            ElevatedButton(
              onPressed: notifier.isSearching
                  ? null
                  : () => notifier.searchMaterials(_searchController.text),
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
              child: const Text('搜索'),
            ),
          ],
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        // 搜索结果网格
        if (notifier.isSearching)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          )
        else if (notifier.bgVideoList.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            child: Column(
              children: [
                Icon(Icons.video_library_outlined,
                    size: 48, color: AppTheme.textHint.withOpacity(0.5)),
                const SizedBox(height: 8),
                Text(
                  '输入关键词搜索背景素材',
                  style: TextStyle(color: AppTheme.textHint, fontSize: 13),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppTheme.spacingSmall,
              crossAxisSpacing: AppTheme.spacingSmall,
              childAspectRatio: 16 / 11,
            ),
            itemCount: notifier.bgVideoList.length,
            itemBuilder: (context, index) {
              final video = notifier.bgVideoList[index];
              final isSelected = notifier.selectedBgVideo?['id'] == video['id'];
              return GestureDetector(
                onTap: () => notifier.selectBgVideo(video),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppTheme.darkCard,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: isSelected
                        ? Border.all(color: AppTheme.primaryColor, width: 2)
                        : null,
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // 缩略图占位
                      Container(
                        decoration: BoxDecoration(
                          color: AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        ),
                        child: const Icon(
                          Icons.play_circle_outline,
                          color: AppTheme.textHint,
                          size: 32,
                        ),
                      ),
                      // 时长标签
                      Positioned(
                        bottom: 4,
                        right: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${video['duration']}s',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ),
                      ),
                      // 选中标识
                      if (isSelected)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: AppTheme.primaryColor,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.check,
                                color: Colors.white, size: 14),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  /// 步骤5：背景音乐
  Widget _buildMusicStep(VideoEditNotifier notifier) {
    final tabs = [
      {'key': 'tech', 'label': '科技感'},
      {'key': 'emotional', 'label': '情感'},
      {'key': 'suspense', 'label': '悬疑'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '选择背景音乐',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        // 音乐分类Tab
        Row(
          children: tabs.map((tab) {
            final isActive = notifier.currentMusicCategory == tab['key'];
            return Expanded(
              child: GestureDetector(
                onTap: () => notifier.switchMusicCategory(tab['key'] as String),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppTheme.primaryColor.withOpacity(0.2)
                        : AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    border: Border.all(
                      color: isActive ? AppTheme.primaryColor : Colors.transparent,
                    ),
                  ),
                  child: Text(
                    tab['label'] as String,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: isActive ? AppTheme.primaryColor : AppTheme.textSecondary,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: AppTheme.spacingMedium),
        // 音乐列表
        if (notifier.musicList.isEmpty)
          Container(
            padding: const EdgeInsets.all(32),
            child: const Center(
              child: Text(
                '暂无音乐数据',
                style: TextStyle(color: AppTheme.textHint),
              ),
            ),
          )
        else
          ...notifier.musicList.map((music) {
            final isSelected = notifier.selectedMusic?['id'] == music['id'];
            return Container(
              margin: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryColor.withOpacity(0.1)
                    : AppTheme.darkCard,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: isSelected
                    ? Border.all(color: AppTheme.primaryColor, width: 1.5)
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.music_note,
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                    size: 24,
                  ),
                  const SizedBox(width: AppTheme.spacingMedium),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          music['name'] ?? '',
                          style: TextStyle(
                            color: isSelected
                                ? AppTheme.primaryColor
                                : AppTheme.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '时长 ${music['duration'] ?? ''}',
                          style: const TextStyle(
                            color: AppTheme.textHint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () => notifier.selectMusic(music),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isSelected
                          ? AppTheme.primaryColor
                          : AppTheme.darkSurface,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(isSelected ? '已选' : '选择'),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }

  /// 步骤6：字幕设置
  Widget _buildSubtitleStep(VideoEditNotifier notifier) {
    final settings = notifier.subtitleSettings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '字幕设置',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: AppTheme.spacingLarge),
        // 字体大小
        Row(
          children: [
            const Text(
              '字体大小',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
            ),
            const Spacer(),
            Text(
              '${settings.fontSize.round()}',
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Slider(
          value: settings.fontSize,
          min: 16,
          max: 32,
          divisions: 16,
          activeColor: AppTheme.primaryColor,
          inactiveColor: AppTheme.darkSurface,
          onChanged: (value) {
            notifier.updateSubtitleSettings(
              settings.copyWith(fontSize: value),
            );
          },
        ),
        const SizedBox(height: AppTheme.spacingLarge),
        // 字幕颜色
        const Text(
          '字幕颜色',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Row(
          children: [
            _buildColorDot(notifier, settings, 'white', Colors.white),
            const SizedBox(width: AppTheme.spacingLarge),
            _buildColorDot(notifier, settings, 'yellow', Colors.yellow),
            const SizedBox(width: AppTheme.spacingLarge),
            _buildColorDot(notifier, settings, 'green', Colors.green),
          ],
        ),
        const SizedBox(height: AppTheme.spacingLarge),
        // 字幕位置
        const Text(
          '字幕位置',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: AppTheme.spacingSmall),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () => notifier.updateSubtitleSettings(
                  settings.copyWith(position: 'top'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: settings.position == 'top'
                      ? AppTheme.primaryColor
                      : AppTheme.darkSurface,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                ),
                child: const Text('顶部'),
              ),
            ),
            const SizedBox(width: AppTheme.spacingMedium),
            Expanded(
              child: ElevatedButton(
                onPressed: () => notifier.updateSubtitleSettings(
                  settings.copyWith(position: 'bottom'),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: settings.position == 'bottom'
                      ? AppTheme.primaryColor
                      : AppTheme.darkSurface,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                ),
                child: const Text('底部'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 字幕颜色选择圆点
  Widget _buildColorDot(
      VideoEditNotifier notifier, SubtitleSettings settings, String colorKey, Color color) {
    final isSelected = settings.color == colorKey;
    return GestureDetector(
      onTap: () => notifier.updateSubtitleSettings(
        settings.copyWith(color: colorKey),
      ),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(color: AppTheme.primaryColor, width: 3)
              : Border.all(color: AppTheme.textHint, width: 1),
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.black54, size: 18)
            : null,
      ),
    );
  }

  /// 底部操作栏
  Widget _buildBottomBar(VideoEditNotifier notifier) {
    // 合成中：显示进度
    if (notifier.isComposing) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        color: AppTheme.darkSurface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Text(
                  '视频合成中...',
                  style: TextStyle(color: AppTheme.textPrimary, fontSize: 14),
                ),
                const Spacer(),
                Text(
                  '${(notifier.composeProgress * 100).round()}%',
                  style: const TextStyle(
                    color: AppTheme.primaryColor,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: notifier.composeProgress,
                backgroundColor: AppTheme.darkCard,
                valueColor: const AlwaysStoppedAnimation<Color>(
                    AppTheme.primaryColor),
                minHeight: 8,
              ),
            ),
          ],
        ),
      );
    }

    // 合成完成：显示结果
    if (notifier.resultVideoPath != null) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        color: AppTheme.darkSurface,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.check_circle, color: AppTheme.safeColor),
                const SizedBox(width: AppTheme.spacingSmall),
                const Expanded(
                  child: Text(
                    '视频合成完成！',
                    style: TextStyle(
                      color: AppTheme.safeColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    // 跳转发布页
                    Navigator.pushNamed(
                      context,
                      AppRoutes.publish,
                      arguments: {
                        'videoPath': notifier.resultVideoPath,
                      },
                    );
                  },
                  icon: const Icon(Icons.publish, size: 18),
                  label: const Text('去发布'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    // 默认：上一步/下一步按钮
    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      color: AppTheme.darkSurface,
      child: Row(
        children: [
          if (notifier.currentStep > 0)
            Expanded(
              child: OutlinedButton(
                onPressed: notifier.prevStep,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                  side: const BorderSide(color: AppTheme.textHint),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                ),
                child: const Text('上一步'),
              ),
            ),
          if (notifier.currentStep > 0)
            const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: notifier.currentStep < 5
                ? ElevatedButton(
                    onPressed: notifier.nextStep,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                    child: const Text('下一步'),
                  )
                : ElevatedButton.icon(
                    onPressed: notifier.compose,
                    icon: const Icon(Icons.movie_creation, size: 20),
                    label: const Text('开始合成'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
