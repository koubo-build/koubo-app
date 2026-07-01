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

  // 表单控制器（新建模式）
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedStyle = 'anime';
  String _selectedGenre = 'romance';
  int _selectedEpisodes = 1;
  String _selectedAspectRatio = '16:9';

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

  Future<void> _generateScript() async {
    if (!_formKey.currentState!.validate()) return;

    final title = _titleController.text.trim();
    final desc = _descController.text.trim();

    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入故事梗概')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final dramaService = ref.read(dramaServiceProvider);
      final drama = await dramaService.createDramaWithScript(
        title: title,
        premise: desc,
        style: _selectedStyle,
        genre: _selectedGenre,
        aspectRatio: _selectedAspectRatio,
        episodeCount: _selectedEpisodes,
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
        _loadData();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('剧本生成成功！')),
        );
        // 切换到分镜Tab
        _tabController.animateTo(2);
      }
    } catch (e) {
      _dismissProgressDialog();
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  void _showProgressDialog(String stage, int progress) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('生成剧本'),
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
        bottom: TabBar(
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
          : TabBarView(
              controller: _tabController,
              children: [
                _buildScriptTab(),
                _buildCharacterTab(),
                _buildStoryboardTab(),
              ],
            ),
    );
  }

  Widget _buildScriptTab() {
    if (_isNewMode) {
      return _buildCreateForm();
    } else {
      return _buildScriptView();
    }
  }

  Widget _buildCreateForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
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
              controller: _descController,
              decoration: const InputDecoration(
                labelText: '故事梗概',
                hintText: '描述你的故事：比如"一个外卖小哥意外救了富家女，两人相识相恋..."',
                alignLabelWithHint: true,
              ),
              maxLines: 5,
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
              '集数',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton(
                  onPressed: _selectedEpisodes > 1
                      ? () => setState(() => _selectedEpisodes--)
                      : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$_selectedEpisodes 集',
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
                IconButton(
                  onPressed: _selectedEpisodes < 10
                      ? () => setState(() => _selectedEpisodes++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
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
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isCreating ? null : _generateScript,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B9D),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                icon: _isCreating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.auto_awesome),
                label: Text(_isCreating ? '生成中...' : 'AI生成剧本'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

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
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _showCharacterDialog(),
              icon: const Icon(Icons.add),
              label: const Text('新增角色'),
            ),
          ),
        ),
        Expanded(
          child: _characters.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.person_outline,
                        size: 64,
                        color: AppTheme.textHint,
                      ),
                      SizedBox(height: 16),
                      Text(
                        '暂无角色',
                        style: TextStyle(color: AppTheme.textHint),
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

  Widget _buildStoryboardTab() {
    if (_drama == null || _episodes.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.movie_creation_outlined, size: 64, color: AppTheme.textHint),
            SizedBox(height: 16),
            Text(
              '暂无分镜',
              style: TextStyle(color: AppTheme.textHint),
            ),
            SizedBox(height: 8),
            Text(
              '请先生成剧本',
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
