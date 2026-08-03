import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../models/task_log.dart';
import '../../utils/storage_util.dart';

/// 后台任务进度页面
/// 展示所有图片/视频生成任务的日志，支持搜索、筛选、重试、删除等操作
class TaskLogPage extends StatefulWidget {
  const TaskLogPage({super.key});

  @override
  State<TaskLogPage> createState() => _TaskLogPageState();
}

class _TaskLogPageState extends State<TaskLogPage>
    with SingleTickerProviderStateMixin {
  List<TaskLog> _logs = [];
  bool _isLoading = true;
  String? _error;
  String _searchQuery = '';
  String? _filterType; // null = all, 'image', 'video', 'audio', 'text'
  String? _filterStatus; // null = all, 'pending', 'running', 'completed', 'failed'

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      List<TaskLog> logs;
      if (_searchQuery.isNotEmpty) {
        logs = await StorageUtil.searchTaskLogs(_searchQuery);
      } else {
        logs = await StorageUtil.getTaskLogs(
          taskType: _filterType,
          status: _filterStatus,
        );
      }
      if (mounted) {
        setState(() {
          _logs = logs;
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

  void _onTypeFilterChanged(String? type) {
    setState(() {
      _filterType = type;
      _searchQuery = '';
    });
    _loadLogs();
  }

  void _onStatusFilterChanged(String? status) {
    setState(() {
      _filterStatus = status;
      _searchQuery = '';
    });
    _loadLogs();
  }

  void _onSearch(String query) {
    setState(() {
      _searchQuery = query;
    });
    _loadLogs();
  }

  // ==================== 操作方法 ====================

  /// 删除单条任务日志
  Future<void> _deleteTaskLog(TaskLog log) async {
    if (log.id == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('删除记录', style: TextStyle(color: AppTheme.textPrimary)),
        content: Text('确定删除任务 ${log.taskId} 的记录吗？此操作不可撤销。',
            style: const TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageUtil.deleteTaskLog(log.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已删除'), duration: Duration(seconds: 1)),
        );
        _loadLogs();
      }
    }
  }

  /// 清除已完成的任务日志
  Future<void> _cleanCompletedLogs() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.darkSurface,
        title: const Text('清除已完成', style: TextStyle(color: AppTheme.textPrimary)),
        content: const Text('确定清除所有已完成的任务记录吗？此操作不可撤销。',
            style: TextStyle(color: AppTheme.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('清除', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await StorageUtil.cleanOldTaskLogs(keepDays: 0);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已清除已完成记录'), duration: Duration(seconds: 1)),
        );
        _loadLogs();
      }
    }
  }

  /// 重试失败任务：创建新的pending状态记录
  Future<void> _retryTask(TaskLog log) async {
    // 创建新的任务记录
    final newLog = TaskLog(
      taskType: log.taskType,
      modelName: log.modelName,
      provider: log.provider,
      status: 'pending',
      dramaTitle: log.dramaTitle,
      shotDescription: log.shotDescription,
    );

    final newId = await StorageUtil.saveTaskLog(newLog);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已创建重试任务 #$newId'),
          duration: const Duration(seconds: 2),
        ),
      );
      _loadLogs();
    }
  }

  /// 打开结果URL
  Future<void> _openResultUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && mounted) {
        // 启动失败则复制到剪贴板
        Clipboard.setData(ClipboardData(text: url));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开链接，已复制到剪贴板'), duration: Duration(seconds: 2)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.darkBackground,
      appBar: AppBar(
        title: const Text('任务进度'),
        backgroundColor: AppTheme.darkSurface,
        actions: [
          // 清除已完成按钮
          IconButton(
            icon: const Icon(Icons.cleaning_services_outlined),
            tooltip: '清除已完成',
            onPressed: _cleanCompletedLogs,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadLogs,
          ),
        ],
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: _onSearch,
              decoration: InputDecoration(
                hintText: '搜索任务ID、模型名、短剧名...',
                hintStyle: const TextStyle(color: AppTheme.textHint),
                prefixIcon: const Icon(Icons.search, color: AppTheme.textHint),
                filled: true,
                fillColor: AppTheme.darkSurface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
              style: const TextStyle(color: AppTheme.textPrimary, fontSize: 14),
            ),
          ),
          // 类型筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                _buildFilterChip('全部', _filterType == null, () => _onTypeFilterChanged(null)),
                const SizedBox(width: 8),
                _buildFilterChip('图片', _filterType == 'image', () => _onTypeFilterChanged('image')),
                const SizedBox(width: 8),
                _buildFilterChip('视频', _filterType == 'video', () => _onTypeFilterChanged('video')),
                const SizedBox(width: 8),
                _buildFilterChip('音频', _filterType == 'audio', () => _onTypeFilterChanged('audio')),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // 状态筛选
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Wrap(
              spacing: 8,
              children: [
                _buildStatusChip('全部', _filterStatus == null, () => _onStatusFilterChanged(null)),
                _buildStatusChip('进行中', _filterStatus == 'running', () => _onStatusFilterChanged('running')),
                _buildStatusChip('已完成', _filterStatus == 'completed', () => _onStatusFilterChanged('completed')),
                _buildStatusChip('失败', _filterStatus == 'failed', () => _onStatusFilterChanged('failed')),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // 统计信息
          if (!_isLoading && _error == null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '共 ${_logs.length} 条记录',
                    style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                  ),
                  const Spacer(),
                  _buildStatsBadge(),
                ],
              ),
            ),
          const SizedBox(height: 8),
          // 列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline, size: 48, color: Colors.red),
                              const SizedBox(height: 16),
                              Text(_error!, style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              ElevatedButton(onPressed: _loadLogs, child: const Text('重试')),
                            ],
                          ),
                        ),
                      )
                    : _logs.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                Icon(Icons.task_alt, size: 48, color: AppTheme.textHint),
                                SizedBox(height: 8),
                                Text('暂无任务记录', style: TextStyle(fontSize: 14, color: AppTheme.textHint)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _logs.length,
                            itemBuilder: (context, index) {
                              return _buildTaskCard(_logs[index]);
                            },
                          ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppTheme.primaryColor : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, bool selected, VoidCallback onTap) {
    Color bgColor;
    if (selected) {
      if (label == '进行中') bgColor = const Color(0xFFFF9800);
      else if (label == '已完成') bgColor = const Color(0xFF4CAF50);
      else if (label == '失败') bgColor = const Color(0xFFF44336);
      else bgColor = AppTheme.primaryColor;
    } else {
      bgColor = AppTheme.darkSurface;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsBadge() {
    final completed = _logs.where((l) => l.status == 'completed').length;
    final failed = _logs.where((l) => l.status == 'failed').length;
    final running = _logs.where((l) => l.status == 'running').length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (running > 0) _miniBadge('$running 进行中', const Color(0xFFFF9800)),
        if (completed > 0) ...[
          const SizedBox(width: 8),
          _miniBadge('$completed 已完成', const Color(0xFF4CAF50)),
        ],
        if (failed > 0) ...[
          const SizedBox(width: 8),
          _miniBadge('$failed 失败', const Color(0xFFF44336)),
        ],
      ],
    );
  }

  Widget _miniBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildTaskCard(TaskLog log) {
    final statusColor = Color(log.statusColor);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: log.status == 'running'
            ? Border.all(color: statusColor.withOpacity(0.4), width: 1)
            : null,
      ),
      child: InkWell(
        onTap: () => _showTaskDetail(log),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 第一行：任务ID + 状态
              Row(
                children: [
                  Expanded(
                    child: Text(
                      log.taskId,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (log.status == 'running')
                          const SizedBox(
                            width: 10,
                            height: 10,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF9800)),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Text(
                          log.statusDisplayName,
                          style: TextStyle(color: statusColor, fontSize: 12, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // 第二行：模型 + 服务商 + 类型
              Row(
                children: [
                  _infoIcon(Icons.memory, log.modelName),
                  const SizedBox(width: 12),
                  if (log.provider.isNotEmpty) _infoIcon(Icons.cloud, log.provider),
                  if (log.provider.isNotEmpty) const SizedBox(width: 12),
                  _infoIcon(_typeIcon(log.taskType), _typeName(log.taskType)),
                  if (log.dramaTitle != null) ...[
                    const Spacer(),
                    _infoIcon(Icons.movie, log.dramaTitle!),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              // 第三行：耗时 + 时间
              Row(
                children: [
                  _infoIcon(Icons.timer, log.durationDisplay),
                  const SizedBox(width: 16),
                  _infoIcon(Icons.schedule, _formatTime(log.createdAt)),
                  if (log.completedAt != null) ...[
                    const SizedBox(width: 16),
                    _infoIcon(Icons.check_circle, _formatTime(log.completedAt!)),
                  ],
                  const Spacer(),
                  if (log.cost > 0)
                    Text('¥${log.cost.toStringAsFixed(4)}', style: const TextStyle(color: AppTheme.accentColor, fontSize: 11)),
                ],
              ),
              // 失败原因
              if (log.errorReason != null && log.errorReason!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF44336).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 14, color: Color(0xFFF44336)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          log.errorReason!.length > 80
                              ? '${log.errorReason!.substring(0, 80)}...'
                              : log.errorReason!,
                          style: const TextStyle(color: Color(0xFFF44336), fontSize: 11),
                          maxLines: 2,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              // 镜头描述
              if (log.shotDescription != null && log.shotDescription!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  log.shotDescription!,
                  style: const TextStyle(color: AppTheme.textHint, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              // 操作按钮行
              const SizedBox(height: 8),
              Row(
                children: [
                  // 失败任务：重试按钮
                  if (log.status == 'failed')
                    SizedBox(
                      height: 28,
                      child: ElevatedButton.icon(
                        onPressed: () => _retryTask(log),
                        icon: const Icon(Icons.refresh, size: 14),
                        label: const Text('重试', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFF44336).withOpacity(0.8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  // 已完成且有结果URL：查看结果按钮
                  if (log.status == 'completed' && log.resultUrl != null && log.resultUrl!.isNotEmpty) ...[
                    if (log.status == 'failed') const SizedBox(width: 8),
                    SizedBox(
                      height: 28,
                      child: ElevatedButton.icon(
                        onPressed: () => _openResultUrl(log.resultUrl!),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text('查看结果', style: TextStyle(fontSize: 11)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50).withOpacity(0.8),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  // 删除按钮（小号灰色）
                  SizedBox(
                    height: 28,
                    child: IconButton(
                      onPressed: () => _deleteTaskLog(log),
                      icon: const Icon(Icons.delete_outline, size: 16),
                      color: AppTheme.textHint,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 28),
                      tooltip: '删除记录',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoIcon(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.textHint),
        const SizedBox(width: 4),
        Text(text, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
      ],
    );
  }

  IconData _typeIcon(String type) {
    switch (type) {
      case 'image': return Icons.image;
      case 'video': return Icons.videocam;
      case 'audio': return Icons.audio_file;
      case 'text': return Icons.text_fields;
      default: return Icons.task;
    }
  }

  String _typeName(String type) {
    switch (type) {
      case 'image': return '图片';
      case 'video': return '视频';
      case 'audio': return '音频';
      case 'text': return '文本';
      default: return type;
    }
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  void _showTaskDetail(TaskLog log) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final statusColor = Color(log.statusColor);
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: AppTheme.textHint.withOpacity(0.3), borderRadius: BorderRadius.circular(2)),
                ),
              ),
              const SizedBox(height: 16),
              Text('任务详情', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 16),
              _detailRow('任务ID', log.taskId, true),
              _detailRow('状态', log.statusDisplayName),
              _detailRow('类型', _typeName(log.taskType)),
              _detailRow('模型', log.modelName),
              if (log.provider.isNotEmpty) _detailRow('服务商', log.provider),
              _detailRow('创建时间', _formatFullTime(log.createdAt)),
              if (log.completedAt != null) _detailRow('完成时间', _formatFullTime(log.completedAt!)),
              _detailRow('耗时', log.durationDisplay),
              if (log.cost > 0) _detailRow('消费', '¥${log.cost.toStringAsFixed(4)}'),
              if (log.tokenUsed > 0) _detailRow('Token', '${log.tokenUsed}'),
              if (log.dramaTitle != null) _detailRow('短剧', log.dramaTitle!),
              if (log.errorReason != null && log.errorReason!.isNotEmpty)
                _detailRow('失败原因', log.errorReason!),
              if (log.resultUrl != null && log.resultUrl!.isNotEmpty)
                _detailRow('结果URL', log.resultUrl!, true),
              const SizedBox(height: 16),
              // 复制任务ID
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: log.taskId));
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(content: Text('已复制任务ID'), duration: Duration(seconds: 1)),
                    );
                  },
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text('复制任务ID'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              // 失败任务：重新执行按钮
              if (log.status == 'failed')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _retryTask(log);
                    },
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重新执行此任务'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF9800),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              if (log.status == 'failed') const SizedBox(height: 8),
              // 已完成且有结果URL：查看结果按钮
              if (log.status == 'completed' && log.resultUrl != null && log.resultUrl!.isNotEmpty)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _openResultUrl(log.resultUrl!);
                    },
                    icon: const Icon(Icons.open_in_new, size: 16),
                    label: const Text('查看结果'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              if (log.status == 'completed' && log.resultUrl != null && log.resultUrl!.isNotEmpty)
                const SizedBox(height: 8),
              // 删除此记录
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _deleteTaskLog(log);
                  },
                  icon: const Icon(Icons.delete_outline, size: 16),
                  label: const Text('删除此记录'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red54, width: 0.5),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Widget _detailRow(String label, String value, [bool mono = false]) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(label, style: const TextStyle(color: AppTheme.textHint, fontSize: 13)),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: AppTheme.textPrimary,
                fontSize: 13,
                fontFamily: mono ? 'monospace' : null,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatFullTime(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}:${dt.second.toString().padLeft(2, '0')}';
  }
}
