import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/voice_model.dart';
import '../services/tts_service.dart';
import '../services/voice_clone_service.dart';
import '../services/api_client.dart';
import '../utils/storage_util.dart';

/// 音源类型
enum VoiceSourceType { system, cloned }

/// 录音模式
enum RecordMode { hold, tap }

/// 录音状态
enum RecordState { idle, recording, recorded, cloning }

/// 合成状态
enum SynthState { idle, synthesizing, completed, failed }

/// 播放状态
enum PlayState { stopped, playing, paused }

/// 语音合成页面状态
class VoiceState {
  /// 文案
  final String scriptText;

  /// 音源类型
  final VoiceSourceType sourceType;

  /// TTS引擎类型: 'cosyvoice' | 'edge_tts' | 'qwen_tts'
  final String ttsEngine;

  /// 系统音色列表
  final List<VoiceModel> systemVoices;

  /// 克隆音色列表
  final List<VoiceModel> clonedVoices;

  /// 当前选中音色
  final VoiceModel? selectedVoice;

  /// 音色搜索关键词
  final String searchKeyword;

  /// 录音状态
  final RecordState recordState;

  /// 录音模式
  final RecordMode recordMode;

  /// 录音时长（秒）
  final int recordDuration;

  /// 录音文件路径
  final String? recordFilePath;

  /// 克隆进度（0-100）
  final int cloneProgress;

  /// 克隆名称
  final String cloneVoiceName;

  /// 合成参数
  final double speed;
  final double pitch;
  final double volume;
  final String? emotion;

  /// 合成状态
  final SynthState synthState;

  /// 合成进度（0-100）
  final int synthProgress;

  /// 合成后音频路径
  final String? audioPath;

  /// 播放状态
  final PlayState playState;

  /// 播放位置（毫秒）
  final int playPosition;

  /// 音频总时长（毫秒）
  final int audioDuration;

  /// 错误信息
  final String? errorMessage;

  /// 是否正在加载音色列表
  final bool isLoadingVoices;

  /// 克隆区是否展开
  final bool isCloneExpanded;

  const VoiceState({
    this.scriptText = '',
    this.sourceType = VoiceSourceType.system,
    this.ttsEngine = 'cosyvoice',
    this.systemVoices = const [],
    this.clonedVoices = const [],
    this.selectedVoice,
    this.searchKeyword = '',
    this.recordState = RecordState.idle,
    this.recordMode = RecordMode.hold,
    this.recordDuration = 0,
    this.recordFilePath,
    this.cloneProgress = 0,
    this.cloneVoiceName = '',
    this.speed = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.emotion,
    this.synthState = SynthState.idle,
    this.synthProgress = 0,
    this.audioPath,
    this.playState = PlayState.stopped,
    this.playPosition = 0,
    this.audioDuration = 0,
    this.errorMessage,
    this.isLoadingVoices = false,
    this.isCloneExpanded = false,
  });

  VoiceState copyWith({
    String? scriptText,
    VoiceSourceType? sourceType,
    String? ttsEngine,
    List<VoiceModel>? systemVoices,
    List<VoiceModel>? clonedVoices,
    VoiceModel? selectedVoice,
    bool clearSelectedVoice = false,
    String? searchKeyword,
    RecordState? recordState,
    RecordMode? recordMode,
    int? recordDuration,
    String? recordFilePath,
    bool clearRecordFilePath = false,
    int? cloneProgress,
    String? cloneVoiceName,
    double? speed,
    double? pitch,
    double? volume,
    String? emotion,
    bool clearEmotion = false,
    SynthState? synthState,
    int? synthProgress,
    String? audioPath,
    bool clearAudioPath = false,
    PlayState? playState,
    int? playPosition,
    int? audioDuration,
    String? errorMessage,
    bool clearError = false,
    bool? isLoadingVoices,
    bool? isCloneExpanded,
  }) {
    return VoiceState(
      scriptText: scriptText ?? this.scriptText,
      sourceType: sourceType ?? this.sourceType,
      ttsEngine: ttsEngine ?? this.ttsEngine,
      systemVoices: systemVoices ?? this.systemVoices,
      clonedVoices: clonedVoices ?? this.clonedVoices,
      selectedVoice: clearSelectedVoice ? null : (selectedVoice ?? this.selectedVoice),
      searchKeyword: searchKeyword ?? this.searchKeyword,
      recordState: recordState ?? this.recordState,
      recordMode: recordMode ?? this.recordMode,
      recordDuration: recordDuration ?? this.recordDuration,
      recordFilePath: clearRecordFilePath ? null : (recordFilePath ?? this.recordFilePath),
      cloneProgress: cloneProgress ?? this.cloneProgress,
      cloneVoiceName: cloneVoiceName ?? this.cloneVoiceName,
      speed: speed ?? this.speed,
      pitch: pitch ?? this.pitch,
      volume: volume ?? this.volume,
      emotion: clearEmotion ? null : (emotion ?? this.emotion),
      synthState: synthState ?? this.synthState,
      synthProgress: synthProgress ?? this.synthProgress,
      audioPath: clearAudioPath ? null : (audioPath ?? this.audioPath),
      playState: playState ?? this.playState,
      playPosition: playPosition ?? this.playPosition,
      audioDuration: audioDuration ?? this.audioDuration,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLoadingVoices: isLoadingVoices ?? this.isLoadingVoices,
      isCloneExpanded: isCloneExpanded ?? this.isCloneExpanded,
    );
  }

  /// 根据搜索关键词过滤的音色列表
  List<VoiceModel> get filteredSystemVoices {
    if (searchKeyword.isEmpty) return systemVoices;
    final kw = searchKeyword.toLowerCase();
    return systemVoices.where((v) =>
      v.voiceName.toLowerCase().contains(kw) ||
      (v.style?.toLowerCase().contains(kw) ?? false) ||
      (v.gender == 'male' ? '男声' : '女声').contains(kw)
    ).toList();
  }

  /// 建议口播时长（秒）
  int get suggestedDurationSeconds => (scriptText.length / 3).round();

  /// 字数统计描述
  String get wordCountHint {
    final len = scriptText.length;
    if (len == 0) return '请输入配音文案';
    final sec30 = 90;
    final sec60 = 180;
    if (len <= sec30) return '$len字 ≈ ${len ~/ 3}秒口播';
    if (len <= sec60) return '$len字 ≈ ${len ~/ 3}秒口播（约1分钟）';
    return '$len字 ≈ ${(len / 60).toStringAsFixed(1)}分钟口播';
  }
}

/// 语音合成状态管理
class VoiceNotifier extends StateNotifier<VoiceState> {
  final TtsService _ttsService;
  final VoiceCloneService _voiceCloneService;

  VoiceNotifier(this._ttsService, this._voiceCloneService) : super(const VoiceState()) {
    _loadVoices();
  }

  /// 加载音色列表
  Future<void> _loadVoices() async {
    state = state.copyWith(isLoadingVoices: true);

    try {
      // 加载系统音色（Edge-TTS内置）
      final systemVoices = TtsService.edgeTtsVoices.map((v) {
        return VoiceModel(
          voiceName: v['name'] ?? '',
          voiceId: v['id'] ?? '',
          provider: 'edge_tts',
          gender: v['gender'],
          style: v['style'],
          language: 'zh-CN',
        );
      }).toList();

      // 加载克隆音色列表
      final clonedVoices = await _loadClonedVoices();

      state = state.copyWith(
        systemVoices: systemVoices,
        clonedVoices: clonedVoices,
        isLoadingVoices: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoadingVoices: false,
        errorMessage: '加载音色列表失败：$e',
      );
    }
  }

  /// 从本地存储加载克隆音色列表
  Future<List<VoiceModel>> _loadClonedVoices() async {
    try {
      final voicesJson = StorageUtil.getString('cloned_voices');
      if (voicesJson == null || voicesJson.isEmpty) return [];
      // 解析存储的克隆音色列表
      // 格式: voiceId1|voiceName1|time1;voiceId2|voiceName2|time2
      final entries = voicesJson.split(';');
      return entries.where((e) => e.isNotEmpty).map((entry) {
        final parts = entry.split('|');
        return VoiceModel(
          voiceId: parts[0],
          voiceName: parts.length > 1 ? parts[1] : '克隆音色',
          provider: 'cosyvoice',
          gender: parts.length > 2 ? parts[2] : null,
          style: '克隆音色',
          isCloned: true,
          createdAt: parts.length > 3 ? DateTime.tryParse(parts[3]) : null,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 保存克隆音色到本地
  Future<void> _saveClonedVoices() async {
    final entries = state.clonedVoices.map((v) =>
      '${v.voiceId}|${v.voiceName}|${v.gender ?? ""}|${v.createdAt?.toIso8601String() ?? ""}'
    ).join(';');
    await StorageUtil.setString('cloned_voices', entries);
  }

  /// 设置文案
  void setScriptText(String text) {
    state = state.copyWith(scriptText: text);
  }

  /// 设置音源类型
  void setSourceType(VoiceSourceType type) {
    state = state.copyWith(sourceType: type, clearSelectedVoice: true);
  }

  /// 设置 TTS 引擎
  void setTtsEngine(String engine) {
    state = state.copyWith(ttsEngine: engine);
  }

  /// 选择音色
  void selectVoice(VoiceModel voice) {
    state = state.copyWith(selectedVoice: voice);
  }

  /// 设置搜索关键词
  void setSearchKeyword(String keyword) {
    state = state.copyWith(searchKeyword: keyword);
  }

  /// 切换克隆区展开
  void toggleCloneExpanded() {
    state = state.copyWith(isCloneExpanded: !state.isCloneExpanded);
  }

  /// 设置录音状态
  void setRecordState(RecordState recordState) {
    state = state.copyWith(recordState: recordState);
  }

  /// 设置录音时长
  void setRecordDuration(int duration) {
    state = state.copyWith(recordDuration: duration);
  }

  /// 设置录音文件路径
  void setRecordFilePath(String? path) {
    if (path == null) {
      state = state.copyWith(clearRecordFilePath: true);
    } else {
      state = state.copyWith(recordFilePath: path);
    }
  }

  /// 设置克隆名称
  void setCloneVoiceName(String name) {
    state = state.copyWith(cloneVoiceName: name);
  }

  /// 设置录音模式
  void setRecordMode(RecordMode mode) {
    state = state.copyWith(recordMode: mode);
  }

  /// 设置语速
  void setSpeed(double speed) {
    state = state.copyWith(speed: speed);
  }

  /// 设置音调
  void setPitch(double pitch) {
    state = state.copyWith(pitch: pitch);
  }

  /// 设置音量
  void setVolume(double volume) {
    state = state.copyWith(volume: volume);
  }

  /// 设置情绪
  void setEmotion(String? emotion) {
    if (emotion == null) {
      state = state.copyWith(clearEmotion: true);
    } else {
      state = state.copyWith(emotion: emotion);
    }
  }

  /// 设置播放状态
  void setPlayState(PlayState playState) {
    state = state.copyWith(playState: playState);
  }

  /// 设置播放位置
  void setPlayPosition(int position) {
    state = state.copyWith(playPosition: position);
  }

  /// 设置音频总时长
  void setAudioDuration(int duration) {
    state = state.copyWith(audioDuration: duration);
  }

  /// 克隆声音
  Future<void> cloneVoice() async {
    if (state.recordFilePath == null || state.recordFilePath!.isEmpty) {
      state = state.copyWith(errorMessage: '请先录制语音样本');
      return;
    }
    if (state.cloneVoiceName.trim().isEmpty) {
      state = state.copyWith(errorMessage: '请为克隆音色命名');
      return;
    }

    state = state.copyWith(
      recordState: RecordState.cloning,
      cloneProgress: 10,
      errorMessage: null,
    );

    try {
      // 模拟上传进度
      state = state.copyWith(cloneProgress: 30);

      final voiceId = await _voiceCloneService.cloneVoice(
        audioFilePath: state.recordFilePath!,
        voiceName: state.cloneVoiceName.trim(),
      );

      state = state.copyWith(cloneProgress: 80);

      // 添加到克隆音色列表
      final newVoice = VoiceModel(
        voiceId: voiceId,
        voiceName: state.cloneVoiceName.trim(),
        provider: 'qwen_tts', // 使用 Qwen TTS 进行克隆音色合成
        style: '克隆音色',
        isCloned: true,
        createdAt: DateTime.now(),
      );

      final updatedList = [...state.clonedVoices, newVoice];
      state = state.copyWith(
        clonedVoices: updatedList,
        cloneProgress: 100,
        recordState: RecordState.idle,
        selectedVoice: newVoice,
        sourceType: VoiceSourceType.cloned,
        isCloneExpanded: false,
      );

      // 保存到本地
      await _saveClonedVoices();

      // 重置克隆名称
      state = state.copyWith(cloneVoiceName: '');
    } catch (e) {
      state = state.copyWith(
        recordState: RecordState.recorded,
        cloneProgress: 0,
        errorMessage: '声音克隆失败：$e',
      );
    }
  }

  /// 合成语音
  Future<void> synthesize() async {
    if (state.selectedVoice == null) {
      state = state.copyWith(errorMessage: '请先选择音色');
      return;
    }
    if (state.scriptText.trim().isEmpty) {
      state = state.copyWith(errorMessage: '请先输入配音文案');
      return;
    }

    state = state.copyWith(
      synthState: SynthState.synthesizing,
      synthProgress: 0,
      errorMessage: null,
      clearAudioPath: true,
      playState: PlayState.stopped,
      playPosition: 0,
      audioDuration: 0,
    );

    try {
      // 模拟进度
      state = state.copyWith(synthProgress: 20);

      // 根据音源类型选择 TTS 引擎
      // 克隆音色使用 qwen_tts，系统音色使用 ttsEngine 配置
      String provider;
      if (state.sourceType == VoiceSourceType.cloned) {
        provider = 'qwen_tts'; // 克隆音色必须使用 Qwen TTS
      } else {
        provider = state.ttsEngine; // 使用用户配置的引擎
      }

      final audioPath = await _ttsService.synthesize(
        text: state.scriptText.trim(),
        voiceId: state.selectedVoice!.voiceId,
        provider: provider,
        speed: state.speed,
        pitch: state.pitch,
        emotion: state.emotion,
      );

      state = state.copyWith(
        synthState: SynthState.completed,
        synthProgress: 100,
        audioPath: audioPath,
      );
    } catch (e) {
      state = state.copyWith(
        synthState: SynthState.failed,
        synthProgress: 0,
        errorMessage: '语音合成失败：$e',
      );
    }
  }

  /// 清除错误信息
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 删除克隆音色
  Future<void> deleteClonedVoice(String voiceId) async {
    final updatedList = state.clonedVoices.where((v) => v.voiceId != voiceId).toList();
    state = state.copyWith(clonedVoices: updatedList);
    if (state.selectedVoice?.voiceId == voiceId) {
      state = state.copyWith(clearSelectedVoice: true);
    }
    await _saveClonedVoices();
  }

  /// 重置合成状态
  void resetSynth() {
    state = state.copyWith(
      synthState: SynthState.idle,
      synthProgress: 0,
      clearAudioPath: true,
      playState: PlayState.stopped,
      playPosition: 0,
      audioDuration: 0,
    );
  }
}

/// VoiceProvider定义
final voiceProvider = StateNotifierProvider<VoiceNotifier, VoiceState>((ref) {
  return VoiceNotifier(
    ref.read(ttsServiceProvider),
    ref.read(voiceCloneServiceProvider),
  );
});
