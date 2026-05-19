import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/theme.dart';
import '../../widgets/common/app_card.dart';

/// 使用帮助页面 - 快速入门、功能说明、常见问题
class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('使用帮助'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ========== 快速入门 ==========
            _buildSectionHeader(Icons.rocket_launch, '快速入门', '3步开始你的口播创作'),
            const SizedBox(height: AppTheme.spacingSmall),

            // 步骤1
            _buildStepCard(
              stepNumber: 1,
              title: '配置API Key',
              desc: '在设置页填写各平台的API Key。推荐优先配置智谱AI（永久免费），即可使用文案改写功能。',
              icon: Icons.key,
              color: AppTheme.primaryColor,
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            // 步骤2
            _buildStepCard(
              stepNumber: 2,
              title: '进入创作工作台',
              desc: '从首页点击「创作工作台」，粘贴抖音视频链接，一键提取文案。',
              icon: Icons.auto_awesome,
              color: const Color(0xFF81C784),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            // 步骤3
            _buildStepCard(
              stepNumber: 3,
              title: '改写 → 审核 → 配音 → 生成视频',
              desc: 'AI改写去重 → 法务合规审核 → 语音合成 → 数字人口播视频，一键完成全流程。',
              icon: Icons.smart_display,
              color: const Color(0xFFBA68C8),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== 功能模块说明 ==========
            _buildSectionHeader(Icons.widgets, '功能模块说明', '了解每个功能的使用方法'),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildFeatureCard(
              icon: Icons.link,
              title: '文案提取',
              desc: '粘贴抖音/快手视频链接，自动提取视频中的口播文案文本。支持多种链接格式。',
              color: AppTheme.primaryColor,
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildFeatureCard(
              icon: Icons.auto_fix_high,
              title: 'AI改写',
              desc: '支持6种改写模式：同义改写、口语化、缩写精简、扩写丰富、风格转换、去重改写。每次生成3个版本供选择。',
              color: const Color(0xFF81C784),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildFeatureCard(
              icon: Icons.shield_outlined,
              title: '法务审核',
              desc: '多维度合规检测：广告法违禁词、敏感词、平台违规、侵权风险、虚假宣传。支持一键修正。',
              color: const Color(0xFFFFB74D),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildFeatureCard(
              icon: Icons.record_voice_over,
              title: '语音合成',
              desc: 'Edge-TTS免费配音 + CosyVoice高质量合成。支持声音克隆，录入10秒样本即可克隆专属音色。',
              color: const Color(0xFFE57373),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildFeatureCard(
              icon: Icons.smart_toy_outlined,
              title: '数字人视频',
              desc: '选择数字人形象+配音，一键生成口播视频。支持自定义数字人形象。',
              color: const Color(0xFFBA68C8),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== 常见问题 FAQ ==========
            _buildSectionHeader(Icons.help_outline, '常见问题', '遇到问题？先看看这里'),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildFaqItem(
              question: 'API Key怎么获取？',
              answer: '见下方「API Key申请教程」，各平台注册后即可在控制台获取API Key。智谱AI的GLM-4-Flash模型永久免费使用。',
            ),
            _buildFaqItem(
              question: '文案提取失败怎么办？',
              answer: '可能原因：1) 视频链接格式不正确，请确认使用分享链接；2) 视频为私密/已删除；3) 网络不稳定。建议重新复制分享链接再试。',
            ),
            _buildFaqItem(
              question: '改写质量不满意怎么办？',
              answer: '可以尝试：1) 切换改写模式（如从同义改写切换到去重改写）；2) 切换AI模型（在设置中更改默认改写模型）；3) 多次生成选择最佳版本。',
            ),
            _buildFaqItem(
              question: '审核报了很多违禁词，怎么处理？',
              answer: '使用「一键修正」功能可自动替换违禁词。也可以逐条查看修改建议手动替换。修正后建议再次审核确认。',
            ),
            _buildFaqItem(
              question: '语音合成的音频可以下载吗？',
              answer: '可以。在语音合成完成后，点击下载按钮即可保存到本地。音频文件保存在应用的音频目录中。',
            ),
            _buildFaqItem(
              question: '数据安全吗？',
              answer: '所有API Key使用加密存储（flutter_secure_storage），不会上传到任何服务器。文案和音频数据仅保存在本地，AI处理通过各平台官方API直连。',
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== API Key申请教程 ==========
            _buildSectionHeader(Icons.vpn_key, 'API Key申请教程', '各平台注册与Key获取指南'),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildApiKeyGuideCard(
              platform: '智谱AI',
              desc: '注册账号 → 登录控制台 → API Keys → 创建新Key',
              url: 'https://open.bigmodel.cn/',
              isFree: true,
              freeDetail: 'GLM-4-Flash永久免费，2000万Token新人额度',
              color: const Color(0xFF4A90D9),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildApiKeyGuideCard(
              platform: '硅基流动',
              desc: '注册账号 → 登录控制台 → API Keys → 创建新Key',
              url: 'https://siliconflow.cn/',
              isFree: true,
              freeDetail: '9B以下模型永久免费，2000万Token额度',
              color: const Color(0xFF7C4DFF),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildApiKeyGuideCard(
              platform: 'DeepSeek',
              desc: '注册账号 → 登录控制台 → API Keys → 创建新Key',
              url: 'https://platform.deepseek.com/',
              isFree: false,
              freeDetail: '100万Token免费额度，30天有效',
              color: const Color(0xFF00BFA5),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildApiKeyGuideCard(
              platform: '阿里百炼',
              desc: '注册阿里云 → 开通百炼服务 → API Keys → 创建新Key',
              url: 'https://dashscope.console.aliyun.com/',
              isFree: false,
              freeDetail: '每模型100万Token免费额度',
              color: const Color(0xFFFF6D00),
            ),
            const SizedBox(height: AppTheme.spacingSmall),

            _buildApiKeyGuideCard(
              platform: '飞影数字人',
              desc: '注册飞影 → 创建Agent → 获取Agent Token',
              url: 'https://hifly.cc/',
              isFree: false,
              freeDetail: '新用户赠送体验时长',
              color: const Color(0xFFE91E63),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  // ==================== 构建组件方法 ====================

  /// 区域标题
  Widget _buildSectionHeader(IconData icon, String title, String subtitle) {
    return Row(
      children: [
        Icon(icon, color: AppTheme.primaryColor, size: 22),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
          ],
        ),
      ],
    );
  }

  /// 步骤卡片
  Widget _buildStepCard({
    required int stepNumber,
    required String title,
    required String desc,
    required IconData icon,
    required Color color,
  }) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 步骤序号
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Center(
              child: Text(
                '$stepNumber',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, color: color, size: 18),
                    const SizedBox(width: 6),
                    Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 功能说明卡片
  Widget _buildFeatureCard({
    required IconData icon,
    required String title,
    required String desc,
    required Color color,
  }) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(desc, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// FAQ项
  Widget _buildFaqItem({required String question, required String answer}) {
    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingSmall),
      iconColor: AppTheme.primaryColor,
      collapsedIconColor: AppTheme.textHint,
      title: Text(
        question,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppTheme.textPrimary),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppTheme.spacingSmall,
            0,
            AppTheme.spacingSmall,
            AppTheme.spacingMedium,
          ),
          child: Text(
            answer,
            style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary, height: 1.6),
          ),
        ),
      ],
    );
  }

  /// API Key申请教程卡片
  Widget _buildApiKeyGuideCard({
    required String platform,
    required String desc,
    required String url,
    required bool isFree,
    required String freeDetail,
    required Color color,
  }) {
    return AppCard(
      onTap: () => _launchUrl(url),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            ),
            child: Center(
              child: Text(
                platform.substring(0, 1),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
              ),
            ),
          ),
          const SizedBox(width: AppTheme.spacingMedium),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(platform, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                    if (isFree) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: AppTheme.safeColor.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: const Text(
                          '免费',
                          style: TextStyle(fontSize: 10, color: AppTheme.safeColor, fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(desc, style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary)),
                const SizedBox(height: 2),
                Text(freeDetail, style: TextStyle(fontSize: 11, color: isFree ? AppTheme.safeColor : AppTheme.textHint)),
              ],
            ),
          ),
          const Icon(Icons.open_in_new, color: AppTheme.textHint, size: 18),
        ],
      ),
    );
  }

  /// 打开URL
  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
