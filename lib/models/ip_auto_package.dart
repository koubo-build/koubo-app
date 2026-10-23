/// IP口播全自动生成 - 数据模型
/// 对应「自动模式」固定输出的7段卡片结构：
/// 选题卡片 / 口播脚本 / 字幕方案 / 动效清单 / BGM / 封面标题 / 社媒发布信息

/// 选题参考卡片（可点【复刻它】）
class TopicCard {
  /// 选题标题
  final String title;

  /// 所属赛道
  final String track;

  /// 前3秒钩子
  final String hook;

  /// 核心痛点
  final String painPoint;

  /// 一句话选题理由（为什么这条能爆）
  final String reason;

  /// 复刻指令（点击【复刻它】时复制/发送的内容）
  final String replicateCommand;

  const TopicCard({
    required this.title,
    required this.track,
    required this.hook,
    required this.painPoint,
    required this.reason,
    required this.replicateCommand,
  });

  factory TopicCard.fromJson(Map<String, dynamic> json) {
    return TopicCard(
      title: (json['title'] ?? '').toString(),
      track: (json['track'] ?? '').toString(),
      hook: (json['hook'] ?? '').toString(),
      painPoint: (json['pain_point'] ?? json['painPoint'] ?? '').toString(),
      reason: (json['reason'] ?? '').toString(),
      replicateCommand:
          (json['replicate_command'] ?? json['replicateCommand'] ?? '').toString(),
    );
  }
}

/// 字幕方案
class SubtitlePlan {
  /// 字幕样式备选（10条）
  final List<String> styles;

  /// 字幕字号建议
  final String fontSize;

  /// 字幕颜色建议
  final String color;

  /// 描边默认值
  final String stroke;

  const SubtitlePlan({
    required this.styles,
    required this.fontSize,
    required this.color,
    required this.stroke,
  });

  factory SubtitlePlan.fromJson(Map<String, dynamic> json) {
    final styles = (json['styles'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return SubtitlePlan(
      styles: styles,
      fontSize: (json['font_size'] ?? json['fontSize'] ?? '').toString(),
      color: (json['color'] ?? '').toString(),
      stroke: (json['stroke'] ?? '').toString(),
    );
  }
}

/// 动效备选（默认不启用，用户要才加）
class MotionEffect {
  /// 动效名称
  final String name;

  /// 适用位置/说明
  final String desc;

  const MotionEffect({required this.name, required this.desc});

  factory MotionEffect.fromJson(Map<String, dynamic> json) {
    return MotionEffect(
      name: (json['name'] ?? '').toString(),
      desc: (json['desc'] ?? '').toString(),
    );
  }
}

/// BGM推荐
class BgmRecommendation {
  /// 曲风
  final String genre;

  /// 适配音乐描述/参考名
  final String name;

  /// 音量建议
  final String volume;

  /// 使用说明
  final String usage;

  const BgmRecommendation({
    required this.genre,
    required this.name,
    required this.volume,
    required this.usage,
  });

  factory BgmRecommendation.fromJson(Map<String, dynamic> json) {
    return BgmRecommendation(
      genre: (json['genre'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      volume: (json['volume'] ?? '').toString(),
      usage: (json['usage'] ?? '').toString(),
    );
  }
}

/// 封面+标题
class CoverTitle {
  /// 3组短视频标题
  final List<String> titles;

  /// 封面文案
  final String coverCopy;

  const CoverTitle({required this.titles, required this.coverCopy});

  factory CoverTitle.fromJson(Map<String, dynamic> json) {
    final titles = (json['titles'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .where((e) => e.trim().isNotEmpty)
        .toList();
    return CoverTitle(
      titles: titles,
      coverCopy: (json['cover_copy'] ?? json['coverCopy'] ?? '').toString(),
    );
  }
}

/// 社媒发布信息
class SocialPublishInfo {
  /// 抖音文案
  final String douyinCopy;

  /// 话题标签
  final List<String> hashtags;

  /// 简介
  final String intro;

  const SocialPublishInfo({
    required this.douyinCopy,
    required this.hashtags,
    required this.intro,
  });

  factory SocialPublishInfo.fromJson(Map<String, dynamic> json) {
    // 话题标签可能是数组，也可能是带#的字符串
    List<String> tags;
    final raw = json['hashtags'];
    if (raw is List) {
      tags = raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
    } else {
      tags = (raw ?? '')
          .toString()
          .split(RegExp(r'[\s,，#]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => e.startsWith('#') ? e : '#$e')
          .toList();
    }
    return SocialPublishInfo(
      douyinCopy: (json['douyin_copy'] ?? json['douyinCopy'] ?? '').toString(),
      hashtags: tags,
      intro: (json['intro'] ?? '').toString(),
    );
  }
}

/// IP口播全自动生成的完整产物（7段卡片）
class IpAutoPackage {
  /// 本次输入（行业关键词 / 复刻指令 / 参考文案）
  final String input;

  /// 触发模式：keyword=行业关键词 / replicate=复刻它 / reference=参考文案
  final String mode;

  /// 2. 口播脚本正文（带情绪停顿标记）
  final String script;

  /// 3. 字幕方案
  final SubtitlePlan subtitle;

  /// 4. 动效清单（6条备选，默认不启用）
  final List<MotionEffect> effects;

  /// 5. BGM推荐
  final BgmRecommendation bgm;

  /// 6. 封面+标题
  final CoverTitle coverTitle;

  /// 7. 社媒发布信息
  final SocialPublishInfo social;

  /// 生成时间
  final DateTime createdAt;

  /// 实际使用的模型
  final String modelUsed;

  const IpAutoPackage({
    required this.input,
    required this.mode,
    required this.script,
    required this.subtitle,
    required this.effects,
    required this.bgm,
    required this.coverTitle,
    required this.social,
    required this.createdAt,
    this.modelUsed = '',
  });

  factory IpAutoPackage.fromJson(
    Map<String, dynamic> json, {
    required String input,
    required String mode,
    String modelUsed = '',
  }) {
    return IpAutoPackage(
      input: input,
      mode: mode,
      script: (json['script'] ?? '').toString().trim(),
      subtitle: SubtitlePlan.fromJson(
          (json['subtitle'] as Map<String, dynamic>?) ?? {}),
      effects: ((json['effects'] as List<dynamic>?) ?? [])
          .whereType<Map>()
          .map((e) => MotionEffect.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
      bgm: BgmRecommendation.fromJson(
          (json['bgm'] as Map<String, dynamic>?) ?? {}),
      coverTitle: CoverTitle.fromJson(
          (json['cover_title'] as Map<String, dynamic>?) ??
              (json['coverTitle'] as Map<String, dynamic>?) ??
              {}),
      social: SocialPublishInfo.fromJson(
          (json['social'] as Map<String, dynamic>?) ?? {}),
      createdAt: DateTime.now(),
      modelUsed: modelUsed,
    );
  }

  /// 组装成可复制的完整文案（一键复制全部）
  String toFullText() {
    final sb = StringBuffer();
    sb.writeln('【口播脚本】');
    sb.writeln(script);
    sb.writeln();
    sb.writeln('【字幕方案】');
    if (subtitle.styles.isNotEmpty) {
      sb.writeln('样式备选：${subtitle.styles.join(' / ')}');
    }
    sb.writeln('字号：${subtitle.fontSize}　颜色：${subtitle.color}　描边：${subtitle.stroke}');
    sb.writeln();
    sb.writeln('【动效备选（默认不加）】');
    for (var i = 0; i < effects.length; i++) {
      sb.writeln('${i + 1}. ${effects[i].name}｜${effects[i].desc}');
    }
    sb.writeln();
    sb.writeln('【BGM】');
    sb.writeln('${bgm.genre}｜${bgm.name}｜音量：${bgm.volume}');
    if (bgm.usage.isNotEmpty) sb.writeln(bgm.usage);
    sb.writeln();
    sb.writeln('【标题候选】');
    for (final t in coverTitle.titles) {
      sb.writeln('· $t');
    }
    if (coverTitle.coverCopy.isNotEmpty) {
      sb.writeln('封面文案：${coverTitle.coverCopy}');
    }
    sb.writeln();
    sb.writeln('【社媒发布】');
    sb.writeln(social.douyinCopy);
    if (social.hashtags.isNotEmpty) sb.writeln(social.hashtags.join(' '));
    if (social.intro.isNotEmpty) sb.writeln('简介：${social.intro}');
    return sb.toString().trim();
  }
}
