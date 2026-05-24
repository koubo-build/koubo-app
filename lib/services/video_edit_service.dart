import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import '../utils/storage_util.dart';

/// 视频混剪服务 - 搜索素材、获取音乐、合成视频
class VideoEditService {
  final ApiClient _apiClient;

  VideoEditService(this._apiClient);

  /// 搜索Pexels视频素材
  /// [keyword] 搜索关键词
  /// 返回List<Map>，每项含 id/thumbnail/url/duration
  Future<List<Map<String, dynamic>>> searchPexelsVideos(String keyword) async {
    if (keyword.trim().isEmpty) return [];

    try {
      // 优先调用后端代理接口（后端携带Pexels API Key）
      final baseUrl = await _getBackendBaseUrl();
      if (baseUrl != null) {
        final response = await _apiClient.get(
          '$baseUrl/api/video-edit/pexels/search',
          queryParameters: {'keyword': keyword},
        );
        final data = response.data as Map<String, dynamic>;
        final list = data['data'] as List<dynamic>? ?? [];
        return list.map((item) {
          final v = item as Map<String, dynamic>;
          return {
            'id': v['id'] ?? '',
            'thumbnail': v['thumbnail'] ?? v['image'] ?? '',
            'url': v['url'] ?? v['video_url'] ?? '',
            'duration': v['duration'] ?? 0,
          };
        }).toList();
      }

      // 兜底：返回模拟数据
      return _getMockPexelsResults(keyword);
    } catch (e) {
      // 接口异常时返回模拟数据
      return _getMockPexelsResults(keyword);
    }
  }

  /// 获取背景音乐列表
  /// [category] 音乐类别：tech/emotional/suspense
  /// 返回本地模拟数据
  Future<List<Map<String, dynamic>>> getMusicList(String category) async {
    // 模拟音乐数据
    final musicMap = {
      'tech': [
        {'id': 'tech_1', 'name': '科技前沿', 'duration': '2:30', 'category': 'tech'},
        {'id': 'tech_2', 'name': '数字浪潮', 'duration': '3:15', 'category': 'tech'},
        {'id': 'tech_3', 'name': '未来之声', 'duration': '1:58', 'category': 'tech'},
        {'id': 'tech_4', 'name': 'AI脉搏', 'duration': '2:45', 'category': 'tech'},
      ],
      'emotional': [
        {'id': 'emo_1', 'name': '温暖时光', 'duration': '3:00', 'category': 'emotional'},
        {'id': 'emo_2', 'name': '心灵共鸣', 'duration': '2:40', 'category': 'emotional'},
        {'id': 'emo_3', 'name': '岁月静好', 'duration': '3:20', 'category': 'emotional'},
        {'id': 'emo_4', 'name': '柔情似水', 'duration': '2:15', 'category': 'emotional'},
      ],
      'suspense': [
        {'id': 'sus_1', 'name': '暗夜追踪', 'duration': '2:50', 'category': 'suspense'},
        {'id': 'sus_2', 'name': '迷雾重重', 'duration': '3:10', 'category': 'suspense'},
        {'id': 'sus_3', 'name': '悬疑时刻', 'duration': '2:20', 'category': 'suspense'},
        {'id': 'sus_4', 'name': '未知领域', 'duration': '2:55', 'category': 'suspense'},
      ],
    };

    return musicMap[category] ?? [];
  }

  /// 合成视频
  /// 调用后端 /api/video-edit/mix 合成视频
  Future<Map<String, dynamic>> composeVideo({
    required String script,
    required String faceVideoPath,
    required String style,
    String? bgVideoUrl,
    String? bgMusicId,
    Map<String, dynamic>? subtitleSettings,
  }) async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) {
      throw Exception('请先在设置页配置后端地址');
    }

    try {
      final response = await _apiClient.post(
        '$baseUrl/api/video-edit/mix',
        data: {
          'script': script,
          'face_video_path': faceVideoPath,
          'style': style,
          if (bgVideoUrl != null) 'bg_video_url': bgVideoUrl,
          if (bgMusicId != null) 'bg_music_id': bgMusicId,
          if (subtitleSettings != null) 'subtitle_settings': subtitleSettings,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return {
        'video_path': data['video_path'] ?? data['data']?['video_path'] ?? '',
        'duration': data['duration'] ?? data['data']?['duration'] ?? 0,
      };
    } catch (e) {
      throw Exception('视频合成失败：$e');
    }
  }

  /// 获取后端基础地址
  Future<String?> _getBackendBaseUrl() async {
    try {
      final url = StorageUtil.getString('backend_base_url');
      return (url != null && url.isNotEmpty) ? url : null;
    } catch (_) {
      return null;
    }
  }

  /// 生成模拟Pexels搜索结果
  List<Map<String, dynamic>> _getMockPexelsResults(String keyword) {
    return List.generate(6, (index) {
      return {
        'id': 'mock_${keyword}_$index',
        'thumbnail': '',
        'url': '',
        'duration': (index + 1) * 15,
      };
    });
  }
}

/// VideoEditService的Riverpod Provider
final videoEditServiceProvider = Provider<VideoEditService>((ref) {
  return VideoEditService(ref.read(apiClientProvider));
});
