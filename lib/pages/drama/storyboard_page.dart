import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../../config/theme.dart';
import '../../models/drama.dart';
import '../../services/drama_service.dart';
import '../../services/drama_task_service.dart';
import '../../services/image_gen_service.dart';
import '../../services/tts_service.dart';
import '../../services/api_client.dart';
import '../../utils/storage_util.dart';

/// 分镜工作台页面
class StoryboardPage extends ConsumerStatefulWidget {
  final int episodeId;
  final int dramaId;

  const StoryboardPage({
    super.key,
    required this.episodeId,
    required this.dramaId,
  });

  @override
  ConsumerState<StoryboardPage> createState() => _StoryboardPageState();
}

class _StoryboardPageState extends ConsumerState<StoryboardPage> {
  DramaEpisode? _episode;
  List<DramaShot> _shots = [];
  List<DramaCharacter> _characters = [];
  Drama? _drama;
  bool _isLoading = true;
  bool _isGenerating = false;
  String _generateProgress = '';
  bool _hasInterruptedTasks = false;
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
    {'value': 'ai32-image', 'label': '32AI · Image'},
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

  int _currentProcessingIndex = -1;
  String _currentStage = '';
  final Set<int> _processingShotIds = {};  // 正在并行处理的镜头ID（最多3张）
  final Map<int, int> _shotLocalIndex = {};  // shotId → 在 _shots 列表中的index
  static const int _maxRetries = 2;
  // key: "${shotId}_${stage}" → retry count
  final Map<String, int> _shotRetryCounts = {};
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(minutes: 15),
    sendTimeout: const Duration(minutes: 5),
  ));

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      setState(() => _isLoading = true);

      // 加载剧集
      _episode = await StorageUtil.getEpisodeWithShots(widget.episodeId);
      if (_episode != null) {
        _shots = _episode!.shots;
      }

      // 加载角色
      _characters = await StorageUtil.getCharactersByDrama(widget.dramaId);

      // 加载Drama获取aspectRatio
      _drama = await StorageUtil.getDrama(widget.dramaId);

      // 检测是否有中断的任务（pending或failed状态的镜头）
      _hasInterruptedTasks = _shots.any(
        (s) => s.status == 'pending' || s.status == 'failed',
      );

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

  Future<void> _generateImages() async {
    final pendingShots = _shots.where((s) => s.status == 'pending' || s.status == 'failed').toList();
    if (pendingShots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有待生成的镜头')),
      );
      return;
    }

    if (_drama == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('短剧信息未加载')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _currentStage = 'image';
      _currentProcessingIndex = 0;
      _generateProgress = '正在准备批量生成...';
      _processingShotIds.clear();
      _shotLocalIndex.clear();
      for (int i = 0; i < _shots.length; i++) {
        if (_shots[i].id != null) {
          _shotLocalIndex[_shots[i].id!] = i;
        }
      }
    });

    try {
      final taskService = ref.read(dramaTaskServiceProvider);

      await taskService.batchGenerateImages(
        dramaId: widget.dramaId,
        episodeId: widget.episodeId,
        shots: pendingShots,
        characters: _characters,
        drama: _drama!,
        onProgress: (completed, total, currentShot, {int? shotId, String? status}) {
          if (mounted) {
            setState(() {
              _generateProgress = '[$completed/$total] $currentShot';
              _currentProcessingIndex = completed < total ? completed : -1;

              // 维护正在处理的镜头集合（最多3张同时，UI 可视化显示）
              if (shotId != null) {
                if (status == 'processing') {
                  _processingShotIds.add(shotId);
                } else if (status == 'image_ready' || status == 'failed') {
                  _processingShotIds.remove(shotId);
                }
              }
            });

            // 单张完成/失败时，实时从 DB 拉最新 shot 数据更新到列表
            if (shotId != null && (status == 'image_ready' || status == 'failed')) {
              _refreshSingleShot(shotId);
            }
          }
        },
      );

      // 重新加载数据（兜底，确保最终状态正确）
      await _loadData();

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('图片生成完成')),
        );
      }
    } catch (e) {
      // 失败时也重新加载，看已完成的进度
      await _loadData();

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成异常：$e')),
        );
      }
    }
  }

  /// 从 DB 拉取单个 shot 的最新数据并更新 _shots 列表（用于并行生成的实时刷新）
  Future<void> _refreshSingleShot(int shotId) async {
    try {
      final freshShot = await StorageUtil.getShot(shotId);
      if (freshShot == null || !mounted) return;
      final idx = _shotLocalIndex[shotId];
      if (idx == null || idx >= _shots.length) return;
      setState(() {
        _shots[idx] = freshShot;
      });
    } catch (_) {
      // 静默失败，最终 _loadData 会兜底
    }
  }

  Future<void> _resumeInterruptTasks() async {
    setState(() {
      _isGenerating = true;
      _generateProgress = '正在恢复中断任务...';
    });

    try {
      final taskService = ref.read(dramaTaskServiceProvider);

      await taskService.resumeInterruptTasks(
        dramaId: widget.dramaId,
        episodeId: widget.episodeId,
        onProgress: (completed, total, stage) {
          if (mounted) {
            setState(() {
              _generateProgress = '[$completed/$total] $stage';
            });
          }
        },
      );

      // 重新加载数据
      await _loadData();

      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('任务恢复完成')),
        );
      }
    } catch (e) {
      await _loadData();

      if (mounted) {
        setState(() => _isGenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('恢复失败：$e')),
        );
      }
    }
  }


  /// 获取短剧使用的音色（优先使用语音模块选择的克隆音色）
  Future<Map<String, String>> _getDramaVoice() async {
    final savedVoiceId = StorageUtil.getDhTtsVoiceId();
    if (savedVoiceId != null && savedVoiceId.isNotEmpty) {
      // 尝试从克隆音色中查找（存储格式: voiceId|voiceName|gender|createdAt;...）
      final clonedVoicesStr = StorageUtil.getString('cloned_voices') ?? '';
      if (clonedVoicesStr.isNotEmpty) {
        try {
          final entries = clonedVoicesStr.split(';');
          for (final entry in entries) {
            if (entry.isEmpty) continue;
            final parts = entry.split('|');
            if (parts.isNotEmpty && parts[0] == savedVoiceId) {
              // 克隆音色使用 cosyvoice 引擎
              return {'voiceId': savedVoiceId, 'provider': 'cosyvoice'};
            }
          }
        } catch (_) {}
      }
      // 是系统音色，直接用
      return {'voiceId': savedVoiceId, 'provider': 'cosyvoice'};
    }
    // 没有设置，使用默认
    return {'voiceId': 'longanhuan', 'provider': 'cosyvoice'};
  }

  Future<void> _generateAudios() async {
    final needAudioShots = _shots
        .where((s) =>
            s.dialogue.isNotEmpty &&
            (s.status == 'pending' || s.status == 'image_ready'))
        .toList();

    if (needAudioShots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有需要生成音频的镜头')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _currentStage = 'audio';
      _currentProcessingIndex = 0;
      _generateProgress = '正在生成音频...';
    });

    try {
      final ttsService = TtsService(ref.read(apiClientProvider));

      for (int i = 0; i < needAudioShots.length; i++) {
        final shot = needAudioShots[i];
        setState(() {
          _currentProcessingIndex = _shots.indexWhere((s) => s.id == shot.id);
          _generateProgress = '[音频 ${i + 1}/${needAudioShots.length}] 镜头 #${shot.shotNumber}';
        });

        try {
          final voiceInfo = await _getDramaVoice();
          final audioPath = await ttsService.synthesize(
            text: shot.dialogue,
            voiceId: voiceInfo['voiceId'] ?? 'longanhuan',
            provider: voiceInfo['provider'] ?? 'cosyvoice',
          );

          String newStatus = 'audio_ready';
          if (shot.imagePath != null && shot.imagePath!.isNotEmpty) {
            newStatus = 'audio_ready';
          }

          final updatedShot = shot.copyWith(
            audioPath: audioPath,
            status: newStatus,
          );
          await StorageUtil.updateShot(updatedShot);

          setState(() {
            final index = _shots.indexWhere((s) => s.id == shot.id);
            if (index != -1) {
              _shots[index] = updatedShot;
            }
          });
        } catch (e) {
          final failedShot = shot.copyWith(status: 'failed');
          await StorageUtil.updateShot(failedShot);
          setState(() {
            final index = _shots.indexWhere((s) => s.id == shot.id);
            if (index != -1) {
              _shots[index] = failedShot;
            }
          });
        }
      }

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('音频生成完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  Future<void> _generateVideos() async {
    final readyShots = _shots
        .where((s) => s.imagePath != null && s.status != 'video_ready')
        .toList();

    if (readyShots.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('没有可以生成视频的镜头')),
      );
      return;
    }

    setState(() {
      _isGenerating = true;
      _currentStage = 'video';
      _currentProcessingIndex = 0;
      _generateProgress = '正在生成视频...';
    });

    try {
      for (int i = 0; i < readyShots.length; i++) {
        final shot = readyShots[i];
        setState(() {
          _currentProcessingIndex = _shots.indexWhere((s) => s.id == shot.id);
          _generateProgress = '[视频 ${i + 1}/${readyShots.length}] 镜头 #${shot.shotNumber}';
        });

        try {
          final videoPath = await _generateVideoForShot(
            imagePath: shot.imagePath!,
            audioPath: shot.audioPath,
            prompt: shot.visualDescription,
          );

          final updatedShot = shot.copyWith(
            videoPath: videoPath,
            status: 'video_ready',
          );
          await StorageUtil.updateShot(updatedShot);

          setState(() {
            final index = _shots.indexWhere((s) => s.id == shot.id);
            if (index != -1) {
              _shots[index] = updatedShot;
            }
          });
        } catch (e) {
          final failedShot = shot.copyWith(status: 'failed');
          await StorageUtil.updateShot(failedShot);
          setState(() {
            final index = _shots.indexWhere((s) => s.id == shot.id);
            if (index != -1) {
              _shots[index] = failedShot;
            }
          });
        }
      }

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('视频生成完成')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  /// 获取百炼API Key
  Future<String> _getApiKey() async {
    var apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    apiKey = apiKey?.trim() ?? '';
    if (apiKey.isEmpty) {
      throw Exception('请先配置阿里百炼API Key（设置页面）');
    }
    return apiKey;
  }

  /// 上传文件到百炼临时存储
  Future<String> _uploadFileToBailian(String localFilePath, String modelName) async {
    final file = File(localFilePath);
    if (!await file.exists()) {
      throw Exception('文件不存在：$localFilePath');
    }

    final fileName = localFilePath.split('/').last;

    final apiKey = await _getApiKey();
    final policyResponse = await _dio.get(
      '${ApiConfig.bailianUploadUrl}?action=getPolicy&model=$modelName',
      options: Options(
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
      ),
    );

    final policyData = policyResponse.data as Map<String, dynamic>;
    final result = policyData['data'] as Map<String, dynamic>? ?? policyData;

    final uploadHost = result['upload_host'] as String;
    final uploadDir = result['upload_dir'] as String;
    final ossKey = '$uploadDir/$fileName';

    final formData = FormData.fromMap({
      'OSSAccessKeyId': result['oss_access_key_id'] as String,
      'Signature': result['signature'] as String,
      'policy': result['policy'] as String,
      'x-oss-object-acl': result['x_oss_object_acl'] as String? ?? 'private',
      'x-oss-forbid-overwrite': result['x_oss_forbid_overwrite']?.toString() ?? 'true',
      'key': ossKey,
      'success_action_status': '200',
      'file': await MultipartFile.fromFile(localFilePath, filename: fileName),
    });

    await _dio.post(
      uploadHost,
      data: formData,
      options: Options(
        headers: {'Content-Type': 'multipart/form-data'},
        sendTimeout: const Duration(minutes: 5),
      ),
    );

    return 'oss://$ossKey';
  }

  /// 下载视频到本地
  Future<String> _downloadVideo(String videoUrl) async {
    final videoDir = await StorageUtil.getDramaVideoDirectory();
    final fileName = 'happyhorse_${DateTime.now().millisecondsSinceEpoch}.mp4';
    final filePath = '$videoDir/$fileName';

    try {
      final response = await _dio.get(
        videoUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 15),
        ),
      );

      final file = File(filePath);
      await file.writeAsBytes(response.data as List<int>);
      return filePath;
    } catch (e) {
      throw Exception('视频下载失败：$e');
    }
  }

  /// 查询任务状态
  Future<Map<String, dynamic>> _queryTaskStatus(String taskId) async {
    final apiKey = await _getApiKey();

    try {
      final response = await _dio.get(
        '${ApiConfig.wanxTaskQueryUrl}$taskId',
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
          receiveTimeout: const Duration(seconds: 30),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      final status = output?['task_status'] as String? ?? 'UNKNOWN';
      String? videoUrl;

      if (status == 'SUCCEEDED') {
        final results = output?['results'] as Map<String, dynamic>?;
        videoUrl = results?['video_url'] as String?;
      }

      return {
        'status': status,
        'video_url': videoUrl,
      };
    } catch (e) {
      throw Exception('查询任务失败：$e');
    }
  }

  /// 轮询等待任务完成
  Future<String> _waitForTaskCompletion(String taskId, {int timeoutSeconds = 600}) async {
    final startTime = DateTime.now();

    while (true) {
      final statusInfo = await _queryTaskStatus(taskId);
      final status = statusInfo['status'] as String;
      final videoUrl = statusInfo['video_url'] as String?;

      if (status == 'SUCCEEDED') {
        if (videoUrl == null || videoUrl.isEmpty) {
          throw Exception('视频生成完成但未返回视频URL');
        }
        return videoUrl;
      } else if (status == 'FAILED') {
        throw Exception('视频生成失败');
      }

      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if (elapsed >= timeoutSeconds) {
        throw Exception('视频生成超时');
      }

      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// HappyHorse图生视频
  Future<String> _generateHappyHorseVideo({
    required String imagePath,
    String? prompt,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await _getApiKey();

    onProgress?.call('上传人像照片中...', 5);
    final imageUrl = await _uploadFileToBailian(imagePath, ApiConfig.happyHorseI2vModel);

    onProgress?.call('提交HappyHorse任务...', 25);
    final resolution = '720P';

    final requestBody = {
      'model': ApiConfig.happyHorseI2vModel,
      'input': {
        'prompt': prompt ?? '人物自然说话，口型同步',
        'media': [
          {
            'type': 'first_frame',
            'url': imageUrl,
          },
        ],
      },
      'parameters': {
        'resolution': resolution,
        'duration': 5,
      },
    };

    try {
      final response = await _dio.post(
        ApiConfig.happyHorseVideoSubmitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-DashScope-Async': 'enable',
            'X-DashScope-OssResourceResolve': 'enable',
          },
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final taskId = data['output']?['task_id'] as String?;
      if (taskId == null || taskId.isEmpty) {
        throw Exception('HappyHorse提交任务未返回task_id');
      }

      onProgress?.call('等待视频生成中...', 50);
      final videoUrl = await _waitForTaskCompletion(taskId, timeoutSeconds: 600);

      onProgress?.call('下载视频中...', 90);
      final localPath = await _downloadVideo(videoUrl);

      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('百炼Key无权限，请确认已开通HappyHorse模型服务');
      }
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? '';
      }
      throw Exception('HappyHorse提交失败($statusCode)：$detail');
    }
  }

  /// 数字人视频生成（图片+音频）
  Future<String> _generateVideoWithAudio({
    required String imagePath,
    required String audioPath,
    String? prompt,
  }) async {
    final apiKey = await _getApiKey();

    final imageUrl = await _uploadFileToBailian(imagePath, ApiConfig.wanxS2vModel);
    final audioUrl = await _uploadFileToBailian(audioPath, ApiConfig.wanxS2vModel);

    final requestBody = {
      'model': ApiConfig.wanxS2vModel,
      'input': {
        'image_url': imageUrl,
        'audio_url': audioUrl,
      },
      'parameters': {
        'resolution': '720P',
      },
    };

    try {
      final response = await _dio.post(
        ApiConfig.wanxVideoSubmitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            'X-DashScope-Async': 'enable',
            'X-DashScope-OssResourceResolve': 'enable',
          },
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final taskId = data['output']?['task_id'] as String?;
      if (taskId == null || taskId.isEmpty) {
        throw Exception('提交任务失败：未返回task_id');
      }

      final videoUrl = await _waitForTaskCompletion(taskId, timeoutSeconds: 900);
      final localPath = await _downloadVideo(videoUrl);

      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['message']?.toString() ?? '';
      }
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('鉴权失败：$detail');
      }
      throw Exception('视频生成失败($statusCode)：$detail');
    }
  }

  /// 统一视频生成入口：根据项目模型配置自动路由
  Future<String> _generateVideoForShot({
    required String imagePath,
    String? audioPath,
    String? prompt,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final config = _drama?.parsedModelConfig ?? DramaModelConfig();
    final videoModel = config.videoModel;

    switch (videoModel) {
      case 'wanx-s2v':
        // 万相 S2V：有音频时走口型同步，无音频回退到 HappyHorse
        if (audioPath != null && audioPath.isNotEmpty) {
          return _generateVideoWithAudio(
            imagePath: imagePath,
            audioPath: audioPath,
            prompt: prompt,
          );
        } else {
          return _generateHappyHorseVideo(
            imagePath: imagePath,
            prompt: prompt,
            onProgress: onProgress,
          );
        }
      case 'happyhorse':
        return _generateHappyHorseVideo(
          imagePath: imagePath,
          prompt: prompt,
          onProgress: onProgress,
        );
      case 'ai32-seedance':
        return _generateSeedanceVideo(
          imagePath: imagePath,
          prompt: prompt,
          onProgress: onProgress,
        );
      case 'agnes-video':
        // Agnes AI Video：走图生视频，无音频支持
        return _generateAgnesVideo(
          imagePath: imagePath,
          prompt: prompt,
          onProgress: onProgress,
        );
      case 'custom':
        if (config.videoApiKey.isEmpty || config.videoBaseUrl.isEmpty) {
          throw Exception('自定义视频模型需要配置API Key和Base URL');
        }
        return _generateCustomVideo(
          imagePath: imagePath,
          prompt: prompt,
          apiKey: config.videoApiKey,
          baseUrl: config.videoBaseUrl,
          onProgress: onProgress,
        );
      default:
        // 默认回退到 HappyHorse
        return _generateHappyHorseVideo(
          imagePath: imagePath,
          prompt: prompt,
          onProgress: onProgress,
        );
    }
  }

  /// 32AI Seedance 图生视频
  Future<String> _generateSeedanceVideo({
    required String imagePath,
    String? prompt,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.ai32ApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先在设置中配置32AI中转站API Key');
    }

    onProgress?.call('上传图片中...', 5);
    final imageUrl = await _uploadFileToBailian(imagePath, ApiConfig.wanxS2vModel);

    onProgress?.call('提交Seedance任务...', 25);
    final submitUrl = '${ApiConfig.ai32VolcBaseUrl}${ApiConfig.ai32VideoGenEndpoint}';

    final requestBody = {
      'model': 'seedance-2.0',
      'content': [
        {
          'type': 'image_url',
          'image_url': {'url': imageUrl},
        },
        if (prompt != null && prompt.isNotEmpty)
          {
            'type': 'text',
            'text': prompt,
          },
      ],
    };

    try {
      final response = await _dio.post(
        submitUrl,
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final taskId = data['id']?.toString() ?? data['task_id']?.toString();
      if (taskId == null || taskId.isEmpty) {
        throw Exception('Seedance提交任务未返回task_id');
      }

      onProgress?.call('Seedance生成中（通常3-5分钟）...', 50);
      final videoUrl = await _pollSeedanceTask(taskId, apiKey, onProgress: onProgress);

      onProgress?.call('下载视频中...', 90);
      final localPath = await _downloadVideo(videoUrl);
      onProgress?.call('完成！', 100);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['error']?['message']?.toString() ??
                 responseBody['message']?.toString() ?? '';
      }
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('32AI API Key无效或无权限：$detail');
      }
      throw Exception('Seedance提交失败($statusCode)：$detail');
    }
  }

  /// 轮询32AI Seedance任务状态
  Future<String> _pollSeedanceTask(
    String taskId,
    String apiKey, {
    void Function(String stage, int progress)? onProgress,
  }) async {
    final queryUrl = '${ApiConfig.ai32VolcBaseUrl}${ApiConfig.ai32VideoGenEndpoint}/$taskId';
    final startTime = DateTime.now();

    while (true) {
      try {
        final response = await _dio.get(
          queryUrl,
          options: Options(
            headers: {'Authorization': 'Bearer $apiKey'},
            receiveTimeout: const Duration(seconds: 30),
          ),
        );

        final data = response.data as Map<String, dynamic>;
        final status = data['status']?.toString() ?? data['state']?.toString() ?? '';

        if (status == 'succeeded' || status == 'success' || status == 'complete') {
          final output = data['output'] ?? data['result'] ?? data;
          String? videoUrl;
          if (output is Map) {
            videoUrl = output['video_url']?.toString() ?? output['url']?.toString();
          }
          if (output is List && output.isNotEmpty) {
            videoUrl = output[0]['url']?.toString() ?? output[0]['video_url']?.toString();
          }
          if (videoUrl == null || videoUrl.isEmpty) {
            throw Exception('Seedance任务完成但未返回视频URL');
          }
          return videoUrl;
        } else if (status == 'failed' || status == 'error') {
          final errorMsg = data['error']?['message']?.toString() ??
                           data['message']?.toString() ?? '生成失败';
          throw Exception('Seedance生成失败：$errorMsg');
        }
        onProgress?.call('Seedance生成中（通常3-5分钟）...', 50);
      } on DioException catch (_) {
        // 查询失败，继续重试
      }

      final elapsed = DateTime.now().difference(startTime).inSeconds;
      if (elapsed >= 600) {
        throw Exception('Seedance视频生成超时（10分钟）');
      }
      await Future.delayed(const Duration(seconds: 10));
    }
  }

  /// Agnes AI 图生视频
  Future<String> _generateAgnesVideo({
    required String imagePath,
    String? prompt,
    void Function(String stage, int progress)? onProgress,
  }) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.agnesApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      throw Exception('请先配置Agnes AI API Key');
    }

    onProgress?.call('上传图片中...', 5);
    // 读取图片并转为base64
    final imageFile = File(imagePath);
    final imageBytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    onProgress?.call('提交Agnes Video任务...', 25);
    final requestBody = {
      'model': 'agnes-video',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
            },
            if (prompt != null && prompt.isNotEmpty)
              {'type': 'text', 'text': prompt},
          ],
        }
      ],
    };

    try {
      final response = await _dio.post(
        '${ApiConfig.agnesBaseUrl}/chat/completions',
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('Agnes Video未返回结果');
      }
      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'];
      String? videoUrl;
      if (content is List) {
        for (final item in content) {
          if (item is Map && item['type'] == 'video_url') {
            videoUrl = item['video_url']?['url']?.toString();
            break;
          }
        }
      }
      if (videoUrl == null || videoUrl.isEmpty) {
        throw Exception('Agnes Video未返回视频URL');
      }

      onProgress?.call('下载视频中...', 90);
      final localPath = await _downloadVideo(videoUrl);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['error']?['message']?.toString() ??
                 responseBody['message']?.toString() ?? '';
      }
      if (statusCode == 401 || statusCode == 403) {
        throw Exception('Agnes AI鉴权失败：$detail');
      }
      throw Exception('Agnes Video生成失败($statusCode)：$detail');
    }
  }

  /// 自定义视频模型（OpenAI兼容接口）
  Future<String> _generateCustomVideo({
    required String imagePath,
    String? prompt,
    required String apiKey,
    required String baseUrl,
    void Function(String stage, int progress)? onProgress,
  }) async {
    onProgress?.call('上传图片中...', 5);
    final imageFile = File(imagePath);
    final imageBytes = await imageFile.readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final ext = imagePath.split('.').last.toLowerCase();
    final mimeType = ext == 'png' ? 'image/png' : 'image/jpeg';

    onProgress?.call('提交自定义视频任务...', 25);
    final requestBody = {
      'model': 'default',
      'messages': [
        {
          'role': 'user',
          'content': [
            {
              'type': 'image_url',
              'image_url': {'url': 'data:$mimeType;base64,$base64Image'},
            },
            if (prompt != null && prompt.isNotEmpty)
              {'type': 'text', 'text': prompt},
          ],
        }
      ],
    };

    try {
      final response = await _dio.post(
        '$baseUrl/chat/completions',
        data: jsonEncode(requestBody),
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(minutes: 10),
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices == null || choices.isEmpty) {
        throw Exception('自定义视频模型未返回结果');
      }
      final message = choices[0]['message'] as Map<String, dynamic>?;
      final content = message?['content'];
      String? videoUrl;
      if (content is List) {
        for (final item in content) {
          if (item is Map && (item['type'] == 'video_url' || item['type'] == 'video')) {
            videoUrl = item['video_url']?['url']?.toString() ?? item['url']?.toString();
            break;
          }
        }
      }
      if (videoUrl == null || videoUrl.isEmpty) {
        throw Exception('自定义视频模型未返回视频URL');
      }

      onProgress?.call('下载视频中...', 90);
      final localPath = await _downloadVideo(videoUrl);
      return localPath;
    } on DioException catch (e) {
      final statusCode = e.response?.statusCode;
      final responseBody = e.response?.data;
      String detail = '';
      if (responseBody is Map) {
        detail = responseBody['error']?['message']?.toString() ??
                 responseBody['message']?.toString() ?? '';
      }
      throw Exception('自定义视频生成失败($statusCode)：$detail');
    }
  }

  Future<void> _generateAll() async {
    // 全流程生成：内联各阶段逻辑，统一控制状态
    final allPendingShots = _shots.where((s) => s.status == 'pending' || s.status == 'failed').toList();

    setState(() {
      _isGenerating = true;
      _currentStage = 'image';
      _currentProcessingIndex = 0;
      _generateProgress = '全流程生成开始...';
    });

    try {
      // ===== 阶段1: 图片 =====
      if (allPendingShots.isNotEmpty && _drama != null) {
        try {
          final taskService = ref.read(dramaTaskServiceProvider);
          await taskService.batchGenerateImages(
            dramaId: widget.dramaId,
            episodeId: widget.episodeId,
            shots: allPendingShots,
            characters: _characters,
            drama: _drama!,
            maxRetries: _maxRetries,
            onProgress: (completed, total, currentShot, {int? shotId, String? status}) {
              if (mounted) {
                setState(() {
                  _generateProgress = '[图片 $completed/$total] $currentShot';
                  if (shotId != null) {
                    if (status == 'processing') {
                      _processingShotIds.add(shotId);
                    } else if (status == 'image_ready' || status == 'failed') {
                      _processingShotIds.remove(shotId);
                    }
                  }
                });
              }
            },
          );
          await _loadData();
        } catch (_) { /* 单阶段失败不中断 */ }
      }
      if (!mounted) return;

      // ===== 阶段2: 音频 =====
      setState(() {
        _currentStage = 'audio';
        _currentProcessingIndex = 0;
        _generateProgress = '开始生成音频...';
      });
      try {
        final ttsService = TtsService(ref.read(apiClientProvider));
        final needAudioShots = _shots
            .where((s) => s.dialogue.isNotEmpty && s.audioPath == null)
            .toList();
        for (int i = 0; i < needAudioShots.length; i++) {
          final shot = needAudioShots[i];
          final retryKey = '${shot.id}_audio';
          int retryCount = 0;
          bool audioSuccess = false;

          if (mounted) {
            setState(() {
              _currentProcessingIndex = _shots.indexWhere((s) => s.id == shot.id);
              _generateProgress = '[音频 ${i + 1}/${needAudioShots.length}] 镜头 #${shot.shotNumber}';
            });
          }

          for (int attempt = 0; attempt <= _maxRetries; attempt++) {
            try {
              if (attempt > 0) {
                retryCount = attempt;
                _shotRetryCounts[retryKey] = retryCount;
                if (mounted) {
                  setState(() {
                    _generateProgress = '[音频 ${i + 1}/${needAudioShots.length}] 镜头 #${shot.shotNumber} 重试 $attempt/$_maxRetries';
                  });
                }
                await Future.delayed(const Duration(seconds: 2));
              }

              final voiceInfo3 = await _getDramaVoice();
              final audioPath = await ttsService.synthesize(
                text: shot.dialogue,
                voiceId: voiceInfo3['voiceId'] ?? 'longanhuan',
                provider: voiceInfo3['provider'] ?? 'cosyvoice',
              );
              final updatedShot = shot.copyWith(
                audioPath: audioPath,
                status: shot.imagePath != null ? 'audio_ready' : 'pending',
              );
              await StorageUtil.updateShot(updatedShot);
              if (mounted) {
                setState(() {
                  final idx = _shots.indexWhere((s) => s.id == shot.id);
                  if (idx != -1) _shots[idx] = updatedShot;
                });
              }
              audioSuccess = true;
              break;
            } catch (_) {
              if (attempt >= _maxRetries) {
                _shotRetryCounts[retryKey] = _maxRetries + 1; // mark as fully failed
              }
            }
          }
          if (!audioSuccess && mounted) {
            setState(() {
              _generateProgress = '[音频 ${i + 1}/${needAudioShots.length}] 镜头 #${shot.shotNumber} 失败（已重试$_maxRetries次）';
            });
          }
        }
        await _loadData();
      } catch (_) { /* skip */ }
      if (!mounted) return;

      // ===== 阶段3: 视频 =====
      setState(() {
        _currentStage = 'video';
        _currentProcessingIndex = 0;
        _generateProgress = '开始生成视频...';
      });
      try {
        final readyShots = _shots
            .where((s) => s.imagePath != null && s.status != 'video_ready')
            .toList();
        for (int i = 0; i < readyShots.length; i++) {
          final shot = readyShots[i];
          final retryKey = '${shot.id}_video';
          bool videoSuccess = false;

          if (mounted) {
            setState(() {
              _currentProcessingIndex = _shots.indexWhere((s) => s.id == shot.id);
              _generateProgress = '[视频 ${i + 1}/${readyShots.length}] 镜头 #${shot.shotNumber}';
            });
          }

          for (int attempt = 0; attempt <= _maxRetries; attempt++) {
            try {
              if (attempt > 0) {
                _shotRetryCounts[retryKey] = attempt;
                if (mounted) {
                  setState(() {
                    _generateProgress = '[视频 ${i + 1}/${readyShots.length}] 镜头 #${shot.shotNumber} 重试 $attempt/$_maxRetries';
                  });
                }
                await Future.delayed(const Duration(seconds: 2));
              }

              final videoPath = await _generateVideoForShot(
                imagePath: shot.imagePath!,
                audioPath: shot.audioPath,
                prompt: shot.visualDescription,
              );
              final updatedShot = shot.copyWith(videoPath: videoPath, status: 'video_ready');
              await StorageUtil.updateShot(updatedShot);
              if (mounted) {
                setState(() {
                  final idx = _shots.indexWhere((s) => s.id == shot.id);
                  if (idx != -1) _shots[idx] = updatedShot;
                });
              }
              videoSuccess = true;
              break;
            } catch (_) {
              if (attempt >= _maxRetries) {
                _shotRetryCounts[retryKey] = _maxRetries + 1; // mark as fully failed
              }
            }
          }
          if (!videoSuccess && mounted) {
            setState(() {
              _generateProgress = '[视频 ${i + 1}/${readyShots.length}] 镜头 #${shot.shotNumber} 失败（已重试$_maxRetries次）';
            });
          }
        }
        await _loadData();
      } catch (_) { /* skip */ }

      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('全流程生成完成！')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成异常：$e')),
        );
      }
    }
  }

  /// 根据镜头关联的角色ID构建角色描述
  String _buildCharacterDescForShot(DramaShot shot, List<DramaCharacter> characters) {
    if (shot.characterIds.isEmpty || characters.isEmpty) {
      return '';
    }
    final charIds = shot.characterIdList;
    final descParts = <String>[];
    for (final charId in charIds) {
      try {
        final character = characters.firstWhere((c) => c.id == charId);
        if (character.description.isNotEmpty) {
          descParts.add('${character.name}: ${character.description}');
        }
      } catch (_) {}
    }
    return descParts.join('; ');
  }

  /// 手动重试单个失败镜头的生成
  Future<void> _retrySingleShot(DramaShot shot) async {
    if (_isGenerating) return;

    setState(() {
      _isGenerating = true;
      _currentProcessingIndex = _shots.indexWhere((s) => s.id == shot.id);
    });

    try {
      // 根据当前状态决定需要重试的阶段
      final needsImage = shot.imagePath == null || shot.status == 'failed';
      final needsAudio = shot.dialogue.isNotEmpty && shot.audioPath == null;
      final needsVideo = shot.imagePath != null && shot.status != 'video_ready';

      if (needsImage && _drama != null) {
        setState(() {
          _currentStage = 'image';
          _generateProgress = '重试图片: 镜头 #${shot.shotNumber}';
        });
        final config = _drama!.parsedModelConfig;
        final imageService = ImageGenService();
        final enhancedPrompt = ImageGenService.enhancePrompt(
          shot.visualDescription,
          _drama!.style,
          _buildCharacterDescForShot(shot, _characters),
        );
        final size = ImageGenService.parseAspectRatio(_drama!.aspectRatio);
        bool success = false;
        for (int attempt = 0; attempt <= _maxRetries; attempt++) {
          try {
            if (attempt > 0) {
              _shotRetryCounts['${shot.id}_image'] = attempt;
              setState(() {
                _generateProgress = '重试图片: 镜头 #${shot.shotNumber} (第$attempt次)';
              });
              await Future.delayed(const Duration(seconds: 2));
            }
            final imagePath = await imageService.generateImage(
              prompt: enhancedPrompt,
              width: size['width']!,
              height: size['height']!,
              model: config.imageModel,
              customApiKey: config.imageApiKey.isNotEmpty ? config.imageApiKey : null,
              customBaseUrl: config.imageBaseUrl.isNotEmpty ? config.imageBaseUrl : null,
            );
            var updated = shot.copyWith(imagePath: imagePath, promptEnhanced: enhancedPrompt, status: 'image_ready');
            await StorageUtil.updateShot(updated);
            if (mounted) setState(() {
              final idx = _shots.indexWhere((s) => s.id == shot.id);
              if (idx != -1) _shots[idx] = updated;
              shot = updated;
            });
            success = true;
            break;
          } catch (_) {
            if (attempt >= _maxRetries) {
              _shotRetryCounts['${shot.id}_image'] = _maxRetries + 1;
            }
          }
        }
        if (!success) {
          if (mounted) setState(() {
            _isGenerating = false;
            _currentStage = '';
            _currentProcessingIndex = -1;
          });
          return;
        }
      }

      if (needsAudio) {
        setState(() {
          _currentStage = 'audio';
          _generateProgress = '重试音频: 镜头 #${shot.shotNumber}';
        });
        final ttsService = TtsService(ref.read(apiClientProvider));
        bool success = false;
        for (int attempt = 0; attempt <= _maxRetries; attempt++) {
          try {
            if (attempt > 0) {
              _shotRetryCounts['${shot.id}_audio'] = attempt;
              setState(() {
                _generateProgress = '重试音频: 镜头 #${shot.shotNumber} (第$attempt次)';
              });
              await Future.delayed(const Duration(seconds: 2));
            }
            final voiceInfo4 = await _getDramaVoice();
            final audioPath = await ttsService.synthesize(
              text: shot.dialogue,
              voiceId: voiceInfo4['voiceId'] ?? 'longanhuan',
              provider: voiceInfo4['provider'] ?? 'cosyvoice',
            );
            var updated = shot.copyWith(audioPath: audioPath, status: shot.imagePath != null ? 'audio_ready' : 'pending');
            await StorageUtil.updateShot(updated);
            if (mounted) setState(() {
              final idx = _shots.indexWhere((s) => s.id == shot.id);
              if (idx != -1) _shots[idx] = updated;
              shot = updated;
            });
            success = true;
            break;
          } catch (_) {
            if (attempt >= _maxRetries) {
              _shotRetryCounts['${shot.id}_audio'] = _maxRetries + 1;
            }
          }
        }
        if (!success) {
          if (mounted) setState(() {
            _isGenerating = false;
            _currentStage = '';
            _currentProcessingIndex = -1;
          });
          return;
        }
      }

      if (needsVideo && shot.imagePath != null) {
        setState(() {
          _currentStage = 'video';
          _generateProgress = '重试视频: 镜头 #${shot.shotNumber}';
        });
        bool success = false;
        for (int attempt = 0; attempt <= _maxRetries; attempt++) {
          try {
            if (attempt > 0) {
              _shotRetryCounts['${shot.id}_video'] = attempt;
              setState(() {
                _generateProgress = '重试视频: 镜头 #${shot.shotNumber} (第$attempt次)';
              });
              await Future.delayed(const Duration(seconds: 2));
            }
            final videoPath = await _generateVideoForShot(
              imagePath: shot.imagePath!,
              audioPath: shot.audioPath,
              prompt: shot.visualDescription,
            );
            var updated = shot.copyWith(videoPath: videoPath, status: 'video_ready');
            await StorageUtil.updateShot(updated);
            if (mounted) setState(() {
              final idx = _shots.indexWhere((s) => s.id == shot.id);
              if (idx != -1) _shots[idx] = updated;
            });
            success = true;
            break;
          } catch (_) {
            if (attempt >= _maxRetries) {
              _shotRetryCounts['${shot.id}_video'] = _maxRetries + 1;
            }
          }
        }
        if (!success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('镜头 #${shot.shotNumber} 重试失败，已尝试$_maxRetries次')),
          );
        }
      }

      await _loadData();
    } catch (e) {
      // ignore
    } finally {
      if (mounted) {
        setState(() {
          _isGenerating = false;
          _currentStage = '';
          _currentProcessingIndex = -1;
        });
      }
    }
  }

  Future<void> _generateSingleShot(DramaShot shot, String action) async {
    try {
      if (action == 'image') {
        final imageService = ImageGenService();
        final aspectRatio = _drama?.aspectRatio ?? '16:9';
        final dimensions = ImageGenService.parseAspectRatio(aspectRatio);

        final enhancedPrompt = DramaService.enhanceShotPrompt(
          shot: shot,
          characters: _characters,
          style: _drama?.style ?? 'anime',
        );

        // 使用项目的模型配置
        final config = _drama?.parsedModelConfig ?? DramaModelConfig();

        final imagePath = await imageService.generateImage(
          prompt: enhancedPrompt,
          width: dimensions['width']!,
          height: dimensions['height']!,
          model: config.imageModel,
          customApiKey: config.imageApiKey.isNotEmpty ? config.imageApiKey : null,
          customBaseUrl: config.imageBaseUrl.isNotEmpty ? config.imageBaseUrl : null,
        );

        final updatedShot = shot.copyWith(
          imagePath: imagePath,
          status: 'image_ready',
          promptEnhanced: enhancedPrompt,
        );
        await StorageUtil.updateShot(updatedShot);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('图片生成成功')),
          );
        }
      } else if (action == 'audio') {
        final ttsService = TtsService(ref.read(apiClientProvider));

        final voiceInfo5 = await _getDramaVoice();
        final audioPath = await ttsService.synthesize(
          text: shot.dialogue,
          voiceId: voiceInfo5['voiceId'] ?? 'longanhuan',
          provider: voiceInfo5['provider'] ?? 'cosyvoice',
        );

        final updatedShot = shot.copyWith(
          audioPath: audioPath,
          status: shot.imagePath != null ? 'audio_ready' : 'pending',
        );
        await StorageUtil.updateShot(updatedShot);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('音频生成成功')),
          );
        }
      } else if (action == 'video') {
        if (shot.imagePath == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('请先生成图片')),
          );
          return;
        }

        final videoPath = await _generateVideoForShot(
          imagePath: shot.imagePath!,
          audioPath: shot.audioPath,
          prompt: shot.visualDescription,
        );

        final updatedShot = shot.copyWith(
          videoPath: videoPath,
          status: 'video_ready',
        );
        await StorageUtil.updateShot(updatedShot);
        await _loadData();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('视频生成成功')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('生成失败：$e')),
        );
      }
    }
  }

  void _showShotDetailDialog(DramaShot shot) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getStatusColor(shot.status).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '镜头${shot.shotNumber}',
                style: TextStyle(
                  fontSize: 14,
                  color: _getStatusColor(shot.status),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                shot.statusDisplayName,
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (shot.imagePath != null && shot.imagePath!.isNotEmpty) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(
                    File(shot.imagePath!),
                    fit: BoxFit.cover,
                    width: double.infinity,
                    height: 200,
                    errorBuilder: (_, __, ___) => Container(
                      height: 200,
                      color: AppTheme.darkSurface,
                      child: const Center(
                        child: Icon(Icons.broken_image, size: 48),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                Container(
                  height: 150,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: AppTheme.darkSurface,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.image_outlined,
                      size: 48,
                      color: AppTheme.textHint,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              const Text(
                '画面描述',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textHint,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(shot.visualDescription),
              if (shot.dialogue.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text(
                  '台词',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(shot.dialogue),
              ],
              if (shot.cameraDirection?.isNotEmpty == true) ...[
                const SizedBox(height: 12),
                const Text(
                  '运镜',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textHint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(shot.cameraDirection!),
              ],
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (shot.status == 'pending' || shot.status == 'failed')
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _generateSingleShot(shot, 'image');
                      },
                      icon: const Icon(Icons.image, size: 16),
                      label: const Text('生成图片'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                      ),
                    ),
                  if (shot.dialogue.isNotEmpty &&
                      (shot.status == 'pending' ||
                          shot.status == 'image_ready' ||
                          shot.status == 'failed'))
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _generateSingleShot(shot, 'audio');
                      },
                      icon: const Icon(Icons.audiotrack, size: 16),
                      label: const Text('生成音频'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6B9D),
                      ),
                    ),
                  if (shot.imagePath != null && shot.status != 'video_ready')
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _generateSingleShot(shot, 'video');
                      },
                      icon: const Icon(Icons.videocam, size: 16),
                      label: const Text('生成视频'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.safeColor,
                      ),
                    ),
                ],
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

  Color _getStatusColor(String status) {
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

  // ==================== 模型设置 ====================

  void _showModelSettings() {
    final config = _drama?.parsedModelConfig ?? DramaModelConfig();
    String selectedText = config.textModel;
    String selectedImage = config.imageModel;
    String selectedVideo = config.videoModel;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppTheme.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔧 模型设置',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      '切换模型可解决持续生成失败的问题',
                      style: TextStyle(fontSize: 12, color: AppTheme.textHint),
                    ),
                    const SizedBox(height: 16),
                    // 文本模型
                    _buildModelDropdown(
                      title: '📝 文本模型',
                      subtitle: '分镜文案生成、改写',
                      selected: selectedText,
                      models: _textModels,
                      onChanged: (v) => setSheetState(() => selectedText = v),
                    ),
                    const SizedBox(height: 12),
                    // 图片模型
                    _buildModelDropdown(
                      title: '🖼️ 图片模型',
                      subtitle: '镜头画面生成',
                      selected: selectedImage,
                      models: _imageModels,
                      onChanged: (v) => setSheetState(() => selectedImage = v),
                    ),
                    const SizedBox(height: 12),
                    // 视频模型
                    _buildModelDropdown(
                      title: '🎬 视频模型',
                      subtitle: '镜头视频生成',
                      selected: selectedVideo,
                      models: _videoModels,
                      onChanged: (v) => setSheetState(() => selectedVideo = v),
                    ),
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          _saveModelConfig(selectedText, selectedImage, selectedVideo);
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppTheme.primaryColor,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('保存设置', style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildModelDropdown({
    required String title,
    required String subtitle,
    required String selected,
    required List<Map<String, String>> models,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.darkBg,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          Text(subtitle, style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            dropdownColor: AppTheme.darkSurface,
            style: const TextStyle(fontSize: 14),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              filled: true,
              fillColor: AppTheme.darkSurface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: AppTheme.border.withOpacity(0.3)),
              ),
            ),
            items: models.map((m) {
              return DropdownMenuItem(
                value: m['value'],
                child: Text(m['label']!, style: const TextStyle(fontSize: 13)),
              );
            }).toList(),
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _saveModelConfig(String textModel, String imageModel, String videoModel) async {
    if (_drama == null) return;
    try {
      final drama = _drama!;
      final config = drama.parsedModelConfig;
      final newConfig = config.copyWith(
        textModel: textModel,
        imageModel: imageModel,
        videoModel: videoModel,
      );
      final updatedDrama = drama.copyWith(modelConfig: jsonEncode(newConfig.toJson()));
      await StorageUtil.updateDrama(updatedDrama);
      setState(() {
        _drama = updatedDrama;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('模型已切换：文本=${_getModelLabel(textModel)}, 图片=${_getModelLabel(imageModel)}, 视频=${_getModelLabel(videoModel)}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败：$e')),
        );
      }
    }
  }

  String _getModelLabel(String value) {
    final allModels = [..._textModels, ..._imageModels, ..._videoModels];
    final found = allModels.firstWhere((m) => m['value'] == value, orElse: () => {'value': value, 'label': value});
    return found['label'] ?? value;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_episode?.title ?? '分镜工作台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '模型设置',
            onPressed: _isGenerating ? null : _showModelSettings,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 中断任务提示条
                if (_hasInterruptedTasks && !_isGenerating)
                  _buildInterruptedBanner(),
                if (_isGenerating) _buildPipelineView(),
                Expanded(child: _buildShotGrid()),
                if (!_isGenerating && _generateProgress.isNotEmpty) _buildProgressBar(),
                _buildBottomBar(),
              ],
            ),
    );
  }

  Widget _buildInterruptedBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFFFF6B9D).withOpacity(0.15),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFFF6B9D)),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              '检测到未完成的任务，点击恢复',
              style: TextStyle(fontSize: 13, color: Color(0xFFFF6B9D)),
            ),
          ),
          TextButton(
            onPressed: _resumeInterruptTasks,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text(
              '恢复',
              style: TextStyle(
                color: Color(0xFFFF6B9D),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShotGrid() {
    if (_shots.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.image_not_supported, size: 64, color: AppTheme.textHint),
            SizedBox(height: 16),
            Text(
              '暂无镜头',
              style: TextStyle(color: AppTheme.textHint),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 0.75,
      ),
      itemCount: _shots.length,
      itemBuilder: (context, index) {
        final shot = _shots[index];
        return _buildShotCard(shot, index);
      },
    );
  }

  Widget _buildShotCard(DramaShot shot, int index) {
    // 并行处理：shot.id 在 _processingShotIds 中就高亮（最多3张同时显示"正在生成"）
    final isProcessing = shot.id != null && _processingShotIds.contains(shot.id);
    final hasImage =
        shot.imagePath != null && File(shot.imagePath!).existsSync();
    final isFailed = shot.status == 'failed';
    final imgRetryKey = '${shot.id}_image';
    final audioRetryKey = '${shot.id}_audio';
    final videoRetryKey = '${shot.id}_video';
    final imgRetries = _shotRetryCounts[imgRetryKey] ?? 0;
    final audioRetries = _shotRetryCounts[audioRetryKey] ?? 0;
    final videoRetries = _shotRetryCounts[videoRetryKey] ?? 0;
    final totalRetries = imgRetries + audioRetries + videoRetries;

    Color borderColor;
    if (isProcessing) {
      borderColor = const Color(0xFFFF6B9D); // 粉色：正在处理
    } else if (isFailed && totalRetries > _maxRetries) {
      borderColor = Colors.red; // 红色：彻底失败
    } else if (isFailed) {
      borderColor = Colors.orange; // 橙色：失败但可重试
    } else {
      borderColor = Colors.transparent;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: borderColor, width: 2),
      ),
      child: InkWell(
        onTap: () => _showShotDetailDialog(shot),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 缩略图
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (hasImage)
                    Image.file(
                      File(shot.imagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildPlaceholder(),
                    )
                  else
                    _buildPlaceholder(),
                  // ===== 可视化：正在生成时显示转圈动画 =====
                  if (isProcessing)
                    Container(
                      color: Colors.black.withOpacity(0.55),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 36,
                              height: 36,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFF6B9D)),
                              ),
                            ),
                            SizedBox(height: 6),
                            Text(
                              '生成中...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // 状态标签
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: _getStatusColor(shot.status),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        shot.statusDisplayName,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  // 镜头序号
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(
                          '${shot.shotNumber}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  // 重试次数标记
                  if (totalRetries > 0)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: totalRetries > _maxRetries ? Colors.red : Colors.orange,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.refresh, size: 10, color: Colors.white),
                            const SizedBox(width: 2),
                            Text(
                              '${totalRetries > _maxRetries ? _maxRetries : totalRetries}/$_maxRetries',
                              style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // 描述 + 重试按钮
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      shot.visualDescription,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (shot.dialogue.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.format_quote,
                            size: 12,
                            color: AppTheme.textHint,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              shot.dialogue,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTheme.textHint,
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    // 手动重试按钮
                    if (isFailed && !_isGenerating)
                      Align(
                        alignment: Alignment.bottomRight,
                        child: GestureDetector(
                          onTap: () => _retrySingleShot(shot),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF6B9D),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.refresh, size: 11, color: Colors.white),
                                SizedBox(width: 3),
                                Text('重试', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600)),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppTheme.darkSurface,
      child: const Center(
        child: Icon(
          Icons.image_outlined,
          size: 32,
          color: AppTheme.textHint,
        ),
      ),
    );
  }

  Widget _buildPipelineView() {
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.darkSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 阶段步骤条
          Row(
            children: [
              _buildPipelineStep('图片生成', Icons.image, _currentStage == 'image',
                  _currentStage == 'audio' || _currentStage == 'video'),
              _buildPipelineArrow(),
              _buildPipelineStep('音频生成', Icons.audiotrack, _currentStage == 'audio',
                  _currentStage == 'video'),
              _buildPipelineArrow(),
              _buildPipelineStep('视频生成', Icons.videocam, _currentStage == 'video', false),
            ],
          ),
          const SizedBox(height: 12),
          // 进度条
          LinearProgressIndicator(
            value: _shots.isEmpty ? 0 : _getCompletedCount() / _shots.length,
            backgroundColor: Colors.grey[800],
            valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B9D)),
          ),
          const SizedBox(height: 8),
          // 当前处理信息
          Row(
            children: [
              const SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF6B9D)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _generateProgress,
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${_getCompletedCount()}/${_shots.length}',
                style: const TextStyle(fontSize: 12, color: AppTheme.textHint),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineStep(String label, IconData icon, bool isActive, bool isCompleted) {
    final color = isActive
        ? const Color(0xFFFF6B9D)
        : isCompleted
            ? AppTheme.primaryColor
            : AppTheme.textHint;
    return Expanded(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isCompleted ? AppTheme.primaryColor.withOpacity(0.2) : Colors.transparent,
              border: Border.all(color: color, width: 1.5),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPipelineArrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 2),
      child: Icon(Icons.arrow_forward, size: 16, color: AppTheme.textHint),
    );
  }

  int _getCompletedCount() {
    return _shots.where((s) =>
        s.status == 'image_ready' ||
        s.status == 'audio_ready' ||
        s.status == 'video_ready').length;
  }

  Widget _buildProgressBar() {
    // 从进度文本中解析 [completed/total] 数字
    final match = RegExp(r'\[(\d+)/(\d+)\]').firstMatch(_generateProgress);
    final completed = match != null ? int.tryParse(match.group(1) ?? '0') ?? 0 : 0;
    final total = match != null ? int.tryParse(match.group(2) ?? '1') ?? 1 : 1;
    final percent = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
    final activeCount = _processingShotIds.length;

    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.darkSurface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 进度条 + 百分比
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: percent,
                    minHeight: 8,
                    backgroundColor: AppTheme.textHint.withOpacity(0.2),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFFF6B9D)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${(percent * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFF6B9D),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // 并行度指示
          if (activeCount > 0)
            Row(
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFA86B)),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$activeCount 张同时生成中',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFFFFA86B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          if (activeCount > 0) const SizedBox(height: 4),
          // 状态文本
          Text(
            _generateProgress,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final pendingCount = _shots.where((s) => s.status == 'pending' || s.status == 'failed').length;
    final imageReadyCount =
        _shots.where((s) => s.imagePath != null && s.status != 'video_ready').length;
    final allReadyCount = _shots.where((s) => s.status != 'video_ready').length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.darkSurface,
        border: Border(
          top: BorderSide(color: Color(0xFF2A2A4A)),
        ),
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _isGenerating || pendingCount == 0
                    ? null
                    : _generateImages,
                icon: const Icon(Icons.image, size: 18),
                label: Text('生成图片($pendingCount)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primaryColor,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isGenerating || imageReadyCount == 0 ? null : _generateVideos,
                icon: const Icon(Icons.videocam, size: 18),
                label: Text('生成视频($imageReadyCount)'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6B9D),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                onPressed:
                    _isGenerating || allReadyCount == 0 ? null : _generateAll,
                icon: const Icon(Icons.auto_awesome, size: 18),
                label: const Text('全部生成'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.safeColor,
                ),
              ),
            ),
            if (_hasInterruptedTasks) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 48,
                child: ElevatedButton(
                  onPressed: _isGenerating ? null : _resumeInterruptTasks,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B9D).withOpacity(0.7),
                    padding: EdgeInsets.zero,
                  ),
                  child: const Icon(Icons.replay, size: 20),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
