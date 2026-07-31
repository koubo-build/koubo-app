import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../services/toonflow_service.dart';
import '../../services/tts_service.dart';

/// ToonFlow短剧流水线页面
/// 输入剧本 → 一键生成全流程 → 显示进度 → 展示结果
class ToonFlowPage extends ConsumerStatefulWidget {
  const ToonFlowPage({super.key});

  @override
  ConsumerState<ToonFlowPage> createState() => _ToonFlowPageState();
}

class _ToonFlowPageState extends ConsumerState<ToonFlowPage> {
  final _scriptController = TextEditingController();
  final _scrollController = ScrollController();

  // 配置参数
  String _videoModel = ToonFlowService.defaultVideoModel;
  String _aspectRatio = ToonFlowService.defaultAspectRatio;
  String _baseStyle = ToonFlowService.defaultBaseStyle;
  String _ttsVoiceId = 'longanhuan';
  bool _enableTts = true;

  // 运行状态
  bool _isRunning = false;
  String _currentStage = '';
  int _progress = 0;
  ToonFlowResult? _result;
  String? _error;

  // 视频模型选项
  static const List<Map<String, String>> _videoModelOptions = [
    {'value': 'Agnes-2.5-Flash', 'label': 'Agnes 2.5 Flash'},
    {'value': 'Agnes-2.0-Flash', 'label': 'Agnes 2.0 Flash'},
  ];

  // 画面比例选项
  static const List<Map<String, String>> _ratioOptions = [
    {'value': '9:16', 'label': '竖屏 9:16'},
    {'value': '16:9', 'label': '横屏 16:9'},
    {'value': '1:1', 'label': '方形 1:1'},
  ];

  @override
  void dispose() {
    _scriptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  /// 启动ToonFlow全流程
  Future<void> _startPipeline() async {
    final script = _scriptController.text.trim();
    if (script.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入剧本文本')),
      );
      return;
    }

    setState(() {
      _isRunning = true;
      _error = null;
      _result = null;
      _progress = 0;
      _currentStage = '准备中...';
    });

    try {
      final service = ref.read(toonFlowServiceProvider);
      final result = await service.runFullPipeline(
        userInput: script,
        videoModel: _videoModel,
        aspectRatio: _aspectRatio,
        baseStyle: _baseStyle,
        ttsVoiceId: _ttsVoiceId,
        enableTts: _enableTts,
        onProgress: (stage, progress) {
          if (mounted) {
            setState(() {
              _currentStage = stage;
              _progress = progress;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _result = result;
          _isRunning = false;
          _progress = 100;
          _currentStage = '完成！';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isRunning = false;
        });
      }
    }
  }

  /// 停止运行（目前不支持中途取消，仅UI提示）
  void _stopPipeline() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('视频生成任务已提交到服务端，无法中途取消')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('ToonFlow 短剧流水线'),
        actions: [
          if (_isRunning)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined),
              tooltip: '停止',
              onPressed: _stopPipeline,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 输入区
                  _buildInputSection(),
                  const SizedBox(height: AppTheme.spacingMedium),
                  // 配置区
                  _buildConfigSection(),
                  const SizedBox(height: AppTheme.spacingMedium),
                  // 进度区
                  if (_isRunning || _result != null || _error != null)
                    _buildProgressSection(),
                  const SizedBox(height: AppTheme.spacingMedium),
                  // 结果区
                  if (_result != null) _buildResultSection(),
                  // 错误区
                  if (_error != null) _buildErrorSection(),
                ],
              ),
            ),
          ),
          // 底部操作栏
          _buildBottomBar(),
        ],
      ),
    );
  }

  // ==================== 输入区 ====================

  Widget _buildInputSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: const Color(0xFF7C4DFF).withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题栏
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium,
              vertical: AppTheme.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMedium),
                topRight: Radius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.auto_stories, size: 18, color: Color(0xFF7C4DFF)),
                const SizedBox(width: 8),
                Text(
                  '剧本文本',
                  style: const TextStyle(
                    color: Color(0xFF7C4DFF),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const Spacer(),
                Text(
                  '粘贴或输入剧本内容',
                  style: TextStyle(color: AppTheme.textHint.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),
          // 文本输入
          Padding(
            padding: const EdgeInsets.all(AppTheme.spacingMedium),
            child: TextField(
              controller: _scriptController,
              maxLines: 8,
              enabled: !_isRunning,
              style: const TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 15,
                height: 1.6,
              ),
              decoration: InputDecoration(
                hintText: '输入短剧剧本...\n\n例如：一个平凡白领意外获得读心术，发现老板是外星人的故事...',
                hintStyle: const TextStyle(color: AppTheme.textHint),
                filled: true,
                fillColor: AppTheme.darkSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 配置区 ====================

  Widget _buildConfigSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(
          horizontal: AppTheme.spacingMedium,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          AppTheme.spacingMedium,
          0,
          AppTheme.spacingMedium,
          AppTheme.spacingMedium,
        ),
        title: const Row(
          children: [
            Icon(Icons.settings, size: 18, color: AppTheme.accentColor),
            SizedBox(width: 8),
            Text('流水线配置', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          ],
        ),
        children: [
          // 视频模型
          _buildConfigDropdown(
            label: '视频模型',
            value: _videoModel,
            items: _videoModelOptions,
            onChanged: _isRunning
                ? null
                : (v) => setState(() => _videoModel = v!),
          ),
          const SizedBox(height: 12),
          // 画面比例
          _buildConfigDropdown(
            label: '画面比例',
            value: _aspectRatio,
            items: _ratioOptions,
            onChanged: _isRunning
                ? null
                : (v) => setState(() => _aspectRatio = v!),
          ),
          const SizedBox(height: 12),
          // TTS开关
          Row(
            children: [
              const Text('配音', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const Spacer(),
              Switch(
                value: _enableTts,
                onChanged: _isRunning
                    ? null
                    : (v) => setState(() => _enableTts = v),
                activeColor: const Color(0xFF7C4DFF),
              ),
            ],
          ),
          if (_enableTts) ...[
            const SizedBox(height: 8),
            // TTS音色
            _buildConfigDropdown(
              label: '配音音色',
              value: _ttsVoiceId,
              items: TtsService.cosyVoiceList
                  .map((v) => {
                        'value': v['id'] ?? '',
                        'label': '${v['name']}（${v['style']}）',
                      })
                  .toList(),
              onChanged: _isRunning
                  ? null
                  : (v) => setState(() => _ttsVoiceId = v!),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConfigDropdown({
    required String label,
    required String value,
    required List<Map<String, String>> items,
    required ValueChanged<String?>? onChanged,
  }) {
    return Row(
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        const Spacer(),
        DropdownButton<String>(
          value: value,
          items: items
              .map((item) => DropdownMenuItem(
                    value: item['value'],
                    child: Text(
                      item['label'] ?? item['value'] ?? '',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ))
              .toList(),
          onChanged: onChanged,
          underline: const SizedBox.shrink(),
          dropdownColor: AppTheme.darkSurface,
          isDense: true,
        ),
      ],
    );
  }

  // ==================== 进度区 ====================

  Widget _buildProgressSection() {
    final stageColor = _result != null
        ? AppTheme.safeColor
        : _error != null
            ? AppTheme.highRiskColor
            : const Color(0xFF7C4DFF);

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 当前阶段
          Row(
            children: [
              if (_isRunning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF7C4DFF)),
                )
              else if (_result != null)
                const Icon(Icons.check_circle, size: 18, color: AppTheme.safeColor)
              else if (_error != null)
                const Icon(Icons.error, size: 18, color: AppTheme.highRiskColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _currentStage,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: stageColor,
                  ),
                ),
              ),
              Text(
                '$_progress%',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: stageColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 进度条
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress / 100.0,
              backgroundColor: AppTheme.darkSurface,
              valueColor: AlwaysStoppedAnimation<Color>(stageColor),
              minHeight: 6,
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 结果区 ====================

  Widget _buildResultSection() {
    final result = _result!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 大纲和角色
        _buildOutlineAndCharacters(result),
        const SizedBox(height: AppTheme.spacingMedium),

        // 分镜列表
        _buildShotsList(result),
        const SizedBox(height: AppTheme.spacingMedium),

        // 视频结果
        _buildVideoResults(result),
        const SizedBox(height: AppTheme.spacingMedium),

        // 音频结果
        if (result.audioSegments.isNotEmpty) _buildAudioResults(result),
      ],
    );
  }

  /// 大纲和角色
  Widget _buildOutlineAndCharacters(ToonFlowResult result) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 分集大纲
          if (result.outline.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingSmall,
              ),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(AppTheme.radiusMedium),
                  topRight: Radius.circular(AppTheme.radiusMedium),
                ),
              ),
              child: const Row(
                children: [
                  Icon(Icons.list_alt, size: 16, color: AppTheme.primaryColor),
                  SizedBox(width: 8),
                  Text('分集大纲', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.primaryColor)),
                ],
              ),
            ),
            ...result.outline.map((o) => _buildOutlineItem(o)),
          ],
          const Divider(height: 1, color: Color(0xFF2A2A4A)),
          // 角色列表
          if (result.characters.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingSmall,
              ),
              child: const Row(
                children: [
                  Icon(Icons.people, size: 16, color: Color(0xFFFF6B9D)),
                  SizedBox(width: 8),
                  Text('角色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFFF6B9D))),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: result.characters.map((c) {
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B9D).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFFFF6B9D).withOpacity(0.3),
                        width: 0.5,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          c.name,
                          style: const TextStyle(
                            color: Color(0xFFFF6B9D),
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 250),
                          child: Text(
                            c.desc,
                            style: const TextStyle(
                              color: AppTheme.textSecondary,
                              fontSize: 11,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  Widget _buildOutlineItem(OutlineItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withOpacity(0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              item.episode,
              style: const TextStyle(
                color: AppTheme.primaryColor,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.content,
                  style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13),
                ),
                if (item.hook.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '悬念：${item.hook}',
                      style: const TextStyle(
                        color: Colors.amber,
                        fontSize: 11,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 分镜列表
  Widget _buildShotsList(ToonFlowResult result) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium,
              vertical: AppTheme.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMedium),
                topRight: Radius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.movie_filter, size: 16, color: Color(0xFF7C4DFF)),
                const SizedBox(width: 8),
                Text(
                  '分镜列表（${result.shots.length}个镜头）',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF7C4DFF),
                  ),
                ),
              ],
            ),
          ),
          ...result.shots.asMap().entries.map((entry) {
            final idx = entry.key;
            final shot = entry.value;
            final video = idx < result.videoSegments.length
                ? result.videoSegments[idx]
                : null;
            final isSuccess = video?.status == 'success';

            return Container(
              padding: const EdgeInsets.all(AppTheme.spacingMedium),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: const Color(0xFF2A2A4A).withOpacity(0.5),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 序号
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: isSuccess
                          ? AppTheme.safeColor.withOpacity(0.2)
                          : video?.status == 'failed'
                              ? AppTheme.highRiskColor.withOpacity(0.2)
                              : const Color(0xFF7C4DFF).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Center(
                      child: Text(
                        '${idx + 1}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isSuccess
                              ? AppTheme.safeColor
                              : video?.status == 'failed'
                                  ? AppTheme.highRiskColor
                                  : const Color(0xFF7C4DFF),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // 镜头信息
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shot.scene_desc,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.darkSurface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                shot.camera,
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.darkSurface,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${shot.durationInt}s',
                                style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                              ),
                            ),
                            if (shot.audio_text.isNotEmpty) ...[
                              const SizedBox(width: 6),
                              const Icon(Icons.record_voice_over, size: 12, color: AppTheme.accentColor),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 状态图标
                  if (isSuccess)
                    const Icon(Icons.check_circle, size: 18, color: AppTheme.safeColor)
                  else if (video?.status == 'failed')
                    const Icon(Icons.error, size: 18, color: AppTheme.highRiskColor),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  /// 视频结果
  Widget _buildVideoResults(ToonFlowResult result) {
    final successVideos = result.videoSegments.where((v) => v.status == 'success').toList();
    final failedVideos = result.videoSegments.where((v) => v.status == 'failed').toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium,
              vertical: AppTheme.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: AppTheme.safeColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMedium),
                topRight: Radius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.videocam, size: 16, color: AppTheme.safeColor),
                const SizedBox(width: 8),
                Text(
                  '视频结果 ${result.successCount}/${result.totalCount}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.safeColor,
                  ),
                ),
                const Spacer(),
                // 结尾悬念
                if (result.endingHook.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '悬念: ${result.endingHook}',
                      style: const TextStyle(fontSize: 10, color: Colors.amber),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
            ),
          ),
          if (successVideos.isEmpty && failedVideos.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(
                child: Text('暂无视频结果', style: TextStyle(color: AppTheme.textHint)),
              ),
            ),
          // 成功视频列表
          ...successVideos.map((v) => _buildVideoItem(v, true)),
          // 失败视频列表
          if (failedVideos.isNotEmpty) ...[
            const Divider(height: 1, color: Color(0xFF2A2A4A)),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 8),
              child: Text(
                '失败 ${failedVideos.length} 个',
                style: const TextStyle(color: AppTheme.highRiskColor, fontSize: 12),
              ),
            ),
            ...failedVideos.map((v) => _buildVideoItem(v, false)),
          ],
        ],
      ),
    );
  }

  Widget _buildVideoItem(VideoSegment v, bool isSuccess) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      child: Row(
        children: [
          Icon(
            isSuccess ? Icons.play_circle_filled : Icons.error_outline,
            size: 20,
            color: isSuccess ? AppTheme.safeColor : AppTheme.highRiskColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '镜头 ${v.index + 1}',
                  style: const TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (isSuccess && v.videoUrl.isNotEmpty)
                  Text(
                    v.videoUrl,
                    style: const TextStyle(color: AppTheme.primaryColor, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (!isSuccess && v.error != null)
                  Text(
                    v.error!,
                    style: const TextStyle(color: AppTheme.highRiskColor, fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 音频结果
  Widget _buildAudioResults(ToonFlowResult result) {
    final successAudios = result.audioSegments.where((a) => a.status == 'success').toList();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppTheme.spacingMedium,
              vertical: AppTheme.spacingSmall,
            ),
            decoration: BoxDecoration(
              color: AppTheme.accentColor.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMedium),
                topRight: Radius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.headset, size: 16, color: AppTheme.accentColor),
                const SizedBox(width: 8),
                Text(
                  '配音结果 ${successAudios.length}/${result.audioSegments.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.accentColor,
                  ),
                ),
              ],
            ),
          ),
          ...result.audioSegments.map((a) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppTheme.spacingMedium,
                  vertical: AppTheme.spacingSmall,
                ),
                child: Row(
                  children: [
                    Icon(
                      a.status == 'success' ? Icons.volume_up : Icons.volume_off,
                      size: 18,
                      color: a.status == 'success' ? AppTheme.safeColor : AppTheme.highRiskColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '镜头 ${a.index + 1}: ${a.audioText}',
                        style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ==================== 错误区 ====================

  Widget _buildErrorSection() {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      decoration: BoxDecoration(
        color: AppTheme.highRiskColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: AppTheme.highRiskColor.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppTheme.highRiskColor, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error ?? '未知错误',
              style: const TextStyle(color: AppTheme.highRiskColor, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 底部操作栏 ====================

  Widget _buildBottomBar() {
    return Container(
      padding: EdgeInsets.only(
        left: AppTheme.spacingMedium,
        right: AppTheme.spacingMedium,
        top: AppTheme.spacingSmall,
        bottom: MediaQuery.of(context).padding.bottom + AppTheme.spacingSmall,
      ),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(
          top: BorderSide(color: const Color(0xFF2A2A4A).withOpacity(0.5), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // 字数统计
          Text(
            '${_scriptController.text.length}字',
            style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
          ),
          const Spacer(),
          // 开始按钮
          ElevatedButton.icon(
            onPressed: _isRunning ? null : _startPipeline,
            icon: _isRunning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.play_arrow),
            label: Text(_isRunning ? '生成中...' : '一键生成短剧'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF7C4DFF),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF7C4DFF).withOpacity(0.5),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
