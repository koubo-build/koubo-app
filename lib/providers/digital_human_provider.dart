import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/digital_human_service.dart';
import '../services/api_client.dart';
import '../services/ai_rewrite_service.dart';
import '../services/tts_service.dart';
import '../utils/storage_util.dart';

/// 视频生成状态枚举
enum VideoGenState {
  idle,           // 空闲/初始状态
  processingImage, // 处理图片中
  uploadingAudio, // 上传音频中
  submitting,     // 提交任务中
  processing,     // 处理中（轮询）
  downloading,    // 下载视频中
  completed,      // 完成
  failed          // 失败
}

/// 数字人页面状态类（分段生成版）
class DigitalHumanState {
  /// 照片路径
  final String? avatarImagePath;

  /// 配音路径（从语音合成页带入，可选，有则用旧流程）
  final String? audioPath;

  /// 口播文案
  final String scriptText;

  /// 文案搜索关键词（用于AI搜索生成）
  final String scriptTopic;

  /// 画面提示词（可选，用于控制生成效果）
  final String prompt;

  /// 输出分辨率：480或720，默认720
  final int outputResolution;

  /// 快速模式（万相强制关闭）
  final bool fastMode;

  /// 视频生成状态
  final VideoGenState genState;

  /// 生成进度（0-100）
  final int progress;

  /// 进度描述信息
  final String progressMessage;

  /// 本地视频路径（单段模式）
  final String? localVideoPath;

  /// 分段生成结果列表（多段模式）
  final List<DigitalHumanService.VideoSegmentResult> segmentResults;

  /// 当前段序号（分段生成时）
  final int currentSegment;

  /// 总段数（分段生成时）
  final int totalSegments;

  /// 历史生成列表
  final List<VideoHistoryItem> historyList;

  /// 错误信息
  final String? errorMessage;

  /// 是否正在加载历史记录
  final bool isLoading;

  /// 是否正在AI生成文案
  final bool isGeneratingScript;

  const DigitalHumanState({
    this.avatarImagePath,
    this.audioPath,
    this.scriptText = '',
    this.scriptTopic = '',
    this.prompt = '',
    this.outputResolution = 720,
    this.fastMode = false,
    this.genState = VideoGenState.idle,
    this.progress = 0,
    this.progressMessage = '',
    this.localVideoPath,
    this.segmentResults = const [],
    this.currentSegment = 0,
    this.totalSegments = 0,
    this.historyList = const [],
    this.errorMessage,
    this.isLoading = false,
    this.isGeneratingScript = false,
  });

  DigitalHumanState copyWith({
    String? avatarImagePath,
    bool clearAvatar = false,
    String? audioPath,
    bool clearAudio = false,
    String? scriptText,
    String? scriptTopic,
    String? prompt,
    int? outputResolution,
    bool? fastMode,
    VideoGenState? genState,
    int? progress,
    String? progressMessage,
    String? localVideoPath,
    bool clearLocalVideoPath = false,
    List<DigitalHumanService.VideoSegmentResult>? segmentResults,
    bool clearSegmentResults = false,
    int? currentSegment,
    int? totalSegments,
    List<VideoHistoryItem>? historyList,
    String? errorMessage,
    bool clearError = false,
    bool? isLoading,
    bool? isGeneratingScript,
  }) {
    return DigitalHumanState(
      avatarImagePath: clearAvatar ? null : (avatarImagePath ?? this.avatarImagePath),
      audioPath: clearAudio ? null : (audioPath ?? this.audioPath),
      scriptText: scriptText ?? this.scriptText,
      scriptTopic: scriptTopic ?? this.scriptTopic,
      prompt: prompt ?? this.prompt,
      outputResolution: outputResolution ?? this.outputResolution,
      fastMode: fastMode ?? this.fastMode,
      genState: genState ?? this.genState,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      localVideoPath: clearLocalVideoPath ? null : (localVideoPath ?? this.localVideoPath),
      segmentResults: clearSegmentResults ? [] : (segmentResults ?? this.segmentResults),
      currentSegment: currentSegment ?? this.currentSegment,
      totalSegments: totalSegments ?? this.totalSegments,
      historyList: historyList ?? this.historyList,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoading: isLoading ?? this.isLoading,
      isGeneratingScript: isGeneratingScript ?? this.isGeneratingScript,
    );
  }

  /// 是否可以生成视频（有照片+有文案即可，不再强制要求音频）
  bool get canGenerate {
    final hasPhoto = avatarImagePath != null;
    final hasText = scriptText.trim().isNotEmpty;
    return hasPhoto && hasText;
  }

  /// 是否为多段生成结果
  bool get hasSegments => segmentResults.isNotEmpty;

  /// 照片是否已就绪
  bool get photoReady => avatarImagePath != null;

  /// 获取分辨率显示文本
  String get resolutionText => '${outputResolution}p';
}

/// 视频历史记录项
class VideoHistoryItem {
  final String id;
  final String videoPath;
  final int durationSeconds;
  final DateTime createdAt;
  final String resolution;
  final int fileSizeBytes;

  const VideoHistoryItem({
    required this.id,
    required this.videoPath,
    this.durationSeconds = 0,
    required this.createdAt,
    this.resolution = '720P',
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

/// 数字人状态管理（Provider）
class DigitalHumanNotifier extends StateNotifier<DigitalHumanState> {
  final DigitalHumanService _service;
  final ApiClient _apiClient;
  final TtsService _ttsService;

  DigitalHumanNotifier(this._service, this._apiClient, this._ttsService) : super(const DigitalHumanState()) {
    _loadDraft();
    _loadHistory();
  }

  /// 从存储恢复数字人页面草稿
  void _loadDraft() {
    final scriptText = StorageUtil.getDhScriptText();
    final scriptTopic = StorageUtil.getDhScriptTopic();
    final prompt = StorageUtil.getDhPrompt();
    final resolution = StorageUtil.getDhResolution();
    final fastMode = StorageUtil.getDhFastMode();
    final avatarPath = StorageUtil.getDhAvatarPath();
    final audioPath = StorageUtil.getDhAudioPath();

    state = DigitalHumanState(
      scriptText: scriptText,
      scriptTopic: scriptTopic,
      prompt: prompt,
      outputResolution: resolution,
      fastMode: fastMode,
      avatarImagePath: avatarPath,
      audioPath: audioPath,
    );
  }

  /// 加载历史记录
  Future<void> _loadHistory() async {
    state = state.copyWith(isLoading: true);
    try {
      final history = await _loadHistoryFromStorage();
      state = state.copyWith(historyList: history, isLoading: false);
    } catch (_) {
      state = state.copyWith(isLoading: false);
    }
  }

  /// 从存储读取历史记录
  Future<List<VideoHistoryItem>> _loadHistoryFromStorage() async {
    try {
      final historyJson = StorageUtil.getString('wanx_history');
      if (historyJson == null || historyJson.isEmpty) return [];
      
      final entries = historyJson.split('|||');
      return entries.where((e) => e.isNotEmpty).map((entry) {
        final parts = entry.split('###');
        return VideoHistoryItem(
          id: parts[0],
          videoPath: parts.length > 1 ? parts[1] : '',
          durationSeconds: parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
          createdAt: parts.length > 3 ? DateTime.tryParse(parts[3]) ?? DateTime.now() : DateTime.now(),
          resolution: parts.length > 4 ? parts[4] : '720P',
          fileSizeBytes: parts.length > 5 ? int.tryParse(parts[5]) ?? 0 : 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存历史记录到存储
  Future<void> _saveHistory() async {
    final entries = state.historyList.map((h) =>
      '${h.id}###${h.videoPath}###${h.durationSeconds}###${h.createdAt.toIso8601String()}###${h.resolution}###${h.fileSizeBytes}'
    ).join('|||');
    await StorageUtil.setString('wanx_history', entries);
  }

  /// 设置照片路径（用户选择照片后）
  /// 万相wan2.2-s2v不需要强制人像检测，直接标记为就绪
  void setAvatarImage(String path) {
    state = state.copyWith(
      avatarImagePath: path,
      genState: VideoGenState.idle,
      progressMessage: '',
    );
    StorageUtil.setDhAvatarPath(path);
  }

  /// 清除照片
  void clearAvatarImage() {
    state = state.copyWith(
      clearAvatar: true,
      genState: VideoGenState.idle,
    );
    StorageUtil.setDhAvatarPath(null);
  }

  /// 设置配音路径（从语音合成页带入）
  void setAudioPath(String? path) {
    if (path == null) {
      state = state.copyWith(clearAudio: true);
      StorageUtil.setDhAudioPath(null);
    } else {
      state = state.copyWith(audioPath: path);
      StorageUtil.setDhAudioPath(path);
    }
  }

  /// 设置文案
  void setScriptText(String text) {
    state = state.copyWith(scriptText: text);
    StorageUtil.setDhScriptText(text);
  }

  /// 设置文案搜索关键词
  void setScriptTopic(String topic) {
    state = state.copyWith(scriptTopic: topic);
    StorageUtil.setDhScriptTopic(topic);
  }

  /// 设置画面提示词
  void setPrompt(String prompt) {
    state = state.copyWith(prompt: prompt);
    StorageUtil.setDhPrompt(prompt);
  }

  /// 设置输出分辨率
  void setOutputResolution(int resolution) {
    state = state.copyWith(outputResolution: resolution);
    StorageUtil.setDhResolution(resolution);
    // 调整快速模式：480P建议开启（更省额度）
    if (resolution == 480) {
      state = state.copyWith(fastMode: true);
      StorageUtil.setDhFastMode(true);
    } else {
      state = state.copyWith(fastMode: false);
      StorageUtil.setDhFastMode(false);
    }
  }

  /// 设置快速模式
  void setFastMode(bool enabled) {
    state = state.copyWith(fastMode: enabled);
    StorageUtil.setDhFastMode(enabled);
  }

  /// 生成视频（分段模式）
  /// 自动将文案切割为多段，每段独立生成TTS配音+数字人视频
  /// 万相模型快速模式强制关闭
  Future<void> generateVideo() async {
    if (!state.canGenerate) {
      state = state.copyWith(errorMessage: '请完善所有必填信息：照片、文案');
      return;
    }

    // 万相模型强制关闭快速模式
    final videoModel = StorageUtil.getVideoModel();
    final forceFastModeOff = (videoModel == 'wan2.2-s2v');

    state = state.copyWith(
      genState: VideoGenState.processingImage,
      progress: 0,
      progressMessage: '校验文案...',
      errorMessage: null,
      clearLocalVideoPath: true,
      clearSegmentResults: true,
      currentSegment: 0,
      totalSegments: 0,
      fastMode: forceFastModeOff ? false : state.fastMode,
    );

    try {
      // 使用多段生成流程：文案校验 → 切割 → 逐段TTS+视频
      final results = await _service.generateVideoMultiSegment(
        scriptText: state.scriptText,
        imagePath: state.avatarImagePath!,
        prompt: state.prompt.isNotEmpty ? state.prompt : null,
        outputResolution: state.outputResolution,
        onProgress: (stage, progress, segmentIdx, totalSegments) {
          VideoGenState genState;
          if (stage.contains('配音')) {
            genState = VideoGenState.processingImage;
          } else if (stage.contains('上传')) {
            genState = VideoGenState.uploadingAudio;
          } else if (stage.contains('提交')) {
            genState = VideoGenState.submitting;
          } else {
            genState = VideoGenState.processing;
          }
          state = state.copyWith(
            genState: stage.contains('完成') ? VideoGenState.completed : genState,
            progress: progress,
            progressMessage: stage,
            currentSegment: segmentIdx,
            totalSegments: totalSegments,
          );
        },
      );

      // 生成成功，保存每段视频到历史记录
      final updatedHistory = List<VideoHistoryItem>.from(state.historyList);
      for (final seg in results) {
        updatedHistory.insert(0, VideoHistoryItem(
          id: '${DateTime.now().millisecondsSinceEpoch}_seg${seg.segmentIndex}',
          videoPath: seg.localVideoPath,
          createdAt: DateTime.now(),
          resolution: '${state.outputResolution}p',
        ));
      }

      state = state.copyWith(
        genState: VideoGenState.completed,
        progress: 100,
        progressMessage: '全部完成！共${results.length}段',
        segmentResults: results,
        historyList: updatedHistory,
      );

      await _saveHistory();
    } catch (e) {
      final errorMsg = e.toString().replaceAll('Exception: ', '');
      state = state.copyWith(
        genState: VideoGenState.failed,
        progress: 0,
        errorMessage: errorMsg,
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

  /// 重置生成状态（允许重新生成）
  void resetGenState() {
    state = state.copyWith(
      genState: VideoGenState.idle,
      progress: 0,
      progressMessage: '',
      clearLocalVideoPath: true,
      clearSegmentResults: true,
      currentSegment: 0,
      totalSegments: 0,
    );
  }

  /// AI生成口播文案
  /// 根据配音内容或画面提示词，自动生成适合数字人口播的文案
  Future<void> generateScript() async {
    state = state.copyWith(isGeneratingScript: true, errorMessage: null);

    try {
      final topic = state.scriptTopic.trim();
      final hasTopic = topic.isNotEmpty;

      // 构建提示词上下文
      final contextHints = <String>[];
      if (state.prompt.isNotEmpty) {
        contextHints.add('画面要求：${state.prompt}');
      }
      if (state.outputResolution == 480) {
        contextHints.add('视频为480P分辨率');
      }

      final contextPart = contextHints.isNotEmpty
          ? '\n\n补充信息：\n${contextHints.map((h) => '- $h').join('\n')}'
          : '';

      // 读取设置中的文案生成模型偏好
      final scriptModel = StorageUtil.getScriptModel();

      // 构建系统提示词
      String systemPrompt;
      String userPrompt;

      if (hasTopic) {
        // 有搜索关键词：AI先联网搜索再创作
        systemPrompt = '你是一位专业的短视频口播文案创作专家，擅长根据最新网络热点和资讯创作口播文案。'
            '你可以根据用户提供的关键词先联网搜索相关最新信息，然后基于搜索结果创作高质量口播文案。'
            '文案要求：\n'
            '1. 适合1-3分钟口播，节奏感强\n'
            '2. 开头3秒抓住注意力\n'
            '3. 口语化表达，自然流畅\n'
            '4. 内容基于最新网络信息，有数据有案例\n'
            '5. 结尾有明确行动号召\n'
            '6. 直接输出文案正文，不要标题、不要解释';
        userPrompt = '请以「$topic」为主题，先联网搜索最新相关信息和素材，然后为我创作一段数字人口播文案，'
            '要求生动有感染力、内容有料有据。$contextPart';
      } else {
        // 无搜索关键词：直接创作
        systemPrompt = '你是一位专业的短视频口播文案创作专家。你创作的文案要求：\n'
            '1. 适合1-3分钟口播，节奏感强\n'
            '2. 开头3秒抓住注意力\n'
            '3. 口语化表达，自然流畅\n'
            '4. 结尾有明确行动号召\n'
            '5. 直接输出文案正文，不要标题、不要解释';
        userPrompt = '请为我创作一段数字人口播文案，要求生动有感染力。$contextPart';
      }

      final result = await _apiClient.chatSmart(
        messages: [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userPrompt},
        ],
        temperature: 0.8,
        modelOverride: scriptModel,
        enableSearch: hasTopic,
      );

      state = state.copyWith(
        scriptText: result.trim(),
        isGeneratingScript: false,
      );
      StorageUtil.setDhScriptText(result.trim());
    } catch (e) {
      state = state.copyWith(
        isGeneratingScript: false,
        errorMessage: 'AI生成文案失败：$e',
      );
    }
  }
}

/// DigitalHuman Provider定义
final digitalHumanProvider = StateNotifierProvider<DigitalHumanNotifier, DigitalHumanState>((ref) {
  return DigitalHumanNotifier(
    ref.read(digitalHumanServiceProvider),
    ref.read(apiClientProvider),
    ref.read(ttsServiceProvider),
  );
});
