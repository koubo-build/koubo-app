import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/theme.dart';
import '../../config/routes.dart';
import '../../models/drama.dart';
import '../../utils/storage_util.dart';

/// 短剧项目列表页
class DramaListPage extends ConsumerStatefulWidget {
  const DramaListPage({super.key});

  @override
  ConsumerState<DramaListPage> createState() => _DramaListPageState();
}

class _DramaListPageState extends ConsumerState<DramaListPage> {
  List<Drama> _dramas = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDramas();
  }

  Future<void> _loadDramas() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final dramas = await StorageUtil.getAllDramas();

      if (mounted) {
        setState(() {
          _dramas = dramas;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _deleteDrama(Drama drama) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除短剧'),
        content: Text('确定要删除"${drama.title}"吗？此操作不可恢复。'),
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

    if (confirmed == true && drama.id != null) {
      try {
        await StorageUtil.deleteDrama(drama.id!);
        _loadDramas();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('删除成功')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('删除失败：$e')),
          );
        }
      }
    }
  }

  void _openEditor({int? dramaId}) {
    Navigator.pushNamed(
      context,
      AppRoutes.dramaEditor,
      arguments: {'dramaId': dramaId},
    ).then((_) => _loadDramas());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI短剧'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDramas,
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openEditor(),
        backgroundColor: const Color(0xFFFF6B9D),
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDramas,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }

    if (_dramas.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.movie_creation_outlined,
              size: 64,
              color: AppTheme.textHint.withOpacity(0.5),
            ),
            const SizedBox(height: 16),
            const Text(
              '还没有短剧项目',
              style: TextStyle(fontSize: 18, color: AppTheme.textSecondary),
            ),
            const SizedBox(height: 8),
            const Text(
              '点击右下角按钮创建第一个短剧',
              style: TextStyle(fontSize: 14, color: AppTheme.textHint),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadDramas,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _dramas.length,
        itemBuilder: (context, index) {
          final drama = _dramas[index];
          return _buildDramaCard(drama);
        },
      ),
    );
  }

  Widget _buildDramaCard(Drama drama) {
    final progress = drama.totalShots > 0
        ? drama.completedShots / drama.totalShots
        : 0.0;

    return Dismissible(
      key: Key('drama_${drama.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        _deleteDrama(drama);
        return false;
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.8),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: () => _openEditor(dramaId: drama.id),
          onLongPress: () => _deleteDrama(drama),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF6B9D).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        drama.genreDisplayName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFFF6B9D),
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryColor.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        drama.styleDisplayName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppTheme.primaryColor,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${drama.episodeCount}集',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  drama.title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                if (drama.description.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    drama.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: progress,
                          backgroundColor: AppTheme.darkSurface,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            progress == 1.0
                                ? AppTheme.safeColor
                                : const Color(0xFFFF6B9D),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      '${drama.completedShots}/${drama.totalShots} 镜头',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textHint,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
