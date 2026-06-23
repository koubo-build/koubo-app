import 'dart:math' as math;
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:record/record.dart' hide RecordState;
import 'package:permission_handler/permission_handler.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/voice_model.dart';
import '../../providers/voice_provider.dart';
import '../../services/tts_service.dart';
import '../../utils/storage_util.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_input.dart';
import '../../widgets/common/api_config_indicator.dart';

/// 语音合成页 - 录音克隆声音 + 文案配音（完整重写版）
class VoicePage extends ConsumerStatefulWidget {
  /// 从工作台跳转时传入的初始文案
  final String? initialText;

  /// 从其他页面带入的音频路径
  final String? audioPath;

  const VoicePage({super.key, this.initialText, this.audioPath});

  @override
  ConsumerState<VoicePage> createState() => _VoicePageState();
}

class _VoicePageState extends ConsumerState<VoicePage>
    with TickerProviderStateMixin {
  // 文案输入控制器
  final _scriptController = TextEditingController();

  // 录音相关
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _recordTimer;
  bool _isRecording = false;

  // 音频播放器
  AudioPlayer? _audioPlayer;
  Timer? _playProgressTimer;

  // 克隆音色名称输入控制器
  final _cloneNameController = TextEditingController();

  // 动画控制器
  late AnimationController _pulseAnimController;
  late AnimationController _waveAnimController;

  // 试听播放器
  AudioPlayer? _previewPlayer;
  String? _previewingVoiceId;

  @override
  void initState() {
    super.initState();

    // 初始化文案
    if (widget.initialText != null && widget.initialText!.isNotEmpty) {
      _scriptController.text = widget.initialText!;
      // 延迟一帧设置provider状态，避免在initState中调用ref
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(voiceProvider.notifier).setScriptText(widget.initialText!);
      });
    }

    // 初始化动画控制器
    _pulseAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _waveAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();

    // 监听文案变化
    _scriptController.addListener(() {
      ref.read(voiceProvider.notifier).setScriptText(_scriptController.text);
    });

    // 初始化音频播放器
    _audioPlayer = AudioPlayer();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _cloneNameController.dispose();
    _recordTimer?.cancel();
    _playProgressTimer?.cancel();
    _pulseAnimController.dispose();
    _waveAnimController.dispose();
    _audioPlayer?.dispose();
    _previewPlayer?.dispose();
    _recorder.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final voiceState = ref.watch(voiceProvider);

    // 监听错误信息
    ref.listen<VoiceState>(voiceProvider, (prev, next) {
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        _showSnackBar(next.errorMessage!, isError: true);
        ref.read(voiceProvider.notifier).clearError();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('语音合成'),
        actions: [
          // 去改写按钮
          if (_scriptController.text.isNotEmpty)
            TextButton.icon(
              onPressed: () {
                Navigator.pushNamed(
                  context,
                  AppRoutes.extract,
                  arguments: {'text': _scriptController.text},
                );
              },
              icon: const Icon(Icons.edit_note, size: 18),
              label: const Text('去改写', style: TextStyle(fontSize: 13)),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // API配置指示器
            ApiConfigIndicator(
              type: ApiConfigIndicatorType.voice,
              onConfigChanged: () {
                // 刷新页面状态
                ref.read(apiConfigProvider.notifier).refresh();
              },
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            // A. 文案输入区
            _buildScriptInputSection(voiceState),
            const SizedBox(height: AppTheme.spacingMedium),

            // B. 音色选择区
            _buildVoiceSelectSection(voiceState),
            const SizedBox(height: AppTheme.spacingMedium),

            // C. 录音克隆区（可折叠）
            _buildVoiceCloneSection(voiceState),
            const SizedBox(height: AppTheme.spacingMedium),

            // D. 合成参数调节区
            _buildSynthParamsSection(voiceState),
            const SizedBox(height: AppTheme.spacingLarge),

            // E. 合成与播放区
            _buildSynthAndPlaySection(voiceState),

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  // ==================== A. 文案输入区 ====================

  Widget _buildScriptInputSection(VoiceState state) {
    final charCount = _scriptController.text.length;
    final hint = state.wordCountHint;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.text_fields, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('配音文案', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const Spacer(),
              // 字数统计与建议
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: charCount > 0
                      ? AppTheme.primaryColor.withOpacity(0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  hint,
                  style: TextStyle(
                    fontSize: 11,
                    color: charCount > 0 ? AppTheme.primaryColor : AppTheme.textHint,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSmall),
          // 参考时长提示
          if (charCount > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: AppTheme.spacingSmall),
              child: Row(
                children: [
                  const Icon(Icons.schedule, size: 14, color: AppTheme.textHint),
                  const SizedBox(width: 4),
                  Text(
                    '建议口播时长：30秒≈90字 | 60秒≈180字',
                    style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
          AppInput(
            controller: _scriptController,
            hintText: '请输入要配音的口播文案...',
            maxLines: 6,
          ),
        ],
      ),
    );
  }

  // ==================== B. 音色选择区 ====================

  Widget _buildVoiceSelectSection(VoiceState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.record_voice_over, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('音色选择', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 音色标题
          const Text('我的克隆音色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: AppTheme.spacingMedium),

          // 音色列表
          if (state.isLoadingVoices)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppTheme.spacingLarge),
                child: CircularProgressIndicator(),
              ),
            )
          else
            _buildClonedVoiceList(state),

          const SizedBox(height: AppTheme.spacingMedium),

          // 克隆新音色按钮
          AppButton(
            text: '🎙 克隆新音色',
            icon: Icons.add_circle_outline,
            isOutlined: true,
            height: 40,
            onPressed: () => ref.read(voiceProvider.notifier).toggleCloneExpanded(),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceTab({
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryColor.withOpacity(0.15) : AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: isSelected ? AppTheme.primaryColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? AppTheme.primaryColor.withOpacity(0.7) : AppTheme.textHint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar(VoiceState state) {
    return SizedBox(
      height: 38,
      child: TextField(
        onChanged: (value) => ref.read(voiceProvider.notifier).setSearchKeyword(value),
        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: '搜索音色名称、风格...',
          hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 13),
          prefixIcon: const Icon(Icons.search, size: 18, color: AppTheme.textHint),
          isDense: true,
          filled: true,
          fillColor: AppTheme.darkSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
        ),
      ),
    );
  }

  Widget _buildSystemVoiceList(VoiceState state) {
    final voices = state.filteredSystemVoices;
    if (voices.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppTheme.spacingLarge),
          child: Text('未找到匹配的音色', style: TextStyle(color: AppTheme.textHint)),
        ),
      );
    }

    // 按性别分组
    final maleVoices = voices.where((v) => v.gender == 'male').toList();
    final femaleVoices = voices.where((v) => v.gender != 'male').toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (femaleVoices.isNotEmpty) ...[
          _buildVoiceGroup('女声', femaleVoices, state),
          const SizedBox(height: AppTheme.spacingSmall),
        ],
        if (maleVoices.isNotEmpty) ...[
          _buildVoiceGroup('男声', maleVoices, state),
        ],
      ],
    );
  }

  Widget _buildVoiceGroup(String groupLabel, List<VoiceModel> voices, VoiceState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Text(
            groupLabel,
            style: const TextStyle(
              fontSize: 12,
              color: AppTheme.textHint,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: voices.map((voice) => _buildVoiceChip(voice, state)).toList(),
        ),
      ],
    );
  }

  Widget _buildVoiceChip(VoiceModel voice, VoiceState state) {
    final isSelected = state.selectedVoice?.voiceId == voice.voiceId;
    final isPreviewing = _previewingVoiceId == voice.voiceId;

    return GestureDetector(
      onTap: () => ref.read(voiceProvider.notifier).selectVoice(voice),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.primaryColor.withOpacity(0.2)
              : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              voice.gender == 'male' ? Icons.face : Icons.face_3,
              size: 16,
              color: isSelected ? AppTheme.primaryColor : AppTheme.textSecondary,
            ),
            const SizedBox(width: 6),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  voice.voiceName,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                  ),
                ),
                if (voice.style != null)
                  Text(
                    voice.style!,
                    style: TextStyle(
                      fontSize: 10,
                      color: isSelected ? AppTheme.primaryColor.withOpacity(0.7) : AppTheme.textHint,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 6),
            // 试听按钮
            GestureDetector(
              onTap: () => _previewVoice(voice),
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: isPreviewing
                    ? const Icon(Icons.stop, size: 12, color: AppTheme.primaryColor)
                    : const Icon(Icons.play_arrow, size: 14, color: AppTheme.primaryColor),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildClonedVoiceList(VoiceState state) {
    if (state.clonedVoices.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLarge),
          child: Column(
            children: [
              const Icon(Icons.mic_none, size: 40, color: AppTheme.textHint),
              const SizedBox(height: 8),
              const Text(
                '还没有克隆音色',
                style: TextStyle(color: AppTheme.textHint),
              ),
              const SizedBox(height: 4),
              Text(
                '点击下方"克隆新音色"开始创建',
                style: TextStyle(fontSize: 12, color: AppTheme.textHint.withOpacity(0.7)),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: state.clonedVoices.map((voice) {
        final isSelected = state.selectedVoice?.voiceId == voice.voiceId;
        final isPreviewing = _previewingVoiceId == voice.voiceId;

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.accentColor.withOpacity(0.15)
                : AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            border: Border.all(
              color: isSelected ? AppTheme.accentColor : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // 克隆音色图标
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.mic, color: AppTheme.accentColor, size: 20),
              ),
              const SizedBox(width: 12),
              // 音色信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      voice.voiceName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        color: isSelected ? AppTheme.accentColor : AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      voice.createdAt != null
                          ? '克隆于 ${_formatDate(voice.createdAt!)}'
                          : '克隆音色',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                  ],
                ),
              ),
              // 试听按钮
              GestureDetector(
                onTap: () => _previewVoice(voice),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.15),
                    shape: BoxShape.circle,
                  ),
                  child: isPreviewing
                      ? const Icon(Icons.stop, size: 14, color: AppTheme.accentColor)
                      : const Icon(Icons.play_arrow, size: 16, color: AppTheme.accentColor),
                ),
              ),
              const SizedBox(width: 6),
              // 删除按钮
              GestureDetector(
                onTap: () => _showDeleteVoiceDialog(voice),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: AppTheme.highRiskColor.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline, size: 14, color: AppTheme.highRiskColor),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ==================== C. 录音克隆区 ====================

  Widget _buildVoiceCloneSection(VoiceState state) {
    if (!state.isCloneExpanded) return const SizedBox.shrink();

    return AnimatedSize(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      child: AppCard(
        border: Border.all(color: AppTheme.accentColor.withOpacity(0.3), width: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.mic, color: AppTheme.accentColor, size: 20),
                const SizedBox(width: 8),
                const Text('声音克隆', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.accentColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'CosyVoice',
                    style: TextStyle(fontSize: 10, color: AppTheme.accentColor, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => ref.read(voiceProvider.notifier).toggleCloneExpanded(),
                  icon: const Icon(Icons.close, size: 18, color: AppTheme.textHint),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            const Text(
              '录制3-10秒的语音样本，即可克隆您的声音',
              style: TextStyle(fontSize: 13, color: AppTheme.textHint),
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            // 录音模式切换
            Row(
              children: [
                const Text('录音模式：', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                const SizedBox(width: 8),
                _buildRecordModeChip('按住录音', RecordMode.hold, state),
                const SizedBox(width: 8),
                _buildRecordModeChip('点击录音', RecordMode.tap, state),
              ],
            ),
            const SizedBox(height: AppTheme.spacingMedium),

            // 录音按钮区域
            Center(
              child: Column(
                children: [
                  // 录音按钮
                  Listener(
                    onPointerDown: state.recordMode == RecordMode.hold
                        ? (_) => _startRecording()
                        : null,
                    onPointerUp: state.recordMode == RecordMode.hold
                        ? (_) => _stopRecording()
                        : null,
                    onPointerCancel: state.recordMode == RecordMode.hold
                        ? (_) => _stopRecording()
                        : null,
                    child: GestureDetector(
                      onTap: state.recordMode == RecordMode.tap
                          ? () {
                              if (_isRecording) {
                                _stopRecording();
                              } else {
                                _startRecording();
                              }
                            }
                          : null,
                      child: AnimatedBuilder(
                      animation: _pulseAnimController,
                      builder: (context, child) {
                        final scale = _isRecording
                            ? 1.0 + 0.1 * _pulseAnimController.value
                            : 1.0;
                        return Transform.scale(
                          scale: scale,
                          child: Container(
                            width: 80,
                            height: 80,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _isRecording
                                  ? AppTheme.highRiskColor
                                  : AppTheme.accentColor.withOpacity(0.2),
                              boxShadow: _isRecording
                                  ? [
                                      BoxShadow(
                                        color: AppTheme.highRiskColor.withOpacity(0.4),
                                        blurRadius: 20,
                                        spreadRadius: 4,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Icon(
                              _isRecording ? Icons.stop : Icons.mic,
                              color: _isRecording ? Colors.white : AppTheme.accentColor,
                              size: 36,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                  const SizedBox(height: 8),
                  // 录音时长
                  Text(
                    _isRecording
                        ? '正在录音 ${_formatDuration(state.recordDuration)}'
                        : state.recordState == RecordState.recorded
                            ? '已录制 ${_formatDuration(state.recordDuration)}'
                            : state.recordMode == RecordMode.hold
                                ? '按住录音'
                                : '点击开始录音',
                    style: TextStyle(
                      fontSize: 13,
                      color: _isRecording
                          ? AppTheme.highRiskColor
                          : state.recordState == RecordState.recorded
                              ? AppTheme.safeColor
                              : AppTheme.textHint,
                    ),
                  ),

                  // 波形可视化
                  if (_isRecording) ...[
                    const SizedBox(height: 8),
                    _buildWaveform(),
                  ],

                  // 录音时长提示
                  if (state.recordDuration > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      state.recordDuration < 3
                          ? '建议至少录制3秒'
                          : state.recordDuration > 30
                              ? '录音过长，建议3-10秒'
                              : '时长合适✓',
                      style: TextStyle(
                        fontSize: 11,
                        color: state.recordDuration >= 3 && state.recordDuration <= 30
                            ? AppTheme.safeColor
                            : AppTheme.mediumRiskColor,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // 录音完成后的操作
            if (state.recordState == RecordState.recorded) ...[
              const SizedBox(height: AppTheme.spacingMedium),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AppButton(
                    text: '回放',
                    icon: Icons.play_arrow,
                    isOutlined: true,
                    height: 36,
                    fontSize: 13,
                    onPressed: _playRecording,
                  ),
                  const SizedBox(width: 8),
                  AppButton(
                    text: '重录',
                    icon: Icons.refresh,
                    isOutlined: true,
                    height: 36,
                    fontSize: 13,
                    onPressed: _resetRecording,
                  ),
                ],
              ),
            ],

            const SizedBox(height: AppTheme.spacingMedium),

            // 克隆音色名称
            AppInput(
              controller: _cloneNameController,
              hintText: '为克隆音色命名（如：我的声音）',
              onChanged: (value) => ref.read(voiceProvider.notifier).setCloneVoiceName(value),
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 克隆进度
            if (state.recordState == RecordState.cloning) ...[
              Column(
                children: [
                  LinearProgressIndicator(
                    value: state.cloneProgress / 100,
                    backgroundColor: AppTheme.textHint.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation(AppTheme.accentColor),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '正在克隆声音... ${state.cloneProgress}%',
                    style: const TextStyle(fontSize: 13, color: AppTheme.accentColor),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingMedium),
            ],

            // 克隆按钮
            AppButton(
              text: '克隆声音',
              icon: Icons.auto_fix_high,
              backgroundColor: AppTheme.accentColor,
              isLoading: state.recordState == RecordState.cloning,
              onPressed: state.recordState == RecordState.recorded
                  ? () => ref.read(voiceProvider.notifier).cloneVoice()
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecordModeChip(String label, RecordMode mode, VoiceState state) {
    final isSelected = state.recordMode == mode;
    return GestureDetector(
      onTap: () => ref.read(voiceProvider.notifier).setRecordMode(mode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentColor.withOpacity(0.15) : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : Colors.transparent,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: isSelected ? AppTheme.accentColor : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildWaveform() {
    return SizedBox(
      height: 30,
      child: AnimatedBuilder(
        animation: _waveAnimController,
        builder: (context, _) {
          return CustomPaint(
            painter: _WaveformPainter(_waveAnimController.value),
            size: Size.infinite,
          );
        },
      ),
    );
  }

  // ==================== D. 合成参数调节区 ====================

  Widget _buildSynthParamsSection(VoiceState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: AppTheme.primaryColor, size: 20),
              const SizedBox(width: 8),
              const Text('合成参数', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 语速滑块
          _buildSliderRow(
            label: '语速',
            value: state.speed,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            displayText: '${state.speed.toStringAsFixed(1)}x',
            activeColor: AppTheme.primaryColor,
            onChanged: (v) => ref.read(voiceProvider.notifier).setSpeed(v),
          ),
          const SizedBox(height: AppTheme.spacingSmall),

          // 音调滑块
          _buildSliderRow(
            label: '音调',
            value: state.pitch,
            min: 0.5,
            max: 2.0,
            divisions: 15,
            displayText: state.pitch.toStringAsFixed(1),
            activeColor: AppTheme.accentColor,
            onChanged: (v) => ref.read(voiceProvider.notifier).setPitch(v),
          ),
          const SizedBox(height: AppTheme.spacingSmall),

          // 音量滑块
          _buildSliderRow(
            label: '音量',
            value: state.volume,
            min: 0.0,
            max: 2.0,
            divisions: 20,
            displayText: '${(state.volume * 100).round()}%',
            activeColor: AppTheme.safeColor,
            onChanged: (v) => ref.read(voiceProvider.notifier).setVolume(v),
          ),
          const SizedBox(height: AppTheme.spacingMedium),

          // 情绪选择（仅CosyVoice支持）
          if (state.sourceType == VoiceSourceType.cloned) ...[
            const Text(
              '情绪风格（CosyVoice专属）',
              style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: AppTheme.spacingSmall),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildEmotionChip('平静', Icons.sentiment_neutral, state),
                _buildEmotionChip('开心', Icons.sentiment_very_satisfied, state),
                _buildEmotionChip('悲伤', Icons.sentiment_dissatisfied, state),
                _buildEmotionChip('激动', Icons.sentiment_very_dissatisfied, state),
              ],
            ),
          ] else ...[
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
                      '情绪风格仅CosyVoice克隆音色支持，选择克隆音色后可设置',
                      style: TextStyle(fontSize: 11, color: AppTheme.textHint),
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

  Widget _buildSliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String displayText,
    required Color activeColor,
    required ValueChanged<double> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderThemeData(
              activeTrackColor: activeColor,
              thumbColor: activeColor,
              inactiveTrackColor: AppTheme.textHint.withOpacity(0.2),
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            ),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
        ),
        SizedBox(
          width: 48,
          child: Text(
            displayText,
            style: TextStyle(fontSize: 13, color: activeColor, fontWeight: FontWeight.w600),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Widget _buildEmotionChip(String emotion, IconData icon, VoiceState state) {
    final isSelected = state.emotion == emotion;
    return GestureDetector(
      onTap: () {
        if (isSelected) {
          ref.read(voiceProvider.notifier).setEmotion(null);
        } else {
          ref.read(voiceProvider.notifier).setEmotion(emotion);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.accentColor.withOpacity(0.2) : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppTheme.accentColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? AppTheme.accentColor : AppTheme.textHint),
            const SizedBox(width: 4),
            Text(
              emotion,
              style: TextStyle(
                fontSize: 12,
                color: isSelected ? AppTheme.accentColor : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ==================== E. 合成与播放区 ====================

  Widget _buildSynthAndPlaySection(VoiceState state) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 生成配音按钮
        if (state.synthState == SynthState.idle || state.synthState == SynthState.failed)
          AppButton(
            text: state.synthState == SynthState.failed ? '重新生成' : '生成配音',
            icon: Icons.play_circle_outline,
            isLoading: state.synthState == SynthState.synthesizing,
            onPressed: state.selectedVoice != null && _scriptController.text.trim().isNotEmpty
                ? () => ref.read(voiceProvider.notifier).synthesize()
                : null,
          ),

        // 合成中进度
        if (state.synthState == SynthState.synthesizing) ...[
          AppCard(
            child: Column(
              children: [
                const Text(
                  '正在合成语音...',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: AppTheme.spacingMedium),
                LinearProgressIndicator(
                  value: state.synthProgress / 100,
                  backgroundColor: AppTheme.textHint.withOpacity(0.2),
                  valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
                ),
                const SizedBox(height: 8),
                Text(
                  '${state.synthProgress}%',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppTheme.primaryColor,
                  ),
                ),
              ],
            ),
          ),
        ],

        // 合成完成 - 音频播放器
        if (state.synthState == SynthState.completed && state.audioPath != null) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.headphones, color: AppTheme.safeColor, size: 20),
                    const SizedBox(width: 8),
                    const Text('合成结果', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    // 音频时长
                    if (state.audioDuration > 0)
                      Text(
                        _formatDuration(state.audioDuration ~/ 1000),
                        style: const TextStyle(fontSize: 13, color: AppTheme.textHint),
                      ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMedium),

                // 波形可视化播放器
                _buildAudioPlayer(state),

                const SizedBox(height: AppTheme.spacingMedium),

                // 操作按钮
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: '重新生成',
                        icon: Icons.refresh,
                        isOutlined: true,
                        height: 40,
                        fontSize: 13,
                        onPressed: () {
                          _audioPlayer?.stop();
                          ref.read(voiceProvider.notifier).resetSynth();
                        },
                      ),
                    ),
                    const SizedBox(width: AppTheme.spacingSmall),
                    Expanded(
                      child: AppButton(
                        text: '保存音频',
                        icon: Icons.download,
                        height: 40,
                        fontSize: 13,
                        onPressed: () => _saveAudio(state.audioPath!),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppTheme.spacingMedium),

                // 去生成视频按钮
                AppButton(
                  text: '去生成视频 →',
                  icon: Icons.smart_toy_outlined,
                  backgroundColor: AppTheme.accentColor,
                  onPressed: () {
                    _audioPlayer?.stop();
                    Navigator.pushNamed(
                      context,
                      AppRoutes.digitalHuman,
                      arguments: {
                        'text': _scriptController.text,
                        'audioPath': state.audioPath,
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAudioPlayer(VoiceState state) {
    final isPlaying = state.playState == PlayState.playing;
    final isPaused = state.playState == PlayState.paused;
    final progress = state.audioDuration > 0
        ? state.playPosition / state.audioDuration
        : 0.0;

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: Row(
        children: [
          // 播放/暂停按钮
          GestureDetector(
            onTap: _togglePlayback,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                isPlaying ? Icons.pause_circle : Icons.play_circle,
                color: AppTheme.primaryColor,
                size: 36,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // 进度条
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 进度条
                GestureDetector(
                  onTapDown: (details) {
                    // 点击进度条跳转
                    final box = context.findRenderObject() as RenderBox;
                    final localPosition = details.localPosition;
                    final width = box.size.width - 88; // 减去按钮和间距
                    final seekProgress = (localPosition.dx / width).clamp(0.0, 1.0);
                    if (state.audioDuration > 0) {
                      _audioPlayer?.seek(Duration(
                        milliseconds: (seekProgress * state.audioDuration).round(),
                      ));
                    }
                  },
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress.clamp(0.0, 1.0),
                      backgroundColor: AppTheme.textHint.withOpacity(0.2),
                      valueColor: const AlwaysStoppedAnimation(AppTheme.primaryColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // 时间显示
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _formatDuration(state.playPosition ~/ 1000),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                    Text(
                      _formatDuration(state.audioDuration ~/ 1000),
                      style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 录音相关方法 ====================

  Future<void> _startRecording() async {
    // 检查录音权限
    final status = await Permission.microphone.request();
    if (!status.isGranted) {
      _showSnackBar('需要麦克风权限才能录音', isError: true);
      return;
    }

    try {
      // 检查是否可以录音
      if (!await _recorder.hasPermission()) {
        _showSnackBar('无法获取录音权限', isError: true);
        return;
      }

      final audioDir = await StorageUtil.getAudioDirectory();
      final filePath = '$audioDir/clone_record_${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          sampleRate: 44100,
          numChannels: 1,
        ),
        path: filePath,
      );

      setState(() => _isRecording = true);
      _pulseAnimController.repeat(reverse: true);

      // 更新录音状态
      ref.read(voiceProvider.notifier).setRecordState(RecordState.recording);
      ref.read(voiceProvider.notifier).setRecordDuration(0);
      ref.read(voiceProvider.notifier).setRecordFilePath(null);

      // 开始计时
      _recordTimer?.cancel();
      int seconds = 0;
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        seconds++;
        ref.read(voiceProvider.notifier).setRecordDuration(seconds);
        // 超过30秒自动停止
        if (seconds >= 30) {
          _stopRecording();
        }
      });
    } catch (e) {
      _showSnackBar('录音启动失败：$e', isError: true);
    }
  }

  Future<void> _stopRecording() async {
    if (!_isRecording) return;

    try {
      final path = await _recorder.stop();
      _recordTimer?.cancel();
      _pulseAnimController.stop();
      setState(() => _isRecording = false);

      if (path != null) {
        ref.read(voiceProvider.notifier).setRecordFilePath(path);
        ref.read(voiceProvider.notifier).setRecordState(RecordState.recorded);
      } else {
        ref.read(voiceProvider.notifier).setRecordState(RecordState.idle);
      }
    } catch (e) {
      _showSnackBar('录音停止失败：$e', isError: true);
      setState(() => _isRecording = false);
    }
  }

  Future<void> _playRecording() async {
    final state = ref.read(voiceProvider);
    if (state.recordFilePath == null) return;

    try {
      _previewPlayer?.dispose();
      _previewPlayer = AudioPlayer();
      await _previewPlayer!.setFilePath(state.recordFilePath!);
      _previewPlayer!.play();
    } catch (e) {
      _showSnackBar('播放录音失败', isError: true);
    }
  }

  void _resetRecording() {
    ref.read(voiceProvider.notifier).setRecordState(RecordState.idle);
    ref.read(voiceProvider.notifier).setRecordDuration(0);
    ref.read(voiceProvider.notifier).setRecordFilePath(null);
  }

  // ==================== 音频播放相关方法 ====================

  Future<void> _togglePlayback() async {
    final state = ref.read(voiceProvider);
    if (state.audioPath == null) return;

    try {
      if (state.playState == PlayState.playing) {
        await _audioPlayer?.pause();
        ref.read(voiceProvider.notifier).setPlayState(PlayState.paused);
        _playProgressTimer?.cancel();
      } else if (state.playState == PlayState.paused) {
        await _audioPlayer?.play();
        ref.read(voiceProvider.notifier).setPlayState(PlayState.playing);
        _startPlayProgressTimer();
      } else {
        // 开始播放
        await _audioPlayer?.setFilePath(state.audioPath!);
        final duration = _audioPlayer?.duration?.inMilliseconds ?? 0;
        ref.read(voiceProvider.notifier).setAudioDuration(duration);
        await _audioPlayer!.play();
        ref.read(voiceProvider.notifier).setPlayState(PlayState.playing);
        _startPlayProgressTimer();

        // 监听播放完成
        _audioPlayer?.playerStateStream.listen((playerState) {
          if (playerState.processingState == ProcessingState.completed) {
            ref.read(voiceProvider.notifier).setPlayState(PlayState.stopped);
            ref.read(voiceProvider.notifier).setPlayPosition(0);
            _playProgressTimer?.cancel();
          }
        });
      }
    } catch (e) {
      _showSnackBar('音频播放失败：$e', isError: true);
    }
  }

  void _startPlayProgressTimer() {
    _playProgressTimer?.cancel();
    _playProgressTimer = Timer.periodic(const Duration(milliseconds: 200), (_) {
      final position = _audioPlayer?.position.inMilliseconds ?? 0;
      ref.read(voiceProvider.notifier).setPlayPosition(position);
    });
  }

  Future<void> _saveAudio(String audioPath) async {
    try {
      final sourceFile = audioPath;
      // 复制到用户可访问的目录
      final saveDir = await StorageUtil.getAudioDirectory();
      final fileName = '配音_${DateTime.now().year}${DateTime.now().month.toString().padLeft(2, '0')}${DateTime.now().day.toString().padLeft(2, '0')}_${DateTime.now().millisecondsSinceEpoch % 100000}.mp3';
      final savePath = '$saveDir/$fileName';
      await File(sourceFile).copy(savePath);
      _showSnackBar('音频已保存到：$savePath');
    } catch (e) {
      _showSnackBar('保存失败：$e', isError: true);
    }
  }

  // ==================== 试听方法 ====================

  Future<void> _previewVoice(VoiceModel voice) async {
    // 停止之前的试听
    await _previewPlayer?.stop();
    await _previewPlayer?.dispose();

    setState(() => _previewingVoiceId = voice.voiceId);

    try {
      _previewPlayer = AudioPlayer();

      // 对于系统音色，先合成一段试听音频
      // 简化处理：播放预设的试听音效
      // 实际应该调用TTS服务合成
      final ttsService = ref.read(ttsServiceProvider);
      final previewPath = await ttsService.previewVoice(
        voiceId: voice.voiceId,
        provider: voice.provider,
        sampleText: '你好，我是${voice.voiceName}，这是一段试听音频。',
      );

      await _previewPlayer!.setFilePath(previewPath);
      await _previewPlayer!.play();

      _previewPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() => _previewingVoiceId = null);
          }
        }
      });
    } catch (e) {
      // 试听失败不报错，静默处理
      if (mounted) {
        setState(() => _previewingVoiceId = null);
      }
    }
  }

  // ==================== 辅助方法 ====================

  void _showDeleteVoiceDialog(VoiceModel voice) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('删除克隆音色', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text(
          '确定要删除克隆音色"${voice.voiceName}"吗？删除后无法恢复。',
          style: const TextStyle(color: AppTheme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(voiceProvider.notifier).deleteClonedVoice(voice.voiceId);
            },
            child: const Text('删除', style: TextStyle(color: AppTheme.highRiskColor)),
          ),
        ],
      ),
    );
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

  String _formatDuration(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _formatDate(DateTime date) {
    return '${date.month}月${date.day}日 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }
}

/// 波形可视化绘制器
class _WaveformPainter extends CustomPainter {
  final double animationValue;

  _WaveformPainter(this.animationValue);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppTheme.accentColor.withOpacity(0.6)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    final waveCount = 20;
    final barWidth = size.width / waveCount;
    final centerY = size.height / 2;

    for (int i = 0; i < waveCount; i++) {
      final x = i * barWidth + barWidth / 2;
      final phase = (i / waveCount * 2 * 3.14159) + animationValue * 2 * 3.14159;
      final amplitude = (0.3 + 0.7 * (0.5 + 0.5 * (math.sin(phase)))) * (size.height * 0.35);
      final barHeight = amplitude;

      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) => true;
}
