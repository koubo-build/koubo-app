import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/video_edit_service.dart';

/// 视频混剪页面状态
class VideoEditState {
  /// 当前步骤（0-5）
  final int currentStep;

  /// 选择的风格：tech/emotional/suspense
  final String selectedStyle;

  /// 选择的背景视频
  final Map<String, dynamic>? selectedBgVideo;

  /// 选择的背景音乐
  final Map<String, dynamic>? selectedMusic;

  /// 字幕设置
  final SubtitleSettings subtitleSettings;

  /// 是否正在合成
  final bool isComposing;

  /// 合成进度（0.0-1.0）
  final double composeProgress;

  /// 合成结果视频路径
  final String? resultVideoPath;

  /// 文案内容
  final String scriptText;

  /// 数字人视频路径
  final String? faceVideoPath;

  /// 搜索到的背景视频列表
  final List<Map<String, dynamic>> bgVideoList;

  /// 搜索关键词
  final String searchKeyword;

  /// 是否正在搜索
  final bool isSearching;

  /// 音乐列表
  final List<Map<String, dynamic>> musicList;

  /// 当前音乐Tab类别
  final String currentMusicCategory;

  /// 错误信息
  final String? errorMessage;

  const VideoEditState({
    this.currentStep = 0,
    this.selectedStyle = 'tech',
    this.selectedBgVideo,
    this.selectedMusic,
    this.subtitleSettings = const SubtitleSettings(),
    this.isComposing = false,
    this.composeProgress = 0,
    this.resultVideoPath,
    this.scriptText = '',
    this.faceVideoPath,
    this.bgVideoList = const [],
    this.searchKeyword = '',
    this.isSearching = false,
    this.musicList = const [],
    this.currentMusicCategory = 'tech',
    this.errorMessage,
  });

  VideoEditState copyWith({
    int? currentStep,
    String? selectedStyle,
    Map<String, dynamic>? selectedBgVideo,
    bool clearBgVideo = false,
    Map<String, dynamic>? selectedMusic,
    bool clearMusic = false,
    SubtitleSettings? subtitleSettings,
    bool? isComposing,
    double? composeProgress,
    String? resultVideoPath,
    bool clearResultVideo = false,
    String? scriptText,
    String? faceVideoPath,
    bool clearFaceVideo = false,
    List<Map<String, dynamic>>? bgVideoList,
    String? searchKeyword,
    bool? isSearching,
    List<Map<String, dynamic>>? musicList,
    String? currentMusicCategory,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VideoEditState(
      currentStep: currentStep ?? this.currentStep,
      selectedStyle: selectedStyle ?? this.selectedStyle,
      selectedBgVideo: clearBgVideo ? null : (selectedBgVideo ?? this.selectedBgVideo),
      selectedMusic: clearMusic ? null : (selectedMusic ?? this.selectedMusic),
      subtitleSettings: subtitleSettings ?? this.subtitleSettings,
      isComposing: isComposing ?? this.isComposing,
      composeProgress: composeProgress ?? this.composeProgress,
      resultVideoPath: clearResultVideo ? null : (resultVideoPath ?? this.resultVideoPath),
      scriptText: scriptText ?? this.scriptText,
      faceVideoPath: clearFaceVideo ? null : (faceVideoPath ?? this.faceVideoPath),
      bgVideoList: bgVideoList ?? this.bgVideoList,
      searchKeyword: searchKeyword ?? this.searchKeyword,
      isSearching: isSearching ?? this.isSearching,
      musicList: musicList ?? this.musicList,
      currentMusicCategory: currentMusicCategory ?? this.currentMusicCategory,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 字幕设置
class SubtitleSettings {
  final double fontSize;
  final String color; // white/yellow/green
  final String position; // top/bottom

  const SubtitleSettings({
    this.fontSize = 24,
    this.color = 'white',
    this.position = 'bottom',
  });

  SubtitleSettings copyWith({
    double? fontSize,
    String? color,
    String? position,
  }) {
    return SubtitleSettings(
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      position: position ?? this.position,
    );
  }
}

/// 视频混剪状态管理
class VideoEditNotifier extends ChangeNotifier {
  final VideoEditService _videoEditService;

  VideoEditState _state = const VideoEditState();
  VideoEditState get state => _state;

  VideoEditNotifier(this._videoEditService);

  /// 初始化（接收传入参数）
  void init({String? initialScript, String? faceVideoPath}) {
    _state = _state.copyWith(
      scriptText: initialScript ?? _state.scriptText,
      faceVideoPath: faceVideoPath ?? _state.faceVideoPath,
    );
    notifyListeners();
  }

  /// 下一步
  void nextStep() {
    if (_state.currentStep < 5) {
      _state = _state.copyWith(currentStep: _state.currentStep + 1);
      notifyListeners();
    }
  }

  /// 上一步
  void prevStep() {
    if (_state.currentStep > 0) {
      _state = _state.copyWith(currentStep: _state.currentStep - 1);
      notifyListeners();
    }
  }

  /// 选择风格
  void selectStyle(String style) {
    _state = _state.copyWith(selectedStyle: style);
    notifyListeners();
  }

  /// 设置文案
  void setScriptText(String text) {
    _state = _state.copyWith(scriptText: text);
    notifyListeners();
  }

  /// 设置数字人视频路径
  void setFaceVideoPath(String? path) {
    if (path == null) {
      _state = _state.copyWith(clearFaceVideo: true);
    } else {
      _state = _state.copyWith(faceVideoPath: path);
    }
    notifyListeners();
  }

  /// 搜索背景素材
  Future<void> searchMaterials(String keyword) async {
    if (keyword.trim().isEmpty) return;

    _state = _state.copyWith(isSearching: true, searchKeyword: keyword, clearError: true);
    notifyListeners();

    try {
      final results = await _videoEditService.searchPexelsVideos(keyword);
      _state = _state.copyWith(bgVideoList: results, isSearching: false);
    } catch (e) {
      _state = _state.copyWith(isSearching: false, errorMessage: '搜索素材失败：$e');
    }
    notifyListeners();
  }

  /// 选择背景视频
  void selectBgVideo(Map<String, dynamic> video) {
    _state = _state.copyWith(selectedBgVideo: video);
    notifyListeners();
  }

  /// 选择音乐
  void selectMusic(Map<String, dynamic> music) {
    _state = _state.copyWith(selectedMusic: music);
    notifyListeners();
  }

  /// 切换音乐Tab
  Future<void> switchMusicCategory(String category) async {
    _state = _state.copyWith(currentMusicCategory: category);
    notifyListeners();

    try {
      final musicList = await _videoEditService.getMusicList(category);
      _state = _state.copyWith(musicList: musicList);
    } catch (e) {
      _state = _state.copyWith(errorMessage: '获取音乐列表失败：$e');
    }
    notifyListeners();
  }

  /// 加载默认音乐列表
  Future<void> loadMusicList() async {
    try {
      final musicList = await _videoEditService.getMusicList(_state.currentMusicCategory);
      _state = _state.copyWith(musicList: musicList);
    } catch (e) {
      _state = _state.copyWith(errorMessage: '获取音乐列表失败：$e');
    }
    notifyListeners();
  }

  /// 更新字幕设置
  void updateSubtitleSettings(SubtitleSettings settings) {
    _state = _state.copyWith(subtitleSettings: settings);
    notifyListeners();
  }

  /// 开始合成视频
  Future<void> compose() async {
    if (_state.scriptText.trim().isEmpty) {
      _state = _state.copyWith(errorMessage: '请先输入文案');
      notifyListeners();
      return;
    }

    _state = _state.copyWith(
      isComposing: true,
      composeProgress: 0,
      clearError: true,
    );
    notifyListeners();

    try {
      // 模拟进度
      for (int i = 0; i <= 80; i += 20) {
        await Future.delayed(const Duration(milliseconds: 500));
        _state = _state.copyWith(composeProgress: i / 100);
        notifyListeners();
      }

      final result = await _videoEditService.composeVideo(
        script: _state.scriptText,
        faceVideoPath: _state.faceVideoPath ?? '',
        style: _state.selectedStyle,
        bgVideoUrl: _state.selectedBgVideo?['url'],
        bgMusicId: _state.selectedMusic?['id'],
        subtitleSettings: {
          'fontSize': _state.subtitleSettings.fontSize,
          'color': _state.subtitleSettings.color,
          'position': _state.subtitleSettings.position,
        },
      );

      _state = _state.copyWith(
        isComposing: false,
        composeProgress: 1.0,
        resultVideoPath: result['video_path'] ?? '',
      );
    } catch (e) {
      _state = _state.copyWith(
        isComposing: false,
        composeProgress: 0,
        errorMessage: '视频合成失败：$e',
      );
    }
    notifyListeners();
  }

  /// 清除错误
  void clearError() {
    _state = _state.copyWith(clearError: true);
    notifyListeners();
  }
}

/// VideoEdit Provider
final videoEditProvider = ChangeNotifierProvider<VideoEditNotifier>((ref) {
  return VideoEditNotifier(ref.read(videoEditServiceProvider));
});
