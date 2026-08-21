import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/drama.dart';
import '../../models/task_log.dart';
import '../../services/drama_service.dart';
import '../../utils/storage_util.dart';

/// 短剧编辑器页面
class DramaEditorPage extends ConsumerStatefulWidget {
  final int? dramaId;

  const DramaEditorPage({super.key, this.dramaId});

  @override
  ConsumerState<DramaEditorPage> createState() => _DramaEditorPageState();
}

class _DramaEditorPageState extends ConsumerState<DramaEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  Drama? _drama;
  List<DramaCharacter> _characters = [];
  List<DramaEpisode> _episodes = [];
  bool _isLoading = true;
  bool _isCreating = false;
  bool _isNewMode = true;

  // 进度对话框计时器
  Timer? _progressTimer;
  final Stopwatch _progressStopwatch = Stopwatch();

  // 新建模式 - 步骤导航（5步流程，对标桌面版ToonFlow）
  int _currentStep = 0;
  // 分步流程中间状态
  int? _createdDramaId; // 步骤3创建drama后保存ID
  List<DramaCharacter> _extractedCharacters = []; // 步骤3提取的角色
  List<DramaEpisode> _generatedEpisodes = []; // 步骤4生成的分镜
  bool _isExtractingChars = false; // 角色提取中
  bool _isGeneratingStoryboard = false; // 分镜生成中

  // 表单控制器（新建模式）
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  final _scriptTextController = TextEditingController();
  String _selectedStyle = 'anime';
  String _selectedGenre = 'romance';
  String _selectedAspectRatio = '16:9';
  String _selectedTemplate = '';  // 预设模板（TikTok爆款：非人类角色+猎奇风格）

  // 模型配置控制器
  String _textModel = 'auto';
  String _textApiKey = '';
  String _textBaseUrl = '';
  final _textApiKeyController = TextEditingController();
  final _textBaseUrlController = TextEditingController();
  String _imageModel = 'wanx';
  String _imageApiKey = '';
  String _imageBaseUrl = '';
  final _imageApiKeyController = TextEditingController();
  final _imageBaseUrlController = TextEditingController();
  String _videoModel = 'happyhorse';
  String _videoApiKey = '';
  String _videoBaseUrl = '';
  final _videoApiKeyController = TextEditingController();
  final _videoBaseUrlController = TextEditingController();

  static const _styles = [
    {'value': 'anime', 'label': '动漫'},
    {'value': 'realistic', 'label': '写实'},
    {'value': '3d', 'label': '3D'},
    {'value': 'watercolor', 'label': '水彩'},
    {'value': 'cartoon', 'label': '卡通'},
    {'value': 'comic', 'label': '漫画'},
  ];

  static const _genres = [
    {'value': 'romance', 'label': '爱情'},
    {'value': 'sci-fi', 'label': '科幻'},
    {'value': 'comedy', 'label': '喜剧'},
    {'value': 'thriller', 'label': '悬疑'},
    {'value': 'horror', 'label': '恐怖'},
    {'value': 'fantasy', 'label': '奇幻'},
    {'value': 'action', 'label': '动作'},
    {'value': 'drama', 'label': '剧情'},
  ];

  static const _aspectRatios = ['16:9', '9:16', '1:1'];

  // 预设模板（TikTok爆款风格：非人类角色 + 猎奇）
  static const _templates = [
    {'value': '', 'label': '无（自由创作）', 'icon': '🎬', 'hint': '不做特殊风格限定'},
    {'value': 'fruit', 'label': '水果拟人', 'icon': '🍅', 'hint': '番茄公主、香蕉国王、草莓战士等'},
    {'value': 'seahorse', 'label': '海洋生物', 'icon': '🌊', 'hint': '海马爸爸、章鱼老板、水母仙女等'},
    {'value': 'animal', 'label': '动物拟人', 'icon': '🐱', 'hint': '猫老板、狗警察、狐狸侦探等'},
    {'value': 'monster', 'label': '怪物克苏鲁', 'icon': '👹', 'hint': '异形、外星生物、变异生物'},
    {'value': 'absurd', 'label': '荒诞讽刺', 'icon': '🤪', 'hint': '超现实、黑色幽默、反转不断'},
    {'value': 'horror', 'label': '猎奇恐怖', 'icon': '💀', 'hint': '诡异、压抑、不安的视觉冲击'},
  ];

  // 模型可选值
  static const _textModels = [
    {'value': 'auto', 'label': '🧠 智能路由 (auto)'},
    {'value': 'qwen-max', 'label': '通义千问 Max (旗舰)'},
    {'value': 'qwen-plus', 'label': '通义千问 Plus (均衡)'},
    {'value': 'qwen-turbo', 'label': '通义千问 Turbo (快速)'},
    {'value': 'glm-4-plus', 'label': '智谱 GLM-4 Plus (旗舰)'},
    {'value': 'glm-4.7-flash', 'label': '智谱 GLM-4.7 Flash (免费)'},
    {'value': 'deepseek-v4-pro', 'label': 'DeepSeek V4 Pro (旗舰)'},
    {'value': 'deepseek-v4-flash', 'label': 'DeepSeek V4 Flash (快速)'},
    {'value': 'deepseek-chat', 'label': 'DeepSeek Chat (标准)'},
    {'value': 'doubao-pro', 'label': '豆包 Pro (火山引擎)'},
    {'value': 'agnes-2.0-flash', 'label': 'Agnes 2.0 Flash (免费)'},
    {'value': 'custom', 'label': '⚙️ 自定义 (Custom)'},
  ];

  static const _imageModels = [
    {'value': 'seedream', 'label': 'Seedream 4.0 (豆包·高质量)'},
    {'value': 'wan27-image', 'label': '万相 2.7 Image (百炼·最新)'},
    {'value': 'wanx', 'label': '万相 Wanx (百炼·经典)'},
    {'value': 'wanx-style', 'label': '万相风格化 (百炼·艺术)'},
    {'value': 'siliconflow-flux-dev', 'label': 'FLUX.1 Dev (硅基流动)'},
    {'value': 'siliconflow-sd3', 'label': 'Stable Diffusion 3 (硅基流动)'},
    {'value': 'siliconflow', 'label': '硅基流动 FLUX Schnell (免费)'},
    {'value': 'agnes-image', 'label': 'Agnes Image (免费)'},
    {'value': 'local_sd', 'label': '本地 SD (8G显存)'},
    {'value': 'custom', 'label': '⚙️ 自定义 (Custom)'},
  ];

  static const _videoModels = [
    {'value': 'seedance', 'label': 'Seedance 1.0 Pro (豆包·高质量)'},
    {'value': 'wan27-i2v', 'label': '万相 2.7 图生视频 (百炼·最新)'},
    {'value': 'wan21-i2v', 'label': '万相 2.1 图生视频 (百炼·经典)'},
    {'value': 'wanx-s2v', 'label': '万相 S2V 口型同步 (百炼)'},
    {'value': 'happyhorse', 'label': 'HappyHorse 1.1 (百炼·快速)'},
    {'value': 'cogvideox', 'label': 'CogVideoX (智谱)'},
    {'value': 'feiying', 'label': '飞影数字人 (音频驱动)'},
    {'value': 'agnes-video', 'label': 'Agnes Video (免费)'},
    {'value': 'custom', 'label': '⚙️ 自定义 (Custom)'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _progressStopwatch.stop();
    _tabController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _scriptTextController.dispose();
    _textApiKeyController.dispose();
    _textBaseUrlController.dispose();
    _imageApiKeyController.dispose();
    _imageBaseUrlController.dispose();
    _videoApiKeyController.dispose();
    _videoBaseUrlController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      if (widget.dramaId != null) {
        final drama = await StorageUtil.getDrama(widget.dramaId!);
        if (drama != null) {
          _drama = drama;
          _isNewMode = false;
          _titleController.text = drama.title;

          // 加载角色
          _characters = await StorageUtil.getCharactersByDrama(drama.id!);

          // 加载剧集
          _episodes = await StorageUtil.getEpisodesByDrama(drama.id!);
          for (var i = 0; i < _episodes.length; i++) {
            final episode = await StorageUtil.getEpisodeWithShots(_episodes[i].id!);
            if (episode != null) {
              _episodes[i] = episode;
            }
          }
        }
      }

      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载失败：$e')),
        );
      }
    }
  }

  /// 一键创建短剧（从完整剧本）
  Future<void> _createDramaFromFullScript() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final scriptText = _scriptTextController.text.trim();

    if (scriptText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入剧本/小说内容')),
      );
      setState(() => _currentStep = 0);
      return;
    }

    setState(() => _isCreating = true);

    // 构建模型配置JSON
    final modelConfig = DramaModelConfig(
      textModel: _textModel,
      textApiKey: _textApiKey,
      textBaseUrl: _textBaseUrl,
      imageModel: _imageModel,
      imageApiKey: _imageApiKey,
      imageBaseUrl: _imageBaseUrl,
      videoModel: _videoModel,
      videoApiKey: _videoApiKey,
      videoBaseUrl: _videoBaseUrl,
    );
    final modelConfigJson = jsonEncode(modelConfig.toJson());

    try {
      // TaskLog: 记录角色提取开始
      final charExtractTaskId = 'drama_char_extract_${DateTime.now().millisecondsSinceEpoch}';
      final charExtractStart = DateTime.now();
      try {
        await StorageUtil.saveTaskLog(TaskLog(
          taskId: charExtractTaskId,
          taskType: 'text',
          modelName: _textModel,
          provider: 'drama_create',
          status: 'running',
          dramaTitle: title,
        ));
      } catch (_) {}

      final dramaService = ref.read(dramaServiceProvider);
      final drama = await dramaService.createDramaFromFullScript(
        title: title,
        scriptText: scriptText,
        style: _selectedStyle,
        genre: _selectedGenre,
        aspectRatio: _selectedAspectRatio,
        modelConfig: modelConfigJson,
        template: _selectedTemplate,
        onProgress: (stage, progress) {
          if (mounted) {
            _showProgressDialog(stage, progress);
          }
        },
      );

      // TaskLog: 角色提取+分镜生成完成
      final charExtractDuration = DateTime.now().difference(charExtractStart).inSeconds;
      try {
        final log = await StorageUtil.getTaskLogByTaskId(charExtractTaskId);
        if (log != null) {
          await StorageUtil.updateTaskLog(log.copyWith(
            status: 'completed',
            durationSeconds: charExtractDuration,
            completedAt: DateTime.now(),
          ));
        }
      } catch (_) {}

      // TaskLog: 记录分镜生成完成
      final storyboardTaskId = 'drama_storyboard_${drama.id}_${DateTime.now().millisecondsSinceEpoch}';
      try {
        await StorageUtil.saveTaskLog(TaskLog(
          taskId: storyboardTaskId,
          taskType: 'text',
          modelName: _textModel,
          provider: 'drama_create',
          status: 'completed',
          dramaTitle: title,
          durationSeconds: charExtractDuration,
          completedAt: DateTime.now(),
        ));
      } catch (_) {}

      _dismissProgressDialog();

      if (mounted) {
        setState(() {
          _drama = drama;
          _isNewMode = false;
          _isCreating = false;
        });
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('短剧创建成功！')),
        );
        // 切换到分镜Tab
        _tabController.animateTo(2);
      }
    } catch (e) {
      // TaskLog: 创建失败
      try {
        final failTaskId = 'drama_create_fail_${DateTime.now().millisecondsSinceEpoch}';
        await StorageUtil.saveTaskLog(TaskLog(
          taskId: failTaskId,
          taskType: 'text',
          modelName: _textModel,
          provider: 'drama_create',
          status: 'failed',
          dramaTitle: title,
          errorReason: e.toString().length > 200 ? e.toString().substring(0, 200) : e.toString(),
        ));
      } catch (_) {}

      _dismissProgressDialog();
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$e')),
        );
      }
    }
  }

  void _showProgressDialog(String stage, int progress) {
    // 启动计时（首次调用时启动）
    if (!_progressStopwatch.isRunning) {
      _progressStopwatch.reset();
      _progressStopwatch.start();
      // 每秒刷新弹窗显示经过时间
      _progressTimer?.cancel();
      _progressTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted && _progressStopwatch.isRunning) {
          // 通过setState触发重建来更新经过时间显示
          final elapsedSec = _progressStopwatch.elapsed.inSeconds;
          // 关闭旧弹窗再显示新的（带更新后的时间）
          Navigator.of(context, rootNavigator: true).pop();
          _showProgressDialogInternal(stage, progress, elapsedSec);
        }
      });
    }

    final elapsedSec = _progressStopwatch.elapsed.inSeconds;
    // 先关闭旧弹窗再显示新的，避免弹窗叠加
    Navigator.of(context, rootNavigator: true).pop();
    _showProgressDialogInternal(stage, progress, elapsedSec);
  }

  void _showProgressDialogInternal(String stage, int progress, int elapsedSec) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('AI创作中'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            LinearProgressIndicator(value: progress / 100),
            const SizedBox(height: 16),
            Text('$stage (已等待 ${elapsedSec}秒)'),
            const SizedBox(height: 8),
            Text('$progress%'),
          ],
        ),
      ),
    );
  }

  void _dismissProgressDialog() {
    _progressTimer?.cancel();
    _progressTimer = null;
    _progressStopwatch.stop();
    _progressStopwatch.reset();
    Navigator.of(context, rootNavigator: true).pop();
  }

  void _showCharacterDialog({DramaCharacter? character}) {
    final nameController = TextEditingController(text: character?.name ?? '');
    final descController = TextEditingController(text: character?.description ?? '');
    final personalityController = TextEditingController(text: character?.personality ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              character == null ? '新增角色' : '编辑角色',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: '角色名称',
                hintText: '请输入角色名称',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descController,
              decoration: const InputDecoration(
                labelText: '外貌描述',
                hintText: '描述角色的外貌特征，用于AI出图',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: personalityController,
              decoration: const InputDecoration(
                labelText: '性格特征',
                hintText: '描述角色的性格',
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      if (nameController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('请输入角色名称')),
                        );
                        return;
                      }

                      try {
                        if (character == null) {
                          final newChar = DramaCharacter(
                            dramaId: _drama!.id!,
                            name: nameController.text.trim(),
                            description: descController.text.trim(),
                            personality: personalityController.text.trim(),
                          );
                          await StorageUtil.insertCharacter(newChar);
                        } else {
                          await StorageUtil.updateCharacter(
                            character.copyWith(
                              name: nameController.text.trim(),
                              description: descController.text.trim(),
                              personality: personalityController.text.trim(),
                            ),
                          );
                        }

                        if (mounted) {
                          Navigator.pop(context);
                          _loadData();
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('保存成功')),
                          );
                        }
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('保存失败：$e')),
                          );
                        }
                      }
                    },
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCharacter(DramaCharacter character) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除角色'),
        content: Text('确定要删除"${character.name}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed == true && character.id != null) {
      try {
        await StorageUtil.deleteCharacter(character.id!);
        _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNewMode ? '新建短剧' : (_drama?.title ?? '短剧编辑')),
        bottom: _isNewMode ? null : TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: '剧本'),
            Tab(text: '角色'),
            Tab(text: '分镜'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _isNewMode
              ? _buildCreateWizard()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildScriptView(),
                    _buildCharacterTab(),
                    _buildStoryboardTab(),
                  ],
                ),
    );
  }

  // ==================== 新建流程 - 步骤引导 ====================

  Widget _buildCreateWizard() {
    return Column(
      children: [
        // 步骤指示条（5步对标桌面ToonFlow流程）
        _buildStepIndicator(),
        // 步骤内容
        Expanded(
          child: IndexedStack(
            index: _currentStep,
            children: [
              _buildStep1_TextImport(),       // 文本导入
              _buildStep2_BasicSetup(),       // 基础设定
              _buildStep3_CharacterGen(),     // 角色生成
              _buildStep4_StoryboardGen(),    // 分镜生成
              _buildStep5_ConfirmAndCreate(), // 确认创作
            ],
          ),
        ),
        // 底部导航按钮
        _buildStepNavigation(),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      child: Row(
        children: [
          _buildStepDot(0, '导入'),
          _buildStepLine(0),
          _buildStepDot(1, '设定'),
          _buildStepLine(1),
          _buildStepDot(2, '角色'),
          _buildStepLine(2),
          _buildStepDot(3, '分镜'),
          _buildStepLine(3),
          _buildStepDot(4, '创作'),
        ],
      ),
    );
  }

  Widget _buildStepDot(int step, String label) {
    final isActive = _currentStep == step;
    final isCompleted = _currentStep > step;
    final color = isActive
        ? const Color(0xFFFF6B9D)
        : isCompleted
            ? AppTheme.primaryColor
            : AppTheme.textHint;

    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? AppTheme.primaryColor : Colors.transparent,
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: isCompleted
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: isActive ? const Color(0xFFFF6B9D) : AppTheme.textHint,
              fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepLine(int step) {
    final isCompleted = _currentStep > step;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        color: isCompleted ? AppTheme.primaryColor : AppTheme.textHint.withOpacity(0.3),
      ),
    );
  }

  Widget _buildStepNavigation() {
    // 步骤3/4中正在AI生成时禁用导航
    final isBusy = _isExtractingChars || _isGeneratingStoryboard || _isCreating;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF2A2A4A))),
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (_currentStep > 0)
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isBusy ? null : () => setState(() => _currentStep--),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('上一步'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: _currentStep > 0 ? 1 : 1,
              child: _currentStep < 4
                  ? ElevatedButton.icon(
                      onPressed: isBusy ? null : () => _goToNextStep(),
                      icon: const Icon(Icons.arrow_forward),
                      label: Text(_getNextStepLabel()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B9D),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: isBusy ? null : _finalizeAndCreate,
                      icon: _isCreating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.auto_awesome),
                      label: Text(_isCreating ? '创作中...' : '开始创作'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B9D),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _getNextStepLabel() {
    switch (_currentStep) {
      case 0: return '下一步';
      case 1: return '提取角色';
      case 2: return '生成分镜';
      case 3: return '下一步';
      default: return '下一步';
    }
  }

  Future<void> _goToNextStep() async {
    // 步骤0→1：验证标题和文本
    if (_currentStep == 0) {
      if (_titleController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入短剧标题')),
        );
        return;
      }
      if (_scriptTextController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请输入剧本/小说内容')),
        );
        return;
      }
      setState(() => _currentStep = 1);
      return;
    }
    // 步骤1→2：进入角色生成页，用户点击后自动提取
    if (_currentStep == 1) {
      setState(() => _currentStep = 2);
      return;
    }
    // 步骤2→3：先提取角色，再生成，然后进入分镜
    if (_currentStep == 2) {
      await _extractAndGoToStoryboard();
      return;
    }
    // 步骤3→4：先生成分镜，再进入确认页
    if (_currentStep == 3) {
      await _generateStoryboardAndFinish();
      return;
    }
  }

  /// 步骤2：提取角色并跳转到分镜步骤
  Future<void> _extractAndGoToStoryboard() async {
    if (_createdDramaId == null) {
      // 先创建Drama记录
      final dramaService = ref.read(dramaServiceProvider);
      final modelConfig = DramaModelConfig(
        textModel: _textModel,
        textApiKey: _textApiKey,
        textBaseUrl: _textBaseUrl,
        imageModel: _imageModel,
        imageApiKey: _imageApiKey,
        imageBaseUrl: _imageBaseUrl,
        videoModel: _videoModel,
        videoApiKey: _videoApiKey,
        videoBaseUrl: _videoBaseUrl,
      );
      final drama = Drama(
        title: _titleController.text.trim(),
        description: _scriptTextController.text.trim().length > 200
            ? '${_scriptTextController.text.trim().substring(0, 200)}...'
            : _scriptTextController.text.trim(),
        style: _selectedStyle,
        genre: _selectedGenre,
        aspectRatio: _selectedAspectRatio,
        modelConfig: jsonEncode(modelConfig.toJson()),
        sourceText: _scriptTextController.text.trim(),
        template: _selectedTemplate,
      );
      final dramaId = await StorageUtil.insertDrama(drama);
      _createdDramaId = dramaId;
    }

    setState(() => _isExtractingChars = true);

    try {
      final dramaService = ref.read(dramaServiceProvider);
      final characters = await dramaService.extractCharacters(
        scriptText: _scriptTextController.text.trim(),
        dramaId: _createdDramaId!,
        template: _selectedTemplate,
        onProgress: (stage, progress) {
          if (mounted) _showProgressDialog('提取角色：$stage', progress);
        },
      );

      // 保存角色到DB
      for (final c in characters) {
        await StorageUtil.insertCharacter(c.copyWith(dramaId: _createdDramaId!));
      }
      setState(() {
        _extractedCharacters = characters;
        _isExtractingChars = false;
        _currentStep = 3;
      });
      _dismissProgressDialog();
    } catch (e) {
      setState(() => _isExtractingChars = false);
      _dismissProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('角色提取失败：$e')),
        );
      }
    }
  }

  /// 步骤3：生成分镜
  Future<void> _generateStoryboardAndFinish() async {
    setState(() => _isGeneratingStoryboard = true);
    try {
      final dramaService = ref.read(dramaServiceProvider);
      final result = await dramaService.generateStoryboardFromScript(
        scriptText: _scriptTextController.text.trim(),
        characters: _extractedCharacters,
        style: _selectedStyle,
        genre: _selectedGenre,
        template: _selectedTemplate,
        onProgress: (stage, progress) {
          if (mounted) _showProgressDialog('生成分镜：$stage', progress);
        },
      );
      // 保存到DB
      await StorageUtil.insertEpisodesWithShots(result.episodes);
      setState(() {
        _generatedEpisodes = result.episodes;
        _isGeneratingStoryboard = false;
        _currentStep = 4;
      });
      _dismissProgressDialog();
    } catch (e) {
      setState(() => _isGeneratingStoryboard = false);
      _dismissProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分镜生成失败：$e')),
        );
      }
    }
  }

  /// 步骤4：最终确认并刷新数据
  Future<void> _finalizeAndCreate() async {
    setState(() => _isCreating = true);
    try {
      // 如果用户在Step5修改了模型配置，更新Drama记录
      if (_createdDramaId != null) {
        final existing = await StorageUtil.getDrama(_createdDramaId!);
        if (existing != null) {
          final modelConfig = DramaModelConfig(
            textModel: _textModel,
            textApiKey: _textApiKey,
            textBaseUrl: _textBaseUrl,
            imageModel: _imageModel,
            imageApiKey: _imageApiKey,
            imageBaseUrl: _imageBaseUrl,
            videoModel: _videoModel,
            videoApiKey: _videoApiKey,
            videoBaseUrl: _videoBaseUrl,
          );
          await StorageUtil.updateDrama(existing.copyWith(
            modelConfig: jsonEncode(modelConfig.toJson()),
          ));
        }
      }

      // 直接用_createdDramaId加载数据（_loadData依赖widget.dramaId，新建模式下为null）
      final dramaId = _createdDramaId;
      if (dramaId != null) {
        final drama = await StorageUtil.getDrama(dramaId);
        if (drama != null) {
          _drama = drama;
          _isNewMode = false;
          _characters = await StorageUtil.getCharactersByDrama(dramaId);
          _episodes = await StorageUtil.getEpisodesByDrama(dramaId);
          for (var i = 0; i < _episodes.length; i++) {
            final episode = await StorageUtil.getEpisodeWithShots(_episodes[i].id!);
            if (episode != null) {
              _episodes[i] = episode;
            }
          }
        }
      }

      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('短剧创建成功！')),
        );
        _tabController.animateTo(2); // 跳转到分镜Tab
      }
    } catch (e) {
      setState(() => _isCreating = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('创建失败：$e')),
        );
      }
    }
  }

  // Step 1: 文本导入（对标桌面版ToonFlow Step1）
  Widget _buildStep1_TextImport() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤标题
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.article_outlined, color: const Color(0xFFFF6B9D), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '文本导入',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '粘贴你的完整剧本、小说章节或故事文本，AI将自动分析内容',
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '短剧标题',
              hintText: '给短剧起个名字',
              prefixIcon: Icon(Icons.title, size: 20),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return '请输入短剧标题';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _scriptTextController,
            decoration: const InputDecoration(
              labelText: '剧本/小说内容',
              hintText: '在此粘贴完整的剧本文本...\n\n支持小说章节、故事梗概、完整剧本等多种文本格式',
              alignLabelWithHint: true,
              prefixIcon: Icon(Icons.edit_note, size: 20),
            ),
            maxLines: 18,
            minLines: 10,
          ),
          const SizedBox(height: 8),
          Builder(
            builder: (context) {
              final charCount = _scriptTextController.text.length;
              return Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: AppTheme.textHint.withOpacity(0.7)),
                  const SizedBox(width: 4),
                  Text(
                    charCount > 0
                        ? '已输入 $charCount 字 · AI将根据篇幅自动决定集数'
                        : 'AI将自动提取角色、生成分镜，并根据篇幅决定集数',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint.withOpacity(0.7)),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // Step 2: 基础设定（对标桌面版ToonFlow风格/类型设定）
  Widget _buildStep2_BasicSetup() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤标题
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.palette_outlined, color: const Color(0xFFFF6B9D), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '基础设定',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '选择短剧的画风、类型和画面比例',
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
          const SizedBox(height: 20),
          // ===== TikTok 爆款模板 =====
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFFF6B9D).withOpacity(0.12),
                  const Color(0xFFFFA86B).withOpacity(0.12),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFFF6B9D).withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 18)),
                    const SizedBox(width: 6),
                    const Text(
                      'TikTok 爆款预设',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFFFF6B9D),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text(
                        'HOT',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '非人类主角+猎奇风格，单周播放3.6亿次的爆款公式',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textSecondary.withOpacity(0.9),
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _templates.map((t) {
                    final isSelected = _selectedTemplate == t['value'];
                    return InkWell(
                      onTap: () {
                        setState(() => _selectedTemplate = t['value']!);
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFFFF6B9D)
                              : AppTheme.darkSurface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFFFF6B9D)
                                : AppTheme.textHint.withOpacity(0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(t['icon']!, style: const TextStyle(fontSize: 16)),
                            const SizedBox(width: 6),
                            Text(
                              t['label']!,
                              style: TextStyle(
                                color: isSelected ? Colors.white : AppTheme.textSecondary,
                                fontSize: 13,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                if (_selectedTemplate.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.lightbulb_outline,
                            size: 14, color: Color(0xFFFFA86B)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            _templates.firstWhere(
                                (t) => t['value'] == _selectedTemplate)['hint']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary.withOpacity(0.95),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            '画风选择',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _styles.map((style) {
              final isSelected = _selectedStyle == style['value'];
              return ChoiceChip(
                label: Text(style['label']!),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedStyle = style['value']!);
                },
                selectedColor: AppTheme.primaryColor,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            '类型选择',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _genres.map((genre) {
              final isSelected = _selectedGenre == genre['value'];
              return ChoiceChip(
                label: Text(genre['label']!),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedGenre = genre['value']!);
                },
                selectedColor: const Color(0xFFFF6B9D),
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          const Text(
            '画面比例',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _aspectRatios.map((ratio) {
              final isSelected = _selectedAspectRatio == ratio;
              return ChoiceChip(
                label: Text(ratio),
                selected: isSelected,
                onSelected: (_) {
                  setState(() => _selectedAspectRatio = ratio);
                },
                selectedColor: AppTheme.primaryColor,
                labelStyle: TextStyle(
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // Step 3: 角色生成（对标桌面版ToonFlow Step2 角色生成）
  Widget _buildStep3_CharacterGen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤标题
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.people_alt_outlined, color: const Color(0xFFFF6B9D), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '角色生成',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI将从你的文本中自动提取角色信息，生成后可编辑调整',
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
          const SizedBox(height: 20),
          // 角色列表
          if (_extractedCharacters.isEmpty && !_isExtractingChars) ...[
            // 尚未提取，显示引导
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.textHint.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.person_search, size: 48, color: AppTheme.textHint.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text(
                    '点击底部「提取角色」按钮',
                    style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI将自动分析剧本文本，提取所有角色及其特征',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
          ] else if (_isExtractingChars) ...[
            // 正在提取中
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFFFF6B9D)),
                  const SizedBox(height: 16),
                  const Text('AI正在分析文本，提取角色...', style: TextStyle(fontSize: 14)),
                ],
              ),
            ),
          ] else ...[
            // 已提取角色，显示列表
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 18, color: Color(0xFF7C4DFF)),
                  const SizedBox(width: 8),
                  Text(
                    '已提取 ${_extractedCharacters.length} 个角色 · 点击可编辑',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF7C4DFF), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._extractedCharacters.asMap().entries.map((entry) {
              final index = entry.key;
              final character = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFFFF6B9D).withOpacity(0.15),
                    child: Text(
                      character.name.isNotEmpty ? character.name[0] : '?',
                      style: const TextStyle(
                        color: Color(0xFFFF6B9D),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  title: Text(
                    character.name,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (character.description.isNotEmpty)
                        Text(
                          character.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (character.personality != null && character.personality!.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            '性格：${character.personality}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit, size: 18),
                        color: const Color(0xFFFF6B9D),
                        onPressed: () => _showEditCharacterDialog(index),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 18),
                        color: AppTheme.textHint,
                        onPressed: () {
                          setState(() => _extractedCharacters.removeAt(index));
                        },
                      ),
                    ],
                  ),
                  onTap: () => _showEditCharacterDialog(index),
                ),
              );
            }),
            // 添加角色按钮
            OutlinedButton.icon(
              onPressed: () => _showAddCharacterDialog(),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加角色'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFFF6B9D),
                side: const BorderSide(color: Color(0xFFFF6B9D), width: 0.5),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 编辑角色对话框
  void _showEditCharacterDialog(int index) {
    final character = _extractedCharacters[index];
    final nameController = TextEditingController(text: character.name);
    final descController = TextEditingController(text: character.description);
    final personalityController = TextEditingController(text: character.personality ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E3A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('编辑角色', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '角色名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(labelText: '外貌描述'),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: personalityController,
                decoration: const InputDecoration(labelText: '性格特征'),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _extractedCharacters[index] = character.copyWith(
                        name: nameController.text.trim(),
                        description: descController.text.trim(),
                        personality: personalityController.text.trim(),
                      );
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B9D),
                  ),
                  child: const Text('保存'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  /// 添加角色对话框
  void _showAddCharacterDialog() {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    final personalityController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E3A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('添加角色', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: '角色名'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descController,
                decoration: const InputDecoration(
                  labelText: '外貌描述',
                  hintText: '如：年轻女性，黑色长发，白色连衣裙',
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: personalityController,
                decoration: const InputDecoration(
                  labelText: '性格特征',
                  hintText: '如：独立、坚强、有点傲娇',
                ),
                maxLines: 2,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameController.text.trim().isEmpty) {
                      Navigator.pop(context);
                      return;
                    }
                    setState(() {
                      _extractedCharacters.add(DramaCharacter(
                        name: nameController.text.trim(),
                        description: descController.text.trim(),
                        personality: personalityController.text.trim(),
                        dramaId: _createdDramaId ?? 0,
                      ));
                    });
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B9D),
                  ),
                  child: const Text('添加'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // Step 4: 分镜生成（对标桌面版ToonFlow Step3-4 剧本+分镜）
  Widget _buildStep4_StoryboardGen() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤标题
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.story, color: const Color(0xFFFF6B9D), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '分镜生成',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'AI将根据角色和文本生成分集分镜脚本，包含画面描述、台词和运镜',
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
          const SizedBox(height: 20),
          if (_generatedEpisodes.isEmpty && !_isGeneratingStoryboard) ...[
            // 尚未生成，显示引导
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.textHint.withOpacity(0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.video_library_outlined, size: 48, color: AppTheme.textHint.withOpacity(0.5)),
                  const SizedBox(height: 12),
                  Text(
                    '点击底部「生成分镜」按钮',
                    style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'AI将根据 ${_extractedCharacters.length} 个角色和剧本文本生成分镜',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
          ] else if (_isGeneratingStoryboard) ...[
            // 正在生成中
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const CircularProgressIndicator(color: Color(0xFFFF6B9D)),
                  const SizedBox(height: 16),
                  const Text('AI正在生成分镜脚本...', style: TextStyle(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text(
                    '根据文本长度，这可能需要1-3分钟',
                    style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
          ] else ...[
            // 已生成分镜，显示预览
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF7C4DFF).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle, size: 18, color: Color(0xFF7C4DFF)),
                  const SizedBox(width: 8),
                  Text(
                    '已生成 ${_generatedEpisodes.length} 集 · ${_generatedEpisodes.fold(0, (sum, ep) => sum + ep.shots.length)} 个镜头',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF7C4DFF), fontWeight: FontWeight.w500),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ..._generatedEpisodes.map((episode) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF6B9D).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${episode.episodeNumber}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFFF6B9D),
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  title: Text(
                    episode.title,
                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${episode.shots.length}个镜头${episode.summary.isNotEmpty ? ' · ${episode.summary}' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                  ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: episode.shots.take(3).map((shot) {
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppTheme.darkSurface,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF6B9D).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Center(
                                    child: Text(
                                      '${shot.shotNumber}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFFF6B9D),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        shot.visualDescription,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      if (shot.dialogue.isNotEmpty)
                                        Padding(
                                          padding: const EdgeInsets.only(top: 2),
                                          child: Text(
                                            '💬 ${shot.dialogue}',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        if (episode.shots.length > 3)
                          Center(
                            child: Text(
                              '...还有 ${episode.shots.length - 3} 个镜头',
                              style: TextStyle(fontSize: 11, color: AppTheme.textHint),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // Step 5: 确认创作（对标桌面版ToonFlow Step5-6 出图+视频合成，此处配置模型并确认）
  Widget _buildStep5_ConfirmAndCreate() {
    final scriptLength = _scriptTextController.text.trim().length;
    final charCountText = scriptLength > 0 ? '$scriptLength 字' : '未输入';
    final totalShots = _generatedEpisodes.fold(0, (sum, ep) => sum + ep.shots.length);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤标题
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, color: const Color(0xFFFF6B9D), size: 22),
                const SizedBox(width: 8),
                const Text(
                  '确认创作',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '配置模型后开始创作，AI将自动完成出图和视频生成',
            style: TextStyle(fontSize: 13, color: AppTheme.textHint),
          ),
          const SizedBox(height: 16),
          // 创作摘要
          _buildSummaryCard('创作摘要', [
            _summaryRow('标题', _titleController.text.trim()),
            _summaryRow('画风', _getStyleLabel(_selectedStyle)),
            _summaryRow('类型', _getGenreLabel(_selectedGenre)),
            _summaryRow('画面比例', _selectedAspectRatio),
            _summaryRow('剧本长度', charCountText),
            _summaryRow('角色数', '${_extractedCharacters.length} 个'),
            _summaryRow('分镜数', '${_generatedEpisodes.length}集 · $totalShots 镜头'),
          ]),
          const SizedBox(height: 12),
          // 模型配置（可折叠）
          Text(
            'AI模型配置（可选，使用默认也能工作）',
            style: TextStyle(fontSize: 13, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 8),
          // 文本模型
          _buildModelGroup(
            title: '文本模型',
            icon: Icons.text_fields,
            initiallyExpanded: false,
            selectedModel: _textModel,
            models: _textModels,
            onModelChanged: (v) {
              setState(() {
                _textModel = v;
                final presetUrl = _getPresetBaseUrl(v);
                if (presetUrl.isNotEmpty && _textBaseUrl.isEmpty) {
                  _textBaseUrl = presetUrl;
                  _textBaseUrlController.text = presetUrl;
                }
                final presetKey = _getPresetApiKey(v);
                if (presetKey.isNotEmpty && _textApiKey.isEmpty) {
                  _textApiKey = presetKey;
                  _textApiKeyController.text = presetKey;
                }
              });
            },
            apiKey: _textApiKey,
            onApiKeyChanged: (v) => setState(() {
              _textApiKey = v;
              _textApiKeyController.text = v;
            }),
            baseUrl: _textBaseUrl,
            onBaseUrlChanged: (v) => setState(() {
              _textBaseUrl = v;
              _textBaseUrlController.text = v;
            }),
            apiKeyController: _textApiKeyController,
            baseUrlController: _textBaseUrlController,
          ),
          const SizedBox(height: 8),
          // 图像模型
          _buildModelGroup(
            title: '图像模型',
            icon: Icons.image,
            initiallyExpanded: false,
            selectedModel: _imageModel,
            models: _imageModels,
            onModelChanged: (v) {
              setState(() {
                _imageModel = v;
                final presetUrl = _getPresetBaseUrl(v);
                if (presetUrl.isNotEmpty && _imageBaseUrl.isEmpty) {
                  _imageBaseUrl = presetUrl;
                  _imageBaseUrlController.text = presetUrl;
                }
                final presetKey = _getPresetApiKey(v);
                if (presetKey.isNotEmpty && _imageApiKey.isEmpty) {
                  _imageApiKey = presetKey;
                  _imageApiKeyController.text = presetKey;
                }
              });
            },
            apiKey: _imageApiKey,
            onApiKeyChanged: (v) => setState(() {
              _imageApiKey = v;
              _imageApiKeyController.text = v;
            }),
            baseUrl: _imageBaseUrl,
            onBaseUrlChanged: (v) => setState(() {
              _imageBaseUrl = v;
              _imageBaseUrlController.text = v;
            }),
            apiKeyController: _imageApiKeyController,
            baseUrlController: _imageBaseUrlController,
          ),
          const SizedBox(height: 8),
          // 视频模型
          _buildModelGroup(
            title: '视频模型',
            icon: Icons.videocam,
            initiallyExpanded: false,
            selectedModel: _videoModel,
            models: _videoModels,
            onModelChanged: (v) {
              setState(() {
                _videoModel = v;
                final presetUrl = _getPresetBaseUrl(v);
                if (presetUrl.isNotEmpty && _videoBaseUrl.isEmpty) {
                  _videoBaseUrl = presetUrl;
                  _videoBaseUrlController.text = presetUrl;
                }
                final presetKey = _getPresetApiKey(v);
                if (presetKey.isNotEmpty && _videoApiKey.isEmpty) {
                  _videoApiKey = presetKey;
                  _videoApiKeyController.text = presetKey;
                }
              });
            },
            apiKey: _videoApiKey,
            onApiKeyChanged: (v) => setState(() {
              _videoApiKey = v;
              _videoApiKeyController.text = v;
            }),
            baseUrl: _videoBaseUrl,
            onBaseUrlChanged: (v) => setState(() {
              _videoBaseUrl = v;
              _videoBaseUrlController.text = v;
            }),
            apiKeyController: _videoApiKeyController,
            baseUrlController: _videoBaseUrlController,
          ),
          const SizedBox(height: 24),
          // 创作流程说明
          _buildSummaryCard('后续自动流程', [
            _summaryRow('1.', '根据分镜描述批量生成画面'),
            _summaryRow('2.', '为每个镜头生成配音和字幕'),
            _summaryRow('3.', '合成视频并可导出分享'),
          ]),
          const SizedBox(height: 20),
          Center(
            child: Text(
              '点击上方「开始创作」完成所有步骤',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ),
        ],
      ),
    );
  }

  /// 获取预设模型的默认Base URL
  static String _getPresetBaseUrl(String model) {
    switch (model) {
      case 'agnes-2.0-flash':
      case 'agnes-image':
      case 'agnes-video':
        return 'https://apihub.agnes-ai.cn/v1';
      case 'qwen-max':
      case 'qwen-plus':
      case 'qwen-turbo':
        return 'https://dashscope.aliyuncs.com/compatible-mode/v1';
      case 'glm-4-plus':
      case 'glm-4.7-flash':
      case 'cogvideox':
        return 'https://open.bigmodel.cn/api/paas/v4';
      case 'deepseek-v4-flash':
      case 'deepseek-v4-pro':
      case 'deepseek-chat':
        return 'https://api.deepseek.com';
      case 'doubao-pro':
      case 'seedream':
      case 'seedance':
        return 'https://ark.cn-beijing.volces.com/api/v3';
      case 'feiying':
        return 'https://hfw-api.hifly.cc';
      case 'wanx':
      case 'wan27-image':
      case 'wanx-style':
      case 'wanx-s2v':
      case 'wan27-i2v':
      case 'wan21-i2v':
        return 'https://dashscope.aliyuncs.com/api/v1';
      case 'siliconflow':
      case 'siliconflow-sd3':
      case 'siliconflow-flux-dev':
        return 'https://api.siliconflow.cn/v1';
      default:
        return '';
    }
  }

  /// 获取预设模型的默认API Key（Agnes AI全模型预填，其他需用户自行输入）
  static String _getPresetApiKey(String model) {
    switch (model) {
      case 'agnes-2.0-flash':
      case 'agnes-image':
      case 'agnes-video':
        return 'sk-7910JE6f3qpCtYchwYPgzPdpFC2X99chkCNExCvTmvLObACo';
      default:
        return '';
    }
  }

  Widget _buildModelGroup({
    required String title,
    required IconData icon,
    required bool initiallyExpanded,
    required String selectedModel,
    required List<Map<String, String>> models,
    required ValueChanged<String> onModelChanged,
    required String apiKey,
    required ValueChanged<String> onApiKeyChanged,
    required String baseUrl,
    required ValueChanged<String> onBaseUrlChanged,
    TextEditingController? apiKeyController,
    TextEditingController? baseUrlController,
  }) {
    final hasPreset = _getPresetBaseUrl(selectedModel).isNotEmpty;
    final showFields = selectedModel == 'custom' || hasPreset;

    return ExpansionTile(
      initiallyExpanded: initiallyExpanded,
      leading: Icon(icon, color: const Color(0xFFFF6B9D), size: 20),
      title: Text(
        title,
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        models.firstWhere((m) => m['value'] == selectedModel,
            orElse: () => {'label': selectedModel})['label']!,
        style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 模型选择下拉
              DropdownButtonFormField<String>(
                value: selectedModel,
                decoration: const InputDecoration(
                  labelText: '选择模型',
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                items: models.map((m) {
                  return DropdownMenuItem(
                    value: m['value'],
                    child: Text(m['label']!, style: const TextStyle(fontSize: 14)),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) onModelChanged(value);
                },
              ),
              // 显示API Key和Base URL
              if (showFields) ...[
                const SizedBox(height: 12),
                TextField(
                  obscureText: true,
                  controller: apiKeyController,
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: hasPreset && _getPresetApiKey(selectedModel).isNotEmpty
                        ? '已预填（可修改）'
                        : '输入API Key',
                  ),
                  onChanged: onApiKeyChanged,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: baseUrlController,
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: hasPreset ? _getPresetBaseUrl(selectedModel) : '输入API Base URL',
                  ),
                  onChanged: onBaseUrlChanged,
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, List<Widget> rows) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFFFF6B9D),
              ),
            ),
            const SizedBox(height: 12),
            ...rows,
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: AppTheme.textHint),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  String _getStyleLabel(String value) {
    return _styles.firstWhere((s) => s['value'] == value, orElse: () => {'label': value})['label']!;
  }

  String _getGenreLabel(String value) {
    return _genres.firstWhere((g) => g['value'] == value, orElse: () => {'label': value})['label']!;
  }

  String _getModelLabel(String value, List<Map<String, String>> models) {
    return models.firstWhere((m) => m['value'] == value, orElse: () => {'label': value})['label']!;
  }

  // ==================== 编辑模式 - 已有项目 ====================

  Widget _buildScriptView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _drama?.title ?? '',
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit),
                        onPressed: () => _showEditTitleDialog(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      Chip(
                        label: Text(_drama?.styleDisplayName ?? ''),
                        backgroundColor: AppTheme.primaryColor.withOpacity(0.2),
                      ),
                      Chip(
                        label: Text(_drama?.genreDisplayName ?? ''),
                        backgroundColor: const Color(0xFFFF6B9D).withOpacity(0.2),
                      ),
                      Chip(
                        label: Text(_drama?.aspectRatio ?? ''),
                        backgroundColor: AppTheme.darkSurface,
                      ),
                      if (_drama?.template.isNotEmpty == true)
                        Chip(
                          avatar: Text(
                            _templates.firstWhere(
                              (t) => t['value'] == _drama?.template,
                              orElse: () => {'icon': '🎬'},
                            )['icon']!,
                            style: const TextStyle(fontSize: 14),
                          ),
                          label: Text(
                            _templates.firstWhere(
                              (t) => t['value'] == _drama?.template,
                              orElse: () => {'label': _drama?.template ?? ''},
                            )['label']!,
                          ),
                          backgroundColor: const Color(0xFFFF6B9D).withOpacity(0.2),
                        ),
                    ],
                  ),
                  if (_drama?.description.isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '故事梗概',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textHint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _drama!.description,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                  // 原始剧本/小说文本
                  if (_drama?.sourceText.isNotEmpty == true) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '原始剧本',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textHint,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.darkSurface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        _drama!.sourceText,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                          height: 1.5,
                        ),
                        maxLines: 20,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Text(
                        '剧本统计',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${_episodes.length}集 · ${_getTotalShots()}镜头',
                        style: const TextStyle(
                          fontSize: 14,
                          color: AppTheme.textHint,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatCard('角色', '${_characters.length}', Icons.person),
                      const SizedBox(width: 12),
                      _buildStatCard('剧集', '${_episodes.length}', Icons.movie),
                      const SizedBox(width: 12),
                      _buildStatCard('镜头', '${_getTotalShots()}', Icons.image),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: const Color(0xFFFF6B9D)),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textHint,
              ),
            ),
          ],
        ),
      ),
    );
  }

  int _getTotalShots() {
    return _episodes.fold(0, (sum, ep) => sum + ep.shots.length);
  }

  void _showEditTitleDialog() {
    final controller = TextEditingController(text: _drama?.title ?? '');

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('修改标题'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '短剧标题',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty && _drama != null) {
                try {
                  await StorageUtil.updateDrama(
                    _drama!.copyWith(title: controller.text.trim()),
                  );
                  if (mounted) {
                    Navigator.pop(context);
                    _loadData();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('修改失败：$e')),
                    );
                  }
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  Future<void> _reExtractCharacters() async {
    if (_drama == null || _drama!.sourceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本文本为空，无法提取角色')),
      );
      return;
    }

    setState(() => _isCreating = true);

    // TaskLog: 角色提取开始
    final charTaskId = 'drama_char_extract_${_drama!.id}_${DateTime.now().millisecondsSinceEpoch}';
    final charTaskStart = DateTime.now();
    try {
      await StorageUtil.saveTaskLog(TaskLog(
        taskId: charTaskId,
        taskType: 'text',
        modelName: _textModel,
        provider: 'drama_reextract',
        status: 'running',
        dramaTitle: _drama!.title,
      ));
    } catch (_) {}

    try {
      final dramaService = ref.read(dramaServiceProvider);
      final characters = await dramaService.extractCharacters(
        scriptText: _drama!.sourceText,
        dramaId: _drama!.id!,
        onProgress: (stage, progress) {
          if (mounted) _showProgressDialog(stage, progress);
        },
      );

      // 先删除旧角色，再保存新角色
      for (final c in _characters) {
        await StorageUtil.deleteCharacter(c.id!);
      }
      for (final character in characters) {
        await StorageUtil.insertCharacter(character.copyWith(dramaId: _drama!.id!));
      }

      // TaskLog: 角色提取完成
      final charDuration = DateTime.now().difference(charTaskStart).inSeconds;
      try {
        final log = await StorageUtil.getTaskLogByTaskId(charTaskId);
        if (log != null) {
          await StorageUtil.updateTaskLog(log.copyWith(
            status: 'completed',
            durationSeconds: charDuration,
            completedAt: DateTime.now(),
          ));
        }
      } catch (_) {}

      _dismissProgressDialog();
      if (mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('角色提取成功！共${characters.length}个角色')),
        );
      }
    } catch (e) {
      // TaskLog: 角色提取失败
      try {
        final log = await StorageUtil.getTaskLogByTaskId(charTaskId);
        if (log != null) {
          await StorageUtil.updateTaskLog(log.copyWith(
            status: 'failed',
            errorReason: e.toString().length > 200 ? e.toString().substring(0, 200) : e.toString(),
            completedAt: DateTime.now(),
          ));
        }
      } catch (_) {}

      _dismissProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('角色提取失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Widget _buildCharacterTab() {
    if (_drama == null) {
      return const Center(
        child: Text('请先生成剧本'),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _showCharacterDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('新增角色'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isCreating ? null : _reExtractCharacters,
                  icon: _isCreating
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.auto_awesome),
                  label: Text(_isCreating ? '提取中...' : 'AI提取角色'),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _characters.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 64,
                        color: AppTheme.textHint,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        '暂无角色',
                        style: TextStyle(color: AppTheme.textHint),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton.icon(
                        onPressed: _isCreating ? null : _reExtractCharacters,
                        icon: _isCreating
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.auto_awesome),
                        label: Text(_isCreating ? 'AI提取角色中...' : 'AI从剧本提取角色'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF6B9D),
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'AI将分析剧本文本自动识别角色',
                        style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _characters.length,
                  itemBuilder: (context, index) {
                    final character = _characters[index];
                    return _buildCharacterCard(character);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildCharacterCard(DramaCharacter character) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: const Color(0xFFFF6B9D).withOpacity(0.2),
                  child: Text(
                    character.name.isNotEmpty ? character.name[0] : '?',
                    style: const TextStyle(
                      color: Color(0xFFFF6B9D),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        character.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (character.personality?.isNotEmpty == true)
                        Text(
                          character.personality!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textHint,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.edit, size: 20),
                  onPressed: () => _showCharacterDialog(character: character),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, size: 20, color: Colors.red),
                  onPressed: () => _deleteCharacter(character),
                ),
              ],
            ),
            if (character.description.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                character.description,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _regenerateStoryboard() async {
    if (_drama == null || _drama!.sourceText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('剧本文本为空，无法生成分镜')),
      );
      return;
    }
    if (_characters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有角色，无法生成分镜')),
      );
      return;
    }

    setState(() => _isCreating = true);

    // TaskLog: 分镜生成开始
    final sbTaskId = 'drama_storyboard_${_drama!.id}_${DateTime.now().millisecondsSinceEpoch}';
    final sbTaskStart = DateTime.now();
    try {
      await StorageUtil.saveTaskLog(TaskLog(
        taskId: sbTaskId,
        taskType: 'text',
        modelName: _textModel,
        provider: 'drama_regenerate_sb',
        status: 'running',
        dramaTitle: _drama!.title,
      ));
    } catch (_) {}

    try {
      final dramaService = ref.read(dramaServiceProvider);
      final result = await dramaService.generateStoryboardFromScript(
        scriptText: _drama!.sourceText,
        characters: _characters,
        style: _drama!.style,
        genre: _drama!.genre,
        onProgress: (stage, progress) {
          if (mounted) _showProgressDialog(stage, progress);
        },
      );

      // 保存剧集和镜头
      await StorageUtil.insertEpisodesWithShots(result.episodes);

      // TaskLog: 分镜生成完成
      final sbDuration = DateTime.now().difference(sbTaskStart).inSeconds;
      try {
        final log = await StorageUtil.getTaskLogByTaskId(sbTaskId);
        if (log != null) {
          await StorageUtil.updateTaskLog(log.copyWith(
            status: 'completed',
            durationSeconds: sbDuration,
            completedAt: DateTime.now(),
          ));
        }
      } catch (_) {}

      _dismissProgressDialog();
      if (mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分镜生成成功！共${result.episodes.length}集')),
        );
      }
    } catch (e) {
      // TaskLog: 分镜生成失败
      try {
        final log = await StorageUtil.getTaskLogByTaskId(sbTaskId);
        if (log != null) {
          await StorageUtil.updateTaskLog(log.copyWith(
            status: 'failed',
            errorReason: e.toString().length > 200 ? e.toString().substring(0, 200) : e.toString(),
            completedAt: DateTime.now(),
          ));
        }
      } catch (_) {}

      _dismissProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分镜生成失败：$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCreating = false);
    }
  }

  Widget _buildStoryboardTab() {
    if (_drama == null || _episodes.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.movie_creation_outlined, size: 64, color: AppTheme.textHint),
            const SizedBox(height: 16),
            const Text(
              '暂无分镜',
              style: TextStyle(color: AppTheme.textHint),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _isCreating ? null : _regenerateStoryboard,
              icon: _isCreating
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(_isCreating ? 'AI生成分镜中...' : 'AI生成分镜'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI将根据剧本和角色自动生成分镜',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        // 顶部操作栏：查看任务记录
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Spacer(),
              TextButton.icon(
                onPressed: () {
                  Navigator.pushNamed(context, AppRoutes.taskLog);
                },
                icon: const Icon(Icons.history, size: 18),
                label: const Text('查看任务记录', style: TextStyle(fontSize: 13)),
                style: TextButton.styleFrom(
                  foregroundColor: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _episodes.length,
            itemBuilder: (context, index) {
              final episode = _episodes[index];
              return _buildEpisodeCard(episode);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildEpisodeCard(DramaEpisode episode) {
    // 判断是否有待处理/失败的镜头
    final hasPendingShots = episode.shots.any(
      (s) => s.status == 'pending' || s.status == 'failed',
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(
              child: Text(
                '第${episode.episodeNumber}集：${episode.title}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            if (hasPendingShots)
              TextButton.icon(
                onPressed: () {
                  Navigator.pushNamed(
                    context,
                    AppRoutes.storyboard,
                    arguments: {
                      'episodeId': episode.id,
                      'dramaId': _drama!.id,
                    },
                  );
                },
                icon: const Icon(Icons.play_circle_outline, size: 18),
                label: const Text('继续创作', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFFF6B9D),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
          ],
        ),
        subtitle: Text(
          '${episode.shots.length}个镜头',
          style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
        ),
        children: episode.shots.map((shot) {
          return ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _getShotStatusColor(shot.status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  '${shot.shotNumber}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _getShotStatusColor(shot.status),
                  ),
                ),
              ),
            ),
            title: Text(
              shot.visualDescription,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: shot.dialogue.isNotEmpty
                ? Text(
                    shot.dialogue,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
                  )
                : null,
            trailing: Chip(
              label: Text(
                shot.statusDisplayName,
                style: const TextStyle(fontSize: 10),
              ),
              backgroundColor: _getShotStatusColor(shot.status).withOpacity(0.2),
              labelStyle: TextStyle(color: _getShotStatusColor(shot.status)),
              padding: EdgeInsets.zero,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onTap: () {
              Navigator.pushNamed(
                context,
                AppRoutes.storyboard,
                arguments: {
                  'episodeId': episode.id,
                  'dramaId': _drama!.id,
                },
              );
            },
          );
        }).toList(),
      ),
    );
  }

  Color _getShotStatusColor(String status) {
    switch (status) {
      case 'pending':
        return AppTheme.textHint;
      case 'image_ready':
        return AppTheme.primaryColor;
      case 'audio_ready':
        return const Color(0xFFFF6B9D);
      case 'video_ready':
        return AppTheme.safeColor;
      case 'failed':
        return Colors.red;
      default:
        return AppTheme.textHint;
    }
  }
}
