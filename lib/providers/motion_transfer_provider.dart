import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/motion_transfer_service.dart';
import '../utils/storage_util.dart';
import '../config/api_config.dart';

/// 动作迁移页面状态
class MotionTransferState {
  /// 人物照片本地路径
  final String? characterImagePath;

  /// 动作参考视频本地路径
  final String? referenceVideoPath;

  /// 动作参考视频来源描述（如"模板-舞蹈1"或"本地视频"）
  final String? referenceVideoLabel;

  /// 当前选中的模型ID
  final String selectedModel;

  /// 质量参数（std/pro 或 分辨率）
  final String quality;

  /// 是否添加水印
  final bool watermark;

  /// 生成状态
  final MotionTransferStatus genStatus;

  /// 生成进度（0-100）
  final int progress;

  /// 进度描述信息
  final String progressMessage;

  /// 生成的结果视频本地路径
  final String? resultVideoPath;

  /// 当前任务ID
  final String? currentTaskId;

  /// 错误信息
  final String? errorMessage;

  const MotionTransferState({
    this.characterImagePath,
    this.referenceVideoPath,
    this.referenceVideoLabel,
    this.selectedModel = 'wan2.2-animate-move',
    this.quality = 'wan-std',
    this.watermark = false,
    this.genStatus = MotionTransferStatus.idle,
    this.progress = 0,
    this.progressMessage = '',
    this.resultVideoPath,
    this.currentTaskId,
    this.errorMessage,
  });

  MotionTransferState copyWith({
    String? characterImagePath,
    String? referenceVideoPath,
    String? referenceVideoLabel,
    String? selectedModel,
    String? quality,
    bool? watermark,
    MotionTransferStatus? genStatus,
    int? progress,
    String? progressMessage,
    String? resultVideoPath,
    String? currentTaskId,
    String? errorMessage,
    bool clearImage = false,
    bool clearVideo = false,
    bool clearResult = false,
    bool clearError = false,
  }) {
    return MotionTransferState(
      characterImagePath: clearImage ? null : (characterImagePath ?? this.characterImagePath),
      referenceVideoPath: clearVideo ? null : (referenceVideoPath ?? this.referenceVideoPath),
      referenceVideoLabel: clearVideo ? null : (referenceVideoLabel ?? this.referenceVideoLabel),
      selectedModel: selectedModel ?? this.selectedModel,
      quality: quality ?? this.quality,
      watermark: watermark ?? this.watermark,
      genStatus: genStatus ?? this.genStatus,
      progress: progress ?? this.progress,
      progressMessage: progressMessage ?? this.progressMessage,
      resultVideoPath: clearResult ? null : (resultVideoPath ?? this.resultVideoPath),
      currentTaskId: currentTaskId ?? this.currentTaskId,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }

  /// 是否可以开始生成
  bool get canGenerate =>
      characterImagePath != null &&
      characterImagePath!.isNotEmpty &&
      referenceVideoPath != null &&
      referenceVideoPath!.isNotEmpty &&
      genStatus == MotionTransferStatus.idle;
}

/// 动作迁移Notifier
class MotionTransferNotifier extends StateNotifier<MotionTransferState> {
  final MotionTransferService _service;
  Timer? _debounceTimer;

  MotionTransferNotifier(this._service) : super(const MotionTransferState()) {
    _loadSavedModel();
  }

  /// 加载用户保存的模型偏好
  Future<void> _loadSavedModel() async {
    final savedModel = StorageUtil.getMotionTransferModel();
    if (savedModel != state.selectedModel) {
      // 设置默认质量
      String defaultQuality = 'wan-std';
      if (savedModel == 'pixverse-motioncontrol') {
        defaultQuality = '540P';
      }
      state = state.copyWith(selectedModel: savedModel, quality: defaultQuality);
    }
  }

  // ==================== 素材设置 ====================

  /// 设置人物照片
  void setCharacterImage(String path) {
    state = state.copyWith(
      characterImagePath: path,
      clearResult: true,
      clearError: true,
    );
  }

  /// 清除人物照片
  void clearCharacterImage() {
    state = state.copyWith(clearImage: true, clearResult: true);
  }

  /// 设置动作参考视频
  void setReferenceVideo(String path, {String? label}) {
    state = state.copyWith(
      referenceVideoPath: path,
      referenceVideoLabel: label ?? '本地视频',
      clearResult: true,
      clearError: true,
    );
  }

  /// 清除动作视频
  void clearReferenceVideo() {
    state = state.copyWith(clearVideo: true, clearResult: true);
  }

  // ==================== 模型/质量设置 ====================

  /// 切换模型
  void setModel(String modelId) {
    // 切换模型时重置质量为对应模型的默认值
    String defaultQuality = 'wan-std';
    if (modelId == 'pixverse-motioncontrol') {
      defaultQuality = '540P';
    }
    state = state.copyWith(
      selectedModel: modelId,
      quality: defaultQuality,
      clearResult: true,
    );
    // 持久化保存
    StorageUtil.setMotionTransferModel(modelId);
  }

  /// 设置质量参数
  void setQuality(String quality) {
    state = state.copyWith(quality: quality, clearResult: true);
  }

  /// 切换水印
  void toggleWatermark(bool value) {
    state = state.copyWith(watermark: value, clearResult: true);
  }

  /// 清除错误
  void clearError() {
    state = state.copyWith(clearError: true);
  }

  /// 重置生成状态（用于重新生成）
  void resetGeneration() {
    state = state.copyWith(
      genStatus: MotionTransferStatus.idle,
      progress: 0,
      progressMessage: '',
      resultVideoPath: null,
      currentTaskId: null,
      clearError: true,
    );
  }

  // ==================== 生成动作迁移视频 ====================

  /// 开始生成动作迁移视频
  Future<void> generate() async {
    if (!state.canGenerate) return;

    state = state.copyWith(
      genStatus: MotionTransferStatus.uploading,
      progress: 0,
      progressMessage: '准备开始...',
      clearResult: true,
      clearError: true,
    );

    try {
      final result = await _service.generateMotionTransferVideo(
        modelId: state.selectedModel,
        imagePath: state.characterImagePath!,
        videoPath: state.referenceVideoPath!,
        quality: state.quality,
        watermark: state.watermark,
        onProgress: (status, progress, message) {
          state = state.copyWith(
            genStatus: status,
            progress: progress,
            progressMessage: message,
          );
        },
      );

      state = state.copyWith(
        genStatus: MotionTransferStatus.completed,
        progress: 100,
        progressMessage: '生成完成！',
        resultVideoPath: result.localVideoPath,
        currentTaskId: result.taskId,
      );

      // 保存到历史记录
      _saveToHistory(result);
    } catch (e) {
      state = state.copyWith(
        genStatus: MotionTransferStatus.failed,
        progress: 0,
        progressMessage: '',
        errorMessage: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  /// 保存到历史记录（通过task_log表）
  Future<void> _saveToHistory(MotionTransferResult result) async {
    try {
      // 这里可以扩展保存到本地数据库
      // 暂时不做复杂历史，仅通过文件缓存体现
    } catch (_) {
      // 历史记录保存失败不影响主流程
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}

/// 动作迁移Provider
final motionTransferProvider =
    StateNotifierProvider<MotionTransferNotifier, MotionTransferState>((ref) {
  return MotionTransferNotifier(MotionTransferService());
});

/// 动作迁移历史记录项
class MotionTransferHistoryItem {
  final int id;
  final String taskId;
  final String modelName;
  final String quality;
  final String? characterImagePath;
  final String? resultVideoPath;
  final int duration;
  final String createdAt;

  const MotionTransferHistoryItem({
    required this.id,
    required this.taskId,
    required this.modelName,
    required this.quality,
    this.characterImagePath,
    this.resultVideoPath,
    required this.duration,
    required this.createdAt,
  });
}
