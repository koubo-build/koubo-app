import 'dart:convert';
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
  /// [input] 视频分享链接或分享口令，支持抖音/快手
  /// 返回提取的文案文本
  Future<String> extractScript(String input) async {
    final trimmedInput = input.trim();
    if (trimmedInput.isEmpty) {
      throw ExtractException('请输入视频链接', ExtractErrorType.emptyUrl);
    }

    // 先尝试从分享文本中提取URL
    String? extractedUrl = extractUrlFromShareText(trimmedInput);
    final bool isShareCode = isShareCodeWithoutUrl(trimmedInput);

    // 如果是分享口令但没有URL，无法自动提取
    if (isShareCode && extractedUrl == null) {
      throw ExtractException(
        '检测到抖音分享口令，但口令中不包含可解析的链接地址\n\n'
        '💡 建议：\n'
        '1. 点击上方「手动输入」，直接输入视频中的口播文案\n'
        '2. 或在抖音App中打开视频，长按视频选择「复制链接」后再粘贴',
        ExtractErrorType.unsupportedPlatform,
      );
    }

    // 如果提取到了URL，用提取到的URL；否则用原始输入
    final url = extractedUrl ?? trimmedInput;

    // 自动识别平台
    final platform = identifyPlatform(url);
    if (platform == null) {
      throw ExtractException(
        '无法识别链接平台，目前支持抖音和快手链接\n请确认粘贴的是完整的分享链接',
        ExtractErrorType.unsupportedPlatform,
      );
    }

    // 1. 先尝试自建解析
    try {
      final result = await _selfParseExtract(url, platform);
      if (result.isNotEmpty) return result;
    } on ExtractException {
      rethrow; // 已知错误直接抛出
    } catch (e) {
      // 自建解析失败，继续尝试第三方
    }

    // 2. 回退到第三方API
    try {
      final result = await _thirdPartyExtract(url);
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
  /// 支持URL格式和分享口令格式
  String? identifyPlatform(String text) {
    final trimmed = text.trim();

    // 抖音链接格式
    if (_isDouyinUrl(trimmed)) return '抖音';

    // 快手链接格式
    if (_isKuaishouUrl(trimmed)) return '快手';

    // 抖音分享口令（不含URL但能识别为抖音）
    if (_isDouyinShareCode(trimmed)) return '抖音';

    // 快手分享口令
    if (_isKuaishouShareCode(trimmed)) return '快手';

    return null;
  }

  /// 验证链接格式是否合法（URL或分享口令均可）
  bool isValidUrl(String url) {
    final trimmedUrl = url.trim();
    return _isDouyinUrl(trimmedUrl) || _isKuaishouUrl(trimmedUrl)
        || _isDouyinShareCode(trimmedUrl) || _isKuaishouShareCode(trimmedUrl);
  }

  // ==================== 链接格式识别（增强版） ====================

  /// 判断是否为抖音链接
  bool _isDouyinUrl(String url) {
    final patterns = [
      RegExp(r'^https?://v\.douyin\.com/[a-zA-Z0-9_-]+'),       // 短链接
      RegExp(r'^https?://v\.douyin\.com/[a-zA-Z0-9_-]+/'),      // 短链接带斜杠
      RegExp(r'^https?://www\.douyin\.com/video/\d+'),           // 完整链接
      RegExp(r'^https?://www\.iesdouyin\.com/'),                 // 旧域名
      RegExp(r'^https?://www\.douyin\.com/user/'),               // 用户主页
      RegExp(r'^https?://www\.douyin\.com/note/'),               // 图文笔记
      RegExp(r'^https?://www\.douyin\.com/discover?'),           // 发现页
      // 支持分享文本中的链接（用户可能复制了整段分享文本）
      RegExp(r'https?://v\.douyin\.com/[a-zA-Z0-9_-]+'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  /// 判断是否为快手链接
  bool _isKuaishouUrl(String url) {
    final patterns = [
      RegExp(r'^https?://v\.kuaishou\.com/[a-zA-Z0-9_-]+'),       // 短链接
      RegExp(r'^https?://v\.kuaishou\.com/[a-zA-Z0-9_-]+/'),      // 短链接带斜杠
      RegExp(r'^https?://www\.kuaishou\.com/short-video/'),        // 完整链接
      RegExp(r'^https?://kuaishou\.cn/'),                          // 短域名
      RegExp(r'^https?://www\.kuaishou\.com/new-reco/'),           // 推荐链接
      RegExp(r'^https?://m\.kuaishou\.com/'),                      // 移动端链接
      RegExp(r'^https?://www\.kuaishou\.com/profile/'),            // 个人主页
      // 支持分享文本中的链接
      RegExp(r'https?://v\.kuaishou\.com/[a-zA-Z0-9_-]+'),
      RegExp(r'https?://kuaishou\.cn/[a-zA-Z0-9_-]+'),
    ];
    return patterns.any((pattern) => pattern.hasMatch(url));
  }

  /// 判断是否为抖音分享口令（不含URL的分享文本）
  /// 抖音分享口令格式举例：
  /// - "7.87 CkT:/ 复制打开抖音，看看【xxx的作品】"
  /// - "19toik5eleY/ 07/21 J@v.sE ndA:/ :6pm"
  /// - "8.94 pqr:/ 复制打开抖音"
  bool _isDouyinShareCode(String text) {
    // 包含"抖音"关键词
    if (text.contains('抖音') || text.contains('douyin')) return true;
    // 包含"复制打开抖音"的口令格式
    if (RegExp(r'\d+\.\d+\s+\S+:/').hasMatch(text)) return true;
    // 典型的抖音口令格式：字母数字+斜杠+空格+数字/斜杠
    if (RegExp(r'^[a-zA-Z0-9]+/[a-zA-Z0-9/\s@.:]+$', dotAll: false).hasMatch(text.trim())) return true;
    return false;
  }

  /// 判断是否为快手分享口令
  bool _isKuaishouShareCode(String text) {
    if (text.contains('快手') || text.contains('kuaishou')) return true;
    return false;
  }

  /// 从分享文本中提取URL
  /// 用户可能复制了整段分享文本，如："7.87 Lkt:/ 复制打开抖音，看看【xxx】https://v.douyin.com/xxx/"
  /// 返回提取到的URL，如果分享文本中没有URL则返回null
  String? extractUrlFromShareText(String text) {
    // 尝试提取抖音链接（短链接和完整链接）
    final douyinPatterns = [
      RegExp(r'https?://v\.douyin\.com/[a-zA-Z0-9_-]+'),
      RegExp(r'https?://www\.douyin\.com/video/\d+'),
      RegExp(r'https?://www\.iesdouyin\.com/\S+'),
      RegExp(r'https?://www\.douyin\.com/note/\d+'),
      RegExp(r'https?://www\.douyin\.com/video/\S+'),
    ];
    for (final pattern in douyinPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(0);
    }

    // 尝试提取快手链接
    final kuaishouPatterns = [
      RegExp(r'https?://v\.kuaishou\.com/[a-zA-Z0-9_-]+'),
      RegExp(r'https?://kuaishou\.cn/\S+'),
      RegExp(r'https?://www\.kuaishou\.com/short-video/\S+'),
      RegExp(r'https?://m\.kuaishou\.com/\S+'),
    ];
    for (final pattern in kuaishouPatterns) {
      final match = pattern.firstMatch(text);
      if (match != null) return match.group(0);
    }

    // 尝试提取通用http链接（兜底，处理非标准格式）
    final genericMatch = RegExp(r'https?://[^\s<>"\x27]+').firstMatch(text);
    if (genericMatch != null) {
      final url = genericMatch.group(0) ?? '';
      // 只返回抖音或快手域名的URL
      if (url.contains('douyin') || url.contains('kuaishou') || url.contains('iesdouyin')) {
        return url;
      }
    }

    return null;
  }

  /// 检查文本是否为分享口令（不含URL）
  /// 如果是口令格式但没有URL，需要引导用户手动输入
  bool isShareCodeWithoutUrl(String text) {
    final trimmed = text.trim();
    // 先检查是否包含URL
    if (extractUrlFromShareText(trimmed) != null) return false;
    // 再检查是否为分享口令
    return _isDouyinShareCode(trimmed) || _isKuaishouShareCode(trimmed);
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

  /// 解析抖音链接 - 多策略提取文案
  /// 策略优先级：1.分享页抓取描述 2.API获取描述 3.视频下载+ASR
  Future<String> _parseDouyin(String url) async {
    // 策略1：直接抓取分享页面HTML，提取视频描述文案
    try {
      final desc = await _fetchDouyinDescription(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    // 策略2：解析短链接获取videoId → API获取视频描述
    try {
      final videoId = await _parseDouyinUrl(url);
      if (videoId.isNotEmpty) {
        final desc = await _getDouyinVideoDescription(videoId);
        if (desc.isNotEmpty) return desc;

        // 策略3：API获取视频URL → ASR语音识别
        final videoUrl = await _getDouyinVideoUrl(videoId);
        if (videoUrl.isNotEmpty) {
          final text = await _asrTranscribe(videoUrl);
          if (text.isNotEmpty) return text;
        }
      }
    } catch (_) {}

    throw ExtractException(
      '文案提取失败，请尝试：\n1. 点击「手动输入」直接粘贴视频中的文案\n2. 确认链接正确且视频未设为私密\n3. 稍后重试',
      ExtractErrorType.extractFailed,
    );
  }

  /// 从抖音分享页面抓取视频描述文案
  /// 通过访问分享链接的HTML页面，提取RENDER_DATA或meta标签中的文案
  Future<String> _fetchDouyinDescription(String url) async {
    try {
      final response = await _apiClient.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            'Referer': 'https://www.douyin.com/',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
            'Cookie': 'ttwid=1%7C',
          },
          followRedirects: true,
          maxRedirects: 5,
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) return '';

      // 方法1：从RENDER_DATA提取（抖音SSR页面内嵌的JSON数据）
      final renderMatch = RegExp(r'<script\s+id="RENDER_DATA"\s+type="application/json">([^<]+)</script>').firstMatch(html);
      if (renderMatch != null) {
        try {
          final encoded = renderMatch.group(1) ?? '';
          final decoded = Uri.decodeComponent(encoded);
          final jsonData = jsonDecode(decoded) as Map<String, dynamic>;
          final desc = _extractDescFromRenderData(jsonData);
          if (desc.isNotEmpty) return desc;
        } catch (_) {}
      }

      // 方法2：从SSR hydration数据提取（新版抖音页面格式）
      final ssrMatch = RegExp(r'"desc"\s*:\s*"([^"]{2,})"').firstMatch(html);
      if (ssrMatch != null) {
        final desc = ssrMatch.group(1) ?? '';
        if (desc.length > 5) return _unescapeJson(desc);
      }

      // 方法3：从og:description meta标签提取
      final ogMatch = RegExp(r'<meta\s+(?:property|name)=["\x27]og:description["\x27]\s+content=["\x27]([^"\x27]+)["\x27]').firstMatch(html)
          ?? RegExp(r'<meta\s+content=["\x27]([^"\x27]+)["\x27]\s+(?:property|name)=["\x27]og:description["\x27]').firstMatch(html);
      if (ogMatch != null) {
        final desc = ogMatch.group(1) ?? '';
        if (desc.length > 5) return desc;
      }

      // 方法4：从<title>标签提取（兜底）
      final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(html);
      if (titleMatch != null) {
        var title = titleMatch.group(1) ?? '';
        // 清理标题中的平台后缀
        title = title.replaceAll(RegExp(r'\s*[-|·]\s*抖音.*$'), '').trim();
        title = title.replaceAll(RegExp(r'^抖音\s*[-|·]?\s*'), '').trim();
        if (title.length > 5) return title;
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  /// 从RENDER_DATA JSON中递归查找视频描述
  String _extractDescFromRenderData(Map<String, dynamic> data) {
    // 尝试多种已知的JSON路径
    final paths = [
      ['awemeDetail', 'desc'],
      ['aweme_detail', 'desc'],
      ['videoDetail', 'desc'],
      ['detail', 'desc'],
    ];

    for (final path in paths) {
      var current = data;
      for (var i = 0; i < path.length - 1; i++) {
        final key = path[i];
        if (current[key] is Map<String, dynamic>) {
          current = current[key] as Map<String, dynamic>;
        } else {
          current = {};
          break;
        }
      }
      final lastKey = path.last;
      if (current.containsKey(lastKey) && current[lastKey] is String) {
        final desc = (current[lastKey] as String).trim();
        if (desc.isNotEmpty) return desc;
      }
    }

    // 递归搜索：查找第一个包含 "desc" 字段且值非空的节点
    return _findDescRecursive(data);
  }

  /// 递归搜索JSON中的desc字段
  String _findDescRecursive(dynamic data, [int depth = 0]) {
    if (depth > 5) return ''; // 防止递归太深
    if (data is! Map<String, dynamic>) return '';

    // 优先查找desc字段
    if (data.containsKey('desc') && data['desc'] is String) {
      final desc = (data['desc'] as String).trim();
      if (desc.length > 5) return desc;
    }

    // 递归搜索子节点
    for (final value in data.values) {
      if (value is Map<String, dynamic>) {
        final result = _findDescRecursive(value, depth + 1);
        if (result.isNotEmpty) return result;
      }
    }

    return '';
  }

  /// 反转义JSON字符串中的转义字符
  String _unescapeJson(String s) {
    return s
        .replaceAll(r'\\n', '\n')
        .replaceAll(r'\\t', '\t')
        .replaceAll(r'\\r', '\r')
        .replaceAll(r'\\"', '"')
        .replaceAll(r'\\\\', '\\');
  }

  /// 通过API获取抖音视频描述文案（不需要下载视频）
  Future<String> _getDouyinVideoDescription(String videoId) async {
    try {
      final response = await _apiClient.get(
        'https://www.douyin.com/aweme/v1/web/aweme/detail/',
        queryParameters: {
          'aweme_id': videoId,
        },
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            'Referer': 'https://www.douyin.com/',
          },
        ),
      );

      final data = response.data as Map<String, dynamic>;
      final awemeDetail = data['aweme_detail'] as Map<String, dynamic>?;
      if (awemeDetail != null) {
        // 优先取desc字段
        final desc = awemeDetail['desc'] as String?;
        if (desc != null && desc.trim().isNotEmpty) return desc.trim();
      }
      return '';
    } catch (_) {
      return '';
    }
  }

  /// 解析快手链接 - 多策略提取文案
  Future<String> _parseKuaishou(String url) async {
    // 策略1：抓取分享页面提取描述
    try {
      final desc = await _fetchKuaishouDescription(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    // 策略2：解析短链接获取videoId → API获取视频
    try {
      final videoId = await _parseKuaishouUrl(url);
      if (videoId.isNotEmpty) {
        final videoUrl = await _getKuaishouVideoUrl(videoId);
        if (videoUrl.isNotEmpty) {
          final text = await _asrTranscribe(videoUrl);
          if (text.isNotEmpty) return text;
        }
      }
    } catch (_) {}

    throw ExtractException(
      '文案提取失败，请尝试：\n1. 点击「手动输入」直接粘贴视频中的文案\n2. 确认链接正确且视频未设为私密\n3. 稍后重试',
      ExtractErrorType.extractFailed,
    );
  }

  /// 从快手分享页面抓取视频描述文案
  Future<String> _fetchKuaishouDescription(String url) async {
    try {
      final response = await _apiClient.get(
        url,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            'Referer': 'https://www.kuaishou.com/',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
            'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.8',
          },
          followRedirects: true,
          maxRedirects: 5,
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 15),
        ),
      );

      final html = response.data?.toString() ?? '';
      if (html.isEmpty) return '';

      // 从og:description提取
      final ogMatch = RegExp(r'<meta\s+(?:property|name)=["\x27]og:description["\x27]\s+content=["\x27]([^"\x27]+)["\x27]').firstMatch(html)
          ?? RegExp(r'<meta\s+content=["\x27]([^"\x27]+)["\x27]\s+(?:property|name)=["\x27]og:description["\x27]').firstMatch(html);
      if (ogMatch != null) {
        final desc = ogMatch.group(1) ?? '';
        if (desc.length > 5) return desc;
      }

      // 从window.__APOLLO_STATE__提取
      final apolloMatch = RegExp(r'window\.__APOLLO_STATE__\s*=\s*(\{.+?\})\s*;?\s*</script>').firstMatch(html);
      if (apolloMatch != null) {
        try {
          final jsonData = jsonDecode(apolloMatch.group(1)!) as Map<String, dynamic>;
          final desc = _findDescRecursive(jsonData);
          if (desc.isNotEmpty) return desc;
        } catch (_) {}
      }

      // 从<title>提取
      final titleMatch = RegExp(r'<title>([^<]+)</title>').firstMatch(html);
      if (titleMatch != null) {
        var title = titleMatch.group(1) ?? '';
        title = title.replaceAll(RegExp(r'\s*[-|·]\s*快手.*$'), '').trim();
        if (title.length > 5) return title;
      }

      return '';
    } catch (_) {
      return '';
    }
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

      // 尝试请求短链接获取重定向URL
      try {
        final response = await _apiClient.get(
          url,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            },
          ),
        );

        // 从重定向URL中提取视频ID
        final location = response.headers['location']?.first ?? '';
        final regex = RegExp(r'/video/(\d+)');
        final match = regex.firstMatch(location);
        if (match != null) {
          return match.group(1) ?? '';
        }
      } catch (_) {}

      // 如果重定向失败，尝试直接访问页面从HTML中提取视频ID
      try {
        final response = await _apiClient.get(
          url,
          options: Options(
            followRedirects: true,
            maxRedirects: 5,
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 500,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            },
          ),
        );

        final html = response.data?.toString() ?? '';
        // 从最终URL或HTML中提取视频ID
        final effectiveUrl = response.realUri.toString();
        final urlMatch = RegExp(r'/video/(\d+)').firstMatch(effectiveUrl);
        if (urlMatch != null) return urlMatch.group(1) ?? '';

        // 从HTML中的canonical链接提取
        final canonicalMatch = RegExp(r'<link[^>]*rel="canonical"[^>]*href="[^"]*/video/(\d+)"').firstMatch(html);
        if (canonicalMatch != null) return canonicalMatch.group(1) ?? '';

        // 从RENDER_DATA中提取aweme_id
        final renderMatch = RegExp(r'"aweme_id"\s*:\s*"(\d+)"').firstMatch(html);
        if (renderMatch != null) return renderMatch.group(1) ?? '';
      } catch (_) {}

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
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            'Referer': 'https://www.douyin.com/',
          },
        ),
      );

      final data = response.data;
      // 处理响应可能是字符串的情况
      Map<String, dynamic> jsonData;
      if (data is String) {
        jsonData = jsonDecode(data) as Map<String, dynamic>;
      } else if (data is Map<String, dynamic>) {
        jsonData = data;
      } else {
        return '';
      }

      final awemeDetail = jsonData['aweme_detail'] as Map<String, dynamic>?;
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
