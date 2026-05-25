import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/api_config.dart';
import '../models/rewrite_version.dart';
import 'api_client.dart';

/// AI改写服务 - 支持6种改写模式、多版本并行生成、SSE流式输出、评分功能
/// 优化版：确保SSE流式完整、多版本并行逻辑完整、改写时自动规避审核风险词
class AiRewriteService {
  final ApiClient _apiClient;

  AiRewriteService(this._apiClient);

  // ==================== 6种改写模式Prompt模板 ====================

  /// 同义改写Prompt
  static const String _promptSynonym = '''你是一位专业的口播文案改写师。请对以下文案进行同义改写，要求：
1. 保持原文核心含义和信息完整
2. 更换表达方式，调整句式结构
3. 适合口播朗读，节奏感好
4. 避免与原文高度相似（相似度低于60%）

原文：
{source_text}

请直接输出改写结果，不要解释。''';

  /// 口语化改写Prompt
  static const String _promptColloquial = '''你是一位短视频口播文案专家。请将以下文案改写为自然口语化的口播风格，要求：
1. 加入口语化表达（如"说实话"、"跟你们讲"等过渡词）
2. 句子短小有力，适合朗读
3. 节奏感强，有呼吸点
4. 保留原文核心信息

原文：
{source_text}

请直接输出改写结果，不要解释。''';

  /// 缩写精简Prompt
  static const String _promptCondense = '''你是一位文案精简专家。请将以下文案精简为{target_length}字以内的短文案，要求：
1. 保留最核心的3个要点
2. 删除所有冗余修饰
3. 开头一句话抓住注意力
4. 结尾有明确的行动号召

原文：
{source_text}

请直接输出改写结果，不要解释。''';

  /// 扩写丰富Prompt
  static const String _promptExpand = '''你是一位口播文案创作专家。请将以下短文案扩写为丰富的口播文案，要求：
1. 补充具体案例、数据、场景描述
2. 加入情感渲染和故事元素
3. 增加互动感（提问、呼吁）
4. 保持口播风格，适合1-3分钟朗读

原文：
{source_text}

请直接输出改写结果，不要解释。''';

  /// 风格转换Prompt
  static const String _promptStyleTransfer = '''你是一位多风格口播文案创作专家。请将以下文案改写为{style}风格，要求：
1. 完全融入{style}的表达特点
2. 语气、用词、节奏匹配该风格
3. 保留原文核心信息
4. 开头3秒必须有该风格的标志性吸引点

原文：
{source_text}

请直接输出改写结果，不要解释。''';

  /// 去重改写Prompt
  static const String _promptDeduplicate = '''你是一位文案去重专家。请对以下文案进行深度改写以避免平台查重，要求：
1. 核心含义不变，但表达方式完全不同
2. 替换所有关键词汇为同义词
3. 调整叙事顺序和逻辑结构
4. 相似度控制在30%以下
5. 保持口播风格的自然流畅

原文：
{source_text}

请直接输出改写结果，不要解释。''';

  /// 评分Prompt
  static const String _promptScore = '''你是一位口播文案质量评审专家。请对以下改写结果进行评分（0-100分）：

原文：
{source_text}

改写模式：{rewrite_mode}
改写结果：
{rewritten_text}

请按以下维度评分并给出改进建议（JSON格式）：
{{
  "语义保真度": {{"score": 0-100, "comment": ""}},
  "表达自然度": {{"score": 0-100, "comment": ""}},
  "差异度": {{"score": 0-100, "comment": ""}},
  "合规性": {{"score": 0-100, "comment": ""}},
  "吸引力": {{"score": 0-100, "comment": ""}},
  "total_score": 0-100,
  "improvement_suggestion": ""
}}''';

  // ==================== 改写模式枚举 ====================

  /// 改写模式列表（公开常量，供UI层引用）
  static const List<Map<String, String>> rewriteModes = [
    {'key': '同义改写', 'label': '同义改写', 'desc': '保持原意，更换表达方式'},
    {'key': '口语化改写', 'label': '口语化改写', 'desc': '转为自然口播语气'},
    {'key': '缩写精简', 'label': '缩写精简', 'desc': '长文案→短文案'},
    {'key': '扩写丰富', 'label': '扩写丰富', 'desc': '短文案→长文案'},
    {'key': '风格转换', 'label': '风格转换', 'desc': '搞笑/专业/情感等'},
    {'key': '去重改写', 'label': '去重改写', 'desc': '深度改写避免查重'},
  ];

  /// 风格列表（公开常量，供UI层引用）
  static const List<String> styleList = [
    '搞笑幽默',
    '专业权威',
    '情感走心',
    '励志鸡血',
    '悬疑吸引',
    '亲切日常',
  ];

  // ==================== 核心方法 ====================

  /// 多版本改写（核心方法）
  /// [sourceText] 原始文案
  /// [mode] 改写模式
  /// [style] 风格（风格转换模式必填）
  /// [targetLength] 目标字数（缩写精简模式使用）
  /// [versionCount] 生成版本数量，默认3个
  /// [avoidWords] 需要规避的词汇列表（来自法务审核）
  Future<List<RewriteVersion>> rewrite({
    required String sourceText,
    required String mode,
    String? style,
    int? targetLength,
    int versionCount = 3,
    List<String>? avoidWords,
  }) async {
    // 1. 构建改写Prompt
    final prompt = _buildPrompt(
      sourceText: sourceText,
      mode: mode,
      style: style,
      targetLength: targetLength,
      avoidWords: avoidWords,
    );

    // 2. 并行生成多个版本（通过不同temperature差异化）
    final futures = <Future<RewriteVersion>>[];
    for (int i = 0; i < versionCount; i++) {
      final temperature = 0.7 + i * 0.1; // 0.7, 0.8, 0.9 递增创意度
      futures.add(
        _generateVersion(
          sourceText: sourceText,
          prompt: prompt,
          mode: mode,
          versionNumber: i + 1,
          temperature: temperature,
        ),
      );
    }

    // 并行等待所有版本生成完成
    final versions = await Future.wait(futures);

    // 3. 按评分排序
    final sortedVersions = List<RewriteVersion>.from(versions)
      ..sort((a, b) => b.score.compareTo(a.score));

    // 标记最高分的版本为选中
    if (sortedVersions.isNotEmpty) {
      sortedVersions[0] = RewriteVersion(
        id: sortedVersions[0].id,
        scriptId: sortedVersions[0].scriptId,
        versionNumber: sortedVersions[0].versionNumber,
        rewrittenText: sortedVersions[0].rewrittenText,
        score: sortedVersions[0].score,
        scoreDetails: sortedVersions[0].scoreDetails,
        similarity: sortedVersions[0].similarity,
        isSelected: true,
        createdAt: sortedVersions[0].createdAt,
      );
    }

    return sortedVersions;
  }

  /// 单次改写（非流式，用于并行生成多版本中的单个版本）
  /// 返回改写后的文本
  Future<String> rewriteSingle({
    required String sourceText,
    required String mode,
    String? style,
    int? targetLength,
    double temperature = 0.8,
    List<String>? avoidWords,
  }) async {
    final prompt = _buildPrompt(
      sourceText: sourceText,
      mode: mode,
      style: style,
      targetLength: targetLength,
      avoidWords: avoidWords,
    );

    final rewrittenText = await _apiClient.chatSmart(
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      temperature: temperature,
    );

    return rewrittenText.trim();
  }

  /// 对单个版本评分
  /// 返回总分（0-100）
  Future<int> scoreVersion({
    required String sourceText,
    required String rewrittenText,
    required String mode,
  }) async {
    try {
      final scorePrompt = _promptScore
          .replaceAll('{source_text}', sourceText)
          .replaceAll('{rewrite_mode}', mode)
          .replaceAll('{rewritten_text}', rewrittenText);

      final result = await _apiClient.chatSmart(
        messages: [
          {
            'role': 'system',
            'content': '你是一位口播文案质量评审专家，请严格按照要求输出JSON格式的评分结果。'
          },
          {'role': 'user', 'content': scorePrompt},
        ],
        temperature: 0.3,
      );

      final jsonStr = _extractJson(result);
      if (jsonStr != null) {
        final data = jsonDecode(jsonStr) as Map<String, dynamic>;
        return data['total_score'] as int? ?? 60;
      }
    } catch (_) {
      // 评分失败
    }
    return 60; // 默认中等分数
  }

  /// 流式改写（SSE逐字输出效果，像ChatGPT一样）
  /// 确保SSE流式输出实现完整，逐块返回文本
  Stream<String> rewriteStream({
    required String sourceText,
    required String mode,
    String? style,
    int? targetLength,
    List<String>? avoidWords,
  }) {
    final prompt = _buildPrompt(
      sourceText: sourceText,
      mode: mode,
      style: style,
      targetLength: targetLength,
      avoidWords: avoidWords,
    );

    return _apiClient.chatSmartStream(
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      temperature: 0.8,
    );
  }

  // ==================== 内部方法 ====================

  /// 构建改写Prompt
  /// 自动将规避词列表注入Prompt，确保改写时自动规避审核已发现的风险词
  String _buildPrompt({
    required String sourceText,
    required String mode,
    String? style,
    int? targetLength,
    List<String>? avoidWords,
  }) {
    String prompt;

    switch (mode) {
      case '同义改写':
        prompt = _promptSynonym;
        break;
      case '口语化改写':
        prompt = _promptColloquial;
        break;
      case '缩写精简':
        prompt = _promptCondense;
        prompt = prompt.replaceAll('{target_length}', '${targetLength ?? 100}');
        break;
      case '扩写丰富':
        prompt = _promptExpand;
        break;
      case '风格转换':
        prompt = _promptStyleTransfer;
        prompt = prompt.replaceAll('{style}', style ?? '搞笑幽默');
        break;
      case '去重改写':
        prompt = _promptDeduplicate;
        break;
      default:
        prompt = _promptSynonym;
    }

    // 替换原文占位符
    prompt = prompt.replaceAll('{source_text}', sourceText);

    // 如果有规避词列表，追加到Prompt
    // 这是改写时自动规避审核已发现风险词的关键逻辑
    if (avoidWords != null && avoidWords.isNotEmpty) {
      final wordsStr = avoidWords.join('、');
      prompt += '\n\n特别注意：以下词汇已被法务审核标记为风险词汇，改写时必须绝对避免使用：$wordsStr';
      prompt += '\n请使用合规的替换词替代上述风险词汇。';
    }

    return prompt;
  }

  /// 生成单个版本（带评分）
  Future<RewriteVersion> _generateVersion({
    required String sourceText,
    required String prompt,
    required String mode,
    required int versionNumber,
    required double temperature,
  }) async {
    // 调用智能路由生成改写（自动选择可用API）
    final rewrittenText = await _apiClient.chatSmart(
      messages: [
        {'role': 'user', 'content': prompt},
      ],
      temperature: temperature,
    );

    // 调用辅助模型（Qwen2.5-7B）评分
    int score = 0;
    String? scoreDetails;
    try {
      final scoreResult = await _scoreVersion(
        sourceText: sourceText,
        rewrittenText: rewrittenText,
        mode: mode,
      );
      score = scoreResult['total_score'] as int? ?? 0;
      scoreDetails = jsonEncode(scoreResult);
    } catch (_) {
      // 评分失败不影响主流程
      score = 50; // 默认中等分数
    }

    return RewriteVersion(
      versionNumber: versionNumber,
      rewrittenText: rewrittenText.trim(),
      score: score,
      scoreDetails: scoreDetails,
      isSelected: false,
      createdAt: DateTime.now(),
    );
  }

  /// 对单个版本评分（完整版，返回详细评分数据）
  Future<Map<String, dynamic>> _scoreVersion({
    required String sourceText,
    required String rewrittenText,
    required String mode,
  }) async {
    final scorePrompt = _promptScore
        .replaceAll('{source_text}', sourceText)
        .replaceAll('{rewrite_mode}', mode)
        .replaceAll('{rewritten_text}', rewrittenText);

    // 调用辅助模型评分（低temperature确保评分稳定）
    final result = await _apiClient.chatSiliconFlow(
      messages: [
        {
          'role': 'system',
          'content': '你是一位口播文案质量评审专家，请严格按照要求输出JSON格式的评分结果。'
        },
        {'role': 'user', 'content': scorePrompt},
      ],
      temperature: 0.3,
    );

    // 解析JSON评分结果
    try {
      final jsonStr = _extractJson(result);
      if (jsonStr != null) {
        return jsonDecode(jsonStr) as Map<String, dynamic>;
      }
    } catch (_) {
      // JSON解析失败
    }

    // 返回默认评分
    return {
      '语义保真度': {'score': 70, 'comment': '评分解析失败'},
      '表达自然度': {'score': 70, 'comment': '评分解析失败'},
      '差异度': {'score': 70, 'comment': '评分解析失败'},
      '合规性': {'score': 70, 'comment': '评分解析失败'},
      '吸引力': {'score': 70, 'comment': '评分解析失败'},
      'total_score': 70,
      'improvement_suggestion': '评分解析失败，请手动评估',
    };
  }

  /// 从文本中提取JSON字符串
  String? _extractJson(String text) {
    // 尝试匹配```json ... ```格式
    final jsonBlockRegex = RegExp(r'```json\s*([\s\S]*?)\s*```');
    final blockMatch = jsonBlockRegex.firstMatch(text);
    if (blockMatch != null) {
      return blockMatch.group(1);
    }

    // 尝试匹配{ ... }格式
    final braceRegex = RegExp(r'\{[\s\S]*\}');
    final braceMatch = braceRegex.firstMatch(text);
    if (braceMatch != null) {
      return braceMatch.group(0);
    }

    return null;
  }
}

/// AiRewriteService的Riverpod Provider
final aiRewriteServiceProvider = Provider<AiRewriteService>((ref) {
  return AiRewriteService(ref.read(apiClientProvider));
});
