import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/publish_service.dart';

/// 一键发布页面状态
class PublishState {
  /// 标题
  final String title;

  /// 关键词列表
  final List<String> keywords;

  /// 风格：tech/emotional/suspense
  final String style;

  /// 选择的视频路径
  final String? selectedVideoPath;

  /// 选择的封面路径
  final String? selectedCoverPath;

  /// 选择的发布平台
  final Set<String> platforms;

  /// 描述
  final String description;

  /// 标签
  final String tags;

  /// 是否正在发布
  final bool isPublishing;

  /// 发布结果（平台 -> 成功/失败）
  final Map<String, bool> publishResults;

  /// 是否正在生成封面
  final bool isGeneratingCover;

  /// 错误信息
  final String? errorMessage;

  const PublishState({
    this.title = '',
    this.keywords = const [],
    this.style = 'tech',
    this.selectedVideoPath,
    this.selectedCoverPath,
    this.platforms = const {},
    this.description = '',
    this.tags = '',
    this.isPublishing = false,
    this.publishResults = const {},
    this.isGeneratingCover = false,
    this.errorMessage,
  });

  PublishState copyWith({
    String? title,
    List<String>? keywords,
    String? style,
    String? selectedVideoPath,
    bool clearVideoPath = false,
    String? selectedCoverPath,
    bool clearCoverPath = false,
    Set<String>? platforms,
    String? description,
    String? tags,
    bool? isPublishing,
    Map<String, bool>? publishResults,
    bool? isGeneratingCover,
    String? errorMessage,
    bool clearError = false,
  }) {
    return PublishState(
      title: title ?? this.title,
      keywords: keywords ?? this.keywords,
      style: style ?? this.style,
      selectedVideoPath: clearVideoPath ? null : (selectedVideoPath ?? this.selectedVideoPath),
      selectedCoverPath: clearCoverPath ? null : (selectedCoverPath ?? this.selectedCoverPath),
      platforms: platforms ?? this.platforms,
      description: description ?? this.description,
      tags: tags ?? this.tags,
      isPublishing: isPublishing ?? this.isPublishing,
      publishResults: publishResults ?? this.publishResults,
      isGeneratingCover: isGeneratingCover ?? this.isGeneratingCover,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// 一键发布状态管理
class PublishNotifier extends ChangeNotifier {
  final PublishService _publishService;

  PublishState _state = const PublishState();
  PublishState get state => _state;

  PublishNotifier(this._publishService);

  /// 初始化（接收传入参数）
  void init({String? videoPath, String? coverPath, String? title}) {
    _state = _state.copyWith(
      selectedVideoPath: videoPath ?? _state.selectedVideoPath,
      selectedCoverPath: coverPath ?? _state.selectedCoverPath,
      title: title ?? _state.title,
    );
    notifyListeners();
  }

  /// 设置标题
  void setTitle(String title) {
    _state = _state.copyWith(title: title);
    notifyListeners();
  }

  /// 添加关键词
  void addKeyword(String keyword) {
    if (keyword.trim().isEmpty) return;
    if (_state.keywords.contains(keyword.trim())) return;
    _state = _state.copyWith(keywords: [..._state.keywords, keyword.trim()]);
    notifyListeners();
  }

  /// 删除关键词
  void removeKeyword(String keyword) {
    _state = _state.copyWith(
      keywords: _state.keywords.where((k) => k != keyword).toList(),
    );
    notifyListeners();
  }

  /// 设置风格
  void setStyle(String style) {
    _state = _state.copyWith(style: style);
    notifyListeners();
  }

  /// 切换平台选择
  void togglePlatform(String platform) {
    final updated = Set<String>.from(_state.platforms);
    if (updated.contains(platform)) {
      updated.remove(platform);
    } else {
      updated.add(platform);
    }
    _state = _state.copyWith(platforms: updated);
    notifyListeners();
  }

  /// 设置描述
  void setDescription(String desc) {
    _state = _state.copyWith(description: desc);
    notifyListeners();
  }

  /// 设置标签
  void setTags(String tags) {
    _state = _state.copyWith(tags: tags);
    notifyListeners();
  }

  /// 生成封面
  Future<void> generateCover() async {
    if (_state.title.trim().isEmpty) {
      _state = _state.copyWith(errorMessage: '请先输入标题');
      notifyListeners();
      return;
    }

    _state = _state.copyWith(isGeneratingCover: true, clearError: true);
    notifyListeners();

    try {
      final coverPath = await _publishService.generateCover(
        title: _state.title,
        keywords: _state.keywords,
        style: _state.style,
      );
      _state = _state.copyWith(
        isGeneratingCover: false,
        selectedCoverPath: coverPath,
      );
    } catch (e) {
      _state = _state.copyWith(
        isGeneratingCover: false,
        errorMessage: '封面生成失败：$e',
      );
    }
    notifyListeners();
  }

  /// 一键发布
  Future<void> publish() async {
    if (_state.selectedVideoPath == null || _state.selectedVideoPath!.isEmpty) {
      _state = _state.copyWith(errorMessage: '请先选择视频');
      notifyListeners();
      return;
    }
    if (_state.platforms.isEmpty) {
      _state = _state.copyWith(errorMessage: '请至少选择一个发布平台');
      notifyListeners();
      return;
    }

    _state = _state.copyWith(isPublishing: true, clearError: true);
    notifyListeners();

    try {
      final tagsList = _state.tags
          .split(RegExp(r'[,，\s]+'))
          .where((t) => t.trim().isNotEmpty)
          .toList();

      final results = await _publishService.publishToPlatforms(
        videoPath: _state.selectedVideoPath!,
        title: _state.title,
        coverPath: _state.selectedCoverPath ?? '',
        platforms: _state.platforms.toList(),
        description: _state.description,
        tags: tagsList,
      );

      // 解析发布结果
      final publishResults = <String, bool>{};
      for (final platform in _state.platforms) {
        final platformResult = results[platform];
        if (platformResult is Map) {
          publishResults[platform] = platformResult['success'] == true;
        } else if (platformResult is bool) {
          publishResults[platform] = platformResult;
        } else {
          publishResults[platform] = false;
        }
      }

      _state = _state.copyWith(
        isPublishing: false,
        publishResults: publishResults,
      );
    } catch (e) {
      // 发布失败时，所有平台标记为失败
      final publishResults = <String, bool>{};
      for (final platform in _state.platforms) {
        publishResults[platform] = false;
      }
      _state = _state.copyWith(
        isPublishing: false,
        publishResults: publishResults,
        errorMessage: '发布失败：$e',
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

/// Publish Provider
final publishProvider = ChangeNotifierProvider<PublishNotifier>((ref) {
  return PublishNotifier(ref.read(publishServiceProvider));
});
