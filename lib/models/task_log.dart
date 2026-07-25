/// 后台任务日志模型
/// 记录每次图片/视频生成任务的状态、耗时、消耗等信息
class TaskLog {
  final int? id;
  final String taskId;          // 任务ID（API返回或本地生成）
  final String taskType;        // 任务类型：image / video / audio / text
  final String modelName;       // 使用的模型名称
  final String provider;        // 服务商：32ai / bailian / local_sd / custom 等
  final String status;          // pending / running / completed / failed
  final String? resultUrl;      // 结果URL或本地路径
  final String? errorReason;    // 失败原因
  final String? dramaTitle;     // 关联的短剧名称（可选）
  final String? shotDescription; // 镜头描述（可选）
  final int durationSeconds;    // 耗时（秒）
  final double cost;            // 消费金额（估算或实际）
  final int tokenUsed;          // 消耗的token/积分数
  final DateTime createdAt;
  final DateTime? completedAt;

  TaskLog({
    this.id,
    required this.taskId,
    required this.taskType,
    required this.modelName,
    this.provider = '',
    this.status = 'pending',
    this.resultUrl,
    this.errorReason,
    this.dramaTitle,
    this.shotDescription,
    this.durationSeconds = 0,
    this.cost = 0,
    this.tokenUsed = 0,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  factory TaskLog.fromMap(Map<String, dynamic> map) {
    return TaskLog(
      id: map['id'] as int?,
      taskId: map['task_id'] as String? ?? '',
      taskType: map['task_type'] as String? ?? 'image',
      modelName: map['model_name'] as String? ?? '',
      provider: map['provider'] as String? ?? '',
      status: map['status'] as String? ?? 'pending',
      resultUrl: map['result_url'] as String?,
      errorReason: map['error_reason'] as String?,
      dramaTitle: map['drama_title'] as String?,
      shotDescription: map['shot_description'] as String?,
      durationSeconds: map['duration_seconds'] as int? ?? 0,
      cost: (map['cost'] as num?)?.toDouble() ?? 0,
      tokenUsed: map['token_used'] as int? ?? 0,
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'] as String)
          : DateTime.now(),
      completedAt: map['completed_at'] != null
          ? DateTime.parse(map['completed_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'task_id': taskId,
      'task_type': taskType,
      'model_name': modelName,
      'provider': provider,
      'status': status,
      if (resultUrl != null) 'result_url': resultUrl,
      if (errorReason != null) 'error_reason': errorReason,
      if (dramaTitle != null) 'drama_title': dramaTitle,
      if (shotDescription != null) 'shot_description': shotDescription,
      'duration_seconds': durationSeconds,
      'cost': cost,
      'token_used': tokenUsed,
      'created_at': createdAt.toIso8601String(),
      if (completedAt != null) 'completed_at': completedAt!.toIso8601String(),
    };
  }

  TaskLog copyWith({
    int? id,
    String? taskId,
    String? taskType,
    String? modelName,
    String? provider,
    String? status,
    String? resultUrl,
    String? errorReason,
    String? dramaTitle,
    String? shotDescription,
    int? durationSeconds,
    double? cost,
    int? tokenUsed,
    DateTime? createdAt,
    DateTime? completedAt,
  }) {
    return TaskLog(
      id: id ?? this.id,
      taskId: taskId ?? this.taskId,
      taskType: taskType ?? this.taskType,
      modelName: modelName ?? this.modelName,
      provider: provider ?? this.provider,
      status: status ?? this.status,
      resultUrl: resultUrl ?? this.resultUrl,
      errorReason: errorReason ?? this.errorReason,
      dramaTitle: dramaTitle ?? this.dramaTitle,
      shotDescription: shotDescription ?? this.shotDescription,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      cost: cost ?? this.cost,
      tokenUsed: tokenUsed ?? this.tokenUsed,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
    );
  }

  /// 状态显示名称
  String get statusDisplayName {
    switch (status) {
      case 'pending': return '排队中';
      case 'running': return '进行中';
      case 'completed': return '已完成';
      case 'failed': return '失败';
      default: return status;
    }
  }

  /// 状态颜色
  int get statusColor {
    switch (status) {
      case 'pending': return 0xFF9E9E9E;  // 灰色
      case 'running': return 0xFFFF9800;  // 橙色
      case 'completed': return 0xFF4CAF50; // 绿色
      case 'failed': return 0xFFF44336;    // 红色
      default: return 0xFF9E9E9E;
    }
  }

  /// 耗时显示
  String get durationDisplay {
    if (status == 'pending' || status == 'running') {
      return '-';
    }
    if (durationSeconds <= 0) return '-';
    if (durationSeconds < 60) return '${durationSeconds}s';
    final min = durationSeconds ~/ 60;
    final sec = durationSeconds % 60;
    return '${min}m${sec}s';
  }
}
