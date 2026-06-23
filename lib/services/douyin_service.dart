import 'dart:convert';
import 'dart:io';
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

    // 如果是纯分享口令（没有URL），尝试多种方式解析
    if (isShareCode && extractedUrl == null) {
      // 策略1：尝试TikHub直接解析原始口令文本
      try {
        final result = await _tikhubExtractWithAsr(trimmedInput);
        if (result.isNotEmpty) return result;
      } on ExtractException {
        rethrow;
      } catch (_) {}

      // 策略2：尝试免费API解析（apibyte.cn，无需Key）
      try {
        final result = await _apibyteExtract(trimmedInput);
        if (result.isNotEmpty) return result;
      } catch (_) {}

      // 策略3：尝试自建解析（有些口令可以通过重定向获取aweme_id）
      try {
        final awemeId = await _resolveShareCodeToAwemeId(trimmedInput);
        if (awemeId.isNotEmpty) {
          final result = await _tikhubDouyinWebExtract(awemeId);
          if (result.isNotEmpty) return result;
        }
      } catch (_) {}

      throw ExtractException(
        '无法解析该分享口令\n\n'
        '💡 获取可解析链接的方法：\n'
        '1. 在抖音App中打开视频 → 点击分享 → 选择「复制链接」（不是复制口令）\n'
        '2. 或者点击上方「手动输入」，直接输入视频中的口播文案',
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

    // 3. 免费API兜底（apibyte.cn，无需Key）
    try {
      final result = await _apibyteExtract(url);
      if (result.isNotEmpty) return result;
    } catch (e) {
      // 免费API也失败
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
  /// - "Zzg:/ :2pm B@T.lP 03/18"
  bool _isDouyinShareCode(String text) {
    // 包含"抖音"关键词
    if (text.contains('抖音') || text.contains('douyin')) return true;
    // 包含"复制打开抖音"的口令格式
    if (RegExp(r'\d+\.\d+\s+\S+:/').hasMatch(text)) return true;
    // 抖音口令特征：字母数字+斜杠+冒号 (如 Zzg:/ 或 ndA:/)
    if (RegExp(r'[a-zA-Z0-9]+:/').hasMatch(text)) return true;
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
  /// 策略优先级：
  /// 1. TikHub hybrid/app端点（获取描述+视频URL，ASR兜底）
  /// 2. 解析短链接→aweme_id→TikHub douyin/web端点
  /// 3. HTML抓取描述
  /// 4. 自建解析+ASR
  Future<String> _parseDouyin(String url) async {
    // 策略1：TikHub hybrid/app解析（获取描述文案 + 视频播放URL用于ASR）
    try {
      final result = await _tikhubExtractWithAsr(url);
      if (result.isNotEmpty) return result;
    } on ExtractException {
      rethrow;
    } catch (_) {}

    // 策略2：解析短链接→aweme_id→TikHub douyin/web端点（hybrid 400时的兜底）
    try {
      final awemeId = await _resolveDouyinAwemeId(url);
      if (awemeId.isNotEmpty) {
        final result = await _tikhubDouyinWebExtract(awemeId);
        if (result.isNotEmpty) return result;
      }
    } on ExtractException {
      rethrow;
    } catch (_) {}

    // 策略3：直接抓取分享页面HTML，提取视频描述文案
    try {
      final desc = await _fetchDouyinDescription(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    // 策略4：解析短链接获取videoId → 下载视频+ASR语音识别
    try {
      final videoId = await _parseDouyinUrl(url);
      if (videoId.isNotEmpty) {
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

  /// 解析抖音短链接，获取视频aweme_id（数字ID）
  /// 方法：请求短链接跟随重定向，从最终URL中提取/video/后面的数字ID
  Future<String> _resolveDouyinAwemeId(String url) async {
    // 如果URL已包含aweme_id，直接提取
    final directMatch = RegExp(r'/video/(\d+)').firstMatch(url);
    if (directMatch != null) return directMatch.group(1) ?? '';

    // 如果是抖音短链接，请求重定向获取真实URL
    if (!url.contains('v.douyin.com') && !url.contains('iesdouyin.com')) return '';

    try {
      final response = await _apiClient.get(
        url,
        options: Options(
          followRedirects: false,
          validateStatus: (status) => status != null && status < 400,
          headers: {
            'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
          },
          receiveTimeout: const Duration(seconds: 10),
        ),
      );

      // 从重定向URL中提取视频ID
      final location = response.headers['location']?.first ?? '';
      var match = RegExp(r'/video/(\d+)').firstMatch(location);
      if (match != null) return match.group(1) ?? '';

      // 部分重定向到modal路径，包含aweme_id参数
      match = RegExp(r'aweme_id=(\d+)').firstMatch(location);
      if (match != null) return match.group(1) ?? '';

      // 二次重定向
      if (location.isNotEmpty) {
        final response2 = await _apiClient.get(
          location,
          options: Options(
            followRedirects: false,
            validateStatus: (status) => status != null && status < 400,
            headers: {
              'User-Agent': 'Mozilla/5.0 (Linux; Android 12; Pixel 6) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.230 Mobile Safari/537.36',
            },
            receiveTimeout: const Duration(seconds: 10),
          ),
        );
        final location2 = response2.headers['location']?.first ?? '';
        match = RegExp(r'/video/(\d+)').firstMatch(location2);
        if (match != null) return match.group(1) ?? '';
        match = RegExp(r'aweme_id=(\d+)').firstMatch(location2);
        if (match != null) return match.group(1) ?? '';
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  /// TikHub douyin/web端点提取文案+视频URL（需要aweme_id）
  /// 当hybrid端点返回400时，用此端点兜底
  Future<String> _tikhubDouyinWebExtract(String awemeId) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.tikhubApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return '';

    try {
      final response = await _apiClient.get(
        '${ApiConfig.tikhubBaseUrl}/douyin/web/fetch_one_video',
        queryParameters: {'aweme_id': awemeId},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 200) {
        final dataField = data['data'];
        if (dataField is Map<String, dynamic>) {
          final awemeDetail = dataField['aweme_detail'];
          if (awemeDetail is Map<String, dynamic>) {
            // 提取描述文案
            final desc = _extractCleanDesc(dataField);
            final videoUrl = _extractVideoPlayUrl(dataField);

            // 描述够长直接返回
            if (desc.isNotEmpty && desc.length > 10) return desc;

            // 描述太短，ASR兜底
            if (videoUrl != null && videoUrl.isNotEmpty) {
              try {
                final asrText = await _asrTranscribe(videoUrl);
                if (asrText.isNotEmpty) return asrText;
              } catch (_) {}
            }

            return desc;
          }
        }
      }

      return '';
    } catch (_) {
      return '';
    }
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
        if (desc.isNotEmpty) return _stripHashtags(desc);
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
      if (desc.length > 5) return _stripHashtags(desc);
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
    // 策略1：TikHub解析 + ASR兜底
    try {
      final result = await _tikhubExtractWithAsr(url);
      if (result.isNotEmpty) return result;
    } on ExtractException {
      rethrow;
    } catch (_) {}

    // 策略2：抓取分享页面提取描述
    try {
      final desc = await _fetchKuaishouDescription(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    // 策略3：解析短链接获取videoId → 下载视频+ASR
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

  /// ASR语音识别 - 下载视频音频 → 百炼qwen3-asr-flash转文字
  /// 流程：TikHub获取视频播放URL → 下载视频 → base64编码 → 调用ASR
  Future<String> _asrTranscribe(String videoUrl) async {
    try {
      final apiKey = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
      if (apiKey == null || apiKey.isEmpty) {
        throw ExtractException(
          '请先配置阿里百炼API Key以使用ASR语音识别功能\n可在设置页面配置',
          ExtractErrorType.apiKeyMissing,
        );
      }

      // 1. 下载视频到本地（限制20MB以内，短视频通常5-20MB）
      final audioDir = await StorageUtil.getAudioDirectory();
      final fileName = 'asr_${DateTime.now().millisecondsSinceEpoch}.mp4';
      final filePath = '$audioDir/$fileName';

      try {
        final response = await _apiClient.get(
          videoUrl,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: const Duration(seconds: 60),
            validateStatus: (status) => status != null && status < 400,
          ),
        );

        final bytes = response.data as List<int>;
        if (bytes.isEmpty || bytes.length > 20 * 1024 * 1024) {
          throw Exception('视频文件过大或为空');
        }

        final file = await File(filePath).create(recursive: true);
        await file.writeAsBytes(bytes);
      } catch (e) {
        throw Exception('视频下载失败：${e.toString().replaceAll("Exception: ", "")}');
      }

      // 2. 读取视频文件并base64编码
      final videoBytes = await File(filePath).readAsBytes();
      final base64Audio = base64Encode(videoBytes);

      // 3. 调用百炼 qwen3-asr-flash（OpenAI兼容接口，同步调用）
      final asrResponse = await _apiClient.post(
        '${ApiConfig.aliBailianCompatUrl}/chat/completions',
        data: {
          'model': 'qwen3-asr-flash',
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'input_audio',
                  'input_audio': {
                    'data': 'data:video/mp4;base64,$base64Audio',
                  },
                },
              ],
            },
          ],
          'stream': false,
          'extra_body': {
            'asr_options': {
              'enable_itn': false,
            },
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          receiveTimeout: const Duration(seconds: 120),
          sendTimeout: const Duration(seconds: 120),
        ),
      );

      // 4. 解析ASR结果
      final data = asrResponse.data as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>?;
      if (choices != null && choices.isNotEmpty) {
        final message = choices[0]['message'] as Map<String, dynamic>?;
        if (message != null) {
          final content = message['content'] as String?;
          if (content != null && content.trim().isNotEmpty) {
            // 清理临时文件
            try { await File(filePath).delete(); } catch (_) {}
            return content.trim();
          }
        }
      }

      // 清理临时文件
      try { await File(filePath).delete(); } catch (_) {}
      return '';
    } on ExtractException {
      rethrow;
    } catch (e) {
      return '';
    }
  }

  /// 从TikHub解析结果中提取视频播放URL（用于ASR）
  String? _extractVideoPlayUrl(Map<String, dynamic> data) {
    final awemeDetail = data['aweme_detail'] ?? data;
    if (awemeDetail is! Map<String, dynamic>) return null;

    final video = awemeDetail['video'];
    if (video is! Map<String, dynamic>) return null;

    // 优先取bit_rate中最高质量的URL（通常第一个就是）
    final bitRate = video['bit_rate'];
    if (bitRate is List && bitRate.isNotEmpty) {
      for (final br in bitRate) {
        if (br is Map<String, dynamic>) {
          final playAddr = br['play_addr'];
          if (playAddr is Map<String, dynamic>) {
            final urlList = playAddr['url_list'];
            if (urlList is List && urlList.isNotEmpty) {
              return urlList[0] as String;
            }
          }
        }
      }
    }

    // 兜底取play_addr
    final playAddr = video['play_addr'];
    if (playAddr is Map<String, dynamic>) {
      final urlList = playAddr['url_list'];
      if (urlList is List && urlList.isNotEmpty) {
        return urlList[0] as String;
      }
    }

    return null;
  }

  // ==================== 第三方API解析 ====================

  /// 第三方API解析抖音视频 - 多源级联
  /// 优先TikHub（最稳定，需API Key），其次酷虎云（用户自配置）
  /// TikHub解析 + ASR兜底：先取描述文案，太短则用ASR识别视频口播内容
  Future<String> _tikhubExtractWithAsr(String url) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.tikhubApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
      // 没TikHub Key，走酷虎云
      return _thirdPartyDouyinExtract(url);
    }

    // 调用TikHub获取数据（desc + 视频URL）
    final tikhubResult = await _callTikHubFull(url);
    
    // 1. 优先返回清洗后的描述文案（已去标签）
    if (tikhubResult.desc.isNotEmpty && tikhubResult.desc.length > 10) {
      return tikhubResult.desc;
    }

    // 2. 描述太短（可能只有标签或空白），用ASR识别视频口播内容
    if (tikhubResult.videoUrl != null && tikhubResult.videoUrl!.isNotEmpty) {
      try {
        final asrText = await _asrTranscribe(tikhubResult.videoUrl!);
        if (asrText.isNotEmpty) return asrText;
      } catch (_) {}
    }

    // 3. ASR也失败，返回短的desc也比没有好
    return tikhubResult.desc;
  }

  /// TikHub解析结果
  // ignore: unused_field
  static const _emptyTikhubResult = _TikhubResult();

  /// 调用TikHub获取完整数据（描述文案 + 视频播放URL）
  /// 优先hybrid端点，失败后尝试douyin/app端点
  Future<_TikhubResult> _callTikHubFull(String url) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.tikhubApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return _TikhubResult();

    try {
      // 优先用hybrid端点
      var response = await _apiClient.get(
        '${ApiConfig.tikhubBaseUrl}/hybrid/video_data',
        queryParameters: {'url': url},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      var data = response.data;
      if (data is Map<String, dynamic>) {
        // hybrid返回200，提取数据
        if (data['code'] == 200) {
          final dataField = data['data'];
          if (dataField is Map<String, dynamic>) {
            final desc = _extractCleanDesc(dataField);
            final videoUrl = _extractVideoPlayUrl(dataField);
            return _TikhubResult(desc: desc, videoUrl: videoUrl);
          }
        }
        // hybrid返回400，可能是抖音链接不支持，直接跳到douyin/app端点
      }

      // hybrid失败，尝试douyin app端点
      response = await _apiClient.get(
        '${ApiConfig.tikhubBaseUrl}/douyin/app/v3/fetch_one_video_by_share_url',
        queryParameters: {'share_url': url},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 200) {
        final dataField = data['data'];
        if (dataField is Map<String, dynamic>) {
          final desc = _extractCleanDesc(dataField);
          final videoUrl = _extractVideoPlayUrl(dataField);
          return _TikhubResult(desc: desc, videoUrl: videoUrl);
        }
      }

      return _TikhubResult();
    } catch (_) {
      return _TikhubResult();
    }
  }

  Future<String> _thirdPartyDouyinExtract(String url) async {
    // 源1: TikHub解析（需配置API Key，新用户有免费额度）
    try {
      final desc = await _callTikHubApi(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    // 源2: 用户自配置的酷虎云API（如果有Key）
    try {
      final desc = await _thirdPartyExtract(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    return '';
  }

  /// 第三方API解析快手视频
  Future<String> _thirdPartyKuaishouExtract(String url) async {
    // TikHub也支持快手
    try {
      final desc = await _callTikHubApi(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    // 酷虎云兜底
    try {
      final desc = await _thirdPartyExtract(url);
      if (desc.isNotEmpty) return desc;
    } catch (_) {}

    return '';
  }

  /// 调用TikHub解析API（需要API Key）
  /// TikHub是目前最稳定的抖音/快手解析服务，需注册获取免费API Key
  /// 注册地址: https://tikhub.io （新用户有免费额度）
  Future<String> _callTikHubApi(String url) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.tikhubApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) return '';

    try {
      // 优先用hybrid端点（支持分享链接/短链接直接解析）
      var response = await _apiClient.get(
        '${ApiConfig.tikhubBaseUrl}/hybrid/video_data',
        queryParameters: {'url': url},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      var data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 200) {
        final dataField = data['data'];
        if (dataField is Map<String, dynamic>) {
          final desc = _extractCleanDesc(dataField);
          if (desc.isNotEmpty) return desc;
        }
      }

      // hybrid失败，尝试douyin app端点
      response = await _apiClient.get(
        '${ApiConfig.tikhubBaseUrl}/douyin/app/v3/fetch_one_video_by_share_url',
        queryParameters: {'share_url': url},
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Accept': 'application/json',
          },
          validateStatus: (status) => status != null && status < 500,
          receiveTimeout: const Duration(seconds: 20),
        ),
      );

      data = response.data;
      if (data is Map<String, dynamic> && data['code'] == 200) {
        final dataField = data['data'];
        if (dataField is Map<String, dynamic>) {
          final desc = _extractCleanDesc(dataField);
          if (desc.isNotEmpty) return desc;
        }
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  /// 提取并清洗视频文案（去除#标签、@提及等，只保留纯文案）
  String _extractCleanDesc(Map<String, dynamic> data) {
    String? rawDesc;

    // 先从aweme_detail取desc
    final awemeDetail = data['aweme_detail'];
    if (awemeDetail is Map<String, dynamic>) {
      rawDesc = awemeDetail['desc'] as String?;
    }

    // 没有的话从data直接取
    rawDesc ??= data['desc'] as String?;

    if (rawDesc == null || rawDesc.trim().isEmpty) return '';

    // 使用text_extra精准去除标签（如果有的话）
    final textExtra = (awemeDetail ?? data)['text_extra'];
    if (textExtra is List && textExtra.isNotEmpty) {
      return _removeTagsFromDesc(rawDesc.trim(), textExtra);
    }

    // 没有text_extra，用正则去除 #标签 和 @提及
    return _stripHashtags(rawDesc.trim());
  }

  // ==================== 免费API解析（apibyte.cn，无需API Key） ====================

  /// 使用apibyte.cn免费API解析抖音链接/口令
  /// 这个API不需要认证，支持短链和完整链接，也支持部分口令
  Future<String> _apibyteExtract(String input) async {
    try {
      // 先尝试从输入中提取URL
      String? url = extractUrlFromShareText(input);
      // 如果没有URL，尝试把原始输入作为url参数发送（有些口令也能解析）
      final parseUrl = url ?? input;

      final response = await _apiClient.get(
        ApiConfig.apibyteParseUrl,
        queryParameters: {'url': parseUrl},
        options: Options(
          receiveTimeout: const Duration(seconds: 20),
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final data = response.data;
      if (data is Map<String, dynamic>) {
        // apibyte返回格式：{ title, desc, video_url, ... }
        // 优先取desc（视频描述/文案）
        final desc = data['desc'] as String?;
        if (desc != null && desc.trim().isNotEmpty && desc.trim().length > 5) {
          return _stripHashtags(desc.trim());
        }

        // 兜底取title
        final title = data['title'] as String?;
        if (title != null && title.trim().isNotEmpty && title.trim().length > 5) {
          return title.trim();
        }

        // 如果有视频URL，尝试ASR
        final videoUrl = data['video_url'] as String?;
        if (videoUrl != null && videoUrl.isNotEmpty) {
          try {
            final asrText = await _asrTranscribe(videoUrl);
            if (asrText.isNotEmpty) return asrText;
          } catch (_) {}
        }
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  // ==================== 分享口令解析为aweme_id ====================

  /// 尝试将纯分享口令解析为aweme_id
  /// 方法：通过抖音的口令解析API或短链重定向
  Future<String> _resolveShareCodeToAwemeId(String shareCode) async {
    // 有些分享口令格式包含隐藏的短链接信息
    // 尝试通过抖音的通用口令解析接口获取
    try {
      // 方法1：尝试把口令当作搜索关键词，通过抖音web搜索API获取视频
      // 注意：这个方法不太可靠，但作为兜底可以尝试

      // 方法2：构造一个模拟抖音客户端的请求来解析口令
      // 抖音客户端解析口令的API：POST https://www.douyin.com/aweme/v1/web/share/parse/
      // 但这个接口需要签名参数，不太稳定

      // 方法3：通过抖音网页端的通用重定向解析
      // 有些口令可以通过 https://www.douyin.com/xxx 格式访问
      // 从口令中提取可能的视频标识

      // 尝试从口令中提取数字ID（19-22位纯数字是视频ID的特征）
      final idMatch = RegExp(r'(\d{19,22})').firstMatch(shareCode);
      if (idMatch != null) {
        final possibleId = idMatch.group(1) ?? '';
        // 验证这个ID是否有效
        try {
          final result = await _tikhubDouyinWebExtract(possibleId);
          if (result.isNotEmpty) return possibleId;
        } catch (_) {}
      }

      return '';
    } catch (_) {
      return '';
    }
  }

  /// 根据text_extra信息精准去除文案中的标签和@提及
  String _removeTagsFromDesc(String desc, List textExtra) {
    // 按start位置降序排列，从后往前删除避免偏移
    final sorted = List<Map<String, dynamic>>.from(
      textExtra.whereType<Map<String, dynamic>>().toList(),
    );
    sorted.sort((a, b) => (b['start'] as int? ?? 0).compareTo(a['start'] as int? ?? 0));

    String result = desc;
    for (final tag in sorted) {
      final start = tag['start'] as int? ?? 0;
      final end = tag['end'] as int? ?? 0;
      final type = tag['type'] as int? ?? 0;
      // type=0: @提及, type=1: #话题标签
      if (type == 0 || type == 1) {
        if (start >= 0 && end <= result.length && start < end) {
          result = result.substring(0, start) + result.substring(end);
        }
      }
    }

    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 用正则去除#标签和@提及（无text_extra时的兜底方案）
  String _stripHashtags(String desc) {
    // 去除 #标签（包括#后面的中文/英文/数字）
    var result = desc.replaceAll(RegExp(r'#[\w\u4e00-\u9fff]+'), '');
    // 去除 @用户名
    result = result.replaceAll(RegExp(r'@[\w\u4e00-\u9fff]+'), '');
    return result.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// 用户自配置的第三方API提取（需API Key）
  Future<String> _thirdPartyExtract(String url) async {
    final apiKey = await StorageUtil.getSecure(ApiConfig.kuhuyunApiKeyKey);
    if (apiKey == null || apiKey.isEmpty) {
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

/// TikHub解析结果（描述文案 + 视频播放URL）
class _TikhubResult {
  final String desc;
  final String? videoUrl;
  const _TikhubResult({this.desc = '', this.videoUrl});
}
