import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/digital_human_provider.dart';
import '../../services/digital_human_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../utils/storage_util.dart';

/// 数字人视频页 - 万相wan2.2-s2v版
/// 
/// 新流程：上传照片 → 选择分辨率 → 生成视频
/// 
/// OmniHuman1.5特点：
/// - 用户上传自己的照片作为数字人形象
/// - 需要配合配音使用（从语音合成页带入）
/// - 可选提示词控制画面效果
/// - 可选分辨率(720p/1080p)和快速模式
class DigitalHumanPage extends ConsumerStatefulWidget {
  /// 从工作台跳转时传入的初始文案
  final String? initialText;

  /// 从语音合成页带入的音频路径
  final String? audioPath;

  const DigitalHumanPage({super.key, this.initialText, this.audioPath});

  @override
  ConsumerState<DigitalHumanPage> createState() => _DigitalHumanPageState();
}

class _DigitalHumanPageState extends ConsumerState<DigitalHumanPage>
    with TickerProviderStateMixin {
  // 提示词控制器
  final _promptController = TextEditingController();

  // 视频播放器
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  // 图片选择器
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();

    // 初始化音频路径（从语音合成页带入）
    if (widget.audioPath != null && widget.audioPath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(digitalHumanProvider.notifier).setAudioPath(widget.audioPath);
      });
    }
    
    // 监听提示词变化
    _promptController.addListener(() {
      ref.read(digitalHumanProvider.notifier).setPrompt(_promptController.text);
    });
  }

  @override
  void dispose() {
    _promptController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dhState = ref.watch(digitalHumanProvider);

    // 监听错误信息
    ref.listen<DigitalHumanState>(digitalHumanProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        _showSnackBar(next.errorMessage!, isError: true);
        ref.read(digitalHumanProvider.notifier).clearError();
      }
      // 视频生成完成时初始化播放器
      if (next.genState == VideoGenState.completed &&
          next.localVideoPath != null &&
          prev?.genState != VideoGenState.completed) {
        _initVideoPlayer(next.localVideoPath!);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('数字人视频'),
        actions: [
          if (dhState.historyList.isNotEmpty)
            IconButton(
              onPressed: _showHistory,
              icon: const Icon(Icons.history, size: 22),
              tooltip: '历史记录',
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // A. 照片上传区
            _buildPhotoSection(dhState),
            const SizedBox(height: AppTheme.spacingMedium),

            // B. 配音信息区（只读，从语音合成页带入）
            _buildAudioSection(dhState),
            const SizedBox(height: AppTheme.spacingMedium),

            // C. 画面参数设置
            _buildVideoSettingsSection(dhState),
            const SizedBox(height: AppTheme.spacingMedium),

            // D. 文案输入
            _buildScriptSection(dhState),
            const SizedBox(height: AppTheme.spacingLarge),

            // E. 视频生成区
            _buildVideoGenSection(dhState),

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  // ==================== A. 照片上传区 ====================

  Widget _buildPhotoSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.photo_camera, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('照片上传', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '万相数字人',
                  style: TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (state.photoReady)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppTheme.safeColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: AppTheme.safeColor),
                      SizedBox(width: 4),
                      Text('就绪', style: TextStyle(fontSize: 10, color: AppTheme.safeColor)),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 照片选择/预览区（idle/failed/completed 都允许更换照片）
          GestureDetector(
            onTap: _canEdit ? _showImageSourceDialog : null,
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                border: Border.all(
                  color: state.photoReady 
                      ? AppTheme.safeColor 
                      : (state.avatarImagePath != null 
                          ? AppTheme.textHint.withOpacity(0.5) 
                          : AppTheme.textHint.withOpacity(0.3)),
                  width: state.photoReady ? 2 : 1,
                ),
              ),
              child: state.avatarImagePath != null
                  ? _buildPhotoPreview(state)
                  : _buildPhotoPlaceholder(),
            ),
          ),

          const SizedBox(height: AppTheme.spacingSmall),

          // 照片要求提示
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppTheme.textHint),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '建议正面照、五官清晰、无遮挡，效果更佳。',
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoPlaceholder() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.add_photo_alternate_outlined, color: AppTheme.textHint, size: 48),
        const SizedBox(height: 8),
        const Text('点击上传照片', style: TextStyle(fontSize: 14, color: AppTheme.textHint)),
        const SizedBox(height: 4),
        Text(
          '支持 jpg/png/bmp/webp，不超过10MB',
          style: TextStyle(fontSize: 11, color: AppTheme.textHint.withOpacity(0.7)),
        ),
      ],
    );
  }

  Widget _buildPhotoPreview(DigitalHumanState state) {
    return Stack(
      children: [
        // 照片预览
        ClipRRect(
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium - 1),
          child: Image.file(
            File(state.avatarImagePath!),
            width: double.infinity,
            height: 180,
            fit: BoxFit.cover,
          ),
        ),
        // 更换按钮（idle/failed/completed 都显示）
        if (_canEdit)
          Positioned(
            top: 8,
            right: 8,
            child: GestureDetector(
              onTap: _showImageSourceDialog,
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Icon(Icons.refresh, color: Colors.white, size: 18),
              ),
            ),
          ),
      ],
    );
  }

  // ==================== B. 配音信息区 ====================

  Widget _buildAudioSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.audiotrack, color: AppTheme.accentColor, size: 20),
              const SizedBox(width: 8),
              const Text('配音信息', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '来自语音合成',
                  style: TextStyle(fontSize: 10, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          if (state.audioPath != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.accentColor.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.music_note, color: AppTheme.accentColor, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '已合成配音',
                          style: TextStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w500),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '可直接用于生成数字人视频',
                          style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.safeColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '就绪',
                      style: TextStyle(fontSize: 11, color: AppTheme.safeColor, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(AppTheme.spacingLarge),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Column(
                children: [
                  const Icon(Icons.music_off, color: AppTheme.textHint, size: 32),
                  const SizedBox(height: 8),
                  const Text(
                    '暂无配音',
                    style: TextStyle(color: AppTheme.textHint, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(context, AppRoutes.voice),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('去生成配音'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.accentColor,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== C. 画面参数设置 ====================

  Widget _buildVideoSettingsSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('画面设置', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '可选',
                  style: TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 分辨率选择
          Row(
            children: [
              const Text('分辨率', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(width: 16),
              _buildResolutionChip('480P', state),
              const SizedBox(width: 8),
              _buildResolutionChip('720P', state),
            ],
          ),

          const SizedBox(height: 12),

          // 快速模式
          Row(
            children: [
              const Text('快速模式', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const SizedBox(width: 8),
              Tooltip(
                message: '480P更便宜，720P更清晰',
                child: Icon(Icons.help_outline, size: 14, color: AppTheme.textHint),
              ),
              const Spacer(),
              Switch(
                value: state.fastMode,
                onChanged: _canEdit
                    ? (v) => ref.read(digitalHumanProvider.notifier).setFastMode(v)
                    : null,
                activeColor: AppTheme.primaryColor,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // 画面提示词
          const Text('画面提示词', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _promptController,
            maxLines: 2,
            minLines: 1,
            style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              hintText: '可选，描述期望的画面效果，如"正式场合"、"微笑"',
              hintStyle: TextStyle(color: AppTheme.textHint, fontSize: 12),
              filled: true,
              fillColor: AppTheme.darkSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(10),
              isDense: true,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '提示词最长300字符（中/英/日/韩），可控制人物动作、表情等',
            style: TextStyle(fontSize: 10, color: AppTheme.textHint),
          ),
        ],
      ),
    );
  }

  Widget _buildResolutionChip(String label, DigitalHumanState state) {
    final isSelected = state.outputResolution.toString() == label.replaceAll('P', '');
    return GestureDetector(
      onTap: _canEdit
          ? () => ref.read(digitalHumanProvider.notifier).setOutputResolution(
              int.parse(label.replaceAll('P', '')))
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected 
              ? AppTheme.primaryColor.withOpacity(0.15)
              : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  // ==================== D. 文案输入 ====================

  Widget _buildScriptSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('口播文案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'AI生成',
                  style: TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
              const Spacer(),
              if (state.scriptText.isNotEmpty)
                Text(
                  '${state.scriptText.length}字',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSmall),

          // 已有文案时显示预览 + 操作按钮
          if (state.scriptText.isNotEmpty) ...[
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: 80),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Text(
                state.scriptText,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6),
              ),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Row(
              children: [
                Expanded(
                  child: AppButton(
                    text: '重新生成',
                    icon: Icons.refresh,
                    isOutlined: true,
                    isLoading: state.isGeneratingScript,
                    onPressed: _canEdit && !state.isGeneratingScript
                        ? () => ref.read(digitalHumanProvider.notifier).generateScript()
                        : null,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSmall),
                Expanded(
                  child: AppButton(
                    text: '清除',
                    icon: Icons.delete_outline,
                    isOutlined: true,
                    onPressed: _canEdit && !state.isGeneratingScript
                        ? () => ref.read(digitalHumanProvider.notifier).setScriptText('')
                        : null,
                  ),
                ),
              ],
            ),
          ] else ...[
            // 无文案时显示生成按钮
            AppButton(
              text: state.isGeneratingScript ? 'AI生成中...' : 'AI生成口播文案',
              icon: Icons.auto_awesome,
              isLoading: state.isGeneratingScript,
              onPressed: _canEdit && !state.isGeneratingScript
                  ? () => ref.read(digitalHumanProvider.notifier).generateScript()
                  : null,
            ),
            const SizedBox(height: 6),
            const Text(
              '根据配音内容自动生成适合口播的文案',
              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
            ),
          ],
        ],
      ),
    );
  }

  // ==================== E. 视频生成区 ====================

  Widget _buildVideoGenSection(DigitalHumanState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 生成按钮（空闲或失败状态）
        if (state.genState == VideoGenState.idle || state.genState == VideoGenState.failed)
          AppButton(
            text: state.genState == VideoGenState.failed ? '重新生成' : '生成数字人视频',
            icon: Icons.smart_display,
            isLoading: false,
            onPressed: state.canGenerate
                ? () => ref.read(digitalHumanProvider.notifier).generateVideo()
                : null,
          ),

        // 进度显示（生成中）
        if (state.genState != VideoGenState.idle &&
            state.genState != VideoGenState.completed &&
            state.genState != VideoGenState.failed) ...[
          AppCard(
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getGenStateText(state.genState),
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: state.progress / 100,
                    backgroundColor: AppTheme.textHint.withOpacity(0.2),
                    valueColor: AlwaysStoppedAnimation(AppTheme.primaryColor),
                    minHeight: 8,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state.progressMessage,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    Text(
                      '${state.progress}%',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.primaryColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingSmall),
                const Text(
                  '万相数字人生成通常需要1-3分钟，请耐心等待',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
              ],
            ),
          ),
        ],

        // 视频预览（完成状态）
        if (state.genState == VideoGenState.completed && state.localVideoPath != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.play_circle, color: AppTheme.safeColor, size: 20),
                    const SizedBox(width: 8),
                    const Text('视频预览', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                _buildVideoPlayer(state),
                const SizedBox(height: AppTheme.spacingMedium),
                _buildVideoInfo(state),
                const SizedBox(height: AppTheme.spacingMedium),
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: '下载视频',
                        icon: Icons.download,
                        onPressed: () => _downloadVideo(state.localVideoPath!),
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSmall),
                    Expanded(
                      child: AppButton(
                        text: '分享',
                        icon: Icons.share,
                        isOutlined: true,
                        onPressed: () => _shareVideo(state.localVideoPath!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingSmall),
                AppButton(
                  text: '重新生成',
                  icon: Icons.refresh,
                  isOutlined: true,
                  onPressed: () {
                    _videoController?.dispose();
                    _videoController = null;
                    ref.read(digitalHumanProvider.notifier).resetGenState();
                  },
                ),
              ],
            ),
          ),
        ],

        // 历史记录
        if (state.historyList.isNotEmpty && state.genState == VideoGenState.idle) ...[
          const SizedBox(height: AppTheme.spacingMedium),
          _buildHistorySection(state),
        ],
      ],
    );
  }

  Widget _buildVideoPlayer(DigitalHumanState state) {
    return Container(
      width: double.infinity,
      height: 240,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: _isVideoInitialized && _videoController != null
          ? ClipRRect(
              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: [
                  AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _videoController!.value.isPlaying
                            ? _videoController!.pause()
                            : _videoController!.play();
                      });
                    },
                    child: Container(
                      color: Colors.transparent,
                      child: Center(
                        child: AnimatedOpacity(
                          opacity: _videoController!.value.isPlaying ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.play_arrow, color: Colors.white, size: 36),
                          ),
                        ),
                      ),
                    ),
                  ),
                  VideoProgressIndicator(
                    _videoController!,
                    allowScrubbing: true,
                    colors: VideoProgressColors(
                      playedColor: AppTheme.primaryColor,
                      bufferedColor: AppTheme.primaryColor.withOpacity(0.3),
                      backgroundColor: AppTheme.textHint.withOpacity(0.3),
                    ),
                  ),
                ],
              ),
            )
          : const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: AppTheme.primaryColor),
                  SizedBox(height: 12),
                  Text('加载视频中...', style: TextStyle(color: Colors.white54, fontSize: 13)),
                ],
              ),
            ),
    );
  }

  Widget _buildVideoInfo(DigitalHumanState state) {
    final localPath = state.localVideoPath;
    if (localPath == null) return const SizedBox.shrink();

    return FutureBuilder<Map<String, dynamic>>(
      future: ref.read(digitalHumanServiceProvider).getVideoInfo(localPath),
      builder: (context, snapshot) {
        final info = snapshot.data ?? {};
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildInfoItem(Icons.timer, '时长', '--'),
              _buildInfoItem(Icons.high_quality, '分辨率', state.resolutionText),
              _buildInfoItem(Icons.folder, '大小', info['sizeText'] as String? ?? '--'),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInfoItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppTheme.textHint),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
        Text(value, style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
      ],
    );
  }

  // ==================== G. 历史记录 ====================

  Widget _buildHistorySection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('历史生成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(
                '${state.historyList.length}条',
                style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),
          ...state.historyList.take(3).map((item) => _buildHistoryItem(item)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(VideoHistoryItem item) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(Icons.play_circle_outline, color: AppTheme.textHint, size: 28),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('数字人视频', style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(_formatDate(item.createdAt), style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
                    const SizedBox(width: 8),
                    Text(item.fileSizeText, style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
                  ],
                ),
              ],
            ),
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: () => _playHistoryVideo(item.videoPath),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.play_arrow, size: 14, color: AppTheme.primaryColor),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _downloadVideo(item.videoPath),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.safeColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.download, size: 14, color: AppTheme.safeColor),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: () => _showDeleteHistoryDialog(item.id),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.highRiskColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline, size: 14, color: AppTheme.highRiskColor),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== 交互方法 ====================

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('选择照片', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: AppTheme.spacingMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildImageSourceOption(
                    icon: Icons.photo_library,
                    label: '从相册选择',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.gallery);
                    },
                  ),
                  _buildImageSourceOption(
                    icon: Icons.camera_alt,
                    label: '拍照',
                    onTap: () {
                      Navigator.pop(context);
                      _pickImage(ImageSource.camera);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.darkCard,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        ),
        child: Column(
          children: [
            Icon(icon, size: 32, color: AppTheme.primaryColor),
            const SizedBox(height: 8),
            Text(label, style: TextStyle(fontSize: 13, color: AppTheme.textPrimary)),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _imagePicker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );

      if (image != null) {
        ref.read(digitalHumanProvider.notifier).setAvatarImage(image.path);
      }
    } catch (e) {
      _showSnackBar('选择图片失败：$e', isError: true);
    }
  }

  Future<void> _initVideoPlayer(String videoPath) async {
    _videoController?.dispose();
    _isVideoInitialized = false;

    _videoController = VideoPlayerController.file(File(videoPath));

    try {
      await _videoController!.initialize();
      setState(() => _isVideoInitialized = true);
      _videoController!.setLooping(true);
      _videoController!.play();
    } catch (e) {
      _showSnackBar('视频加载失败', isError: true);
    }

    _videoController!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  Future<void> _downloadVideo(String videoPath) async {
    try {
      final saveDir = await StorageUtil.getVideoDirectory();
      final fileName = 'wanx_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savePath = '$saveDir/$fileName';
      await File(videoPath).copy(savePath);
      _showSnackBar('视频已保存到：$savePath');
    } catch (e) {
      _showSnackBar('保存失败：$e', isError: true);
    }
  }

  Future<void> _shareVideo(String videoPath) async {
    try {
      await Share.shareXFiles(
        [XFile(videoPath)],
        text: '口播智能体生成的数字人视频',
      );
    } catch (e) {
      _showSnackBar('分享失败：$e', isError: true);
    }
  }

  Future<void> _playHistoryVideo(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      _showSnackBar('视频文件不存在', isError: true);
      return;
    }
    await _initVideoPlayer(videoPath);
  }

  void _showDeleteHistoryDialog(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('删除记录', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('确定要删除这条生成记录吗？', style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(digitalHumanProvider.notifier).deleteHistoryItem(id);
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.highRiskColor)),
          ),
        ],
      ),
    );
  }

  void _showHistory() {
    final state = ref.read(digitalHumanProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        minChildSize: 0.3,
        expand: false,
        builder: (context, scrollController) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: Row(
                children: [
                  const Text('历史生成记录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            Expanded(
              child: state.historyList.isEmpty
                  ? const Center(child: Text('暂无生成记录', style: TextStyle(color: AppTheme.textHint)))
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
                      itemCount: state.historyList.length,
                      itemBuilder: (context, index) => _buildHistoryItem(state.historyList[index]),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 辅助方法 ====================

  /// 是否可编辑设置（非生成过程中都可操作）
  bool get _canEdit {
    final s = ref.read(digitalHumanProvider).genState;
    return s == VideoGenState.idle || s == VideoGenState.failed || s == VideoGenState.completed;
  }

  String _getGenStateText(VideoGenState genState) {
    switch (genState) {
      case VideoGenState.processingImage:
        return '处理图片中...';
      case VideoGenState.uploadingAudio:
        return '上传配音中...';
      case VideoGenState.submitting:
        return '提交任务中...';
      case VideoGenState.processing:
        return '生成中...';
      case VideoGenState.downloading:
        return '下载视频中...';
      case VideoGenState.completed:
        return '生成完成！';
      case VideoGenState.failed:
        return '生成失败';
      default:
        return '准备中...';
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? AppTheme.highRiskColor : AppTheme.safeColor,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.month}/${date.day} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}
