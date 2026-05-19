import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../providers/digital_human_provider.dart';
import '../../services/digital_human_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../utils/storage_util.dart';

/// 数字人视频页 - 上传图片 + 配音 → 生成口播视频（完整重写版）
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
  // 文案编辑控制器
  final _scriptController = TextEditingController();

  // 视频播放器
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  // 音频试听播放器
  AudioPlayer? _audioPlayer;
  bool _isAudioPlaying = false;

  // 图片选择器
  final ImagePicker _imagePicker = ImagePicker();

  // 动画控制器
  late AnimationController _progressAnimController;

  @override
  void initState() {
    super.initState();

    // 初始化文案
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _scriptController.text = widget.initialText!;
    }

    // 初始化音频路径
    if (widget.audioPath != null && widget.audioPath!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(digitalHumanProvider.notifier).setSynthesizedAudio(widget.audioPath);
        ref.read(digitalHumanProvider.notifier).setAudioSourceType(AudioSourceType.synthesized);
      });
    }

    // 监听文案变化
    _scriptController.addListener(() {
      ref.read(digitalHumanProvider.notifier).setScriptText(_scriptController.text);
    });

    // 初始化进度动画
    _progressAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );

    // 初始化音频播放器
    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _videoController?.dispose();
    _audioPlayer?.dispose();
    _progressAnimController.dispose();
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
          if (dhState.localVideoPath != null)
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
            // A. 形象选择区
            _buildAvatarSection(dhState),
            const SizedBox(height: AppTheme.spacingMedium),

            // B. 声音选择区
            _buildVoiceSection(dhState),
            const SizedBox(height: AppTheme.spacingMedium),

            // C. 文案/字幕区
            _buildScriptSection(dhState),
            const SizedBox(height: AppTheme.spacingLarge),

            // D. 视频生成区
            _buildVideoGenSection(dhState),

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  // ==================== A. 形象选择区 ====================

  Widget _buildAvatarSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('数字人形象', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '飞影数字人',
                  style: TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 形象选择方式
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 上传照片区
              Expanded(
                child: _buildPhotoUploadArea(state),
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              // 分割线
              Column(
                children: [
                  const Text('或', style: TextStyle(color: AppTheme.textHint, fontSize: 12)),
                  const SizedBox(height: 40),
                ],
              ),
              const SizedBox(width: AppTheme.spacingMedium),
              // 公版模板区
              Expanded(
                child: _buildTemplateArea(state),
              ),
            ],
          ),

          const SizedBox(height: AppTheme.spacingSmall),

          // 照片要求提示
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppTheme.darkSurface,
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: AppTheme.textHint),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '建议使用正面照、五官清晰、无遮挡，效果更佳',
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

  Widget _buildPhotoUploadArea(DigitalHumanState state) {
    final hasImage = state.avatarImagePath != null;

    return GestureDetector(
      onTap: _showImageSourceDialog,
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
          border: Border.all(
            color: hasImage ? AppTheme.primaryColor : AppTheme.textHint.withOpacity(0.3),
            width: hasImage ? 1.5 : 1,
          ),
        ),
        child: hasImage
            ? Stack(
                children: [
                  // 圆形头像预览
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ClipOval(
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              color: AppTheme.darkCard,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check_circle,
                              color: AppTheme.safeColor,
                              size: 40,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '照片已选择',
                          style: TextStyle(fontSize: 13, color: AppTheme.safeColor),
                        ),
                      ],
                    ),
                  ),
                  // 更换按钮
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface.withOpacity(0.8),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.refresh,
                        color: AppTheme.textSecondary,
                        size: 16,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.add_photo_alternate_outlined,
                    color: AppTheme.textHint,
                    size: 36,
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '上传照片',
                    style: TextStyle(fontSize: 13, color: AppTheme.textHint),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildTemplateArea(DigitalHumanState state) {
    if (state.templates.isEmpty) {
      return GestureDetector(
        onTap: () => _showSnackBar('暂无公版模板，请上传照片'),
        child: Container(
          height: 160,
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
            border: Border.all(
              color: AppTheme.textHint.withOpacity(0.3),
              width: 1,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_outline, color: AppTheme.textHint, size: 36),
              const SizedBox(height: 6),
              const Text(
                '公版模板',
                style: TextStyle(fontSize: 13, color: AppTheme.textHint),
              ),
              const SizedBox(height: 2),
              const Text(
                '暂无可用模板',
                style: TextStyle(fontSize: 11, color: AppTheme.textHint),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 160,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '公版模板',
            style: TextStyle(fontSize: 12, color: AppTheme.textHint),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: state.templates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final template = state.templates[index];
                final isSelected = state.selectedTemplate?.id == template.id;
                return GestureDetector(
                  onTap: () => ref.read(digitalHumanProvider.notifier).selectTemplate(template),
                  child: Container(
                    width: 70,
                    decoration: BoxDecoration(
                      color: AppTheme.darkCard,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.person,
                          color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                          size: 24,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          template.name,
                          style: TextStyle(
                            fontSize: 10,
                            color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ==================== B. 声音选择区 ====================

  Widget _buildVoiceSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over, color: AppTheme.accentColor, size: 20),
              const SizedBox(width: 8),
              const Text('选择声音', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 声音来源选择
          Row(
            children: [
              Expanded(
                child: _buildAudioSourceTab(
                  icon: Icons.headphones,
                  label: '使用已合成配音',
                  subtitle: state.synthesizedAudioPath != null ? '已有配音' : '暂无',
                  isSelected: state.audioSourceType == AudioSourceType.synthesized,
                  isAvailable: state.synthesizedAudioPath != null,
                  onTap: () {
                    if (state.synthesizedAudioPath != null) {
                      ref.read(digitalHumanProvider.notifier).setAudioSourceType(AudioSourceType.synthesized);
                    } else {
                      _showSnackBar('请先在语音合成页面生成配音', isError: true);
                    }
                  },
                ),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              Expanded(
                child: _buildAudioSourceTab(
                  icon: Icons.surround_sound,
                  label: '选择平台音色',
                  subtitle: '${state.platformVoices.length}个可用',
                  isSelected: state.audioSourceType == AudioSourceType.platform,
                  isAvailable: true,
                  onTap: () => ref.read(digitalHumanProvider.notifier).setAudioSourceType(AudioSourceType.platform),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 已合成配音预览
          if (state.audioSourceType == AudioSourceType.synthesized &&
              state.synthesizedAudioPath != null) ...[
            _buildSynthesizedAudioPreview(state),
          ],

          // 平台音色列表
          if (state.audioSourceType == AudioSourceType.platform) ...[
            _buildPlatformVoiceList(state),
          ],
        ],
      ),
    );
  }

  Widget _buildAudioSourceTab({
    required IconData icon,
    required String label,
    required String subtitle,
    required bool isSelected,
    required bool isAvailable,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? (isAvailable ? AppTheme.primaryColor.withOpacity(0.15) : AppTheme.textHint.withOpacity(0.05))
              : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected && isAvailable ? AppTheme.primaryColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected && isAvailable ? AppTheme.primaryColor : AppTheme.textHint,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected && isAvailable ? AppTheme.primaryColor : AppTheme.textHint,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected && isAvailable
                    ? AppTheme.primaryColor.withOpacity(0.7)
                    : AppTheme.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSynthesizedAudioPreview(DigitalHumanState state) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          // 播放按钮
          GestureDetector(
            onTap: _toggleAudioPreview,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isAudioPlaying ? Icons.pause : Icons.play_arrow,
                color: AppTheme.primaryColor,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 音频信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '已合成配音',
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  '来自语音合成页面',
                  style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                ),
              ],
            ),
          ),
          // 音频状态标识
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
    );
  }

  Widget _buildPlatformVoiceList(DigitalHumanState state) {
    if (state.platformVoices.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppTheme.spacingLarge),
        child: Column(
          children: [
            const Icon(Icons.surround_sound, size: 40, color: AppTheme.textHint),
            const SizedBox(height: 8),
            const Text(
              '暂无可用平台音色',
              style: TextStyle(color: AppTheme.textHint),
            ),
            const SizedBox(height: 4),
            Text(
              '请先配置飞影Agent Token',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint.withOpacity(0.7)),
            ),
          ],
        ),
      );
    }

    // 按性别分组
    final maleVoices = state.platformVoices.where((v) => v.gender == 'male').toList();
    final femaleVoices = state.platformVoices.where((v) => v.gender != 'male').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (femaleVoices.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('女声', style: TextStyle(fontSize: 12, color: AppTheme.textHint, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: femaleVoices.map((voice) => _buildPlatformVoiceChip(voice, state)).toList(),
          ),
          const SizedBox(height: AppTheme.spacingSmall),
        ],
        if (maleVoices.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text('男声', style: TextStyle(fontSize: 12, color: AppTheme.textHint, fontWeight: FontWeight.w600)),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: maleVoices.map((voice) => _buildPlatformVoiceChip(voice, state)).toList(),
          ),
        ],
      ],
    );
  }

  Widget _buildPlatformVoiceChip(HiflyVoice voice, DigitalHumanState state) {
    final isSelected = state.selectedPlatformVoice?.id == voice.id;

    return GestureDetector(
      onTap: () => ref.read(digitalHumanProvider.notifier).selectPlatformVoice(voice),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.accentColor.withOpacity(0.2)
              : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              voice.gender == 'male' ? Icons.face : Icons.face_3,
              size: 14,
              color: isSelected ? AppTheme.accentColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 4),
            Text(
              voice.name,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? AppTheme.accentColor : AppTheme.textSecondary,
              ),
            ),
            if (voice.style != null && voice.style!.isNotEmpty) ...[
              const SizedBox(width: 4),
              Text(
                voice.style!,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected
                      ? AppTheme.accentColor.withOpacity(0.7)
                      : AppTheme.textHint,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ==================== C. 文案/字幕区 ====================

  Widget _buildScriptSection(DigitalHumanState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('口播文案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              // 字数统计
              Text(
                '${_scriptController.text.length}字',
                style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSmall),

          // 文案编辑区
          Container(
            constraints: const BoxConstraints(minHeight: 80),
            child: TextField(
              controller: _scriptController,
              maxLines: 4,
              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.5),
              decoration: InputDecoration(
                hintText: '请输入口播文案...',
                hintStyle: const TextStyle(color: AppTheme.textHint),
                filled: true,
                fillColor: AppTheme.darkSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
                ),
                contentPadding: const EdgeInsets.all(AppTheme.spacingMedium),
              ),
            ),
          ),

          const SizedBox(height: AppTheme.spacingSmall),

          // 字幕样式预览
          _buildSubtitleStylePreview(state),
        ],
      ),
    );
  }

  Widget _buildSubtitleStylePreview(DigitalHumanState state) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black87,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '字幕样式预览',
            style: TextStyle(fontSize: 10, color: AppTheme.textHint),
          ),
          const SizedBox(height: 8),
          // 模拟视频画面
          Container(
            height: 60,
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Stack(
              alignment: Alignment.bottomCenter,
              children: [
                // 字幕
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      _scriptController.text.isEmpty ? '字幕预览文本' : _scriptController.text.substring(0, _scriptController.text.length > 15 ? 15 : _scriptController.text.length),
                      style: TextStyle(
                        color: _hexToColor(state.subtitleStyle.fontColor),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          // 字幕样式选项
          Row(
            children: [
              // 位置选择
              const Text('位置:', style: TextStyle(fontSize: 10, color: AppTheme.textHint)),
              const SizedBox(width: 4),
              _buildSubtitlePositionChip('上', 'top', state),
              const SizedBox(width: 4),
              _buildSubtitlePositionChip('中', 'center', state),
              const SizedBox(width: 4),
              _buildSubtitlePositionChip('下', 'bottom', state),
              const Spacer(),
              // 颜色选择
              const Text('颜色:', style: TextStyle(fontSize: 10, color: AppTheme.textHint)),
              const SizedBox(width: 4),
              _buildSubtitleColorDot('#FFFFFF', state),
              const SizedBox(width: 3),
              _buildSubtitleColorDot('#FFFF00', state),
              const SizedBox(width: 3),
              _buildSubtitleColorDot('#00FFFF', state),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSubtitlePositionChip(String label, String position, DigitalHumanState state) {
    final isSelected = state.subtitleStyle.position == position;
    return GestureDetector(
      onTap: () => ref.read(digitalHumanProvider.notifier).setSubtitleStyle(
        state.subtitleStyle.copyWith(position: position),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.3) : Colors.transparent,
          borderRadius: BorderRadius.circular(2),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : AppTheme.textHint.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
          ),
        ),
      ),
    );
  }

  Widget _buildSubtitleColorDot(String color, DigitalHumanState state) {
    final isSelected = state.subtitleStyle.fontColor == color;
    return GestureDetector(
      onTap: () => ref.read(digitalHumanProvider.notifier).setSubtitleStyle(
        state.subtitleStyle.copyWith(fontColor: color),
      ),
      child: Container(
        width: 16,
        height: 16,
        decoration: BoxDecoration(
          color: _hexToColor(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: isSelected ? Colors.white : Colors.transparent,
            width: 2,
          ),
        ),
      ),
    );
  }

  // ==================== D. 视频生成区 ====================

  Widget _buildVideoGenSection(DigitalHumanState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 生成按钮
        if (state.genState == VideoGenState.idle || state.genState == VideoGenState.failed)
          AppButton(
            text: state.genState == VideoGenState.failed ? '重新生成' : '生成数字人口播视频',
            icon: Icons.smart_display,
            isLoading: state.isLoading,
            onPressed: state.canGenerate
                ? () => ref.read(digitalHumanProvider.notifier).generateVideo()
                : null,
          ),

        // 生成进度
        if (state.genState != VideoGenState.idle &&
            state.genState != VideoGenState.completed &&
            state.genState != VideoGenState.failed) ...[
          AppCard(
            child: Column(
              children: [
                // 状态描述
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

                // 进度条
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

                // 进度百分比和描述
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

                // 预计等待时间
                if (state.genState == VideoGenState.queuing ||
                    state.genState == VideoGenState.processing)
                  Text(
                    '数字人视频生成通常需要2-5分钟，请耐心等待',
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                  ),
              ],
            ),
          ),
        ],

        // 视频预览播放器
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

                // 视频播放器
                _buildVideoPlayer(state),

                const SizedBox(height: AppTheme.spacingMedium),

                // 视频信息
                _buildVideoInfo(state),

                const SizedBox(height: AppTheme.spacingMedium),

                // 操作按钮
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

                // 重新生成
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

        // E. 历史生成列表
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
                  // 视频画面
                  AspectRatio(
                    aspectRatio: _videoController!.value.aspectRatio,
                    child: VideoPlayer(_videoController!),
                  ),
                  // 播放控制覆盖层
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
                            decoration: BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.play_arrow,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 进度条
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
          : Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const CircularProgressIndicator(color: AppTheme.primaryColor),
                  const SizedBox(height: 12),
                  const Text(
                    '加载视频中...',
                    style: TextStyle(color: Colors.white54, fontSize: 13),
                  ),
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
              _buildInfoItem(Icons.high_quality, '分辨率', '1080p'),
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

  // ==================== E. 历史生成列表 ====================

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
                '${state.historyList.length}条记录',
                style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 历史列表
          ...state.historyList.take(5).map((item) => _buildHistoryItem(item, state)),
        ],
      ),
    );
  }

  Widget _buildHistoryItem(VideoHistoryItem item, DigitalHumanState state) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          // 缩略图占位
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppTheme.darkCard,
              borderRadius: BorderRadius.circular(4),
            ),
            child: const Icon(
              Icons.play_circle_outline,
              color: AppTheme.textHint,
              size: 28,
            ),
          ),
          const SizedBox(width: 10),

          // 视频信息
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '数字人视频',
                  style: TextStyle(fontSize: 13, color: AppTheme.textPrimary),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      item.durationText,
                      style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _formatDate(item.createdAt),
                      style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      item.fileSizeText,
                      style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 操作按钮
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 查看按钮
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
              // 下载按钮
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
              // 删除按钮
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

  /// 显示图片来源选择对话框
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
              const Text(
                '选择照片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
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
                      _pickImage(ImageSource.gallery); // 使用gallery模拟camera
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

  /// 选择图片
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

  /// 切换音频预览播放
  Future<void> _toggleAudioPreview() async {
    final state = ref.read(digitalHumanProvider);
    if (state.synthesizedAudioPath == null) return;

    try {
      if (_isAudioPlaying) {
        await _audioPlayer?.pause();
        setState(() => _isAudioPlaying = false);
      } else {
        await _audioPlayer?.setFilePath(state.synthesizedAudioPath!);
        await _audioPlayer!.play();
        setState(() => _isAudioPlaying = true);

        _audioPlayer?.playerStateStream.listen((playerState) {
          if (playerState.processingState == ProcessingState.completed) {
            if (mounted) {
              setState(() => _isAudioPlaying = false);
            }
          }
        });
      }
    } catch (e) {
      _showSnackBar('音频播放失败', isError: true);
    }
  }

  /// 初始化视频播放器
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

    // 监听播放状态变化以更新UI
    _videoController!.addListener(() {
      if (mounted) setState(() {});
    });
  }

  /// 下载视频到相册
  Future<void> _downloadVideo(String videoPath) async {
    try {
      // 复制到用户可访问的目录
      final saveDir = await StorageUtil.getVideoDirectory();
      final fileName = '数字人_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final savePath = '$saveDir/$fileName';
      await File(videoPath).copy(savePath);
      _showSnackBar('视频已保存到：$savePath');
    } catch (e) {
      _showSnackBar('保存失败：$e', isError: true);
    }
  }

  /// 分享视频
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

  /// 播放历史视频
  Future<void> _playHistoryVideo(String videoPath) async {
    final file = File(videoPath);
    if (!await file.exists()) {
      _showSnackBar('视频文件不存在', isError: true);
      return;
    }
    await _initVideoPlayer(videoPath);
  }

  /// 显示删除历史记录对话框
  void _showDeleteHistoryDialog(String id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('删除记录', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text(
          '确定要删除这条生成记录吗？',
          style: TextStyle(color: AppTheme.textSecondary),
        ),
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

  /// 显示历史记录弹窗
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
                  const Text(
                    '历史生成记录',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
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
                  ? const Center(
                      child: Text('暂无生成记录', style: TextStyle(color: AppTheme.textHint)),
                    )
                  : ListView.builder(
                      controller: scrollController,
                      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMedium),
                      itemCount: state.historyList.length,
                      itemBuilder: (context, index) {
                        return _buildHistoryItem(state.historyList[index], state);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== 辅助方法 ====================

  String _getGenStateText(VideoGenState genState) {
    switch (genState) {
      case VideoGenState.uploading:
        return '上传照片中...';
      case VideoGenState.queuing:
        return '排队中...';
      case VideoGenState.processing:
        return '处理中...';
      case VideoGenState.rendering:
        return '渲染中...';
      case VideoGenState.completed:
        return '生成完成！';
      case VideoGenState.failed:
        return '生成失败';
      default:
        return '准备中...';
    }
  }

  Color _hexToColor(String hexColor) {
    final hex = hexColor.replaceAll('#', '');
    return Color(int.parse('FF$hex', radix: 16));
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
