import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/digital_human_service.dart';
import '../services/api_client.dart';
import '../utils/storage_util.dart';

/// 声音来源类型
enum AudioSourceType { synthesized, platform }

/// 视频生成状态
enum VideoGenState { idle, uploading, queuing, processing, rendering, completed, failed }

/// 数字人页面状态
class DigitalHumanState {
  /// 形象图片路径
  final String? avatarImagePath;

  /// 数字人视频模板URL（上传后返回）
  final String? avatarVideoUrl;

  /// 公版数字人模板列表
  final List<DigitalHumanTemplate> templates;

  /// 选中的公版模板
  final DigitalHumanTemplate? selectedTemplate;

  /// 声音来源类型
  final AudioSourceType audioSourceType;

  /// 已合成配音路径（从语音合成页带入）
  final String? synthesizedAudioPath;

  /// 平台音色列表
  final List<HiflyVoice> platformVoices;

  /// 选中的平台音色
  final HiflyVoice? selectedPlatformVoice;

  /// 口播文案
  final String scriptText;

  /// 字幕样式
  final SubtitleStyle subtitleStyle;

  /// 视频生成状态
  final VideoGenState genState;

  /// 生成进度（0-100）
  final int progress;

  /// 进度描述信息
  final String progressMessage;

  /// 生成视频URL
  final String? videoUrl;

  /// 本地视频路径
  final String? localVideoPath;

  /// 音频预览播放状态
  final bool isAudioPlaying;

  /// 历史生成列表
  final List<VideoHistoryItem> historyList;

  /// 错误信息
  final String? errorMessage;

  /// 是否正在加载
  final bool isLoading;

  const DigitalHumanState({
    this.avatarImagePath,
    this.avatarVideoUrl,
    this.templates = const [],
    this.selectedTemplate,
    this.audioSourceType = AudioSourceType.synthesized,
    this.synthesizedAudioPath,
    this.platformVoices = const [],
    this.selectedPlatformVoice,
    this.scriptText = '',
    this.subtitleStyle = const SubtitleStyle(),
    this.genState = VideoGenState.idle,
    this.progress = 0,
    this.progressMessage = '',
    this.videoUrl,
    this.localVideoPath,
    this.isAudioPlaying = false,
    this.historyList = const [],
    this.errorMessage,
    this.isLoading = false,
  });

  DigitalHumanState copyWith({
    String? avatarImagePath,
    bool clearAvatar = false,
    String? avatarVideoUrl,
    bool clearAvatarVideoUrl = false,
    List<DigitalHumanTemplate>? templates,
    DigitalHumanTemplate? selectedTemplate,
    bool clearSelectedTemplate = false,
    AudioSourceType? audioSourceType,
    String? synthesizedAudioPath,
    bool clearSynthesizedAudio = false,
    List<HiflyVoice>? platformVoices,
    HiflyVoice? selectedPlatformVoice,
    bool clearSelectedPlatformVoice = false,
    String? scriptText,
    SubtitleStyle? subtitleStyle,
    VideoGenState? genState,
    int? progress,
    String? progressMessage,
    String? videoUrl,
    bool clearVideoUrl = false,
    String? localVideoPath,
    bool clearLocalVideoPath = false,
    bool? isAudioPlaying,
    List<VideoHistoryItem>? historyList,
    String? errorMessage,
    bool clearError = false,
    bool? isLoading,
  }) {
    return DigitalHumanState(
      avatarImagePath: clearAvatar ? null : (avatarImagePath ?? this.avatarImagePath),
      avatarVideoUrl: clearAvatarVideoUrl ? null : (avatarVideoUrl ?? this.avatarVideoUrl),
      templates: templates ?? this.templates,
      selectedTemplate: clearSelectedTemplate ? null : (selectedTemplate ?? this.selectedTemplate),
      audioSourceType: audioSourceType ?? this.audioSourceType,
      synthesizedAudioPath: clearSynthesizedAudio ? null : (synthesizedAudioPath ?? this.synthesizedAudioPath),
      platformVoices: platformVoices ?? this.platformVoices,
      selectedPlatformVoice: clearSelectedPlatformVoice ? null : (selectedPlatformVoice ?? this.selectedPlatformVoice),
      scriptText: scriptText ?? this.scriptText,
      subtitleStyle: subtitleStyle ?? this.subtitleStyle,
      genState: genState ?? this.genState,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      videoUrl: clearVideoUrl ? null : (videoUrl ?? this.videoUrl),
      localVideoPath: clearLocalVideoPath ? null : (localVideoPath ?? this.localVideoPath),
      isAudioPlaying: isAudioPlaying ?? this.isAudioPlaying,
      historyList: historyList ?? this.historyList,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
    );
  }

  /// 是否使用自定义照片
  bool get useCustomAvatar => avatarImagePath != null;

  /// 是否可以生成视频
  bool get canGenerate {
    final hasAvatar = avatarImagePath != null || selectedTemplate != null;
    final hasAudio = audioSourceType == AudioSourceType.synthesized
        ? synthesizedAudioPath != null
        : selectedPlatformVoice != null;
    final hasText = scriptText.trim().isNotEmpty;
    return hasAvatar && hasAudio && hasText;
  }
}

/// 公版数字人模板
class DigitalHumanTemplate {
  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? videoUrl;
  final String? gender;

  const DigitalHumanTemplate({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.videoUrl,
    this.gender,
  });
}

/// 飞影平台音色
class HiflyVoice {
  final String id;
  final String name;
  final String? gender;
  final String? language;
  final String? style;
  final String? sampleUrl;

  const HiflyVoice({
    required this.id,
    required this.name,
    this.gender,
    this.language,
    this.style,
    this.sampleUrl,
  });
}

/// 字幕样式
class SubtitleStyle {
  final String fontColor;
  final double fontSize;
  final String position; // top / center / bottom

  const SubtitleStyle({
    this.fontColor = '#FFFFFF',
    this.fontSize = 24,
    this.position = 'bottom',
  });

  SubtitleStyle copyWith({
    String? fontColor,
    double? fontSize,
    String? position,
  }) {
    return SubtitleStyle(
      fontColor: fontColor ?? this.fontColor,
      fontSize: fontSize ?? this.fontSize,
      position: position ?? this.position,
    );
  }
}

/// 视频历史记录项
class VideoHistoryItem {
  final String id;
  final String? thumbnailPath;
  final String videoPath;
  final int durationSeconds;
  final DateTime createdAt;
  final String resolution;
  final int fileSizeBytes;

  const VideoHistoryItem({
    required this.id,
    this.thumbnailPath,
    required this.videoPath,
    this.durationSeconds = 0,
    required this.createdAt,
    this.resolution = '1080x1920',
    this.fileSizeBytes = 0,
  });

  /// 格式化文件大小
  String get fileSizeText {
    if (fileSizeBytes < 1024) return '$fileSizeBytes B';
    if (fileSizeBytes < 1024 * 1024) return '${(fileSizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(fileSizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  /// 格式化时长
  String get durationText {
    final min = durationSeconds ~/ 60;
    final sec = durationSeconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}

/// 数字人状态管理
class DigitalHumanNotifier extends StateNotifier<DigitalHumanState> {
  final DigitalHumanService _digitalHumanService;

  DigitalHumanNotifier(this._digitalHumanService) : super(const DigitalHumanState()) {
    _loadData();
  }

  /// 初始化加载数据
  Future<void> _loadData() async {
    state = state.copyWith(isLoading: true);
    try {
      // 加载平台音色列表
      final voices = await _digitalHumanService.getAvailableVoices();
      final hiflyVoices = voices.map((v) => HiflyVoice(
        id: v['id'] ?? '',
        name: v['name'] ?? '',
        gender: v['gender'],
        language: v['language'],
      )).toList();

      // 加载公版模板列表
      final templates = await _digitalHumanService.getAvatarTemplates();
      final templateList = templates.map((t) => DigitalHumanTemplate(
        id: t['id'] ?? '',
        name: t['name'] ?? '',
        thumbnailUrl: t['thumbnail_url'],
        videoUrl: t['video_url'],
        gender: t['gender'],
      )).toList();

      // 加载历史记录
      final history = await _loadHistory();

      state = state.copyWith(
        platformVoices: hiflyVoices,
        templates: templateList,
        historyList: history,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 加载历史记录
  Future<List<VideoHistoryItem>> _loadHistory() async {
    try {
      final historyJson = StorageUtil.getString('video_history');
      if (historyJson == null || historyJson.isEmpty) return [];
      final entries = historyJson.split('|||');
      return entries.where((e) => e.isNotEmpty).map((entry) {
        final parts = entry.split('###');
        return VideoHistoryItem(
          id: parts[0],
          videoPath: parts.length > 1 ? parts[1] : '',
          durationSeconds: parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
          createdAt: parts.length > 3 ? DateTime.tryParse(parts[3]) ?? DateTime.now() : DateTime.now(),
          resolution: parts.length > 4 ? parts[4] : '1080x1920',
          fileSizeBytes: parts.length > 5 ? int.tryParse(parts[5]) ?? 0 : 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存历史记录
  Future<void> _saveHistory() async {
    final entries = state.historyList.map((h) =>
      '${h.id}###${h.videoPath}###${h.durationSeconds}###${h.createdAt.toIso8601String()}###${h.resolution}###${h.fileSizeBytes}'
    ).join('|||');
    await StorageUtil.setString('video_history', entries);
  }

  /// 设置形象图片
  void setAvatarImage(String path) {
    state = state.copyWith(
      avatarImagePath: path,
      clearSelectedTemplate: true,
    );
  }

  /// 选择公版模板
  void selectTemplate(DigitalHumanTemplate template) {
    state = state.copyWith(
      selectedTemplate: template,
      clearAvatar: true,
      avatarVideoUrl: template.videoUrl,
    );
  }

  /// 设置声音来源类型
  void setAudioSourceType(AudioSourceType type) {
    state = state.copyWith(audioSourceType: type);
  }

  /// 设置已合成配音路径
  void setSynthesizedAudio(String? path) {
    if (path == null) {
      state = state.copyWith(clearSynthesizedAudio: true);
    } else {
      state = state.copyWith(synthesizedAudioPath: path);
    }
  }

  /// 选择平台音色
  void selectPlatformVoice(HiflyVoice voice) {
    state = state.copyWith(selectedPlatformVoice: voice);
  }

  /// 设置文案
  void setScriptText(String text) {
    state = state.copyWith(scriptText: text);
  }

  /// 设置字幕样式
  void setSubtitleStyle(SubtitleStyle style) {
    state = state.copyWith(subtitleStyle: style);
  }

  /// 设置音频播放状态
  void setAudioPlaying(bool playing) {
    state = state.copyWith(isAudioPlaying: playing);
  }

  /// 生成视频
  Future<void> generateVideo() async {
    if (!state.canGenerate) {
      state = state.copyWith(errorMessage: '请完善所有必填信息');
      return;
    }

    state = state.copyWith(
      genState: VideoGenState.uploading,
      progress: 0,
      progressMessage: '准备中...',
      errorMessage: null,
    );

    try {
      // 1. 上传照片（如果使用自定义照片）
      String videoUrl = state.avatarVideoUrl ?? '';
      if (state.useCustomAvatar && state.avatarImagePath != null) {
        state = state.copyWith(
          genState: VideoGenState.uploading,
          progress: 10,
          progressMessage: '上传照片中...',
        );
        videoUrl = await _digitalHumanService.uploadAvatarImage(state.avatarImagePath!);
      }

      // 2. 创建视频任务
      state = state.copyWith(
        genState: VideoGenState.queuing,
        progress: 20,
        progressMessage: '排队中...',
      );

      // 确定声音ID
      String speakerId = '';
      if (state.audioSourceType == AudioSourceType.platform && state.selectedPlatformVoice != null) {
        speakerId = state.selectedPlatformVoice!.id;
      }

      final jobId = await _digitalHumanService.createVideo(
        text: state.scriptText.trim(),
        videoUrl: videoUrl,
        speakerId: speakerId,
      );

      // 3. 轮询等待完成
      state = state.copyWith(
        genState: VideoGenState.processing,
        progress: 30,
        progressMessage: '处理中...',
      );

      final resultVideoUrl = await _digitalHumanService.waitForCompletion(
        jobId: jobId,
        onProgress: (status, progress) {
          VideoGenState genState;
          String msg;
          switch (status) {
            case 1:
              genState = VideoGenState.queuing;
              msg = '排队中...';
              break;
            case 2:
              genState = VideoGenState.processing;
              msg = '处理中...';
              break;
            case 3:
              genState = VideoGenState.completed;
              msg = '渲染完成！';
              break;
            default:
              genState = VideoGenState.rendering;
              msg = '渲染中...';
          }
          final progressValue = 30 + (progress * 0.6).round();
          state = state.copyWith(
            genState: genState,
            progress: progressValue.clamp(30, 90),
            progressMessage: msg,
          );
        },
      );

      // 4. 下载视频
      state = state.copyWith(
        genState: VideoGenState.rendering,
        progress: 95,
        progressMessage: '下载视频中...',
      );

      final localPath = await _digitalHumanService.downloadVideo(resultVideoUrl);

      // 5. 完成
      final historyItem = VideoHistoryItem(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        videoPath: localPath,
        createdAt: DateTime.now(),
      );

      final updatedHistory = [historyItem, ...state.historyList];

      state = state.copyWith(
        genState: VideoGenState.completed,
        progress: 100,
        progressMessage: '生成完成！',
        videoUrl: resultVideoUrl,
        localVideoPath: localPath,
        historyList: updatedHistory,
      );

      await _saveHistory();
    } catch (e) {
      state = state.copyWith(
        genState: VideoGenState.failed,
        progress: 0,
        errorMessage: '视频生成失败：$e',
      );
    }
  }

  /// 删除历史记录
  Future<void> deleteHistoryItem(String id) async {
    final updatedList = state.historyList.where((h) => h.id != id).toList();
    state = state.copyWith(historyList: updatedList);
    await _saveHistory();
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 重置生成状态
  void resetGenState() {
    state = state.copyWith(
      genState: VideoGenState.idle,
      progress: 0,
      progressMessage: '',
      clearVideoUrl: true,
      clearLocalVideoPath: true,
    );
  }
}

/// DigitalHuman Provider定义
final digitalHumanProvider = StateNotifierProvider<DigitalHumanNotifier, DigitalHumanState>((ref) {
  return DigitalHumanNotifier(ref.read(digitalHumanServiceProvider));
});
