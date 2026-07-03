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
  int _currentProcessingIndex = -1;
  String _currentStage = '';
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
    });

    try {
      final taskService = ref.read(dramaTaskServiceProvider);

      await taskService.batchGenerateImages(
        dramaId: widget.dramaId,
        episodeId: widget.episodeId,
        shots: pendingShots,
        characters: _characters,
        drama: _drama!,
        onProgress: (completed, total, currentShot) {
          if (mounted) {
            setState(() {
              _generateProgress = '[$completed/$total] $currentShot';
              _currentProcessingIndex = completed < total ? completed : -1;
            });
          }
        },
      );

      // 重新加载数据
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
          final audioPath = await ttsService.synthesize(
            text: shot.dialogue,
            voiceId: 'longanhuan',
            provider: 'cosyvoice',
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
          String videoPath;

          if (shot.audioPath != null && shot.audioPath!.isNotEmpty) {
            videoPath = await _generateVideoWithAudio(
              imagePath: shot.imagePath!,
              audioPath: shot.audioPath!,
              prompt: shot.visualDescription,
            );
          } else {
            videoPath = await _generateHappyHorseVideo(
              imagePath: shot.imagePath!,
              prompt: shot.visualDescription,
            );
          }

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
            onProgress: (completed, total, currentShot) {
              if (mounted) {
                setState(() {
                  _generateProgress = '[图片 $completed/$total] $currentShot';
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

              final audioPath = await ttsService.synthesize(
                text: shot.dialogue,
                voiceId: 'longanhuan',
                provider: 'cosyvoice',
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

              String videoPath;
              if (shot.audioPath != null && shot.audioPath!.isNotEmpty) {
                videoPath = await _generateVideoWithAudio(
                  imagePath: shot.imagePath!,
                  audioPath: shot.audioPath!,
                  prompt: shot.visualDescription,
                );
              } else {
                videoPath = await _generateHappyHorseVideo(
                  imagePath: shot.imagePath!,
                  prompt: shot.visualDescription,
                );
              }
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
            final audioPath = await ttsService.synthesize(
              text: shot.dialogue,
              voiceId: 'longanhuan',
              provider: 'cosyvoice',
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
            String videoPath;
            if (shot.audioPath != null && shot.audioPath!.isNotEmpty) {
              videoPath = await _generateVideoWithAudio(
                imagePath: shot.imagePath!,
                audioPath: shot.audioPath!,
                prompt: shot.visualDescription,
              );
            } else {
              videoPath = await _generateHappyHorseVideo(
                imagePath: shot.imagePath!,
                prompt: shot.visualDescription,
              );
            }
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

        final audioPath = await ttsService.synthesize(
          text: shot.dialogue,
          voiceId: 'longanhuan',
          provider: 'cosyvoice',
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

        String videoPath;

        if (shot.audioPath != null) {
          videoPath = await _generateVideoWithAudio(
            imagePath: shot.imagePath!,
            audioPath: shot.audioPath!,
            prompt: shot.visualDescription,
          );
        } else {
          videoPath = await _generateHappyHorseVideo(
            imagePath: shot.imagePath!,
            prompt: shot.visualDescription,
          );
        }

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_episode?.title ?? '分镜工作台'),
        actions: [
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
    final isProcessing = index == _currentProcessingIndex && _isGenerating;
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
    return Container(
      padding: const EdgeInsets.all(12),
      color: AppTheme.darkSurface,
      child: Column(
        children: [
          const LinearProgressIndicator(),
          const SizedBox(height: 8),
          Text(
            _generateProgress,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
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
