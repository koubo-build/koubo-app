import '../models/audit_result.dart';

/// 关键词过滤引擎 - 精确匹配 + 模糊匹配 + 拼音匹配
/// 内置基础违禁词库，支持自定义词库扩展
class WordFilterEngine {
  WordFilterEngine() {
    _initBuiltinWords();
  }

  // ==================== 词库存储 ====================

  /// 广告法违禁词库
  final List<WordEntry> _adLawWords = [];

  /// 抖音平台敏感词库
  final List<WordEntry> _douyinSensitiveWords = [];

  /// 行业特规词库
  final List<WordEntry> _industryWords = [];

  /// 用户自定义词库
  final List<WordEntry> _customWords = [];

  /// 所有词库的合并列表（用于快速匹配）
  List<WordEntry> get _allWords => [
        ..._adLawWords,
        ..._douyinSensitiveWords,
        ..._industryWords,
        ..._customWords,
      ];

  // ==================== 初始化内置词库 ====================

  void _initBuiltinWords() {
    // ===== 广告法违禁词库 =====

    // 绝对化用语
    _adLawWords.addAll([
      WordEntry(word: '最好', category: '广告法违禁词', riskLevel: '高风险', suggestion: '非常好'),
      WordEntry(word: '最佳', category: '广告法违禁词', riskLevel: '高风险', suggestion: '优秀'),
      WordEntry(word: '最优', category: '广告法违禁词', riskLevel: '高风险', suggestion: '领先'),
      WordEntry(word: '第一', category: '广告法违禁词', riskLevel: '高风险', suggestion: '名列前茅'),
      WordEntry(word: '首个', category: '广告法违禁词', riskLevel: '高风险', suggestion: '早期'),
      WordEntry(word: '唯一', category: '广告法违禁词', riskLevel: '高风险', suggestion: '稀有'),
      WordEntry(word: '顶级', category: '广告法违禁词', riskLevel: '高风险', suggestion: '高端'),
      WordEntry(word: '极品', category: '广告法违禁词', riskLevel: '高风险', suggestion: '精品'),
      WordEntry(word: '绝对', category: '广告法违禁词', riskLevel: '高风险', suggestion: '非常'),
      WordEntry(word: '绝佳', category: '广告法违禁词', riskLevel: '高风险', suggestion: '出色'),
      WordEntry(word: '至尊', category: '广告法违禁词', riskLevel: '高风险', suggestion: '尊享'),
      WordEntry(word: '冠军', category: '广告法违禁词', riskLevel: '中风险', suggestion: '领先者'),
      WordEntry(word: '王者', category: '广告法违禁词', riskLevel: '中风险', suggestion: '领先品牌'),
      WordEntry(word: '国家级', category: '广告法违禁词', riskLevel: '高风险', suggestion: '权威'),
      WordEntry(word: '世界级', category: '广告法违禁词', riskLevel: '高风险', suggestion: '国际水准'),
      WordEntry(word: '全网最低', category: '广告法违禁词', riskLevel: '高风险', suggestion: '极具性价比'),
      WordEntry(word: '史上最', category: '广告法违禁词', riskLevel: '高风险', suggestion: '非常'),
      WordEntry(word: '前无古人', category: '广告法违禁词', riskLevel: '高风险', suggestion: '前所未见'),
    ]);

    // 虚假承诺
    _adLawWords.addAll([
      WordEntry(word: '包治百病', category: '广告法违禁词', riskLevel: '高风险', suggestion: '有助于改善'),
      WordEntry(word: '药到病除', category: '广告法违禁词', riskLevel: '高风险', suggestion: '辅助调理'),
      WordEntry(word: '零风险', category: '广告法违禁词', riskLevel: '高风险', suggestion: '低风险'),
      WordEntry(word: '稳赚不赔', category: '广告法违禁词', riskLevel: '高风险', suggestion: '稳健投资'),
      WordEntry(word: '100%有效', category: '广告法违禁词', riskLevel: '高风险', suggestion: '效果显著'),
      WordEntry(word: '无效退款', category: '广告法违禁词', riskLevel: '中风险', suggestion: '售后保障'),
      WordEntry(word: '三天见效', category: '广告法违禁词', riskLevel: '高风险', suggestion: '持续使用有效'),
      WordEntry(word: '永不复发', category: '广告法违禁词', riskLevel: '高风险', suggestion: '长期稳定'),
      WordEntry(word: '根除', category: '广告法违禁词', riskLevel: '高风险', suggestion: '有效改善'),
      WordEntry(word: '彻底治愈', category: '广告法违禁词', riskLevel: '高风险', suggestion: '科学调理'),
    ]);

    // 权威暗示
    _adLawWords.addAll([
      WordEntry(word: '特供', category: '广告法违禁词', riskLevel: '高风险', suggestion: '精选'),
      WordEntry(word: '专供', category: '广告法违禁词', riskLevel: '高风险', suggestion: '定制'),
      WordEntry(word: '驰名商标', category: '广告法违禁词', riskLevel: '中风险', suggestion: '知名品牌'),
      WordEntry(word: '质量免检', category: '广告法违禁词', riskLevel: '高风险', suggestion: '质量可靠'),
      WordEntry(word: '指定产品', category: '广告法违禁词', riskLevel: '中风险', suggestion: '优选产品'),
    ]);

    // 诱导消费
    _adLawWords.addAll([
      WordEntry(word: '秒杀', category: '广告法违禁词', riskLevel: '中风险', suggestion: '限时优惠'),
      WordEntry(word: '抢购', category: '广告法违禁词', riskLevel: '低风险', suggestion: '热销中'),
      WordEntry(word: '仅剩最后', category: '广告法违禁词', riskLevel: '中风险', suggestion: '库存紧张'),
      WordEntry(word: '限时特价', category: '广告法违禁词', riskLevel: '低风险', suggestion: '限时优惠'),
      WordEntry(word: '亏本甩卖', category: '广告法违禁词', riskLevel: '中风险', suggestion: '超值特惠'),
    ]);

    // ===== 抖音平台敏感词库 =====

    // 引流类
    _douyinSensitiveWords.addAll([
      WordEntry(word: '加微信', category: '平台违规', riskLevel: '高风险', suggestion: '评论区留言'),
      WordEntry(word: '加VX', category: '平台违规', riskLevel: '高风险', suggestion: '主页了解'),
      WordEntry(word: '私聊领取', category: '平台违规', riskLevel: '中风险', suggestion: '评论区留言'),
      WordEntry(word: '关注公众号', category: '平台违规', riskLevel: '高风险', suggestion: '关注了解更多'),
      WordEntry(word: '加群', category: '平台违规', riskLevel: '中风险', suggestion: '粉丝互动'),
      WordEntry(word: '转账', category: '平台违规', riskLevel: '高风险', suggestion: '正规渠道购买'),
      WordEntry(word: '红包返现', category: '平台违规', riskLevel: '高风险', suggestion: '优惠活动'),
    ]);

    // 虚假互动类
    _douyinSensitiveWords.addAll([
      WordEntry(word: '互关互赞', category: '平台违规', riskLevel: '中风险', suggestion: '感谢关注'),
      WordEntry(word: '刷粉', category: '平台违规', riskLevel: '高风险', suggestion: '提升内容质量'),
      WordEntry(word: '买赞', category: '平台违规', riskLevel: '高风险', suggestion: '创作优质内容'),
      WordEntry(word: '代运营', category: '平台违规', riskLevel: '中风险', suggestion: '专业运营建议'),
      WordEntry(word: '保证上热门', category: '平台违规', riskLevel: '高风险', suggestion: '提升曝光'),
      WordEntry(word: '包涨粉', category: '平台违规', riskLevel: '高风险', suggestion: '稳步增长'),
    ]);

    // 违规内容类
    _douyinSensitiveWords.addAll([
      WordEntry(word: '代孕', category: '敏感词', riskLevel: '高风险', suggestion: ''),
      WordEntry(word: '买卖器官', category: '敏感词', riskLevel: '高风险', suggestion: ''),
      WordEntry(word: '赌博', category: '敏感词', riskLevel: '高风险', suggestion: ''),
      WordEntry(word: '高利贷', category: '敏感词', riskLevel: '高风险', suggestion: ''),
      WordEntry(word: '传销', category: '敏感词', riskLevel: '高风险', suggestion: ''),
      WordEntry(word: '非法集资', category: '敏感词', riskLevel: '高风险', suggestion: ''),
    ]);

    // ===== 行业特规词库 =====

    // 医疗健康
    _industryWords.addAll([
      WordEntry(word: '治愈率', category: '虚假宣传', riskLevel: '高风险', suggestion: '康复情况'),
      WordEntry(word: '有效率', category: '虚假宣传', riskLevel: '高风险', suggestion: '使用反馈'),
      WordEntry(word: '偏方', category: '虚假宣传', riskLevel: '中风险', suggestion: '传统方法'),
      WordEntry(word: '秘方', category: '虚假宣传', riskLevel: '中风险', suggestion: '独特配方'),
      WordEntry(word: '祖传', category: '虚假宣传', riskLevel: '低风险', suggestion: '传统'),
      WordEntry(word: '神药', category: '虚假宣传', riskLevel: '高风险', suggestion: '好用的产品'),
    ]);

    // 金融理财
    _industryWords.addAll([
      WordEntry(word: '保本保息', category: '虚假宣传', riskLevel: '高风险', suggestion: '稳健理财'),
      WordEntry(word: '荐股', category: '虚假宣传', riskLevel: '高风险', suggestion: '投资参考'),
      WordEntry(word: '内幕消息', category: '虚假宣传', riskLevel: '高风险', suggestion: '市场分析'),
      WordEntry(word: '庄家', category: '虚假宣传', riskLevel: '中风险', suggestion: '大资金'),
      WordEntry(word: '割韭菜', category: '虚假宣传', riskLevel: '中风险', suggestion: '市场波动'),
      WordEntry(word: '杠杆暴富', category: '虚假宣传', riskLevel: '高风险', suggestion: '合理投资'),
    ]);

    // 教育培训
    _industryWords.addAll([
      WordEntry(word: '保过', category: '虚假宣传', riskLevel: '高风险', suggestion: '高效备考'),
      WordEntry(word: '包过', category: '虚假宣传', riskLevel: '高风险', suggestion: '系统学习'),
      WordEntry(word: '考前押题', category: '虚假宣传', riskLevel: '高风险', suggestion: '重点复习'),
      WordEntry(word: '包录取', category: '虚假宣传', riskLevel: '高风险', suggestion: '提升录取率'),
      WordEntry(word: '零基础包就业', category: '虚假宣传', riskLevel: '高风险', suggestion: '零基础系统学习'),
    ]);
  }

  // ==================== 核心过滤方法 ====================

  /// 执行三重过滤：精确匹配 + 模糊匹配 + 拼音匹配
  /// [text] 待检测文本
  /// 返回匹配到的违禁词问题列表
  List<AuditIssue> filter(String text) {
    final issues = <AuditIssue>[];

    // 1. 精确匹配
    issues.addAll(_exactMatch(text));

    // 2. 模糊匹配（处理变体写法）
    issues.addAll(_fuzzyMatch(text));

    // 3. 拼音匹配（处理谐音规避）
    issues.addAll(_pinyinMatch(text));

    // 去重
    return _deduplicate(issues);
  }

  /// 精确匹配 - 直接比对文本中的关键词
  List<AuditIssue> _exactMatch(String text) {
    final issues = <AuditIssue>[];

    for (final entry in _allWords) {
      if (text.contains(entry.word)) {
        // 找到所有出现位置
        int startIndex = 0;
        while (true) {
          final index = text.indexOf(entry.word, startIndex);
          if (index == -1) break;

          issues.add(AuditIssue(
            type: entry.category,
            riskLevel: entry.riskLevel,
            originalText: entry.word,
            position: '$index-${index + entry.word.length}',
            reason: _getReason(entry),
            suggestion: entry.suggestion.isNotEmpty ? entry.suggestion : '请删除或替换该词汇',
          ));

          startIndex = index + 1;
        }
      }
    }

    return issues;
  }

  /// 模糊匹配 - 识别变体写法
  /// 处理：最.好 → 最好，第① → 第一，符号插入等
  List<AuditIssue> _fuzzyMatch(String text) {
    final issues = <AuditIssue>[];

    // 先对文本做规范化处理
    final normalizedText = _normalizeText(text);

    for (final entry in _adLawWords) {
      // 如果精确匹配已经找到，跳过
      if (text.contains(entry.word)) continue;

      // 在规范化后的文本中搜索
      if (normalizedText.contains(entry.word)) {
        // 尝试在原文中定位变体写法
        final variant = _findVariantInOriginal(text, entry.word);
        if (variant != null) {
          issues.add(AuditIssue(
            type: '${entry.category}(变体)',
            riskLevel: entry.riskLevel,
            originalText: variant,
            position: '',
            reason: '检测到"${entry.word}"的变体写法"${variant}"，${_getReason(entry)}',
            suggestion: entry.suggestion,
          ));
        }
      }
    }

    return issues;
  }

  /// 拼音匹配 - 识别谐音规避
  /// 处理："醉好" → "最好"，"国佳" → "国家"
  List<AuditIssue> _pinyinMatch(String text) {
    final issues = <AuditIssue>[];

    // 拼音匹配词库（常见的谐音规避映射）
    final pinyinMappings = {
      '最好': ['醉好', '最壕', '蕞好'],
      '第一': ['第①', '第1', '地衣', '弟一'],
      '顶级': ['鼎级', '丁级'],
      '唯一': ['唯①', '为依'],
      '最佳': ['醉佳'],
      '国家级': ['国佳级', '国家集'],
      '加微信': ['加VX', '加威信', '加V', '➕V'],
      '关注公众号': ['关注公号', '关注众号'],
    };

    for (final entry in pinyinMappings.entries) {
      final standardWord = entry.key;
      final variants = entry.value;

      for (final variant in variants) {
        if (text.contains(variant)) {
          // 检查精确匹配是否已找到标准词
          if (text.contains(standardWord)) continue;

          // 查找标准词对应的WordEntry
          final wordEntry = _allWords.where((w) => w.word == standardWord).firstOrNull;

          issues.add(AuditIssue(
            type: '${wordEntry?.category ?? '广告法违禁词'}(谐音规避)',
            riskLevel: wordEntry?.riskLevel ?? '中风险',
            originalText: variant,
            position: '',
            reason: '检测到"${standardWord}"的谐音规避写法"${variant}"',
            suggestion: wordEntry?.suggestion ?? '请使用合规表达',
          ));
        }
      }
    }

    return issues;
  }

  // ==================== 辅助方法 ====================

  /// 文本规范化 - 移除干扰字符，还原变体写法
  String _normalizeText(String text) {
    var result = text;

    // 移除常见的干扰符号
    final noiseChars = ['.', '·', '✅', '❌', '⭐', '🔥', '💡', ' ', ' ', '/', '|', '-', '_'];
    for (final char in noiseChars) {
      result = result.replaceAll(char, '');
    }

    // 还原数字变体
    result = result.replaceAll('①', '1');
    result = result.replaceAll('②', '2');
    result = result.replaceAll('③', '3');

    // 还全角为半角
    result = result.replaceAll('０', '0');
    result = result.replaceAll('１', '1');
    result = result.replaceAll('２', '2');
    result = result.replaceAll('３', '3');
    result = result.replaceAll('４', '4');
    result = result.replaceAll('５', '5');
    result = result.replaceAll('６', '6');
    result = result.replaceAll('７', '7');
    result = result.replaceAll('８', '8');
    result = result.replaceAll('９', '9');

    return result;
  }

  /// 在原文中查找变体写法
  String? _findVariantInOriginal(String originalText, String standardWord) {
    // 简单实现：查找原文中与标准词长度相近、包含部分相同字符的子串
    // 实际场景中可用更精确的算法

    // 对于2字词，查找可能的2字变体
    if (standardWord.length == 2) {
      for (int i = 0; i < originalText.length - 1; i++) {
        final twoChars = originalText.substring(i, i + 2);
        final normalized = _normalizeText(twoChars);
        if (normalized == standardWord && twoChars != standardWord) {
          return twoChars;
        }
      }
    }

    return null;
  }

  /// 获取违规原因描述
  String _getReason(WordEntry entry) {
    switch (entry.category) {
      case '广告法违禁词':
        if (entry.riskLevel == '高风险') {
          return '使用了广告法禁止的绝对化用语/虚假承诺，违反《广告法》第九条';
        }
        return '使用了广告法限制性用语，可能引起消费者误解';
      case '敏感词':
        return '包含平台严禁的敏感内容，可能导致视频被下架或账号封禁';
      case '平台违规':
        return '违反抖音社区规范，可能导致内容被限流或删除';
      case '虚假宣传':
        return '存在虚假/夸大宣传，违反《广告法》及相关行业法规';
      case '侵权风险':
        return '可能涉及他人知识产权侵权风险';
      default:
        return '存在合规风险';
    }
  }

  /// 去重 - 移除重复的审核问题
  List<AuditIssue> _deduplicate(List<AuditIssue> issues) {
    final seen = <String>{};
    return issues.where((issue) {
      final key = '${issue.originalText}_${issue.type}';
      if (seen.contains(key)) return false;
      seen.add(key);
      return true;
    }).toList();
  }

  // ==================== 自定义词库管理 ====================

  /// 添加自定义敏感词
  void addCustomWord(WordEntry entry) {
    _customWords.add(entry);
  }

  /// 批量添加自定义敏感词
  void addCustomWords(List<WordEntry> entries) {
    _customWords.addAll(entries);
  }

  /// 删除自定义敏感词
  void removeCustomWord(String word) {
    _customWords.removeWhere((entry) => entry.word == word);
  }

  /// 获取所有自定义敏感词
  List<WordEntry> getCustomWords() {
    return List.unmodifiable(_customWords);
  }

  /// 清空自定义词库
  void clearCustomWords() {
    _customWords.clear();
  }

  /// 获取所有内置词库（只读）
  List<WordEntry> getBuiltinWords() {
    return List.unmodifiable([..._adLawWords, ..._douyinSensitiveWords, ..._industryWords]);
  }

  /// 获取词库统计信息
  Map<String, int> getWordCount() {
    return {
      '广告法违禁词': _adLawWords.length,
      '抖音敏感词': _douyinSensitiveWords.length,
      '行业特规词': _industryWords.length,
      '自定义词': _customWords.length,
      '总计': _allWords.length,
    };
  }
}

/// 词语条目 - 表示词库中的一个词
class WordEntry {
  final String word;          // 敏感词/违禁词
  final String category;      // 分类
  final String riskLevel;     // 风险等级
  final String suggestion;    // 修改建议

  const WordEntry({
    required this.word,
    required this.category,
    required this.riskLevel,
    this.suggestion = '',
  });

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is WordEntry && other.word == word && other.category == category;
  }

  @override
  int get hashCode => word.hashCode ^ category.hashCode;
}
