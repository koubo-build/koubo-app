import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'api_client.dart';
import '../utils/storage_util.dart';

/// 发布服务 - 封面生成、多平台发布
class PublishService {
  final ApiClient _apiClient;

  PublishService(this._apiClient);

  /// 生成封面图
  /// [title] 封面标题
  /// [keywords] 关键词列表
  /// [style] 风格：tech/emotional/suspense
  /// 返回封面路径
  Future<String> generateCover({
    required String title,
    required List<String> keywords,
    required String style,
  }) async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) {
      throw Exception('请先在设置页配置后端地址');
    }

    try {
      final response = await _apiClient.post(
        '$baseUrl/api/publish/cover/generate',
        data: {
          'title': title,
          'keywords': keywords,
          'style': style,
        },
      );

      final data = response.data as Map<String, dynamic>;
      final coverPath = data['cover_path'] ?? data['data']?['cover_path'] ?? '';
      if (coverPath.isEmpty) {
        throw Exception('封面生成失败，未返回封面路径');
      }
      return coverPath;
    } catch (e) {
      throw Exception('封面生成失败：$e');
    }
  }

  /// 一键发布到多平台
  /// [videoPath] 视频路径
  /// [title] 标题
  /// [coverPath] 封面路径
  /// [platforms] 发布平台列表（douyin/xiaohongshu/bilibili）
  /// [description] 描述
  /// [tags] 标签列表
  /// 返回每个平台的发布结果
  Future<Map<String, dynamic>> publishToPlatforms({
    required String videoPath,
    required String title,
    required String coverPath,
    required List<String> platforms,
    String? description,
    List<String>? tags,
  }) async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) {
      throw Exception('请先在设置页配置后端地址');
    }

    try {
      final response = await _apiClient.post(
        '$baseUrl/api/publish/multi-platform',
        data: {
          'video_path': videoPath,
          'title': title,
          'cover_path': coverPath,
          'platforms': platforms,
          if (description != null) 'description': description,
          if (tags != null) 'tags': tags,
        },
      );

      final data = response.data as Map<String, dynamic>;
      return data['results'] ?? data['data'] ?? {};
    } catch (e) {
      throw Exception('发布失败：$e');
    }
  }

  /// 获取已绑定平台账号列表
  Future<List<Map<String, dynamic>>> getAccounts() async {
    final baseUrl = await _getBackendBaseUrl();
    if (baseUrl == null) return [];

    try {
      final response = await _apiClient.get(
        '$baseUrl/api/publish/accounts',
      );

      final data = response.data as Map<String, dynamic>;
      final list = data['data'] as List<dynamic>? ?? [];
      return list.map((item) {
        final a = item as Map<String, dynamic>;
        return {
          'platform': a['platform'] ?? '',
          'username': a['username'] ?? '',
          'avatar': a['avatar'] ?? '',
          'status': a['status'] ?? 'unbound',
        };
      }).toList();
    } catch (e) {
      return [];
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
}

/// PublishService的Riverpod Provider
final publishServiceProvider = Provider<PublishService>((ref) {
  return PublishService(ref.read(apiClientProvider));
});
