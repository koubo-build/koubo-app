import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../config/theme.dart';
import '../../models/ip_auto_package.dart';
import '../../providers/ip_auto_provider.dart';
import '../../services/ip_auto_service.dart';

/// IP口播全自动生成页（自动模式）
///
/// 一条龙：选题参考卡片 →（复刻它）→ 脚本/字幕/动效/BGM/封面标题/社媒文案。
/// 默认画中画不插、动效只给备选不启用。
class IpAutoPage extends ConsumerStatefulWidget {
  const IpAutoPage({super.key});

  @override
  ConsumerState<IpAutoPage> createState() => _IpAutoPageState();
}

class _IpAutoPageState extends ConsumerState<IpAutoPage> {
  final TextEditingController _keywordCtrl = TextEditingController();
  final TextEditingController _referenceCtrl = TextEditingController();

  @override
  void dispose() {
    _keywordCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ipAutoProvider);
    final notifier = ref.read(ipAutoProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('IP口播·全自动'),
        actions: [
          // 模型选择
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: state.selectedModel,
                dropdownColor: AppTheme.darkSurface,
                icon: const Icon(Icons.arrow_drop_down, color: AppTheme.textSecondary, size: 20),
                isDense: true,
                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                hint: const Text('模型', style: TextStyle(fontSize: 12)),
                items: IpAutoService.modelOptions
                    .map((m) => DropdownMenuItem(
                          value: m['value'],
                          child: Text(m['label']!, overflow: TextOverflow.ellipsis),
                        ))
                    .toList(),
                onChanged: state.generating || state.loadingTopics
                    ? null
                    : (v) {
                        if (v != null) notifier.changeModel(v);
                      },
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                _buildAutoModeBanner(state),
                _buildKeywordSection(state, notifier),
                _buildReferenceSection(state, notifier),
                if (state.error != null) _buildError(state.error!),
                if (state.loadingTopics) _buildTopicsLoading(),
                if (state.topics.isNotEmpty && !state.loadingTopics)
                  _buildTopicsSection(state, notifier),
                if (state.package != null)
                  _buildPackageSection(state.package!, notifier),
                const SizedBox(height: 24),
              ],
            ),
            // 全自动生成中的全屏遮罩进度
            if (state.generating) _buildGeneratingOverlay(state),
          ],
        ),
      ),
    );
  }

  // ==================== 顶部：自动模式说明 ====================

  Widget _buildAutoModeBanner(IpAutoState state) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F3460), Color(0xFF1A1A2E)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.bolt, color: Color(0xFFFFD54F), size: 26),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('自动模式已开启',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                SizedBox(height: 4),
                Text(
                  '输入行业关键词出选题 → 点【复刻它】，脚本/字幕/动效/BGM/封面/发布文案一次跑完。默认不插画中画、不加动效。',
                  style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 入口1：行业关键词 → 选题卡片 ====================

  Widget _buildKeywordSection(IpAutoState state, IpAutoNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('① 输入赛道 / 行业关键词', Icons.category_outlined),
          const SizedBox(height: 8),
          TextField(
            controller: _keywordCtrl,
            enabled: !state.loadingTopics && !state.generating,
            maxLines: 1,
            textInputAction: TextInputAction.search,
            style: const TextStyle(fontSize: 14, color: Colors.white),
            onChanged: notifier.setKeyword,
            onSubmitted: (_) => notifier.loadTopics(),
            decoration: InputDecoration(
              hintText: '如：宝妈副业、同城餐饮、AI工具、知识付费…',
              hintStyle: const TextStyle(fontSize: 13, color: AppTheme.textHint),
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: IconButton(
                icon: const Icon(Icons.auto_awesome, color: AppTheme.primaryColor),
                tooltip: '生成5条选题',
                onPressed: state.loadingTopics || state.generating ? null : notifier.loadTopics,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: state.loadingTopics || state.generating
                  ? null
                  : () {
                      notifier.setKeyword(_keywordCtrl.text);
                      notifier.loadTopics();
                    },
              icon: const Icon(Icons.lightbulb_outline, size: 18),
              label: const Text('生成 5 条高流量痛点选题'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 入口2：粘贴参考文案 → 提取框架复刻 ====================

  Widget _buildReferenceSection(IpAutoState state, IpAutoNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('② 或粘贴爆款参考文案 / 口播稿（可选）', Icons.content_copy),
          const SizedBox(height: 8),
          TextField(
            controller: _referenceCtrl,
            enabled: !state.generating && !state.loadingTopics,
            minLines: 3,
            maxLines: 6,
            style: const TextStyle(fontSize: 13, color: Colors.white),
            onChanged: notifier.setReferenceText,
            decoration: const InputDecoration(
              hintText: '把想复刻的爆款口播文案粘进来，自动提取它的钩子和结构，生成同赛道新稿…',
              hintStyle: TextStyle(fontSize: 12, color: AppTheme.textHint),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (state.referenceText.trim().isEmpty || state.generating)
                  ? null
                  : notifier.generateFromReference,
              icon: const Icon(Icons.casino_outlined, size: 18),
              label: const Text('提取框架并一键全自动'),
            ),
          ),
        ],
      ),
    );
  }

  // ==================== 选题卡片列表 ====================

  Widget _buildTopicsLoading() {
    return const Padding(
      padding: EdgeInsets.all(28),
      child: Column(children: [
        CircularProgressIndicator(),
        SizedBox(height: 12),
        Text('正在策划高流量痛点选题…', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
      ]),
    );
  }

  Widget _buildTopicsSection(IpAutoState state, IpAutoNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('选题参考卡片（点【复刻它】开始）', Icons.style_outlined),
          const SizedBox(height: 4),
          ...state.topics.asMap().entries.map((e) {
            return _TopicCardView(
              index: e.key + 1,
              card: e.value,
              busy: state.generating,
              onReplicate: () => notifier.replicate(e.value.replicateCommand),
            );
          }),
        ],
      ),
    );
  }

  // ==================== 全自动产物：7段卡片 ====================

  Widget _buildPackageSection(IpAutoPackage pkg, IpAutoNotifier notifier) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionTitle('全自动创作包', Icons.verified_outlined, color: AppTheme.safeColor),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _shareAll(pkg),
                icon: const Icon(Icons.ios_share, size: 16),
                label: const Text('整套复制'),
              ),
            ],
          ),
          _ResultCard(
            no: '1',
            title: '口播脚本正文',
            icon: Icons.record_voice_over,
            color: const Color(0xFFE57373),
            body: pkg.script.isEmpty ? const Text('（模型未返回脚本，请重试）') : SelectableText(
              pkg.script,
              style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.white),
            ),
            copyText: pkg.script,
          ),
          _ResultCard(
            no: '2',
            title: '字幕方案',
            icon: Icons.closed_caption_off_outlined,
            color: const Color(0xFF1A73E8),
            body: _buildSubtitleBody(pkg.subtitle),
            copyText: _subtitleCopy(pkg.subtitle),
          ),
          _ResultCard(
            no: '3',
            title: '动效清单（备选 · 默认不启用）',
            icon: Icons.animation,
            color: const Color(0xFFFFB74D),
            body: _buildEffectsBody(pkg.effects),
            copyText: _effectsCopy(pkg.effects),
          ),
          _ResultCard(
            no: '4',
            title: 'BGM 推荐',
            icon: Icons.library_music_outlined,
            color: const Color(0xFFBA68C8),
            body: _buildBgmBody(pkg.bgm),
            copyText: _bgmCopy(pkg.bgm),
          ),
          _ResultCard(
            no: '5',
            title: '封面 + 标题（3组）',
            icon: Icons.image_outlined,
            color: const Color(0xFF26C6DA),
            body: _buildCoverBody(pkg.coverTitle),
            copyText: _coverCopy(pkg.coverTitle),
          ),
          _ResultCard(
            no: '6',
            title: '社媒发布信息',
            icon: Icons.send_outlined,
            color: const Color(0xFF81C784),
            body: _buildSocialBody(pkg.social),
            copyText: _socialCopy(pkg.social),
          ),
          if (pkg.modelUsed.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('生成模型：${pkg.modelUsed}',
                  style: const TextStyle(fontSize: 11, color: AppTheme.textHint)),
            ),
        ],
      ),
    );
  }

  // ---- 各段内容渲染 ----

  Widget _buildSubtitleBody(SubtitlePlan s) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (s.styles.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: s.styles
                .map((t) => Chip(
                      label: Text(t, style: const TextStyle(fontSize: 11, color: Colors.white)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: AppTheme.darkSurface,
                    ))
                .toList(),
          ),
        const SizedBox(height: 8),
        _kv('字号', s.fontSize),
        _kv('颜色', s.color),
        _kv('描边', s.stroke),
      ],
    );
  }

  Widget _buildEffectsBody(List<MotionEffect> list) {
    if (list.isEmpty) return _emptyHint();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('默认不启用，需要哪个再手动加：',
            style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
        const SizedBox(height: 6),
        ...list.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check_circle_outline, size: 15, color: AppTheme.mediumRiskColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4),
                        children: [
                          TextSpan(text: '${e.name}　', style: const TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(text: e.desc, style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )),
      ],
    );
  }

  Widget _buildBgmBody(BgmRecommendation b) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kv('曲风', b.genre),
      _kv('适配音乐', b.name),
      _kv('音量建议', b.volume),
      if (b.usage.isNotEmpty) _kv('用法', b.usage),
    ]);
  }

  Widget _buildCoverBody(CoverTitle c) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (c.coverCopy.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF26C6DA).withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF26C6DA).withOpacity(0.4)),
            ),
            child: Text('封面大字：${c.coverCopy}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ...c.titles.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 20, height: 20,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: Color(0xFF26C6DA), shape: BoxShape.circle),
                  child: Text('${e.key + 1}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(e.value, style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.4))),
              ]),
            )),
        if (c.titles.isEmpty) _emptyHint(),
      ],
    );
  }

  Widget _buildSocialBody(SocialPublishInfo s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (s.douyinCopy.isNotEmpty) ...[
        const Text('抖音文案', style: TextStyle(fontSize: 12, color: AppTheme.primaryColor, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        SelectableText(s.douyinCopy, style: const TextStyle(fontSize: 13, height: 1.5, color: Colors.white)),
        const SizedBox(height: 10),
      ],
      if (s.hashtags.isNotEmpty)
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: s.hashtags
              .map((t) => Chip(
                    label: Text(t, style: const TextStyle(fontSize: 11, color: Color(0xFF81C784))),
                    visualDensity: VisualDensity.compact,
                    backgroundColor: const Color(0xFF81C784).withOpacity(0.12),
                    side: BorderSide.none,
                  ))
              .toList(),
        ),
      if (s.hashtags.isNotEmpty) const SizedBox(height: 10),
      if (s.intro.isNotEmpty) _kv('简介', s.intro),
      if (s.douyinCopy.isEmpty && s.hashtags.isEmpty) _emptyHint(),
    ]);
  }

  Widget _kv(String k, String v) {
    if (v.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: Text(k, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
          ),
          Expanded(child: SelectableText(v, style: const TextStyle(fontSize: 13, color: Colors.white, height: 1.4))),
        ],
      ),
    );
  }

  Widget _emptyHint() =>
      const Text('（本段暂无内容，可点右上重新生成）', style: TextStyle(fontSize: 12, color: AppTheme.textHint));

  // ---- 复制纯文本 ----

  String _subtitleCopy(SubtitlePlan s) =>
      '字幕样式：${s.styles.join(' / ')}\n字号：${s.fontSize}\n颜色：${s.color}\n描边：${s.stroke}';
  String _effectsCopy(List<MotionEffect> list) =>
      list.asMap().map((i, e) => MapEntry(i, '${i + 1}. ${e.name}｜${e.desc}')).values.join('\n');
  String _bgmCopy(BgmRecommendation b) =>
      '曲风：${b.genre}\n音乐：${b.name}\n音量：${b.volume}\n${b.usage}'.trim();
  String _coverCopy(CoverTitle c) =>
      '封面文案：${c.coverCopy}\n标题：\n${c.titles.map((e) => '· $e').join('\n')}';
  String _socialCopy(SocialPublishInfo s) =>
      '${s.douyinCopy}\n${s.hashtags.join(' ')}\n简介：${s.intro}'.trim();

  // ==================== 错误 / 遮罩 / 通用 ====================

  Widget _buildError(String msg) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.highRiskColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.highRiskColor.withOpacity(0.4)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.error_outline, color: AppTheme.highRiskColor, size: 20),
        const SizedBox(width: 8),
        Expanded(child: Text(msg, style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.4))),
      ]),
    );
  }

  Widget _buildGeneratingOverlay(IpAutoState state) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withOpacity(0.75),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const SizedBox(
                width: 52, height: 52,
                child: CircularProgressIndicator(strokeWidth: 4),
              ),
              const SizedBox(height: 20),
              Text(
                state.statusText.isEmpty ? '自动生成中…' : state.statusText,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.white, height: 1.5),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String t, IconData icon, {Color color = AppTheme.primaryColor}) {
    return Row(children: [
      Icon(icon, size: 17, color: color),
      const SizedBox(width: 6),
      Flexible(
        child: Text(t,
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
      ),
    ]);
  }

  void _shareAll(IpAutoPackage pkg) {
    final text = pkg.toFullText();
    Clipboard.setData(ClipboardData(text: text));
    try {
      Share.share(text);
    } catch (_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('整套内容已复制到剪贴板'), duration: Duration(seconds: 2)),
      );
    }
  }
}

// ==================== 选题卡片视图 ====================

class _TopicCardView extends StatelessWidget {
  final int index;
  final TopicCard card;
  final bool busy;
  final VoidCallback onReplicate;

  const _TopicCardView({
    required this.index,
    required this.card,
    required this.busy,
    required this.onReplicate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.primaryColor.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColor.withOpacity(0.18),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text('#$index', style: const TextStyle(fontSize: 11, color: AppTheme.primaryColor, fontWeight: FontWeight.bold)),
              ),
              const SizedBox(width: 8),
              if (card.track.isNotEmpty)
                Flexible(
                  child: Text(card.track,
                      style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                      overflow: TextOverflow.ellipsis),
                ),
            ]),
            const SizedBox(height: 8),
            Text(card.title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white, height: 1.3)),
            if (card.hook.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFD54F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('钩子：${card.hook}',
                    style: const TextStyle(fontSize: 12.5, color: Color(0xFFFFE082), height: 1.4)),
              ),
            ],
            if (card.painPoint.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text('痛点：${card.painPoint}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.4)),
            ],
            if (card.reason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('为什么能爆：${card.reason}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textHint, height: 1.4)),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: busy ? null : onReplicate,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF6D00),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                ),
                icon: const Icon(Icons.rocket_launch, size: 18),
                label: const Text('复刻它 · 一键全自动'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== 产物卡片通用容器 ====================

class _ResultCard extends StatelessWidget {
  final String no;
  final String title;
  final IconData icon;
  final Color color;
  final Widget body;
  final String copyText;

  const _ResultCard({
    required this.no,
    required this.title,
    required this.icon,
    required this.color,
    required this.body,
    required this.copyText,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 26, height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color.withOpacity(0.18), borderRadius: BorderRadius.circular(7)),
                child: Icon(icon, size: 15, color: color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
              IconButton(
                tooltip: '复制本段',
                visualDensity: VisualDensity.compact,
                icon: Icon(Icons.copy_rounded, size: 17, color: color),
                onPressed: copyText.trim().isEmpty
                    ? null
                    : () {
                        Clipboard.setData(ClipboardData(text: copyText));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('已复制：$title'),
                            duration: const Duration(seconds: 1,),
                          ),
                        );
                      },
              ),
            ]),
            const Divider(height: 16, color: Color(0xFF2A2A4A)),
            body,
          ],
        ),
      ),
    );
  }
}
