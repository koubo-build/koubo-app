import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../config/api_config.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// 视频文案提取服务 - 支持抖音/快手等多平台链接
/// 优化版：更完善的链接识别、友好的错误提示、多平台支持
class DouyinService {
  final ApiClient _apiClient;

  DouyinService(this._apiClient);

  // ==================== 平台类型 ====================

  /// 支持的平台列表
  static const List<String> supportedPlatforms = ['抖音', '快手'];

  // ==================== 核心方法 ====================

  /// 从视频链接提取文案
  /// [url] 视频分享链接，支持抖音/快手
  /// 返回提取的文案文本
  Future<String> extractScript(String url) async {
    final trimmedUrl = url.trim();
    if (trimmedUrl.isEmpty) {
      throw ExtractException('请输入视频链接', ExtractErrorType.emptyUrl);
    }

    // 自动识别平台
    final platform = identifyPlatform(trimmedUrl);
    if (platform == null) {
      throw ExtractException(
        '无法识别链接平台，目前支持抖音和快手链接\n请确认粘贴的是完整的分享链接',
        ExtractErrorType.unsupportedPlatform,
      );
    }

    // 1. 先尝试自建解析
    try {
      final result = await _selfParseExtract(trimmedUrl, platform);
      if (result.isNotEmpty) return result;
    } on ExtractException {
      rethrow; // 已知错误直接抛出
    } catch (e) {
      // 自建解析失败，继续尝试第三方
    }

    // 2. 回退到第三方API
    try {
      final result = await _thirdPartyExtract(trimmedUrl);
      if (result.isNotEmpty) return result;
    } on ExtractException {
      rethrow;
    } catch (e) {
      // 第三方API也失败
    }

    throw ExtractException(
      '文案提取失败，请检查：\n1. 链接是否正确且未过期\n2. 视频是否包含语音内容\n3. 稍后重试',
      ExtractErrorType.extractFailed,
    );
  }

  /// 识别链接所属平台
  /// 返回平台名称（抖音/快手），无法识别返回null
  String? identifyPlatform(String url) {
    final trimmedUrl = url.trim();

    // 抖音链接格式
    if (_isDouyinUrl(trimmedUrl)) return '抖音';

    // 快手链接格式
    if (_isKuaishouUrl(trimmedUrl)) return '快手';

    return null;
  }

  /// 验证链接格式是否合法
  bool isValidUrl(String url) {
    final trimmedUrl = url.trim();
    return _isDouyinUrl(trimmedUrl) || _isKuaishouUrl(trimmedUrl);
  }

  // ==================== 链接格式识别（增强版） ====================

  /// 判断是否为抖音链接
  bool _isDouyinUrl(String url) {
    final patterns = [
      RegExp(r'^https?://v\.douyin\.com/\w+'),              // 短链接
      RegExp(r'^https?://v\.douyin\.com/\w+/'),             // 短链接带斜杠
      RegExp(r'^https?://www\.douyin\.com/video/\d+'),      // 完整链接
      RegExp(r'^https?://www\.iesdouyin\.com/'),            // 旧域名
      RegExp(r'^https?://www\.douyin\.com/user/'),          // 用户主页
      RegExp(r'^https?://www\.douyin\.com/note/'),          // 图文笔记
      RegExp(r'^https?://www\.douyin\.com/discover?'),      // 发现页
      // 支持分享文本中的链接（用户可能复制了整段分享文本）
      RegExp(r'https?://v\.douyin\.com/\w+'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  /// 判断是否为快手链接
  bool _isKuaishouUrl(String url) {
    final patterns = [
      RegExp(r'^https?://v\.kuaishou\.com/\w+'),            // 短链接
      RegExp(r'^https?://v\.kuaishou\.com/\w+/'),           // 短链接带斜杠
      RegExp(r'^https?://www\.kuaishou\.com/short-video/'), // 完整链接
      RegExp(r'^https?://kuaishou\.cn/'),                   // 短域名
      RegExp(r'^https?://www\.kuaishou\.com/new-reco/'),    // 推荐链接
      RegExp(r'^https?://m\.kuaishou\.com/'),               // 移动端链接
      RegExp(r'^https?://www\.kuaishou\.com/short-video/'), // 短视频
      RegExp(r'^https?://www\.kuaishou\.com/profile/'),     // 个人主页
      // 支持分享文本中的链接
      RegExp(r'https?://v\.kuaishou\.com/\w+'),
      RegExp(r'https?://kuaishou\.cn/\w+'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  /// 从分享文本中提取URL
  /// 用户可能复制了整段分享文本，如："7.87 Lkt:/ 复制打开抖音，看看【xxx】https://v.douyin.com/xxx/"
  String? extractUrlFromShareText(String text) {
    // 尝试提取抖音链接
    final douyinRegex = RegExp(r'https?://v\.douyin\.com/\w+');
    final douyinMatch = douyinRegex.firstMatch(text);
    if (douyinMatch != null) return douyinMatch.group(0);

    // 尝试提取快手链接
    final kuaishouRegex = RegExp(r'https?://v\.kuaishou\.com/\w+');
    final kuaishouMatch = kuaishouRegex.firstMatch(text);
    if (kuaishouMatch != null) return kuaishouMatch.group(0);

    // 尝试提取快手短域名链接
    final kuaishouShortRegex = RegExp(r'https?://kuaishou\.cn/\w+');
    final kuaishouShortMatch = kuaishouShortRegex.firstMatch(text);
    if (kuaishouShortMatch != null) return kuaishouShortMatch.group(0);

    return null;
  }

  // ==================== 自建解析 ====================

  /// 自建解析：链接解析 → 去水印下载视频 → 提取音频 → ASR转文字
  Future<String> _selfParseExtract(String url, String platform) async {
    if (platform == '抖音') {
      return _parseDouyin(url);
    } else if (platform == '快手') {
      return _parseKuaishou(url);
    }
    throw ExtractException('不支持的平台：$platform', ExtractErrorType.unsupportedPlatform);
  }

  /// 解析抖音链接
  Future<String> _parseDouyin(String url) async {
    // 步骤1：解析抖音短链接，获取视频ID
    final videoId = await _parseDouyinUrl(url);
    if (videoId.isEmpty) {
      throw ExtractException(
        '无法解析抖音链接，请检查链接格式\n支持格式：https://v.douyin.com/xxx/',
        ExtractErrorType.parseFailed,
      );
    }

    // 步骤2：获取无水印视频URL
    final videoUrl = await _getDouyinVideoUrl(videoId);
    if (videoUrl.isEmpty) {
      throw ExtractException(
        '无法获取抖音视频地址，可能是视频已被删除或设为私密',
        ExtractErrorType.videoUnavailable,
      );
    }

    // 步骤3：调用ASR服务将视频音频转为文字
    final text = await _asrTranscribe(videoUrl);
    if (text.isEmpty) {
      throw ExtractException(
        '语音识别失败，该视频可能没有语音内容',
        ExtractErrorType.asrFailed,
      );
    }
    return text;
  }

  /// 解析快手链接
  Future<String> _parseKuaishou(String url) async {
    // 步骤1：解析快手短链接，获取视频ID
    final videoId = await _parseKuaishouUrl(url);
    if (videoId.isEmpty) {
      throw ExtractException(
        '无法解析快手链接，请检查链接格式\n支持格式：https://v.kuaishou.com/xxx/',
        ExtractErrorType.parseFailed,
      );
    }

    // 步骤2：获取快手视频URL
    final videoUrl = await _getKuaishouVideoUrl(videoId);
    if (videoUrl.isEmpty) {
      throw ExtractException(
        '无法获取快手视频地址，可能是视频已被删除或设为私密',
        ExtractErrorType.videoUnavailable,
      );
    }

    // 步骤3：调用ASR服务将视频音频转为文字
    final text = await _asrTranscribe(videoUrl);
    if (text.isEmpty) {
      throw ExtractException(
        '语音识别失败，该视频可能没有语音内容',
        ExtractErrorType.asrFailed,
      );
    }
    return text;
  }

  /// 解析抖音短链接，提取视频ID
  Future<String> _parseDouyinUrl(String url) async {
    try {
      // 如果已经是完整链接，直接提取ID
      final directRegex = RegExp(r'/video/(\d+)');
      final directMatch = directRegex.firstMatch(url);
      if (directMatch != null) {
        return directMatch.group(1) ?? '';
      }

      // 请求短链接，获取重定向后的URL
      final response = await _apiClient.get(
        url,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // 从重定向URL中提取视频ID
      final location = response.headers['location']?.first ?? '';
      // 视频ID通常在URL路径中，格式如 /video/7xxxxxxxx/
      final regex = RegExp(r'/video/(\d+)');
      final match = regex.firstMatch(location);
      if (match != null) {
        return match.group(1) ?? '';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 解析快手短链接，提取视频ID
  Future<String> _parseKuaishouUrl(String url) async {
    try {
      // 如果已经是完整链接，直接提取ID
      final directRegex = RegExp(r'/short-video/([a-zA-Z0-9_-]+)');
      final directMatch = directRegex.firstMatch(url);
      if (directMatch != null) {
        return directMatch.group(1) ?? '';
      }

      // 请求短链接，获取重定向后的URL
      final response = await _apiClient.get(
        url,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
        ),
      );

      // 从重定向URL中提取视频ID
      final location = response.headers['location']?.first ?? '';
      // 快手视频ID格式如 /short-video/3xabcdefghij
      final regex = RegExp(r'/short-video/([a-zA-Z0-9_-]+)');
      final match = regex.firstMatch(location);
      if (match != null) {
        return match.group(1) ?? '';
      }

      // 尝试从URL参数中提取
      final paramRegex = RegExp(r'photoId=([a-zA-Z0-9_-]+)');
      final paramMatch = paramRegex.firstMatch(location);
      if (paramMatch != null) {
        return paramMatch.group(1) ?? '';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 获取抖音无水印视频URL
  Future<String> _getDouyinVideoUrl(String videoId) async {
    try {
      final response = await _apiClient.get(
        'https://www.douyin.com/aweme/v1/web/aweme/detail/',
        queryParameters: {
          'aweme_id': videoId,
        },
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
            'Referer': 'https://www.douyin.com/',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final awemeDetail = data['aweme_detail'] as Map<String, dynamic>?;
      if (awemeDetail != null) {
        final video = awemeDetail['video'] as Map<String, dynamic>?;
        if (video != null) {
          final playAddr = video['play_addr'] as Map<String, dynamic>?;
          if (playAddr != null) {
            final urlList = playAddr['url_list'] as List<dynamic>?;
            if (urlList != null && urlList.isNotEmpty) {
              return urlList[0] as String;
            }
          }
        }
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 获取快手视频URL
  Future<String> _getKuaishouVideoUrl(String videoId) async {
    try {
      final response = await _apiClient.post(
        'https://www.kuaishou.com/graphql',
        data: {
          'operationName': 'visionVideoDetail',
          'variables': {'photoId': videoId, 'isLongVideo': false},
          'query': r'query visionVideoDetail($photoId: String, $isLongVideo: Boolean) { visionVideoDetail(photoId: $photoId, isLongVideo: $isLongVideo) { photo { videoUrl } } }',
        },
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36',
            'Referer': 'https://www.kuaishou.com/',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final detail = data['data']?['visionVideoDetail']?['photo'] as Map<String, dynamic>?;
      if (detail != null) {
        return detail['videoUrl'] as String? ?? '';
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  // ==================== ASR语音识别 ====================

  /// ASR语音识别 - 将视频音频转为文字
  Future<String> _asrTranscribe(String videoUrl) async {
    try {
      // 调用阿里百炼Paraformer ASR
      final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
      if (apiKey == null || apiKey.isEmpty) {
        throw ExtractException(
          '请先配置阿里百炼API Key以使用ASR语音识别功能\n可在设置页面配置',
          ExtractErrorType.apiKeyMissing,
        );
      }

      final response = await _apiClient.post(
        '${ApiConfig.aliBailianBaseUrl}${ApiConfig.aliAsrEndpoint}',
        data: {
          'model': 'paraformer-v2',
          'input': {
            'audio_url': videoUrl,
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final output = data['output'] as Map<String, dynamic>?;
      if (output != null) {
        final results = output['results'] as List<dynamic>?;
        if (results != null && results.isNotEmpty) {
          // 拼接所有识别片段
          final transcript = results.map((r) {
            final map = r as Map<String, dynamic>;
            return map['text'] as String? ?? '';
          }).join('');
          return transcript;
        }
      }
      return '';
    } on ExtractException {
      rethrow;
    } catch (e) {
      // ASR失败，返回空
      return '';
    }
  }

  // ==================== 第三方API兜底 ====================

  /// 第三方API文案提取（兜底方案）
  Future<String> _thirdPartyExtract(String url) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.kuhuyunApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      // 没有第三方API Key不算错误，直接返回空让上层处理
      return '';
    }

    try {
      final response = await _apiClient.post(
        '${ApiConfig.kuhuyunBaseUrl}${ApiConfig.kuhuyunVideoAnalysisEndpoint}',
        data: {
          'url': url,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      // 解析第三方API返回格式
      final result = data['data'] as Map<String, dynamic>?;
      if (result != null) {
        return result['text'] as String? ?? result['content'] as String? ?? '';
      }
      return '';
    } catch (e) {
      return '';
    }
  }

  // ==================== 兼容方法 ====================

  /// 验证抖音链接格式是否合法（保留旧接口兼容）
  @Deprecated('使用 isValidUrl 替代，支持多平台')
  bool isValidDouyinUrl(String url) {
    return _isDouyinUrl(url);
  }

  /// 验证快手链接格式是否合法
  bool isValidKuaishouUrl(String url) {
    return _isKuaishouUrl(url);
  }

  /// 从链接中提取友好的提示信息
  String getLinkHint(String url) {
    final platform = identifyPlatform(url);
    if (platform == null) {
      return '无法识别链接格式，请粘贴抖音或快手分享链接';
    }
    return '已识别为${platform}链接';
  }
}

// ==================== 自定义异常 ====================

/// 提取异常类型
enum ExtractErrorType {
  emptyUrl,              // 空链接
  unsupportedPlatform,   // 不支持的平台
  parseFailed,           // 链接解析失败
  videoUnavailable,      // 视频不可用
  asrFailed,             // ASR识别失败
  apiKeyMissing,         // API Key缺失
  extractFailed,         // 提取失败（通用）
  networkError,          // 网络错误
}

/// 文案提取自定义异常 - 提供友好的错误信息
class ExtractException implements Exception {
  final String message;
  final ExtractErrorType type;

  const ExtractException(this.message, this.type);

  @override
  String toString() => message;
}

/// DouyinService的Riverpod Provider
final douyinServiceProvider = Provider<DouyinService>((ref) {
  return DouyinService(ref.read(apiClientProvider));
});
