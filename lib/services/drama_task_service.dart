import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/drama.dart';
import '../utils/storage_util.dart';
import 'image_gen_service.dart';

/// 短剧后台任务队列服务
/// 负责批量生成图片/视频，支持中断恢复
/// 每个镜头处理完就立即更新DB，即使App被杀掉也能根据shot.status恢复
class DramaTaskService {
  final ImageGenService _imageGenService;

  DramaTaskService(this._imageGenService);

  // 当前是否正在执行任务（防止并发）
  bool _isRunning = false;

  /// 当前是否正在执行任务
  bool get isRunning => _isRunning;

  // ==================== 批量图片生成 ====================

  /// 执行批量图片生成（后台持久化）
  /// 每个镜头生成完就更新DB，即使App退到后台也不丢失进度
  Future<void> batchGenerateImages({
    required int dramaId,
    required int episodeId,
    required List<DramaShot> shots,
    required List<DramaCharacter> characters,
    required Drama drama,
    void Function(int completed, int total, String currentShot)? onProgress,
  }) async {
    if (_isRunning) {
      throw Exception('已有任务正在执行，请等待完成后再试');
    }
    _isRunning = true;

    final config = drama.parsedModelConfig;
    final total = shots.length;
    int completed = 0;

    try {
      for (int i = 0; i < total; i++) {
        final shot = shots[i];

        // 跳过已完成的镜头（中断恢复场景）
        if (shot.status != 'pending') {
          completed++;
          onProgress?.call(completed, total, '跳过已完成: #${shot.shotNumber}');
          continue;
        }

        onProgress?.call(completed, total, '生成图片: 镜头 #${shot.shotNumber}');

        try {
          // 构建增强的prompt（注入角色描述和画风）
          final enhancedPrompt = ImageGenService.enhancePrompt(
            shot.visualDescription,
            drama.style,
            _buildCharacterDescForShot(shot, characters),
          );

          // 解析画面比例
          final size = ImageGenService.parseAspectRatio(drama.aspectRatio);

          // 生成图片
          final imagePath = await _imageGenService.generateImage(
            prompt: enhancedPrompt,
            width: size['width']!,
            height: size['height']!,
            model: config.imageModel,
            customApiKey: config.imageApiKey.isNotEmpty ? config.imageApiKey : null,
            customBaseUrl: config.imageBaseUrl.isNotEmpty ? config.imageBaseUrl : null,
            onProgress: (stage, progress) {
              // 可选：细化每个镜头的生成进度
            },
          );

          // 更新镜头状态和图片路径
          final updatedShot = shot.copyWith(
            imagePath: imagePath,
            promptEnhanced: enhancedPrompt,
            status: 'image_ready',
          );
          await StorageUtil.updateShot(updatedShot);

          completed++;
          onProgress?.call(completed, total, '镜头 #${shot.shotNumber} 图片完成');
        } catch (e) {
          // 单个镜头失败不中断整个批次
          final failedShot = shot.copyWith(status: 'failed');
          await StorageUtil.updateShot(failedShot);

          completed++;
          onProgress?.call(completed, total, '镜头 #${shot.shotNumber} 失败: ${e.toString().substring(0, e.toString().length > 50 ? 50 : e.toString().length)}');
        }
      }
    } finally {
      _isRunning = false;
    }
  }

  // ==================== 批量视频生成 ====================

  /// 执行批量视频生成
  Future<void> batchGenerateVideos({
    required int dramaId,
    required int episodeId,
    required List<DramaShot> shots,
    required Drama drama,
    void Function(int completed, int total, String currentShot)? onProgress,
  }) async {
    if (_isRunning) {
      throw Exception('已有任务正在执行，请等待完成后再试');
    }
    _isRunning = true;

    final total = shots.length;
    int completed = 0;

    try {
      for (int i = 0; i < total; i++) {
        final shot = shots[i];

        // 跳过已完成或图片未就绪的镜头
        if (shot.status == 'video_ready') {
          completed++;
          onProgress?.call(completed, total, '跳过已完成: #${shot.shotNumber}');
          continue;
        }
        if (shot.status == 'pending' || shot.imagePath == null) {
          completed++;
          onProgress?.call(completed, total, '跳过无图片: #${shot.shotNumber}');
          continue;
        }

        onProgress?.call(completed, total, '生成视频: 镜头 #${shot.shotNumber}');

        try {
          // TODO: 实现视频生成逻辑（调用视频生成API）
          // 目前先标记为完成，后续接入wanx-s2v等视频模型
          final updatedShot = shot.copyWith(status: 'video_ready');
          await StorageUtil.updateShot(updatedShot);

          completed++;
          onProgress?.call(completed, total, '镜头 #${shot.shotNumber} 视频完成');
        } catch (e) {
          final failedShot = shot.copyWith(status: 'failed');
          await StorageUtil.updateShot(failedShot);

          completed++;
          onProgress?.call(completed, total, '镜头 #${shot.shotNumber} 视频失败');
        }
      }
    } finally {
      _isRunning = false;
    }
  }

  // ==================== 恢复中断任务 ====================

  /// 恢复中断的任务
  /// 检查DB中status=pending但有部分已完成的镜头，继续生成
  Future<void> resumeInterruptTasks({
    required int dramaId,
    required int episodeId,
    void Function(int completed, int total, String stage)? onProgress,
  }) async {
    if (_isRunning) {
      throw Exception('已有任务正在执行，请等待完成后再试');
    }

    // 获取短剧信息
    final drama = await StorageUtil.getDrama(dramaId);
    if (drama == null) {
      throw Exception('短剧不存在');
    }

    // 获取角色列表
    final characters = await StorageUtil.getCharactersByDrama(dramaId);

    // 获取该集所有镜头
    final allShots = await StorageUtil.getShotsByEpisode(episodeId);

    // 统计已完成的镜头数
    final completedCount = allShots.where((s) => s.status == 'image_ready' || s.status == 'audio_ready' || s.status == 'video_ready').length;
    final pendingCount = allShots.where((s) => s.status == 'pending' || s.status == 'failed').length;

    if (pendingCount == 0) {
      onProgress?.call(allShots.length, allShots.length, '所有镜头已完成');
      return;
    }

    onProgress?.call(completedCount, allShots.length, '恢复任务：${pendingCount}个镜头待处理');

    // 获取待处理的镜头
    final pendingShots = allShots.where((s) => s.status == 'pending' || s.status == 'failed').toList();

    // 先恢复图片生成
    await batchGenerateImages(
      dramaId: dramaId,
      episodeId: episodeId,
      shots: pendingShots,
      characters: characters,
      drama: drama,
      onProgress: (completed, total, currentShot) {
        onProgress?.call(completedCount + completed, allShots.length, currentShot);
      },
    );
  }

  // ==================== 辅助方法 ====================

  /// 构建镜头的角色描述（用于增强prompt）
  String _buildCharacterDescForShot(DramaShot shot, List<DramaCharacter> characters) {
    if (shot.characterIds.isEmpty || characters.isEmpty) {
      return '';
    }

    final charIds = shot.characterIdList;
    final descParts = <String>[];

    for (final charId in charIds) {
      try {
        final character = characters.firstWhere((c) => c.id == charId);
        if (character.description.isNotEmpty) {
          descParts.add('${character.name}: ${character.description}');
        }
      } catch (_) {
        // 角色不存在，忽略
      }
    }

    return descParts.join('; ');
  }
}

/// DramaTaskService的Riverpod Provider
final dramaTaskServiceProvider = Provider<DramaTaskService>((ref) {
  return DramaTaskService(ImageGenService());
});
