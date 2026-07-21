import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/drama.dart';
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

  // 新建模式 - 步骤导航
  int _currentStep = 0;

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
    {'value': 'auto', 'label': '智能路由 (auto)'},
    {'value': 'qwen-plus', 'label': '通义千问 Plus'},
    {'value': 'glm-4.7-flash', 'label': '智谱 GLM-4.7 Flash'},
    {'value': 'agnes-2.0-flash', 'label': 'Agnes 2.0 Flash (免费)'},
    {'value': 'ai32-qwen-plus', 'label': '32AI · 千问 Plus'},
    {'value': 'ai32-deepseek', 'label': '32AI · DeepSeek'},
    {'value': 'ai32-doubao-pro', 'label': '32AI · 豆包 Pro'},
    {'value': 'deepseek-v4-flash', 'label': 'DeepSeek V4 Flash'},
    {'value': 'deepseek-v4-pro', 'label': 'DeepSeek V4 Pro'},
    {'value': 'doubao-pro', 'label': '豆包 Pro (火山引擎)'},
    {'value': 'custom', 'label': '自定义 (Custom)'},
  ];

  static const _imageModels = [
    {'value': 'wanx', 'label': '万相 (Wanx)'},
    {'value': 'agnes-image', 'label': 'Agnes AI Image (免费)'},
    {'value': 'ai32-image', 'label': '32AI · FLUX Kontext'},
    {'value': 'local_sd', 'label': '本地 SD'},
    {'value': 'custom', 'label': '自定义 (Custom)'},
  ];

  static const _videoModels = [
    {'value': 'happyhorse', 'label': 'HappyHorse'},
    {'value': 'agnes-video', 'label': 'Agnes AI Video (免费)'},
    {'value': 'wanx-s2v', 'label': '万相 S2V'},
    {'value': 'ai32-seedance', 'label': '32AI · 豆包 Seedance'},
    {'value': 'custom', 'label': '自定义 (Custom)'},
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
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
    // 先关闭旧弹窗再显示新的，避免弹窗叠加
    Navigator.of(context, rootNavigator: true).pop();
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
            Text(stage),
            const SizedBox(height: 8),
            Text('$progress%'),
          ],
        ),
      ),
    );
  }

  void _dismissProgressDialog() {
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
        // 步骤指示条
        _buildStepIndicator(),
        // 步骤内容
        Expanded(
          child: Form(
            key: _formKey,
            child: IndexedStack(
              index: _currentStep,
              children: [
                _buildStep1_BasicInfo(),
                _buildStep2_ModelConfig(),
                _buildStep3_ConfirmAndCreate(),
              ],
            ),
          ),
        ),
        // 底部导航按钮
        _buildStepNavigation(),
      ],
    );
  }

  Widget _buildStepIndicator() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      child: Row(
        children: [
          _buildStepDot(0, '基本信息'),
          _buildStepLine(0),
          _buildStepDot(1, '模型配置'),
          _buildStepLine(1),
          _buildStepDot(2, '确认创作'),
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
                  onPressed: _isCreating ? null : () => setState(() => _currentStep--),
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('上一步'),
                ),
              ),
            if (_currentStep > 0) const SizedBox(width: 12),
            Expanded(
              flex: _currentStep > 0 ? 1 : 1,
              child: _currentStep < 2
                  ? ElevatedButton.icon(
                      onPressed: () {
                        if (_currentStep == 0) {
                          // 验证Step1
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
                        }
                        setState(() => _currentStep++);
                      },
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('下一步'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B9D),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: _isCreating ? null : _createDramaFromFullScript,
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

  // Step 1: 基本信息 + 剧本输入
  Widget _buildStep1_BasicInfo() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _titleController,
            decoration: const InputDecoration(
              labelText: '短剧标题',
              hintText: '给短剧起个名字',
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
              hintText: '粘贴你的完整剧本、小说章节或故事文本...',
              alignLabelWithHint: true,
            ),
            maxLines: 15,
            minLines: 8,
          ),
          const SizedBox(height: 8),
          Text(
            'AI将根据文本内容自动提取角色、生成分镜，并根据篇幅决定集数',
            style: TextStyle(fontSize: 12, color: AppTheme.textHint.withOpacity(0.7)),
          ),
          const SizedBox(height: 20),
          // ===== TikTok 爆款模板：非人类角色 + 猎奇风格 =====
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
          const SizedBox(height: 20),
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

  // Step 2: 模型配置
  Widget _buildStep2_ModelConfig() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '配置AI模型（可选）',
            style: TextStyle(
              fontSize: 14,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '使用默认配置也能正常工作，如需自定义请展开对应分组',
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.textHint.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
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
            initiallyExpanded: true,
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
        return 'https://apihub.agnes-ai.com/v1';
      case 'ai32-qwen-plus':
      case 'ai32-deepseek':
        return 'https://32ai.uk/v1';
      case 'ai32-doubao-pro':
      case 'ai32-seedance':
        return 'https://32ai.uk/volc/v1';
      case 'ai32-image':
        return 'https://32ai.uk/v1';
      case 'deepseek-v4-flash':
      case 'deepseek-v4-pro':
        return 'https://api.deepseek.com';
      case 'doubao-pro':
        return 'https://ark.cn-beijing.volces.com/api/v3';
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
        return 'sk-Rcb7FziWSyPq3cZPEcrHx4Xh4MOte1DlUjuEg6w0TBVvhiub';
      case 'ai32-qwen-plus':
      case 'ai32-deepseek':
      case 'ai32-doubao-pro':
      case 'ai32-seedance':
      case 'ai32-image':
        return 'sk-sMC4yb8EUgS2G6OTlFYVwlqJJ5Pg08NpmbuoTg0Qiceh5uq6';
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

  // Step 3: 确认并生成
  Widget _buildStep3_ConfirmAndCreate() {
    final scriptLength = _scriptTextController.text.trim().length;
    final charCountText = scriptLength > 0 ? '$scriptLength 字' : '未输入';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '创作配置摘要',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 20),
          // 基本信息
          _buildSummaryCard('基本信息', [
            _summaryRow('标题', _titleController.text.trim()),
            _summaryRow('画风', _getStyleLabel(_selectedStyle)),
            _summaryRow('类型', _getGenreLabel(_selectedGenre)),
            _summaryRow('画面比例', _selectedAspectRatio),
            _summaryRow('剧本长度', charCountText),
          ]),
          const SizedBox(height: 12),
          // 模型配置
          _buildSummaryCard('模型配置', [
            _summaryRow('文本模型', _getModelLabel(_textModel, _textModels)),
            _summaryRow('图像模型', _getModelLabel(_imageModel, _imageModels)),
            _summaryRow('视频模型', _getModelLabel(_videoModel, _videoModels)),
            if (_textModel == 'custom') _summaryRow('文本API', _textBaseUrl.isNotEmpty ? '已配置' : '未配置'),
            if (_imageModel == 'custom') _summaryRow('图像API', _imageBaseUrl.isNotEmpty ? '已配置' : '未配置'),
            if (_videoModel == 'custom') _summaryRow('视频API', _videoBaseUrl.isNotEmpty ? '已配置' : '未配置'),
          ]),
          const SizedBox(height: 12),
          // 流程说明
          _buildSummaryCard('创作流程', [
            _summaryRow('1.', 'AI自动分析剧本提取角色'),
            _summaryRow('2.', 'AI根据角色生成分镜脚本'),
            _summaryRow('3.', '自动保存所有剧集和镜头'),
          ]),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCreating ? null : _createDramaFromFullScript,
              icon: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, size: 24),
              label: Text(
                _isCreating ? 'AI创作中...' : '开始创作',
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B9D),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '创作过程需要几分钟，请耐心等待',
              style: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ),
        ],
      ),
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

      _dismissProgressDialog();
      if (mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('角色提取成功！共${characters.length}个角色')),
        );
      }
    } catch (e) {
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

      _dismissProgressDialog();
      if (mounted) {
        await _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分镜生成成功！共${result.episodes.length}集')),
        );
      }
    } catch (e) {
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

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _episodes.length,
      itemBuilder: (context, index) {
        final episode = _episodes[index];
        return _buildEpisodeCard(episode);
      },
    );
  }

  Widget _buildEpisodeCard(DramaEpisode episode) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: ExpansionTile(
        title: Text(
          '第${episode.episodeNumber}集：${episode.title}',
          style: const TextStyle(fontWeight: FontWeight.w600),
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
