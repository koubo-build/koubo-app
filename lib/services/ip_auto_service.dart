import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/ip_auto_package.dart';
import '../utils/storage_util.dart';
import 'api_client.dart';

/// IP口播全自动生成服务
///
/// 对应产品规则（自动模式）：
/// 全程不打断，一路跑完【参考生成】→脚本→配音文案（脚本即可朗读）→字幕配置→
/// 动效清单→BGM推荐→封面标题→社媒发布文案。
/// 默认规则：画中画不插、动效一律不加（仅生成备选清单），用户不主动提就不加额外素材。
///
/// 触发方式：
/// 1) 行业关键词 → 产出5条高流量痛点选题卡片
/// 2) 【复刻它】+模板指令 → 仿写该爆款的语气/结构/钩子，生成同赛道新口播稿
/// 3) 上传/粘贴参考视频文案 → 提取爆款框架，生成复刻卡片并一键全自动
class IpAutoService {
  final ApiClient _apiClient;

  IpAutoService(this._apiClient);

  /// IP全自动页面使用的文案模型偏好存储键
  static const String modelPrefKey = 'ip_auto_text_model';

  /// 默认可选模型（与设置页一致，新增 MiniMax 选项）
  static const List<Map<String, String>> modelOptions = [
    {'value': '自动选择', 'label': '自动选择（免费，开箱即用）'},
    {'value': 'MiniMax-Text-01', 'label': 'MiniMax（海螺AI，需填Key）'},
    {'value': 'glm-4.7-flash', 'label': 'GLM-4-Flash（智谱，免费）'},
    {'value': 'agnes-2.0-flash', 'label': 'Agnes-2.0-Flash（免费）'},
    {'value': 'qwen-plus', 'label': 'qwen-plus（百炼）'},
    {'value': 'deepseek-chat', 'label': 'DeepSeek-V3（需填Key）'},
  ];

  /// 读取当前选择的模型
  Future<String> getSelectedModel() async {
    return StorageUtil.getString(modelPrefKey) ?? '自动选择';
  }

  /// 保存模型选择
  Future<void> setSelectedModel(String value) {
    return StorageUtil.setString(modelPrefKey, value);
  }

  // ==================== 系统人设（IP口播全自动Agent） ====================

  static const String _systemPrompt = '''你是「IP口播视频全自动生成Agent」，服务于商业IP、创业、知识付费、个人成长等赛道的短视频口播创作者。
你的文案要求：
- 语言通俗、网感强、像真人说话，杜绝书面腔和AI腔；
- 严格遵循短视频逻辑：前3秒强钩子 → 中间戳痛点/给干货 → 结尾引导互动；
- 适合真人或数字人口播，句子短、有呼吸点、可直接朗读；
- 只输出用户要求的内容与格式，不寒暄、不解释、不额外加戏。
默认规则：不插入画中画建议，不默认加动效（动效只作为备选清单），用户没提就不加额外素材。''';

  // ==================== 1. 选题参考卡片 ====================

  /// 根据行业关键词生成5条高流量痛点选题卡片
  Future<List<TopicCard>> generateTopicCards(String keyword) async {
    final prompt = '''你是短视频爆款选题策划。用户所在赛道/行业关键词是：「$keyword」。
请围绕该赛道，产出5条最容易出爆款的高流量"痛点型"口播选题。
每条都要精准命中目标人群的焦虑、好奇、损失厌恶或身份认同，前3秒钩子要让人停下来。

严格只输出JSON数组，不要输出任何解释或markdown代码块标记，格式如下：
[
  {
    "title": "选题标题（15字以内，带钩子/冲突/数字/反差）",
    "track": "所属细分赛道",
    "hook": "前3秒开场钩子原话（可直接念）",
    "pain_point": "这条选题戳中的核心痛点",
    "reason": "为什么这条容易爆（一句话）",
    "replicate_command": "【复刻它】以「选题标题」为题，赛道xxx，仿写爆款口播稿"
  }
]

要求：5条选题角度互不重复；replicate_command 必须以「【复刻它】」开头，方便用户点击后直接触发挥写。''';

    final raw = await _callTextModel([
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': prompt},
    ], temperature: 0.9);

    final list = _extractJsonArray(raw);
    final cards = <TopicCard>[];
    for (final item in list) {
      if (item is Map) {
        final card = TopicCard.fromJson(Map<String, dynamic>.from(item));
        // 兜底：确保复刻指令带触发词
        var cmd = card.replicateCommand;
        if (cmd.isEmpty) {
          cmd = '【复刻它】以「${card.title}」为题，赛道${card.track}，仿写爆款口播稿';
        } else if (!cmd.contains('【复刻它】')) {
          cmd = '【复刻它】$cmd';
        }
        cards.add(TopicCard(
          title: card.title,
          track: card.track,
          hook: card.hook,
          painPoint: card.painPoint,
          reason: card.reason,
          replicateCommand: cmd,
        ));
      }
    }
    if (cards.isEmpty) {
      throw Exception('选题生成失败：模型未返回可解析的卡片，请重试或换个关键词');
    }
    return cards;
  }

  // ==================== 2~7. 全自动一条龙 ====================

  /// 全自动生成完整7段产物。
  ///
  /// [input] 用户输入：复刻指令 / 行业关键词 / 参考文案。
  /// [mode] keyword | replicate | reference
  Future<IpAutoPackage> generateFullPackage({
    required String input,
    required String mode,
  }) async {
    final modeDesc = _buildModeInstruction(input, mode);

    final prompt = '''$modeDesc

请进入【自动模式】，全程不打断、不追问，一次性产出这条口播视频的完整创作包。
严格只输出一个JSON对象（不要markdown代码块、不要任何解释），字段如下：
{
  "script": "口播脚本正文：抖音/小红书风格，适合真人或数字人口播，节奏紧凑，用「/」或「（停顿）」标注情绪停顿；前3秒强钩子，中间戳痛点给干货，结尾引导互动；控制在300-600字",
  "subtitle": {
    "styles": ["字幕样式备选1", "备选2", "...共10条，描述字体/位置/高亮风格"],
    "font_size": "字号建议，例如：主字幕42-48px",
    "color": "字幕颜色默认值，例如：白色+黄色关键词高亮",
    "stroke": "描边默认值，例如：2px黑色描边"
  },
  "effects": [
    {"name": "动效名称", "desc": "适用位置与作用"}
  ],
  "bgm": {
    "genre": "曲风，例如：轻快/悬疑/燃向/治愈",
    "name": "适配BGM描述或参考曲目类型",
    "volume": "音量建议，例如：人声的15%-25%",
    "usage": "在哪些段落起伏的使用建议"
  },
  "cover_title": {
    "titles": ["短视频标题1", "标题2", "标题3"],
    "cover_copy": "封面主文案（大字，8字以内，含冲突/结果）"
  },
  "social": {
    "douyin_copy": "抖音发布文案（带钩子和互动引导）",
    "hashtags": ["#话题1", "#话题2", "#话题3"],
    "intro": "简介/置顶评论引导"
  }
}

硬性要求：
1. effects 必须给足6条备选，但只是"备选清单"，脚本里不要插入任何动效标记；
2. 不要输出画中画建议；
3. titles 必须正好3组；hashtags 5-8个且带#号；
4. 所有内容必须围绕上面这条选题，可直接落地使用。''';

    final selectedModel = await getSelectedModel();
    final raw = await _callTextModel([
      {'role': 'system', 'content': _systemPrompt},
      {'role': 'user', 'content': prompt},
    ], temperature: 0.85, modelOverride: selectedModel == '自动选择' ? null : selectedModel, maxTokens: 6000);

    final obj = _extractJsonObject(raw);
    if (obj == null) {
      // JSON解析失败：把整段文本当作脚本兜底，保证用户有可用产出
      return IpAutoPackage(
        input: input,
        mode: mode,
        script: raw.trim(),
        subtitle: const SubtitlePlan(styles: [], fontSize: '', color: '', stroke: ''),
        effects: const [],
        bgm: const BgmRecommendation(genre: '', name: '', volume: '', usage: ''),
        coverTitle: const CoverTitle(titles: [], coverCopy: ''),
        social: const SocialPublishInfo(douyinCopy: '', hashtags: [], intro: ''),
        createdAt: DateTime.now(),
        modelUsed: selectedModel,
      );
    }

    return IpAutoPackage.fromJson(
      obj,
      input: input,
      mode: mode,
      modelUsed: selectedModel,
    );
  }

  /// 根据触发模式拼装指令段
  String _buildModeInstruction(String input, String mode) {
    switch (mode) {
      case 'replicate':
        // 用户点了【复刻它】，input 是复刻指令（可能自带【复刻它】前缀）
        final cleaned = input.replaceAll('【复刻它】', '').trim();
        return '用户发送了复刻指令：「【复刻它】$cleaned」。\n'
            '请仿写这条爆款的语气、结构、钩子，生成同赛道的一条全新口播稿：保留原版的节奏与爆款框架，但选题角度、案例、措辞必须是新的，不能照抄。';
      case 'reference':
        return '用户提供了一段爆款参考视频文案/口播稿，请先在脑中提取它的爆款框架（钩子类型、结构节奏、痛点切入、结尾引导），'
            '然后基于该框架生成一条同赛道的全新口播创作包。参考文案如下：\n"""\n$input\n"""';
      case 'keyword':
      default:
        return '用户输入的行业关键词/选题是：「$input」。请直接为该选题产出完整创作包。';
    }
  }

  // ==================== 底层模型调用 ====================

  /// 调用文本模型：指定模型走对应Provider，未指定走免费智能路由。
  /// 对 MiniMax 做特殊兜底：用户没配Key时自动回退智能路由，避免功能直接不可用。
  Future<String> _callTextModel(
    List<Map<String, String>> messages, {
    double temperature = 0.8,
    String? modelOverride,
    int maxTokens = 4096,
  }) async {
    Future<String> viaSmart() => _apiClient.chatSmart(
          messages: messages,
          temperature: temperature,
          maxTokens: maxTokens,
        );

    if (modelOverride == null || modelOverride == '自动选择') {
      return viaSmart();
    }

    // MiniMax：检查Key是否已配置，未配置则回退智能路由（零成本可用）
    if (modelOverride == 'MiniMax-Text-01') {
      final key = await StorageUtil.getSecure(ApiConfig.minimaxApiKeyKey);
      if (key == null || key.trim().isEmpty) {
        return viaSmart();
      }
    }

    try {
      return await _apiClient.chatSmart(
        messages: messages,
        temperature: temperature,
        modelOverride: modelOverride,
        maxTokens: maxTokens,
      );
    } catch (e) {
      // 指定模型失败（如Key无效、限流），回退到免费智能路由，保证出结果
      if (modelOverride == 'MiniMax-Text-01' ||
          modelOverride == 'deepseek-chat') {
        return viaSmart();
      }
      rethrow;
    }
  }

  // ==================== JSON 解析工具 ====================

  /// 从模型输出中提取JSON对象
  Map<String, dynamic>? _extractJsonObject(String text) {
    final cleaned = _stripCodeFence(text);
    // 直接解析
    final direct = _tryDecode(cleaned);
    if (direct is Map<String, dynamic>) return direct;

    // 抓第一个 { 到最后一个 }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final candidate = cleaned.substring(start, end + 1);
      final parsed = _tryDecode(candidate);
      if (parsed is Map<String, dynamic>) return parsed;
    }
    return null;
  }

  /// 从模型输出中提取JSON数组
  List<dynamic> _extractJsonArray(String text) {
    final cleaned = _stripCodeFence(text);
    final direct = _tryDecode(cleaned);
    if (direct is List) return direct;

    final start = cleaned.indexOf('[');
    final end = cleaned.lastIndexOf(']');
    if (start >= 0 && end > start) {
      final candidate = cleaned.substring(start, end + 1);
      final parsed = _tryDecode(candidate);
      if (parsed is List) return parsed;
    }
    return const [];
  }

  String _stripCodeFence(String text) {
    var t = text.trim();
    final fence = RegExp(r'^```(?:json)?\s*([\s\S]*?)\s*```$');
    final m = fence.firstMatch(t);
    if (m != null) {
      t = m.group(1)!.trim();
    }
    return t;
  }

  dynamic _tryDecode(String src) {
    try {
      return jsonDecode(src);
    } catch (_) {
      return null;
    }
  }
}

/// IpAutoService 的 Riverpod Provider
final ipAutoServiceProvider = Provider<IpAutoService>((ref) {
  return IpAutoService(ref.read(apiClientProvider));
});
