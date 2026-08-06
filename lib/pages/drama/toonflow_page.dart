import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../services/toonflow_service.dart';
import '../../services/tts_service.dart';
import '../../utils/storage_util.dart';

/// ToonFlow短剧流水线页面
/// 输入剧本 → 导演Agent识别角色 → 分配角色音色 → 分镜+视频+配音 → 展示结果
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
  bool _enableTts = true;

  // 角色与音色
  List<ToonCharacter> _characters = [];
  bool _charactersReady = false; // 导演Agent是否已完成，角色已就绪
  bool _portraitsReady = false; // 定妆照是否已生成
  int _portraitSuccessCount = 0; // 成功生成定妆照的角色数

  // 运行状态
  bool _isRunning = false;
  String _currentStage = '';
  int _progress = 0;
  ToonFlowResult? _result;
  String? _error;

  // 单角色/单镜头重生成状态
  int? _regeneratingPortraitIdx; // 正在重新生成定妆照的角色索引
  int? _retryingVideoIdx; // 正在重试的视频镜头索引

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
  void initState() {
    super.initState();
    _loadSavedState();
  }

  @override
  void dispose() {
    _scriptController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ==================== 状态持久化 ====================

  static const String _stateKey = 'toonflow_cache_v2';

  /// 保存当前状态到本地缓存
  void _saveState() {
    try {
      final state = <String, dynamic>{
        'script': _scriptController.text,
        'videoModel': _videoModel,
        'aspectRatio': _aspectRatio,
        'baseStyle': _baseStyle,
        'enableTts': _enableTts,
        'charactersReady': _charactersReady,
        'portraitsReady': _portraitsReady,
        'portraitSuccessCount': _portraitSuccessCount,
        'characters': _characters.map((c) => c.toJson()).toList(),
        if (_result != null) 'result': _result!.toJson(),
      };
      StorageUtil.setString(_stateKey, jsonEncode(state));
    } catch (_) {}
  }

  /// 从本地缓存恢复状态
  Future<void> _loadSavedState() async {
    try {
      final saved = StorageUtil.getString(_stateKey);
      if (saved == null || saved.isEmpty) return;
      final state = jsonDecode(saved) as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _scriptController.text = state['script'] as String? ?? '';
        _videoModel = state['videoModel'] as String? ?? ToonFlowService.defaultVideoModel;
        _aspectRatio = state['aspectRatio'] as String? ?? ToonFlowService.defaultAspectRatio;
        _baseStyle = state['baseStyle'] as String? ?? ToonFlowService.defaultBaseStyle;
        _enableTts = state['enableTts'] as bool? ?? true;
        _charactersReady = state['charactersReady'] as bool? ?? false;
        _portraitsReady = state['portraitsReady'] as bool? ?? false;
        _portraitSuccessCount = state['portraitSuccessCount'] as int? ?? 0;
        if (state['characters'] != null) {
          _characters = (state['characters'] as List)
              .map((e) => ToonCharacter.fromJson(e as Map<String, dynamic>))
              .toList();
        }
        if (state['result'] != null) {
          _result = ToonFlowResult.fromJson(state['result'] as Map<String, dynamic>);
        }
      });
    } catch (_) {}
  }

  /// 清除缓存状态
  void _clearSavedState() {
    try {
      StorageUtil.setString(_stateKey, '');
    } catch (_) {}
  }

  /// 第一步：分析剧本，识别角色并生成定妆照
  Future<void> _analyzeScript() async {
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
      _currentStage = '导演Agent分析剧本...';
      _charactersReady = false;
      _portraitsReady = false;
      _portraitSuccessCount = 0;
      _characters = [];
    });

    try {
      final service = ref.read(toonFlowServiceProvider);
      final directorResult = await service.runDirectorAgent(
        userInput: script,
        onProgress: (stage, progress) {
          if (mounted) {
            setState(() {
              _currentStage = stage;
              _progress = progress;
            });
          }
        },
      );

      // 自动为角色分配音色
      ToonFlowService.autoAssignVoices(directorResult.characters);

      if (mounted) {
        setState(() {
          _characters = directorResult.characters;
          _charactersReady = true;
          _currentStage = '导演分析完成，正在生成角色定妆照...';
          _progress = 20;
        });
        _saveState();
      }

      // 自动生成定妆照
      final successCount = await service.runPortraitGeneration(
        characters: directorResult.characters,
        baseStyle: _baseStyle,
        aspectRatio: _aspectRatio,
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
          _portraitsReady = true;
          _portraitSuccessCount = successCount;
          _isRunning = false;
          _progress = 40;
          _currentStage = '定妆照生成完成，请确认角色配置';
        });
        // 滚动到角色配置区
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOut,
        );
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

  /// 第二步：开始生成视频+配音（复用已有角色含定妆照）
  Future<void> _startGeneration() async {
    final script = _scriptController.text.trim();
    if (script.isEmpty || _characters.isEmpty) return;

    setState(() {
      _isRunning = true;
      _error = null;
      _result = null;
      _progress = 0;
      _currentStage = '开始生成视频与配音...';
    });

    try {
      final service = ref.read(toonFlowServiceProvider);

      // 构建角色音色映射
      final voiceMap = <String, String>{};
      for (final char in _characters) {
        if (char.voiceId.isNotEmpty) {
          voiceMap[char.name] = char.voiceId;
        }
      }

      // 传入已有的角色（含定妆照和已确认的音色），避免重复执行导演Agent
      final result = await service.runFullPipeline(
        userInput: script,
        videoModel: _videoModel,
        aspectRatio: _aspectRatio,
        baseStyle: _baseStyle,
        characterVoiceMap: voiceMap,
        existingCharacters: _characters,
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
        _saveState();
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

  /// 一键生成（跳过角色确认，直接全流程）
  Future<void> _quickGenerate() async {
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
      _charactersReady = false;
      _portraitsReady = false;
      _portraitSuccessCount = 0;
      _characters = [];
    });

    try {
      final service = ref.read(toonFlowServiceProvider);
      final result = await service.runFullPipeline(
        userInput: script,
        videoModel: _videoModel,
        aspectRatio: _aspectRatio,
        baseStyle: _baseStyle,
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
          _characters = result.characters;
          _charactersReady = true;
          _isRunning = false;
          _progress = 100;
          _currentStage = '完成！';
        });
        _saveState();
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

  /// 重新生成单个角色的定妆照
  Future<void> _regeneratePortrait(int idx) async {
    if (_isRunning || idx < 0 || idx >= _characters.length) return;
    final char = _characters[idx];

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('重新生成定妆照', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定重新生成「${char.name}」的定妆照吗？',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('重新生成', style: TextStyle(color: Color(0xFF7C4DFF))),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _regeneratingPortraitIdx = idx;
    });

    try {
      final service = ref.read(toonFlowServiceProvider);
      final newUrl = await service.regenerateSinglePortrait(
        character: char,
        baseStyle: _baseStyle,
        aspectRatio: _aspectRatio,
      );
      if (mounted) {
        setState(() {
          _characters[idx].portraitUrl = newUrl;
          _regeneratingPortraitIdx = null;
          _portraitSuccessCount = _characters.where((c) => c.portraitUrl.isNotEmpty).length;
        });
        _saveState();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('「${char.name}」定妆照已更新'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _regeneratingPortraitIdx = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('定妆照生成失败: ${e.toString().substring(0, e.toString().length > 60 ? 60 : e.toString().length)}'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  /// 重试单个失败镜头的视频生成
  Future<void> _retrySingleVideo(int shotIdx) async {
    if (_result == null || shotIdx < 0) return;
    final shots = _result!.shots;
    if (shotIdx >= shots.length) return;
    final shot = shots[shotIdx];

    setState(() {
      _retryingVideoIdx = shotIdx;
    });

    try {
      final service = ref.read(toonFlowServiceProvider);
      final newVideo = await service.retrySingleShot(
        shotIndex: shotIdx,
        shot: shot,
        characters: _result!.characters,
        videoModel: _videoModel,
        aspectRatio: _aspectRatio,
        baseStyle: _baseStyle,
      );
      if (mounted) {
        setState(() {
          // 替换旧的视频片段
          final newSegments = <VideoSegment>[];
          for (final v in _result!.videoSegments) {
            if (v.index == shotIdx) {
              newSegments.add(newVideo);
            } else {
              newSegments.add(v);
            }
          }
          _result = ToonFlowResult(
            videoSegments: newSegments,
            audioSegments: _result!.audioSegments,
            endingHook: _result!.endingHook,
            characters: _result!.characters,
            outline: _result!.outline,
            shots: _result!.shots,
          );
          _retryingVideoIdx = null;
        });
        _saveState();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('镜头${shotIdx + 1}${newVideo.status == 'success' ? '重试成功' : '重试失败'}'), duration: const Duration(seconds: 2)),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() { _retryingVideoIdx = null; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('重试失败: ${e.toString().substring(0, e.toString().length > 60 ? 60 : e.toString().length)}'), duration: const Duration(seconds: 3)),
        );
      }
    }
  }

  /// 停止运行
  void _stopPipeline() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('视频生成任务已提交到服务端，无法中途取消')),
    );
  }

  /// 重试失败镜头
  Future<void> _retryFailedShots() async {
    if (_result == null) return;
    final failedCount = _result!.videoSegments.where((v) => v.status == 'failed').length;
    if (failedCount == 0) return;

    setState(() {
      _isRunning = true;
      _error = null;
      _progress = 0;
      _currentStage = '准备重试$failedCount个失败镜头...';
    });

    try {
      final service = ref.read(toonFlowServiceProvider);
      final result = await service.retryFailedShots(
        previousResult: _result!,
        videoModel: _videoModel,
        aspectRatio: _aspectRatio,
        baseStyle: _baseStyle,
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
          _currentStage = '重试完成！';
        });
      }
    } catch (e) {
        _saveState();
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isRunning = false;
        });
      }
    }
  }

  /// 预览全部成功视频
  void _previewAllVideos() {
    if (_result == null) return;
    final successVideos = _result!.videoSegments.where((v) => v.status == 'success').toList();
    if (successVideos.isEmpty) return;

    // 逐个打开成功视频的URL
    for (final v in successVideos) {
      if (v.videoUrl.isNotEmpty) {
        final uri = Uri.tryParse(v.videoUrl);
        if (uri != null) {
          launchUrl(uri, mode: LaunchMode.externalApplication);
        }
      }
    }
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
                  // 角色音色配置区（导演分析完成后显示）
                  if (_charactersReady && _result == null) ...[
                    _buildCharacterVoiceSection(),
                    const SizedBox(height: AppTheme.spacingMedium),
                  ],
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
            onChanged: (v) => setState(() { _videoModel = v!; _saveState(); }),
          ),
          const SizedBox(height: 12),
          // 画面比例
          _buildConfigDropdown(
            label: '画面比例',
            value: _aspectRatio,
            items: _ratioOptions,
            onChanged: (v) => setState(() { _aspectRatio = v!; _saveState(); }),
          ),
          const SizedBox(height: 12),
          // TTS开关
          Row(
            children: [
              const Text('配音', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
              const Spacer(),
              Switch(
                value: _enableTts,
                onChanged: (v) => setState(() { _enableTts = v; _saveState(); }),
                activeColor: const Color(0xFF7C4DFF),
              ),
            ],
          ),
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

  // ==================== 角色配置区（定妆照+音色） ====================

  Widget _buildCharacterVoiceSection() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
        border: Border.all(
          color: const Color(0xFFFF6B9D).withOpacity(0.3),
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
              color: const Color(0xFFFF6B9D).withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(AppTheme.radiusMedium),
                topRight: Radius.circular(AppTheme.radiusMedium),
              ),
            ),
            child: Row(
              children: [
                const Icon(Icons.theater_comedy, size: 18, color: Color(0xFFFF6B9D)),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '角色配置',
                    style: TextStyle(
                      color: Color(0xFFFF6B9D),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                Text(
                  '${_characters.length}个角色, $_portraitSuccessCount张定妆照',
                  style: TextStyle(color: AppTheme.textHint.withOpacity(0.7), fontSize: 12),
                ),
              ],
            ),
          ),
          // 角色配置列表（含定妆照）
          ..._characters.asMap().entries.map((entry) {
            final idx = entry.key;
            final char = entry.value;
            return _buildCharacterVoiceItem(idx, char);
          }),
          // 底部操作
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppTheme.spacingMedium,
              AppTheme.spacingSmall,
              AppTheme.spacingMedium,
              AppTheme.spacingMedium,
            ),
            child: Row(
              children: [
                // 重新分析按钮
                OutlinedButton.icon(
                  onPressed: _isRunning ? null : _analyzeScript,
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('重新分析', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFFF6B9D),
                    side: const BorderSide(color: Color(0xFFFF6B9D), width: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                ),
                const Spacer(),
                // 开始生成按钮
                ElevatedButton.icon(
                  onPressed: _isRunning ? null : _startGeneration,
                  icon: const Icon(Icons.play_arrow, size: 16),
                  label: const Text('开始生成', style: TextStyle(fontSize: 13)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7C4DFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
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

  Widget _buildCharacterVoiceItem(int idx, ToonCharacter char) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall + 4,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: const Color(0xFF2A2A4A).withOpacity(0.3),
            width: 0.5,
          ),
        ),
      ),
      child: Row(
        children: [
          // 角色定妆照（点击重新生成）
          GestureDetector(
            onTap: _regeneratingPortraitIdx == idx ? null : () => _showPortraitViewer(idx),
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: char.portraitUrl.isNotEmpty
                      ? const Color(0xFF7C4DFF).withOpacity(0.5)
                      : const Color(0xFF2A2A4A).withOpacity(0.5),
                  width: 1,
                ),
              ),
              child: Stack(
                children: [
                  char.portraitUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.network(
                            char.portraitUrl,
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, loadingProgress) {
                              if (loadingProgress == null) return child;
                              return Container(
                                color: const Color(0xFF2A2A4A),
                                child: const Center(
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Color(0xFF7C4DFF),
                                    ),
                                  ),
                                ),
                              );
                            },
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: const Color(0xFF2A2A4A),
                                child: const Icon(
                                  Icons.broken_image,
                                  color: AppTheme.textHint,
                                  size: 20,
                                ),
                              );
                            },
                          ),
                        )
                      : Container(
                          color: const Color(0xFF2A2A4A),
                          child: const Icon(
                            Icons.person_outline,
                            color: AppTheme.textHint,
                            size: 24,
                          ),
                        ),
                  // 重新生成中的加载遮罩
                  if (_regeneratingPortraitIdx == idx)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF7C4DFF),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          // 角色名和描述（点击编辑）
          Expanded(
            flex: 2,
            child: GestureDetector(
              onTap: () => _showCharacterEditDialog(idx),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 20,
                        height: 20,
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF6B9D).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Center(
                          child: Text(
                            '${idx + 1}',
                            style: const TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFFF6B9D),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          char.name,
                          style: const TextStyle(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Icon(Icons.edit, size: 12, color: AppTheme.textHint),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    char.desc,
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          // 音色选择下拉
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF7C4DFF).withOpacity(0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: const Color(0xFF7C4DFF).withOpacity(0.3),
                width: 0.5,
              ),
            ),
            child: DropdownButton<String>(
              value: char.voiceId.isEmpty ? null : char.voiceId,
              items: ToonFlowService.voicePool
                  .map((v) => DropdownMenuItem(
                        value: v['id'],
                        child: Text(
                          '${v['name']}（${v['style']}）',
                          style: const TextStyle(fontSize: 11),
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                      if (v != null) {
                        setState(() {
                          _characters[idx].voiceId = v;
                          _saveState();
                        });
                      }
                    },
              underline: const SizedBox.shrink(),
              dropdownColor: AppTheme.darkSurface,
              isDense: true,
              icon: const Icon(Icons.arrow_drop_down, size: 18, color: Color(0xFF7C4DFF)),
              style: const TextStyle(fontSize: 11, color: Color(0xFF7C4DFF)),
            ),
          ),
        ],
      ),
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
          // 角色列表（含音色信息）
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
                  Text('角色与音色', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFFFF6B9D))),
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
                  // 获取角色对应的音色名称
                  final voiceInfo = ToonFlowService.voicePool.firstWhere(
                    (v) => v['id'] == c.voiceId,
                    orElse: () => {'name': '', 'style': ''},
                  );
                  final voiceName = voiceInfo['name'] ?? '';

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
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // 角色定妆照小头像
                            if (c.portraitUrl.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Image.network(
                                  c.portraitUrl,
                                  width: 28,
                                  height: 28,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      Container(
                                        width: 28,
                                        height: 28,
                                        color: const Color(0xFF2A2A4A),
                                        child: const Icon(
                                          Icons.person_outline,
                                          color: AppTheme.textHint,
                                          size: 16,
                                        ),
                                      ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              c.name,
                              style: const TextStyle(
                                color: Color(0xFFFF6B9D),
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            if (voiceName.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF7C4DFF).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  '🎤 $voiceName',
                                  style: const TextStyle(
                                    color: Color(0xFF7C4DFF),
                                    fontSize: 9,
                                  ),
                                ),
                              ),
                            ],
                          ],
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

  /// 分镜列表（显示角色音色信息）
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

            // 获取说话角色对应的音色名和定妆照
            String speakerVoiceName = '';
            String speakerPortraitUrl = '';
            if (shot.speaker.isNotEmpty) {
              for (final char in result.characters) {
                if (char.name == shot.speaker) {
                  if (char.voiceId.isNotEmpty) {
                    final voiceInfo = ToonFlowService.voicePool.firstWhere(
                      (v) => v['id'] == char.voiceId,
                      orElse: () => {'name': ''},
                    );
                    speakerVoiceName = voiceInfo['name'] ?? '';
                  }
                  speakerPortraitUrl = char.portraitUrl;
                  break;
                }
              }
            }

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
              child: GestureDetector(
                onTap: () => _showShotEditDialog(idx),
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
                        Wrap(
                          spacing: 6,
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
                            if (shot.speaker.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF6B9D).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 角色定妆照小头像
                                    if (speakerPortraitUrl.isNotEmpty) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(3),
                                        child: Image.network(
                                          speakerPortraitUrl,
                                          width: 16,
                                          height: 16,
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) =>
                                              const SizedBox.shrink(),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      speakerVoiceName.isNotEmpty
                                          ? '${shot.speaker} · $speakerVoiceName'
                                          : shot.speaker,
                                      style: const TextStyle(fontSize: 10, color: Color(0xFFFF6B9D)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // 状态图标与操作按钮区
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 状态图标
                      if (isSuccess)
                        const Icon(Icons.check_circle, size: 18, color: AppTheme.safeColor)
                      else if (video?.status == 'failed')
                        const Icon(Icons.error_outline, size: 18, color: AppTheme.highRiskColor)
                      else
                        const Icon(Icons.hourglass_empty, size: 18, color: AppTheme.textHint),
                      const SizedBox(height: 4),
                      // 生成/重新生成视频按钮（始终显示）
                      if (_retryingVideoIdx == idx)
                        const SizedBox(
                          width: 24, height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                          ),
                        )
                      else
                        GestureDetector(
                          onTap: () => _retrySingleVideo(idx),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF9800).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.videocam, size: 12, color: Color(0xFFFF9800)),
                                const SizedBox(width: 2),
                                Text(
                                  isSuccess ? '重新生成' : '生成',
                                  style: const TextStyle(fontSize: 10, color: Color(0xFFFF9800)),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              ), // 关闭GestureDetector
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
    final isRetrying = _retryingVideoIdx == v.index;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMedium,
        vertical: AppTheme.spacingSmall,
      ),
      child: Row(
        children: [
          Icon(
            isRetrying ? Icons.hourglass_empty : (isSuccess ? Icons.play_circle_filled : Icons.error_outline),
            size: 20,
            color: isRetrying ? const Color(0xFFFF9800) : (isSuccess ? AppTheme.safeColor : AppTheme.highRiskColor),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              // 点击视频URL区域可复制链接
              onTap: isSuccess && v.videoUrl.isNotEmpty
                  ? () {
                      Clipboard.setData(ClipboardData(text: v.videoUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('镜头${v.index + 1}视频链接已复制'), duration: const Duration(seconds: 2)),
                      );
                    }
                  : null,
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
          ),
          // 操作按钮区
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 成功视频：打开链接按钮（绿色）
              if (isSuccess && v.videoUrl.isNotEmpty) ...[
                const SizedBox(width: 4),
                SizedBox(
                  height: 28,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      final uri = Uri.tryParse(v.videoUrl);
                      if (uri != null) {
                        launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                    icon: const Icon(Icons.open_in_new, size: 12),
                    label: const Text('打开', style: TextStyle(fontSize: 10)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(width: 4),
              // 所有视频：重新生成按钮（橙色），不管成功失败
              SizedBox(
                height: 28,
                child: isRetrying
                    ? const SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                        ),
                      )
                    : ElevatedButton.icon(
                        onPressed: () => _retrySingleVideo(v.index),
                        icon: const Icon(Icons.refresh, size: 12),
                        label: Text(isSuccess ? '重新生成' : '重试', style: const TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9800),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 音频结果（显示角色音色信息）
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
          ...result.audioSegments.map((a) {
            // 获取该镜头对应的角色和音色
            final shot = a.index < result.shots.length ? result.shots[a.index] : null;
            String voiceLabel = '';
            if (shot != null && shot.speaker.isNotEmpty) {
              for (final char in result.characters) {
                if (char.name == shot.speaker && char.voiceId.isNotEmpty) {
                  final voiceInfo = ToonFlowService.voicePool.firstWhere(
                    (v) => v['id'] == char.voiceId,
                    orElse: () => {'name': ''},
                  );
                  voiceLabel = voiceInfo['name'] ?? '';
                  break;
                }
              }
            }

            return Padding(
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
                    // 点击复制配音文本
                    child: GestureDetector(
                      onTap: a.audioText.isNotEmpty
                          ? () {
                              Clipboard.setData(ClipboardData(text: a.audioText));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('镜头${a.index + 1}配音文本已复制'),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          : null,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '镜头 ${a.index + 1}',
                                style: const TextStyle(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (voiceLabel.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF7C4DFF).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: Text(
                                    '🎤 $voiceLabel',
                                    style: const TextStyle(fontSize: 9, color: Color(0xFF7C4DFF)),
                                  ),
                                ),
                              ],
                              if (a.audioText.isNotEmpty) ...[
                                const SizedBox(width: 4),
                                const Icon(Icons.copy, size: 12, color: AppTheme.textHint),
                              ],
                            ],
                          ),
                          Text(
                            a.audioText,
                            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ==================== 对话框 ====================

  /// 显示定妆照大图查看器
  void _showPortraitViewer(int idx) {
    if (idx < 0 || idx >= _characters.length) return;
    final char = _characters[idx];
    if (char.portraitUrl.isEmpty) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.darkSurface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Text(
                      '「${char.name}」定妆照',
                      style: const TextStyle(color: AppTheme.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        _regeneratePortrait(idx);
                      },
                      icon: const Icon(Icons.refresh, size: 14),
                      label: const Text('重新生成', style: TextStyle(fontSize: 12)),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF7C4DFF),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppTheme.textHint, size: 20),
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
              // 大图
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 500),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    char.portraitUrl,
                    fit: BoxFit.contain,
                    width: double.infinity,
                    loadingBuilder: (context, child, loadingProgress) {
                    if (loadingProgress == null) return child;
                    return Container(
                      height: 300,
                      color: AppTheme.darkCard,
                      child: const Center(
                        child: CircularProgressIndicator(color: Color(0xFF7C4DFF)),
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      height: 200,
                      color: AppTheme.darkCard,
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.broken_image, color: AppTheme.textHint, size: 40),
                            SizedBox(height: 8),
                            Text('图片加载失败', style: TextStyle(color: AppTheme.textHint)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              ), // SizedBox
              // 角色描述
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  char.desc,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 角色编辑对话框
  void _showCharacterEditDialog(int idx) {
    if (idx < 0 || idx >= _characters.length) return;
    final char = _characters[idx];
    final nameCtrl = TextEditingController(text: char.name);
    final descCtrl = TextEditingController(text: char.desc);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('编辑角色', style: TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: '角色名称',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4A))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: '角色描述',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4A))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _characters[idx] = ToonCharacter(
                  name: nameCtrl.text.trim().isNotEmpty ? nameCtrl.text.trim() : char.name,
                  desc: descCtrl.text.trim(),
                  voiceId: char.voiceId,
                  portraitUrl: char.portraitUrl,
                );
                _saveState();
              });
              Navigator.of(ctx).pop();
            },
            child: const Text('保存', style: TextStyle(color: Color(0xFF7C4DFF))),
          ),
        ],
      ),
    );
  }

  /// 分镜编辑对话框
  void _showShotEditDialog(int shotIdx) {
    if (_result == null || shotIdx < 0 || shotIdx >= _result!.shots.length) return;
    final shot = _result!.shots[shotIdx];
    final descCtrl = TextEditingController(text: shot.scene_desc);
    final cameraCtrl = TextEditingController(text: shot.camera);
    final durationCtrl = TextEditingController(text: shot.duration);
    final speakerCtrl = TextEditingController(text: shot.speaker);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: Text('编辑镜头 ${shotIdx + 1}', style: const TextStyle(color: AppTheme.textPrimary)),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: descCtrl,
                maxLines: 3,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: '画面描述',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4A))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: cameraCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: '镜头类型',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4A))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: durationCtrl,
                      style: const TextStyle(color: AppTheme.textPrimary),
                      decoration: const InputDecoration(
                        labelText: '时长(秒)',
                        labelStyle: TextStyle(color: AppTheme.textSecondary),
                        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4A))),
                        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: speakerCtrl,
                style: const TextStyle(color: AppTheme.textPrimary),
                decoration: const InputDecoration(
                  labelText: '说话角色（留空=无台词）',
                  labelStyle: TextStyle(color: AppTheme.textSecondary),
                  enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF2A2A4A))),
                  focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Color(0xFF7C4DFF))),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final newShot = ShotItem(
                scene_desc: descCtrl.text.trim().isNotEmpty ? descCtrl.text.trim() : shot.scene_desc,
                camera: cameraCtrl.text.trim().isNotEmpty ? cameraCtrl.text.trim() : shot.camera,
                audio_text: shot.audio_text,
                duration: durationCtrl.text.trim().isNotEmpty ? durationCtrl.text.trim() : shot.duration,
                speaker: speakerCtrl.text.trim(),
              );
              setState(() {
                _result = ToonFlowResult(
                  videoSegments: _result!.videoSegments,
                  audioSegments: _result!.audioSegments,
                  endingHook: _result!.endingHook,
                  characters: _result!.characters,
                  outline: _result!.outline,
                  shots: _result!.shots.asMap().entries.map((e) {
                    if (e.key == shotIdx) return newShot;
                    return e.value;
                  }).toList(),
                );
                _saveState();
              });
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('分镜已更新，可点击重试按钮重新生成视频'), duration: Duration(seconds: 2)),
              );
            },
            child: const Text('保存并更新', style: TextStyle(color: Color(0xFF7C4DFF))),
          ),
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
    final hasResult = _result != null;
    final failedCount = _result?.videoSegments.where((v) => v.status == 'failed').length ?? 0;
    final successCount = _result?.videoSegments.where((v) => v.status == 'success').length ?? 0;
    final hasFailedShots = hasResult && failedCount > 0;
    final hasSuccessVideos = hasResult && successCount > 0;

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 结果状态时的按钮行
          if (hasResult) ...[
            Row(
              children: [
                // 字数统计
                Text(
                  '${_scriptController.text.length}字',
                  style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
                ),
                const Spacer(),
                // 重试失败镜头按钮（橙色警告风格）
                if (hasFailedShots) ...[
                  ElevatedButton.icon(
                    onPressed: _isRunning ? null : _retryFailedShots,
                    icon: _isRunning
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.refresh, size: 16),
                    label: Text(
                      _isRunning ? '重试中...' : '重试失败($failedCount)',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFFFF9800).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // 预览全部视频按钮
                if (hasSuccessVideos) ...[
                  ElevatedButton.icon(
                    onPressed: _isRunning ? null : _previewAllVideos,
                    icon: const Icon(Icons.play_circle_filled, size: 16),
                    label: Text('预览($successCount)', style: const TextStyle(fontSize: 12)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: const Color(0xFF4CAF50).withOpacity(0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // 重新分析按钮
                OutlinedButton.icon(
                  onPressed: _isRunning ? null : _analyzeScript,
                  icon: const Icon(Icons.auto_awesome, size: 16),
                  label: const Text('重新分析', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF7C4DFF),
                    side: const BorderSide(color: Color(0xFF7C4DFF), width: 0.5),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // 无结果时的原始按钮行
            Row(
              children: [
                // 字数统计
                Text(
                  '${_scriptController.text.length}字',
                  style: const TextStyle(color: AppTheme.textHint, fontSize: 12),
                ),
                const Spacer(),
                if (_charactersReady) ...[
                  // 角色已就绪时显示"一键生成"
                  OutlinedButton.icon(
                    onPressed: _isRunning ? null : _quickGenerate,
                    icon: const Icon(Icons.flash_on, size: 16),
                    label: const Text('一键生成', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7C4DFF),
                      side: const BorderSide(color: Color(0xFF7C4DFF), width: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                // 主按钮
                ElevatedButton.icon(
                  onPressed: _isRunning
                      ? null
                      : (_charactersReady ? null : _analyzeScript),
                  icon: _isRunning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : Icon(_charactersReady
                          ? Icons.check_circle_outline
                          : Icons.auto_awesome),
                  label: Text(_isRunning
                      ? '生成中...'
                      : (_charactersReady ? '角色已就绪' : '分析剧本')),
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
          ],
        ],
      ),
    );
  }
}
