import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../utils/storage_util.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_button.dart';
import '../../widgets/risk_badge.dart';

/// 历史记录页面 - 三个Tab：文案记录 / 音频记录 / 视频记录
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 数据列表
  List<Map<String, dynamic>> _scripts = [];
  List<Map<String, dynamic>> _audios = [];
  List<Map<String, dynamic>> _videos = [];

  // 搜索关键词
  final _searchController = TextEditingController();
  String _searchKeyword = '';

  // 批量选择模式
  bool _isSelectMode = false;
  final Set<int> _selectedIds = {};

  // 音频播放器
  final AudioPlayer _audioPlayer = AudioPlayer();
  int? _playingAudioId;

  // 加载状态
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.indexIsChanging) {
        setState(() {
          _isSelectMode = false;
          _selectedIds.clear();
        });
      }
    });
    _loadAllData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }

  /// 加载所有数据
  Future<void> _loadAllData() async {
    setState(() => _isLoading = true);
    try {
      _scripts = await StorageUtil.getAllScripts();
      _audios = await StorageUtil.getAllAudioFiles();
      _videos = await StorageUtil.getAllVideoFiles();

      // 如果有搜索关键词，过滤文案
      if (_searchKeyword.isNotEmpty) {
        _scripts = await StorageUtil.searchScripts(_searchKeyword);
      }
    } catch (e) {
      debugPrint('加载历史记录失败：$e');
    }
    setState(() => _isLoading = false);
  }

  /// 下拉刷新
  Future<void> _onRefresh() async {
    await _loadAllData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('历史记录'),
        actions: [
          if (_isSelectMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _isSelectMode = false;
                  _selectedIds.clear();
                });
              },
            )
          else
            IconButton(
              icon: const Icon(Icons.select_all),
              onPressed: () => setState(() => _isSelectMode = true),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '文案记录', icon: Icon(Icons.description_outlined, size: 18)),
            Tab(text: '音频记录', icon: Icon(Icons.audiotrack_outlined, size: 18)),
            Tab(text: '视频记录', icon: Icon(Icons.videocam_outlined, size: 18)),
          ],
          labelColor: AppTheme.primaryColor,
          unselectedLabelColor: AppTheme.textHint,
          indicatorColor: AppTheme.primaryColor,
        ),
      ),
      body: Column(
        children: [
          // 搜索栏（仅文案Tab显示）
          if (_tabController.index == 0)
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppTheme.spacingMedium,
                AppTheme.spacingSmall,
                AppTheme.spacingMedium,
                0,
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                decoration: InputDecoration(
                  hintText: '搜索文案内容...',
                  hintStyle: const TextStyle(color: AppTheme.textHint, fontSize: 14),
                  prefixIcon: const Icon(Icons.search, color: AppTheme.textHint, size: 20),
                  suffixIcon: _searchKeyword.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 18, color: AppTheme.textHint),
                          onPressed: () {
                            _searchController.clear();
                            _searchKeyword = '';
                            _loadAllData();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: AppTheme.darkSurface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
                onSubmitted: (value) {
                  _searchKeyword = value.trim();
                  _loadAllData();
                },
              ),
            ),

          // 批量操作栏
          if (_isSelectMode && _selectedIds.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppTheme.spacingMedium,
                vertical: AppTheme.spacingSmall,
              ),
              color: AppTheme.darkSurface,
              child: Row(
                children: [
                  Text('已选择 ${_selectedIds.length} 项', style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: _batchDelete,
                    icon: const Icon(Icons.delete, size: 16, color: AppTheme.highRiskColor),
                    label: const Text('删除', style: TextStyle(color: AppTheme.highRiskColor)),
                  ),
                ],
              ),
            ),

          // Tab内容
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: AppTheme.primaryColor))
                : RefreshIndicator(
                    onRefresh: _onRefresh,
                    color: AppTheme.primaryColor,
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildScriptList(),
                        _buildAudioList(),
                        _buildVideoList(),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ==================== 文案记录列表 ====================

  Widget _buildScriptList() {
    if (_scripts.isEmpty) {
      return _buildEmptyView('暂无文案记录', Icons.description_outlined);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      itemCount: _scripts.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSmall),
      itemBuilder: (context, index) {
        final script = _scripts[index];
        final id = script['id'] as int;
        final sourceText = script['source_text'] as String? ?? '';
        final platform = script['platform'] as String? ?? '抖音';
        final auditStatus = script['audit_status'] as String? ?? '未审核';
        final riskLevel = script['risk_level'] as String?;
        final createdAt = _formatTime(script['created_at'] as String?);

        // 显示前20个字
        final preview = sourceText.length > 20 ? '${sourceText.substring(0, 20)}...' : sourceText;

        final isSelected = _selectedIds.contains(id);

        return AppCard(
          child: InkWell(
            onTap: () {
              if (_isSelectMode) {
                setState(() {
                  if (isSelected) {
                    _selectedIds.remove(id);
                  } else {
                    _selectedIds.add(id);
                  }
                });
              } else {
                _showScriptDetail(script);
              }
            },
            onLongPress: () {
              if (!_isSelectMode) {
                setState(() {
                  _isSelectMode = true;
                  _selectedIds.add(id);
                });
              }
            },
            child: Row(
              children: [
                // 选择框（批量模式）
                if (_isSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spacingSmall),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                      size: 22,
                    ),
                  ),

                // 内容区
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          // 平台标签
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppTheme.primaryColor.withOpacity(0.15),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              platform,
                              style: const TextStyle(fontSize: 10, color: AppTheme.primaryColor, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // 审核状态徽章
                          if (riskLevel != null && riskLevel!.isNotEmpty)
                            RiskBadge(riskLevel: riskLevel!, compact: true)
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.textHint.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(3),
                              ),
                              child: Text(
                                auditStatus,
                                style: const TextStyle(fontSize: 10, color: AppTheme.textHint),
                              ),
                            ),
                          const Spacer(),
                          Text(createdAt, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        preview,
                        style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                // 操作箭头
                if (!_isSelectMode)
                  const Icon(Icons.chevron_right, color: AppTheme.textHint, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== 音频记录列表 ====================

  Widget _buildAudioList() {
    if (_audios.isEmpty) {
      return _buildEmptyView('暂无音频记录', Icons.audiotrack_outlined);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      itemCount: _audios.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSmall),
      itemBuilder: (context, index) {
        final audio = _audios[index];
        final id = audio['id'] as int;
        final voiceName = audio['voice_name'] as String? ?? '未知音色';
        final duration = audio['duration'] as num? ?? 0;
        final fileSize = audio['file_size'] as int? ?? 0;
        final createdAt = _formatTime(audio['created_at'] as String?);
        final isPlaying = _playingAudioId == id;
        final isSelected = _selectedIds.contains(id);

        return AppCard(
          child: InkWell(
            onTap: () {
              if (_isSelectMode) {
                setState(() {
                  if (isSelected) {
                    _selectedIds.remove(id);
                  } else {
                    _selectedIds.add(id);
                  }
                });
              } else {
                _playAudio(audio);
              }
            },
            onLongPress: () {
              if (!_isSelectMode) {
                setState(() {
                  _isSelectMode = true;
                  _selectedIds.add(id);
                });
              }
            },
            child: Row(
              children: [
                if (_isSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spacingSmall),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                      size: 22,
                    ),
                  ),

                // 播放按钮
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: (isPlaying ? AppTheme.primaryColor : const Color(0xFFE57373)).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                  ),
                  child: Icon(
                    isPlaying ? Icons.pause_circle : Icons.play_circle_filled,
                    color: isPlaying ? AppTheme.primaryColor : const Color(0xFFE57373),
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppTheme.spacingSmall),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(voiceName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(_formatDuration(duration.toDouble()), style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                          const SizedBox(width: 12),
                          Text(StorageUtil.formatFileSize(fileSize), style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                          const SizedBox(width: 12),
                          Text(createdAt, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                        ],
                      ),
                    ],
                  ),
                ),

                // 操作菜单
                if (!_isSelectMode)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textHint, size: 20),
                    onSelected: (action) => _handleAudioAction(action, audio),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'play', child: Text('播放')),
                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.highRiskColor))),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== 视频记录列表 ====================

  Widget _buildVideoList() {
    if (_videos.isEmpty) {
      return _buildEmptyView('暂无视频记录', Icons.videocam_outlined);
    }

    return ListView.separated(
      padding: const EdgeInsets.all(AppTheme.spacingMedium),
      itemCount: _videos.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppTheme.spacingSmall),
      itemBuilder: (context, index) {
        final video = _videos[index];
        final id = video['id'] as int;
        final avatarName = video['avatar_name'] as String? ?? '未知数字人';
        final duration = video['duration'] as num? ?? 0;
        final fileSize = video['file_size'] as int? ?? 0;
        final resolution = video['resolution'] as String? ?? '';
        final createdAt = _formatTime(video['created_at'] as String?);
        final isSelected = _selectedIds.contains(id);

        return AppCard(
          child: InkWell(
            onTap: () {
              if (_isSelectMode) {
                setState(() {
                  if (isSelected) {
                    _selectedIds.remove(id);
                  } else {
                    _selectedIds.add(id);
                  }
                });
              } else {
                _showVideoOptions(video);
              }
            },
            onLongPress: () {
              if (!_isSelectMode) {
                setState(() {
                  _isSelectMode = true;
                  _selectedIds.add(id);
                });
              }
            },
            child: Row(
              children: [
                if (_isSelectMode)
                  Padding(
                    padding: const EdgeInsets.only(right: AppTheme.spacingSmall),
                    child: Icon(
                      isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                      size: 22,
                    ),
                  ),

                // 视频缩略图占位
                Container(
                  width: 64,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFFBA68C8).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: const Icon(Icons.play_circle_outline, color: Color(0xFFBA68C8), size: 28),
                ),
                const SizedBox(width: AppTheme.spacingSmall),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(avatarName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (resolution.isNotEmpty) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: const Color(0xFFBA68C8).withOpacity(0.15),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(resolution, style: const TextStyle(fontSize: 10, color: Color(0xFFBA68C8))),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Text(_formatDuration(duration.toDouble()), style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                          const SizedBox(width: 8),
                          Text(StorageUtil.formatFileSize(fileSize), style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                          const SizedBox(width: 8),
                          Text(createdAt, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                        ],
                      ),
                    ],
                  ),
                ),

                if (!_isSelectMode)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: AppTheme.textHint, size: 20),
                    onSelected: (action) => _handleVideoAction(action, video),
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'play', child: Text('播放')),
                      const PopupMenuItem(value: 'share', child: Text('分享')),
                      const PopupMenuItem(value: 'delete', child: Text('删除', style: TextStyle(color: AppTheme.highRiskColor))),
                    ],
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ==================== 空视图 ====================

  Widget _buildEmptyView(String message, IconData icon) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 64, color: AppTheme.textHint.withOpacity(0.3)),
          const SizedBox(height: AppTheme.spacingMedium),
          Text(message, style: const TextStyle(fontSize: 16, color: AppTheme.textHint)),
        ],
      ),
    );
  }

  // ==================== 交互方法 ====================

  /// 显示文案详情
  void _showScriptDetail(Map<String, dynamic> script) {
    final id = script['id'] as int;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.7,
        minChildSize: 0.5,
        maxChildSize: 0.9,
        expand: false,
        builder: (_, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(AppTheme.spacingMedium),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 拖拽条
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textHint.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: AppTheme.spacingMedium),

              // 原文
              const Text('原始文案', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
              const SizedBox(height: 4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppTheme.spacingMedium),
                decoration: BoxDecoration(
                  color: AppTheme.darkBackground,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: SelectableText(
                  script['source_text'] as String? ?? '',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6),
                ),
              ),

              // 改写后文案
              if (script['rewritten_text'] != null) ...[
                const SizedBox(height: AppTheme.spacingMedium),
                const Text('改写文案', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppTheme.textSecondary)),
                const SizedBox(height: 4),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppTheme.spacingMedium),
                  decoration: BoxDecoration(
                    color: AppTheme.darkBackground,
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  ),
                  child: SelectableText(
                    script['rewritten_text'] as String? ?? '',
                    style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary, height: 1.6),
                  ),
                ),
              ],

              const SizedBox(height: AppTheme.spacingLarge),

              // 操作按钮
              Row(
                children: [
                  Expanded(
                    child: AppButton(
                      text: '重新编辑',
                      icon: Icons.edit,
                      isOutlined: true,
                      height: 44,
                      onPressed: () {
                        Navigator.pop(ctx);
                        Navigator.pushNamed(context, AppRoutes.rewrite, arguments: {
                          'text': script['source_text'] as String? ?? '',
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: AppTheme.spacingSmall),
                  Expanded(
                    child: AppButton(
                      text: '重新配音',
                      icon: Icons.record_voice_over,
                      height: 44,
                      onPressed: () {
                        Navigator.pop(ctx);
                        final text = script['rewritten_text'] as String? ?? script['source_text'] as String? ?? '';
                        Navigator.pushNamed(context, AppRoutes.voice, arguments: {'text': text});
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppTheme.spacingSmall),
              AppButton(
                text: '删除记录',
                icon: Icons.delete,
                height: 44,
                backgroundColor: AppTheme.highRiskColor,
                onPressed: () async {
                  await StorageUtil.deleteScript(id);
                  Navigator.pop(ctx);
                  _loadAllData();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 播放音频
  Future<void> _playAudio(Map<String, dynamic> audio) async {
    final id = audio['id'] as int;
    final filePath = audio['file_path'] as String?;

    if (filePath == null || filePath.isEmpty) {
      _showSnackBar('音频文件不存在');
      return;
    }

    try {
      if (_playingAudioId == id) {
        // 停止播放
        await _audioPlayer.stop();
        setState(() => _playingAudioId = null);
      } else {
        // 播放新音频
        await _audioPlayer.setFilePath(filePath);
        await _audioPlayer.play();
        setState(() => _playingAudioId = id);

        // 播放完毕后重置
        _audioPlayer.playerStateStream.listen((state) {
          if (state.processingState == ProcessingState.completed) {
            if (mounted) {
              setState(() => _playingAudioId = null);
            }
          }
        });
      }
    } catch (e) {
      _showSnackBar('播放失败：文件可能已移除');
      setState(() => _playingAudioId = null);
    }
  }

  /// 音频操作
  void _handleAudioAction(String action, Map<String, dynamic> audio) async {
    final id = audio['id'] as int;
    switch (action) {
      case 'play':
        _playAudio(audio);
        break;
      case 'delete':
        final confirmed = await _showDeleteConfirmDialog('确认删除该音频？');
        if (confirmed == true) {
          await StorageUtil.deleteAudioFile(id);
          _loadAllData();
          _showSnackBar('已删除');
        }
        break;
    }
  }

  /// 视频操作
  void _showVideoOptions(Map<String, dynamic> video) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppTheme.radiusLarge)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_circle_outline, color: AppTheme.primaryColor),
              title: const Text('播放视频'),
              onTap: () {
                Navigator.pop(ctx);
                final filePath = video['file_path'] as String?;
                if (filePath != null && filePath.isNotEmpty) {
                  Navigator.pushNamed(context, AppRoutes.digitalHuman, arguments: {
                    'videoPath': filePath,
                  });
                } else {
                  _showSnackBar('视频文件不存在');
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.share, color: AppTheme.accentColor),
              title: const Text('分享视频'),
              onTap: () {
                Navigator.pop(ctx);
                _showSnackBar('分享功能开发中');
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: AppTheme.highRiskColor),
              title: const Text('删除', style: TextStyle(color: AppTheme.highRiskColor)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirmed = await _showDeleteConfirmDialog('确认删除该视频？');
                if (confirmed == true) {
                  await StorageUtil.deleteVideoFile(video['id'] as int);
                  _loadAllData();
                  _showSnackBar('已删除');
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _handleVideoAction(String action, Map<String, dynamic> video) async {
    final id = video['id'] as int;
    switch (action) {
      case 'play':
        _showVideoOptions(video);
        break;
      case 'share':
        _showSnackBar('分享功能开发中');
        break;
      case 'delete':
        final confirmed = await _showDeleteConfirmDialog('确认删除该视频？');
        if (confirmed == true) {
          await StorageUtil.deleteVideoFile(id);
          _loadAllData();
          _showSnackBar('已删除');
        }
        break;
    }
  }

  /// 批量删除
  Future<void> _batchDelete() async {
    final confirmed = await _showDeleteConfirmDialog('确认删除选中的 ${_selectedIds.length} 项？');
    if (confirmed != true) return;

    final ids = _selectedIds.toList();
    setState(() {
      _isSelectMode = false;
      _selectedIds.clear();
    });

    switch (_tabController.index) {
      case 0:
        await StorageUtil.deleteScripts(ids);
        break;
      case 1:
        await StorageUtil.deleteAudioFiles(ids);
        break;
      case 2:
        await StorageUtil.deleteVideoFiles(ids);
        break;
    }
    _loadAllData();
    _showSnackBar('已删除 ${ids.length} 项');
  }

  /// 删除确认对话框
  Future<bool?> _showDeleteConfirmDialog(String message) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.highRiskColor),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }

  // ==================== 工具方法 ====================

  /// 格式化时间显示
  String _formatTime(String? isoTime) {
    if (isoTime == null || isoTime.isEmpty) return '';
    try {
      final dt = DateTime.parse(isoTime);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) return '刚刚';
      if (diff.inMinutes < 60) return '${diff.inMinutes}分钟前';
      if (diff.inHours < 24) return '${diff.inHours}小时前';
      if (diff.inDays < 7) return '${diff.inDays}天前';
      return '${dt.month}/${dt.day} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    } catch (_) {
      return '';
    }
  }

  /// 格式化时长
  String _formatDuration(double seconds) {
    if (seconds <= 0) return '0:00';
    final mins = (seconds / 60).floor();
    final secs = (seconds % 60).round();
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
