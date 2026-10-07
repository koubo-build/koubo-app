import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../config/api_config.dart';
import '../../providers/motion_transfer_provider.dart';
import '../../services/motion_transfer_service.dart';
import '../../services/image_gen_service.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';

/// 动作模板信息
class MotionTemplate {
  final String name;
  final String category;
  final String url;
  final String thumbnailUrl;
  final int duration; // 秒

  const MotionTemplate({
    required this.name,
    required this.category,
    required this.url,
    required this.thumbnailUrl,
    required this.duration,
  });
}

/// 内置动作模板（供用户快速选择，无需自己上传视频）
final List<MotionTemplate> _builtinTemplates = [
  MotionTemplate(
    name: '自信演讲',
    category: '口播',
    url: 'https://help-static-aliyun-doc.aliyuncs.com/file-manage-files/zh-CN/20250919/kaakcn/move_input_video.mp4',
    thumbnailUrl: '',
    duration: 5,
  ),
  MotionTemplate(
    name: '手势讲解',
    category: '口播',
    url: 'https://help-static-aliyun-doc.aliyuncs.com/file-manage-files/zh-CN/20250919/kaakcn/move_input_video.mp4',
    thumbnailUrl: '',
    duration: 5,
  ),
];

/// 动作迁移页面 - AI动作迁移创作
///
/// 功能：
/// 1. 上传人物照片（相册/拍照/AI生成）
/// 2. 选择动作参考视频（本地视频/模板库）
/// 3. 选择模型和质量
/// 4. 一键生成动作迁移视频
/// 5. 结果视频播放与分享
class MotionTransferPage extends ConsumerStatefulWidget {
  const MotionTransferPage({super.key});

  @override
  ConsumerState<MotionTransferPage> createState() => _MotionTransferPageState();
}

class _MotionTransferPageState extends ConsumerState<MotionTransferPage> {
  // 图片选择器
  final ImagePicker _imagePicker = ImagePicker();

  // 结果视频播放器
  VideoPlayerController? _resultVideoController;
  bool _resultVideoInitialized = false;

  // 参考视频预览播放器
  VideoPlayerController? _referenceVideoController;
  bool _referenceVideoInitialized = false;

  // AI生成图片服务
  final ImageGenService _imageGenService = ImageGenService();
  bool _isGeneratingImage = false;
  final TextEditingController _imagePromptController = TextEditingController();

  @override
  void dispose() {
    _resultVideoController?.dispose();
    _referenceVideoController?.dispose();
    _imagePromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mtState = ref.watch(motionTransferProvider);

    // 监听状态变化
    ref.listen<MotionTransferState>(motionTransferProvider, (prev, next) {
      // 错误提示
      if (next.errorMessage != null && next.errorMessage != prev?.errorMessage) {
        _showSnackBar(next.errorMessage!, isError: true);
      }

      // 生成完成时初始化播放器
      if (next.genStatus == MotionTransferStatus.completed &&
          next.resultVideoPath != null &&
          prev?.genStatus != MotionTransferStatus.completed) {
        _initResultVideoPlayer(next.resultVideoPath!);
      }

      // 参考视频变化时初始化预览
      if (next.referenceVideoPath != null &&
          next.referenceVideoPath != prev?.referenceVideoPath) {
        _initReferenceVideoPlayer(next.referenceVideoPath!);
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('AI动作迁移'),
        actions: [
          IconButton(
            onPressed: () => Navigator.pushNamed(context, AppRoutes.settings),
            icon: const Icon(Icons.settings, size: 22),
            tooltip: '设置',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部说明
            _buildIntroBanner(),
            const SizedBox(height: AppTheme.spacingMedium),

            // A. 素材上传区（左侧动作视频 + 右侧人物照片）
            _buildMediaSection(mtState),
            const SizedBox(height: AppTheme.spacingMedium),

            // B. 模型与参数设置
            _buildModelSettingsSection(mtState),
            const SizedBox(height: AppTheme.spacingMedium),

            // C. 生成进度与结果
            _buildGenerationSection(mtState),

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  // ==================== 顶部说明 Banner ====================

  Widget _buildIntroBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF6C5CE7), Color(0xFF0984E3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.directions_run, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '让照片里的人动起来',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  '上传照片 + 动作视频，一键生成动作迁移视频',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== A. 素材上传区 ====================

  Widget _buildMediaSection(MotionTransferState state) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 左侧：动作视频
        Expanded(
          child: _buildVideoUploadCard(
            title: '动作视频',
            subtitle: '参考动作',
            icon: Icons.videocam,
            iconColor: const Color(0xFFFF6B6B),
            videoPath: state.referenceVideoPath,
            label: state.referenceVideoLabel,
            onTap: _showVideoSourceDialog,
            onClear: state.genStatus == MotionTransferStatus.idle
                ? () => ref.read(motionTransferProvider.notifier).clearReferenceVideo()
                : null,
          ),
        ),
        const SizedBox(width: 12),
        // 中间箭头
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.swap_horiz, color: AppTheme.primaryColor, size: 18),
          ),
        ),
        const SizedBox(width: 12),
        // 右侧：人物照片
        Expanded(
          child: _buildImageUploadCard(
            title: '人物照片',
            subtitle: '目标角色',
            icon: Icons.person,
            iconColor: const Color(0xFF4ECDC4),
            imagePath: state.characterImagePath,
            onTap: _showImageSourceDialog,
            onClear: state.genStatus == MotionTransferStatus.idle
                ? () => ref.read(motionTransferProvider.notifier).clearCharacterImage()
                : null,
          ),
        ),
      ],
    );
  }

  Widget _buildVideoUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String? videoPath,
    required String? label,
    required VoidCallback onTap,
    required VoidCallback? onClear,
  }) {
    final hasVideo = videoPath != null && videoPath.isNotEmpty;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 标题栏
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (hasVideo && onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: const Icon(Icons.close, size: 16, color: AppTheme.textHint),
                  ),
              ],
            ),
          ),
          // 视频/占位区
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 140,
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E3A5F)),
              ),
              child: hasVideo
                  ? ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          _referenceVideoInitialized && _referenceVideoController != null
                              ? VideoPlayer(_referenceVideoController!)
                              : Container(color: Colors.black),
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.play_arrow, color: Colors.white, size: 24),
                            ),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: iconColor.withOpacity(0.6), size: 28),
                        const SizedBox(height: 4),
                        Text('点击选择', style: TextStyle(color: iconColor.withOpacity(0.8), fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(color: AppTheme.textHint, fontSize: 10)),
                      ],
                    ),
            ),
          ),
          if (hasVideo && label != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Text(
                label,
                style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required String? imagePath,
    required VoidCallback onTap,
    required VoidCallback? onClear,
  }) {
    final hasImage = imagePath != null && imagePath.isNotEmpty;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 16),
                const SizedBox(width: 6),
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (hasImage && onClear != null)
                  GestureDetector(
                    onTap: onClear,
                    child: const Icon(Icons.close, size: 16, color: AppTheme.textHint),
                  ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onTap,
            child: Container(
              height: 140,
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1B2A),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFF1E3A5F)),
                image: hasImage
                    ? DecorationImage(
                        image: FileImage(File(imagePath!)),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: hasImage
                  ? null
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add, color: iconColor.withOpacity(0.6), size: 28),
                        const SizedBox(height: 4),
                        Text('点击上传', style: TextStyle(color: iconColor.withOpacity(0.8), fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(subtitle, style: const TextStyle(color: AppTheme.textHint, fontSize: 10)),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== B. 模型与参数设置 ====================

  Widget _buildModelSettingsSection(MotionTransferState state) {
    final qualityOptions = MotionTransferService.getQualityOptions(state.selectedModel);

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.tune, color: AppTheme.primaryColor, size: 18),
              SizedBox(width: 8),
              Text('生成设置', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),

          // 模型选择
          const Text('选择模型', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: ApiConfig.motionTransferModelOptions.map((opt) {
              final isSelected = state.selectedModel == opt['value'];
              return Expanded(
                child: GestureDetector(
                  onTap: state.genStatus == MotionTransferStatus.idle
                      ? () => ref.read(motionTransferProvider.notifier).setModel(opt['value']!)
                      : null,
                  child: Container(
                    margin: EdgeInsets.only(
                      right: opt == ApiConfig.motionTransferModelOptions.last ? 0 : 8,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withOpacity(0.2)
                          : const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryColor : const Color(0xFF1E3A5F),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          opt['label']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          opt['desc']!,
                          style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
                          textAlign: TextAlign.center,
                          maxLines: 2,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 质量选择
          const Text('画质选择', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
          const SizedBox(height: 6),
          Row(
            children: qualityOptions.map((opt) {
              final isSelected = state.quality == opt['value'];
              return Expanded(
                child: GestureDetector(
                  onTap: state.genStatus == MotionTransferStatus.idle
                      ? () => ref.read(motionTransferProvider.notifier).setQuality(opt['value']!)
                      : null,
                  child: Container(
                    margin: EdgeInsets.only(
                      right: opt == qualityOptions.last ? 0 : 6,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.primaryColor.withOpacity(0.15)
                          : const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSelected ? AppTheme.primaryColor : const Color(0xFF1E3A5F),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          opt['label']!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          opt['desc']!,
                          style: const TextStyle(fontSize: 9, color: AppTheme.textHint),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 水印开关
          Row(
            children: [
              const Icon(Icons.water_drop_outlined, color: AppTheme.textHint, size: 16),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('添加AI水印', style: TextStyle(fontSize: 13)),
              ),
              Switch(
                value: state.watermark,
                onChanged: state.genStatus == MotionTransferStatus.idle
                    ? (v) => ref.read(motionTransferProvider.notifier).toggleWatermark(v)
                    : null,
                activeColor: AppTheme.primaryColor,
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ==================== C. 生成进度与结果 ====================

  Widget _buildGenerationSection(MotionTransferState state) {
    if (state.genStatus == MotionTransferStatus.completed &&
        state.resultVideoPath != null) {
      return _buildResultSection(state);
    }

    if (state.genStatus != MotionTransferStatus.idle &&
        state.genStatus != MotionTransferStatus.failed) {
      return _buildProgressSection(state);
    }

    // 空闲状态：显示生成按钮
    return Column(
      children: [
        // 估算费用提示
        if (state.canGenerate)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1B4332).withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2D6A4F).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: Color(0xFF52B788), size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '预计消耗：约${_estimateCost(state)}元（按实际生成秒数计费）',
                      style: const TextStyle(color: Color(0xFF95D5B2), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

        // 生成按钮
        AppButton(
          text: '开始生成',
          icon: Icons.auto_awesome,
          onPressed: state.canGenerate
              ? () => ref.read(motionTransferProvider.notifier).generate()
              : null,
          width: double.infinity,
        ),

        if (!state.canGenerate && state.genStatus == MotionTransferStatus.idle)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              '请先上传人物照片和动作视频',
              style: TextStyle(color: AppTheme.textHint, fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),

        if (state.genStatus == MotionTransferStatus.failed)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: AppButton(
              text: '重新生成',
              icon: Icons.refresh,
              onPressed: () {
                ref.read(motionTransferProvider.notifier).resetGeneration();
              },
              isOutlined: true,
              width: double.infinity,
            ),
          ),
      ],
    );
  }

  Widget _buildProgressSection(MotionTransferState state) {
    String statusText = '处理中...';
    IconData statusIcon = Icons.hourglass_empty;

    switch (state.genStatus) {
      case MotionTransferStatus.uploading:
        statusText = '上传素材';
        statusIcon = Icons.cloud_upload;
        break;
      case MotionTransferStatus.submitting:
        statusText = '提交任务';
        statusIcon = Icons.send;
        break;
      case MotionTransferStatus.processing:
        statusText = 'AI生成中';
        statusIcon = Icons.auto_awesome;
        break;
      case MotionTransferStatus.downloading:
        statusText = '下载视频';
        statusIcon = Icons.download;
        break;
      default:
        break;
    }

    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(statusIcon, color: AppTheme.primaryColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      statusText,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      state.progressMessage.isNotEmpty
                          ? state.progressMessage
                          : '请耐心等待...',
                      style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Text(
                '${state.progress}%',
                style: const TextStyle(
                  color: AppTheme.primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress / 100,
              backgroundColor: const Color(0xFF0D1B2A),
              valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.primaryColor),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            '生成过程通常需要1-5分钟，请不要关闭页面',
            style: TextStyle(color: AppTheme.textHint, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildResultSection(MotionTransferState state) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Color(0xFF52B788), size: 20),
              SizedBox(width: 8),
              Text('生成完成', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),

          // 视频播放器
          Container(
            height: 200,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(12),
            ),
            child: _resultVideoInitialized && _resultVideoController != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        VideoPlayer(_resultVideoController!),
                        Center(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                if (_resultVideoController!.value.isPlaying) {
                                  _resultVideoController!.pause();
                                } else {
                                  _resultVideoController!.play();
                                }
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                _resultVideoController!.value.isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : const Center(
                    child: Icon(Icons.play_circle_outline, color: Colors.white54, size: 48),
                  ),
          ),
          const SizedBox(height: 12),

          // 模型信息
          Row(
            children: [
              _buildInfoChip(Icons.model_training, state.selectedModel),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.star, state.quality),
            ],
          ),
          const SizedBox(height: 12),

          // 操作按钮
          Row(
            children: [
              Expanded(
                child: AppButton(
                  text: '分享视频',
                  icon: Icons.share,
                  onPressed: state.resultVideoPath != null
                      ? () => _shareVideo(state.resultVideoPath!)
                      : null,
                  isOutlined: true,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AppButton(
                  text: '再生成一个',
                  icon: Icons.refresh,
                  onPressed: () =>
                      ref.read(motionTransferProvider.notifier).resetGeneration(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: AppTheme.textHint),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  // ==================== 图片选择相关 ====================

  void _showImageSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择人物照片',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildImageSourceOption(
                icon: Icons.photo_library,
                title: '从相册选择',
                subtitle: '选择手机相册中的照片',
                color: const Color(0xFF4ECDC4),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 10),
              _buildImageSourceOption(
                icon: Icons.camera_alt,
                title: '拍照',
                subtitle: '立即拍摄一张照片',
                color: const Color(0xFFFF6B6B),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              const SizedBox(height: 10),
              _buildImageSourceOption(
                icon: Icons.auto_awesome,
                title: 'AI生成图片',
                subtitle: '用AI生成虚拟人物照片',
                color: const Color(0xFF6C5CE7),
                onTap: () {
                  Navigator.pop(context);
                  _showAIImageDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageSourceOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: const Color(0xFF0D1B2A),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(color: AppTheme.textHint, fontSize: 12)),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: AppTheme.textHint),
            ],
          ),
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
        ref.read(motionTransferProvider.notifier).setCharacterImage(image.path);
      }
    } catch (e) {
      _showSnackBar('选择图片失败：${e.toString().replaceAll('Exception: ', '')}', isError: true);
    }
  }

  // ==================== AI生成图片 ====================

  void _showAIImageDialog() {
    _imagePromptController.text = '';
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('AI生成人物照片', style: TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '描述你想要的人物形象，AI将自动生成',
                style: TextStyle(color: AppTheme.textHint, fontSize: 12),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _imagePromptController,
                maxLines: 3,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  hintText: '例如：一位年轻女性，职业装，微笑，白色背景，高清写真',
                  hintStyle: TextStyle(color: AppTheme.textHint),
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(10),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _buildPromptChip('职业女性', setDialogState),
                  _buildPromptChip('商务男士', setDialogState),
                  _buildPromptChip('年轻女孩', setDialogState),
                  _buildPromptChip('老师形象', setDialogState),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            _isGeneratingImage
                ? const CircularProgressIndicator(strokeWidth: 2)
                : TextButton(
                    onPressed: () => _generateAIImage(),
                    child: const Text('生成'),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptChip(String text, void Function(void Function()) setDialogState) {
    return GestureDetector(
      onTap: () {
        setDialogState(() {
          _imagePromptController.text = text;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppTheme.primaryColor.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.primaryColor.withOpacity(0.3)),
        ),
        child: Text(text, style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor)),
      ),
    );
  }

  Future<void> _generateAIImage() async {
    final prompt = _imagePromptController.text.trim();
    if (prompt.isEmpty) {
      _showSnackBar('请输入图片描述', isError: true);
      return;
    }

    Navigator.pop(context);
    setState(() => _isGeneratingImage = true);

    // 显示加载提示
    _showSnackBar('AI正在生成图片，请稍候...');

    try {
      final imagePath = await _imageGenService.generateImage(
        prompt: prompt,
        model: 'siliconflow', // 默认用硅基流动FLUX免费模型
        width: 768,
        height: 1024,
        onProgress: (stage, progress) {},
      );

      if (mounted) {
        ref.read(motionTransferProvider.notifier).setCharacterImage(imagePath);
        _showSnackBar('图片生成成功！');
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('图片生成失败：${e.toString().replaceAll('Exception: ', '')}', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingImage = false);
      }
    }
  }

  // ==================== 视频选择相关 ====================

  void _showVideoSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择动作视频',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              _buildImageSourceOption(
                icon: Icons.video_library,
                title: '从相册选择',
                subtitle: '选择本地视频作为动作参考',
                color: const Color(0xFFFF6B6B),
                onTap: () {
                  Navigator.pop(context);
                  _pickVideo();
                },
              ),
              const SizedBox(height: 10),
              _buildImageSourceOption(
                icon: Icons.library_books,
                title: '模板库',
                subtitle: '精选动作模板，一键使用',
                color: const Color(0xFF4ECDC4),
                onTap: () {
                  Navigator.pop(context);
                  _showTemplateDialog();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickVideo() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (video != null) {
        ref
            .read(motionTransferProvider.notifier)
            .setReferenceVideo(video.path, label: '本地视频');
      }
    } catch (e) {
      _showSnackBar('选择视频失败：${e.toString().replaceAll('Exception: ', '')}', isError: true);
    }
  }

  void _showTemplateDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2E),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('动作模板库', style: TextStyle(fontSize: 16)),
        content: SizedBox(
          width: 300,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '选择一个模板作为动作参考',
                style: TextStyle(color: AppTheme.textHint, fontSize: 12),
              ),
              const SizedBox(height: 12),
              ..._builtinTemplates.map((t) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: const Color(0xFF0D1B2A),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () {
                          // 直接使用URL（通过百炼公网URL访问）
                          ref.read(motionTransferProvider.notifier).setReferenceVideo(
                                t.url,
                                label: '模板-${t.name}',
                              );
                          Navigator.pop(context);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF1E3A5F),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(Icons.play_circle_outline,
                                    color: AppTheme.primaryColor),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(t.name,
                                        style: const TextStyle(
                                            fontSize: 14, fontWeight: FontWeight.w600)),
                                    const SizedBox(height: 2),
                                    Text('${t.category} · ${t.duration}秒',
                                        style: const TextStyle(
                                            color: AppTheme.textHint, fontSize: 11)),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right, color: AppTheme.textHint),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
              // 提示信息
              const SizedBox(height: 8),
              const Text(
                '更多模板陆续更新中...',
                style: TextStyle(color: AppTheme.textHint, fontSize: 11),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  // ==================== 视频播放器初始化 ====================

  Future<void> _initResultVideoPlayer(String videoPath) async {
    await _resultVideoController?.dispose();
    _resultVideoController = VideoPlayerController.file(File(videoPath));
    try {
      await _resultVideoController!.initialize();
      await _resultVideoController!.setLooping(true);
      if (mounted) {
        setState(() {
          _resultVideoInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('结果视频初始化失败：$e');
    }
  }

  Future<void> _initReferenceVideoPlayer(String videoPath) async {
    await _referenceVideoController?.dispose();

    // 判断是本地文件还是网络URL
    if (videoPath.startsWith('http://') || videoPath.startsWith('https://')) {
      _referenceVideoController = VideoPlayerController.networkUrl(Uri.parse(videoPath));
    } else {
      _referenceVideoController = VideoPlayerController.file(File(videoPath));
    }

    try {
      await _referenceVideoController!.initialize();
      await _referenceVideoController!.setLooping(true);
      if (mounted) {
        setState(() {
          _referenceVideoInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('参考视频初始化失败：$e');
    }
  }

  // ==================== 分享 ====================

  Future<void> _shareVideo(String videoPath) async {
    try {
      await Share.shareXFiles(
        [XFile(videoPath)],
        text: '来自我的AI动作迁移视频',
      );
    } catch (e) {
      _showSnackBar('分享失败：$e', isError: true);
    }
  }

  // ==================== 工具方法 ====================

  String _estimateCost(MotionTransferState state) {
    // 假设平均5秒（实际按生成秒数计费）
    final cost = MotionTransferService.estimateCost(
      state.selectedModel,
      state.quality,
      5,
    );
    return cost.toStringAsFixed(2);
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : AppTheme.primaryColor,
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }
}
