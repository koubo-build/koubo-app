import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../../config/theme.dart';
import '../../config/api_config.dart';
import '../../config/routes.dart';
import '../../utils/storage_util.dart';
import '../../utils/word_filter.dart';

import '../../widgets/common/app_button.dart';
import '../../widgets/common/app_card.dart';
import '../../widgets/common/app_input.dart';

/// 设置页 - API Key管理、模型配置、词库管理、历史记录、关于
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  // API Key控制器
  final _zhipuKeyController = TextEditingController();
  final _siliconFlowKeyController = TextEditingController();
  final _aliBailianKeyController = TextEditingController();
  final _tikhubKeyController = TextEditingController();
  final _ai32KeyController = TextEditingController();
  final _agnesKeyController = TextEditingController();


  // API Key显示/隐藏状态
  bool _zhipuKeyVisible = false;
  bool _siliconFlowKeyVisible = false;
  bool _aliBailianKeyVisible = false;
  bool _tikhubKeyVisible = false;
  bool _ai32KeyVisible = false;
  bool _agnesKeyVisible = false;


  // API Key有效性检测状态：null=未检测, 'valid'=有效, 'invalid'=无效
  String? _zhipuKeyStatus;
  String? _siliconFlowKeyStatus;
  String? _aliBailianKeyStatus;
  String? _tikhubKeyStatus;
  String? _ai32KeyStatus;
  String? _agnesKeyStatus;


  // 正在检测的Key标识
  String? _testingKey;

  bool _isSaving = false;

  // 默认模型选择
  String _rewriteModel = '自动选择';
  String _auditModel = '自动选择';
  String _ttsEngine = 'CosyVoice';
  String _scriptModel = '自动选择';
  String _videoModel = 'wan2.2-s2v';
  String _ttsVoiceModel = 'cosyvoice-v3-flash';

  // 缓存统计
  int _scriptCount = 0;
  int _audioCount = 0;
  int _videoCount = 0;
  String _audioCacheSize = '0 B';
  String _videoCacheSize = '0 B';

  // 自定义敏感词
  final _customWordController = TextEditingController();
  List<Map<String, dynamic>> _customWords = [];

  // 词库统计
  int _adLawWordCount = 0;
  int _sensitiveWordCount = 0;

  @override
  void initState() {
    super.initState();
    _loadAllSettings();
  }

  @override
  void dispose() {
    _zhipuKeyController.dispose();
    _siliconFlowKeyController.dispose();
    _aliBailianKeyController.dispose();
    _tikhubKeyController.dispose();
    _ai32KeyController.dispose();
    _agnesKeyController.dispose();

    _customWordController.dispose();
    super.dispose();
  }

  /// 加载所有设置
  Future<void> _loadAllSettings() async {
    // 加载API Key
    _zhipuKeyController.text = await StorageUtil.getSecure(ApiConfig.zhipuApiKeyKey) ?? '';
    _siliconFlowKeyController.text = await StorageUtil.getSecure(ApiConfig.siliconFlowApiKeyKey) ?? '';
    _aliBailianKeyController.text = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey) ?? '';
    _tikhubKeyController.text = await StorageUtil.getSecure(ApiConfig.tikhubApiKeyKey) ?? '';
    _ai32KeyController.text = await StorageUtil.getSecure(ApiConfig.ai32ApiKeyKey) ?? '';
    _agnesKeyController.text = await StorageUtil.getSecure(ApiConfig.agnesApiKeyKey) ?? '';


    // 加载模型偏好
    _rewriteModel = StorageUtil.getRewriteModel();
    _auditModel = StorageUtil.getAuditModel();
    _ttsEngine = StorageUtil.getTtsEngine();
    _scriptModel = StorageUtil.getScriptModel();
    _videoModel = StorageUtil.getVideoModel();
    _ttsVoiceModel = StorageUtil.getTtsVoiceModel();

    // 加载缓存统计
    await _loadCacheStats();

    // 加载自定义词库
    await _loadCustomWords();

    // 统计内置词库
    _countBuiltinWords();

    setState(() {});
  }

  /// 加载缓存统计
  Future<void> _loadCacheStats() async {
    _scriptCount = await StorageUtil.getScriptCount();
    _audioCount = await StorageUtil.getAudioFileCount();
    _videoCount = await StorageUtil.getVideoFileCount();

    final cacheStats = await StorageUtil.getCacheStats();
    _audioCacheSize = StorageUtil.formatFileSize(cacheStats['audio'] ?? 0);
    _videoCacheSize = StorageUtil.formatFileSize(cacheStats['video'] ?? 0);
  }

  /// 加载自定义词库
  Future<void> _loadCustomWords() async {
    _customWords = await StorageUtil.getAllCustomWords();
  }

  /// 统计内置词库
  void _countBuiltinWords() {
    final engine = WordFilterEngine();
    final counts = engine.getWordCount();
    _adLawWordCount = counts['广告法违禁词'] ?? 0;
    // 敏感词 = 抖音敏感词 + 行业特规词
    _sensitiveWordCount = (counts['抖音敏感词'] ?? 0) + (counts['行业特规词'] ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppTheme.spacingMedium),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ========== A. API Key管理区 ==========
            _buildSectionTitle(Icons.key, 'API Key 配置', '各平台Key本地加密存储，不会上传服务器'),
            const SizedBox(height: AppTheme.spacingSmall),

            // 智谱AI
            _buildApiKeyCard(
              platformName: '智谱AI',
              platformDesc: 'GLM-4-Flash 永久免费',
              icon: Icons.auto_awesome,
              iconColor: const Color(0xFF4A90D9),
              controller: _zhipuKeyController,
              hintText: '输入智谱AI API Key',
              isVisible: _zhipuKeyVisible,
              onToggleVisibility: () => setState(() => _zhipuKeyVisible = !_zhipuKeyVisible),
              status: _zhipuKeyStatus,
              isTesting: _testingKey == 'zhipu',
              onTest: () => _testApiKey('zhipu'),
              onClear: () => _clearApiKey('zhipu'),
              isFree: true,
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 硅基流动
            _buildApiKeyCard(
              platformName: '硅基流动',
              platformDesc: 'Qwen2.5-7B 免费模型',
              icon: Icons.memory,
              iconColor: const Color(0xFF7C4DFF),
              controller: _siliconFlowKeyController,
              hintText: '输入硅基流动 API Key',
              isVisible: _siliconFlowKeyVisible,
              onToggleVisibility: () => setState(() => _siliconFlowKeyVisible = !_siliconFlowKeyVisible),
              status: _siliconFlowKeyStatus,
              isTesting: _testingKey == 'siliconflow',
              onTest: () => _testApiKey('siliconflow'),
              onClear: () => _clearApiKey('siliconflow'),
              isFree: true,
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 阿里百炼
            _buildApiKeyCard(
              platformName: '阿里百炼',
              platformDesc: 'CosyVoice语音 + 万相数字人',
              icon: Icons.record_voice_over,
              iconColor: const Color(0xFFFF6D00),
              controller: _aliBailianKeyController,
              hintText: '输入阿里百炼 API Key',
              isVisible: _aliBailianKeyVisible,
              onToggleVisibility: () => setState(() => _aliBailianKeyVisible = !_aliBailianKeyVisible),
              status: _aliBailianKeyStatus,
              isTesting: _testingKey == 'alibailian',
              onTest: () => _testApiKey('alibailian'),
              onClear: () => _clearApiKey('alibailian'),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // TikHub（视频解析）
            _buildApiKeyCard(
              platformName: 'TikHub',
              platformDesc: '抖音/快手视频文案提取（新用户免费）',
              icon: Icons.video_library_outlined,
              iconColor: const Color(0xFF00BCD4),
              controller: _tikhubKeyController,
              hintText: '输入 TikHub API Key（tikhub.io）',
              isVisible: _tikhubKeyVisible,
              onToggleVisibility: () => setState(() => _tikhubKeyVisible = !_tikhubKeyVisible),
              status: _tikhubKeyStatus,
              isTesting: _testingKey == 'tikhub',
              onTest: () => _testApiKey('tikhub'),
              onClear: () => _clearApiKey('tikhub'),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 32AI中转站
            _buildApiKeyCard(
              platformName: '32AI中转站',
              platformDesc: '约官方价56%，支持豆包/DeepSeek等',
              icon: Icons.swap_horiz,
              iconColor: const Color(0xFFFF9800),
              controller: _ai32KeyController,
              hintText: '输入 32AI API Key（32ai.uk）',
              isVisible: _ai32KeyVisible,
              onToggleVisibility: () => setState(() => _ai32KeyVisible = !_ai32KeyVisible),
              status: _ai32KeyStatus,
              isTesting: _testingKey == 'ai32',
              onTest: () => _testApiKey('ai32'),
              onClear: () => _clearApiKey('ai32'),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // Agnes AI
            _buildApiKeyCard(
              platformName: 'Agnes AI',
              platformDesc: '全模态免费平台，Agnes-2.0-Flash',
              icon: Icons.smart_toy_outlined,
              iconColor: const Color(0xFF00E676),
              controller: _agnesKeyController,
              hintText: '输入 Agnes AI API Key（platform.agnes-ai.com）',
              isVisible: _agnesKeyVisible,
              onToggleVisibility: () => setState(() => _agnesKeyVisible = !_agnesKeyVisible),
              status: _agnesKeyStatus,
              isTesting: _testingKey == 'agnes',
              onTest: () => _testApiKey('agnes'),
              onClear: () => _clearApiKey('agnes'),
              isFree: true,
            ),

            const SizedBox(height: AppTheme.spacingMedium),

            // 保存按钮
            AppButton(
              text: '保存所有配置',
              icon: Icons.save,
              isLoading: _isSaving,
              onPressed: _saveAllSettings,
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== B. 模型偏好设置 ==========
            _buildSectionTitle(Icons.tune, '模型偏好', '选择各场景使用的默认模型'),
            const SizedBox(height: AppTheme.spacingSmall),

            // 文案生成模型
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('文案生成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('数字人页AI生成口播文案使用的模型', style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
                  const SizedBox(height: 8),
                  _buildModelSelectorWithDesc(
                    value: _scriptModel,
                    items: ApiConfig.scriptModelOptions,
                    onChanged: (v) => setState(() => _scriptModel = v!),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 语音合成模型
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('语音合成', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('TTS引擎和音色模型配置', style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
                  const SizedBox(height: 8),
                  _buildModelSelectorWithDesc(
                    value: _ttsEngine,
                    items: ApiConfig.ttsEngineOptions,
                    onChanged: (v) => setState(() => _ttsEngine = v!),
                  ),
                  if (_ttsEngine == 'CosyVoice') ...[
                    const Divider(color: Color(0xFF2A2A4A), height: 16),
                    const Text('CosyVoice模型版本', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                    const SizedBox(height: 6),
                    _buildModelSelectorWithDesc(
                      value: _ttsVoiceModel,
                      items: ApiConfig.cosyVoiceModelOptions,
                      onChanged: (v) => setState(() => _ttsVoiceModel = v!),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 数字人视频模型
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('数字人视频', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  const Text('选择视频生成接口模型', style: TextStyle(fontSize: 11, color: AppTheme.textHint)),
                  const SizedBox(height: 8),
                  _buildModelSelectorWithDesc(
                    value: _videoModel,
                    items: ApiConfig.videoModelOptions,
                    onChanged: (v) => setState(() => _videoModel = v!),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 改写 & 审核模型
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('改写 & 审核', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _buildModelSelector(
                    label: '改写模型',
                    value: _rewriteModel,
                    items: const ['GLM-4-Flash', 'Qwen2.5-7B', 'qwen-plus'],
                    onChanged: (v) => setState(() => _rewriteModel = v!),
                  ),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  _buildModelSelector(
                    label: '审核模型',
                    value: _auditModel,
                    items: const ['qwen-plus', 'GLM-4-Flash'],
                    onChanged: (v) => setState(() => _auditModel = v!),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== C. 词库管理 ==========
            _buildSectionTitle(Icons.library_books, '词库管理', '违禁词/敏感词配置与管理'),
            const SizedBox(height: AppTheme.spacingSmall),

            // 内置词库统计
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('内置词库（只读）', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppTheme.spacingSmall),
                  Row(
                    children: [
                      _buildWordCountChip('广告法词', _adLawWordCount, AppTheme.highRiskColor),
                      const SizedBox(width: AppTheme.spacingSmall),
                      _buildWordCountChip('敏感词', _sensitiveWordCount, AppTheme.mediumRiskColor),
                      const SizedBox(width: AppTheme.spacingSmall),
                      _buildWordCountChip('自定义', _customWords.length, AppTheme.primaryColor),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingSmall),

            // 自定义词库管理
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('自定义词库', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppTheme.spacingSmall),

                  // 添加自定义词
                  Row(
                    children: [
                      Expanded(
                        child: AppInput(
                          controller: _customWordController,
                          hintText: '输入敏感词',
                          onChanged: (v) => _addCustomWord(),
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSmall),
                      SizedBox(
                        height: 48,
                        child: ElevatedButton(
                          onPressed: _addCustomWord,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppTheme.primaryColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusMedium),
                            ),
                          ),
                          child: const Text('添加', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: AppTheme.spacingSmall),

                  // 自定义词列表
                  if (_customWords.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(AppTheme.spacingMedium),
                        child: Text('暂无自定义敏感词', style: TextStyle(color: AppTheme.textHint, fontSize: 13)),
                      ),
                    )
                  else
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: _customWords.length,
                        separatorBuilder: (_, __) => const Divider(color: Color(0xFF2A2A4A), height: 1),
                        itemBuilder: (context, index) {
                          final word = _customWords[index];
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                            title: Text(
                              word['word'] ?? '',
                              style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                            ),
                            subtitle: Text(
                              word['category'] ?? '自定义',
                              style: const TextStyle(fontSize: 11, color: AppTheme.textHint),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, size: 18, color: AppTheme.textHint),
                              onPressed: () => _deleteCustomWord(word['id'] as int),
                            ),
                          );
                        },
                      ),
                    ),

                  const SizedBox(height: AppTheme.spacingSmall),

                  // 导入/导出按钮
                  Row(
                    children: [
                      Expanded(
                        child: AppButton(
                          text: '导入词库',
                          icon: Icons.file_upload,
                          isOutlined: true,
                          height: 40,
                          fontSize: 13,
                          onPressed: _importCustomWords,
                        ),
                      ),
                      const SizedBox(width: AppTheme.spacingSmall),
                      Expanded(
                        child: AppButton(
                          text: '导出词库',
                          icon: Icons.file_download,
                          isOutlined: true,
                          height: 40,
                          fontSize: 13,
                          onPressed: _exportCustomWords,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== D. 历史与缓存管理 ==========
            _buildSectionTitle(Icons.history, '历史与缓存', '查看和管理本地存储数据'),
            const SizedBox(height: AppTheme.spacingSmall),

            AppCard(
              child: Column(
                children: [
                  _buildCacheInfoRow(Icons.description_outlined, '文案记录', '$_scriptCount 条', AppTheme.primaryColor),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  _buildCacheInfoRow(Icons.audiotrack_outlined, '音频缓存', _audioCacheSize, const Color(0xFFE57373)),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  _buildCacheInfoRow(Icons.videocam_outlined, '视频缓存', _videoCacheSize, const Color(0xFFBA68C8)),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSmall),
                    child: Row(
                      children: [
                        Expanded(
                          child: AppButton(
                            text: '清理缓存',
                            icon: Icons.cleaning_services_outlined,
                            isOutlined: true,
                            height: 40,
                            fontSize: 13,
                            onPressed: _showClearCacheDialog,
                          ),
                        ),
                        const SizedBox(width: AppTheme.spacingSmall),
                        Expanded(
                          child: AppButton(
                            text: '清除全部历史',
                            icon: Icons.delete_forever,
                            height: 40,
                            fontSize: 13,
                            backgroundColor: AppTheme.highRiskColor,
                            onPressed: _showClearAllHistoryDialog,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),

            // ========== E. 关于 ==========
            _buildSectionTitle(Icons.info_outline, '关于', '应用信息与帮助'),
            const SizedBox(height: AppTheme.spacingSmall),

            AppCard(
              child: Column(
                children: [
                  _buildAboutRow('应用版本', 'v1.0.0'),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  _buildActionRow(
                    icon: Icons.system_update_outlined,
                    title: '检查更新',
                    onTap: () => _showSnackBar('当前已是最新版本'),
                  ),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  _buildActionRow(
                    icon: Icons.help_outline,
                    title: '使用帮助',
                    onTap: () => Navigator.pushNamed(context, AppRoutes.help),
                  ),
                  const Divider(color: Color(0xFF2A2A4A), height: 1),
                  _buildActionRow(
                    icon: Icons.feedback_outlined,
                    title: '反馈建议',
                    onTap: () => _showSnackBar('反馈功能开发中'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppTheme.spacingXLarge),
          ],
        ),
      ),
    );
  }

  // ==================== 构建组件方法 ====================

  /// 区域标题
  Widget _buildSectionTitle(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppTheme.spacingXS),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.primaryColor, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
            ],
          ),
        ],
      ),
    );
  }

  /// API Key配置卡片
  Widget _buildApiKeyCard({
    required String platformName,
    required String platformDesc,
    required IconData icon,
    required Color iconColor,
    required TextEditingController controller,
    required String hintText,
    required bool isVisible,
    required VoidCallback onToggleVisibility,
    required String? status,
    required bool isTesting,
    required VoidCallback onTest,
    required VoidCallback onClear,
    bool isFree = false,
  }) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 平台名称行
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: AppTheme.spacingSmall),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(platformName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
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
                    Text(platformDesc, style: const TextStyle(fontSize: 12, color: AppTheme.textHint)),
                  ],
                ),
              ),
              // 检测状态指示
              if (status != null)
                Icon(
                  status == 'valid' ? Icons.check_circle : Icons.cancel,
                  color: status == 'valid' ? AppTheme.safeColor : AppTheme.highRiskColor,
                  size: 20,
                ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingSmall),

          // Key输入框
          AppInput(
            controller: controller,
            hintText: hintText,
            obscureText: !isVisible,
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 显示/隐藏切换
                IconButton(
                  onPressed: onToggleVisibility,
                  icon: Icon(
                    isVisible ? Icons.visibility : Icons.visibility_off,
                    size: 18,
                    color: AppTheme.textHint,
                  ),
                ),
                // 清除按钮
                if (controller.text.isNotEmpty)
                  IconButton(
                    onPressed: onClear,
                    icon: const Icon(Icons.close, size: 16, color: AppTheme.textHint),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppTheme.spacingSmall),

          // 检测按钮
          SizedBox(
            height: 36,
            child: ElevatedButton.icon(
              onPressed: controller.text.isEmpty ? null : (isTesting ? null : onTest),
              icon: isTesting
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline, size: 16),
              label: Text(
                isTesting ? '检测中...' : '检测有效性',
                style: const TextStyle(fontSize: 13),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppTheme.textHint.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 模型选择器
  Widget _buildModelSelector({
    required String label,
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSmall),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppTheme.darkSurface,
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  dropdownColor: AppTheme.darkSurface,
                  style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
                  items: items.map((item) {
                    return DropdownMenuItem(
                      value: item,
                      child: Text(item),
                    );
                  }).toList(),
                  onChanged: onChanged,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 词库统计芯片
  Widget _buildWordCountChip(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: color.withOpacity(0.3), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          const SizedBox(width: 4),
          Text('$count', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 2),
          Text('词', style: TextStyle(fontSize: 10, color: color.withOpacity(0.7))),
        ],
      ),
    );
  }


  /// 缓存信息行
  Widget _buildCacheInfoRow(IconData icon, String title, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSmall),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
          Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }

  /// 关于信息行
  Widget _buildAboutRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSmall),
      child: Row(
        children: [
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary))),
          Text(value, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
        ],
      ),
    );
  }

  /// 关于操作行
  Widget _buildActionRow({required IconData icon, required String title, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingSmall),
        child: Row(
          children: [
            Icon(icon, color: AppTheme.textSecondary, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(title, style: const TextStyle(fontSize: 14))),
            const Icon(Icons.chevron_right, color: AppTheme.textHint, size: 20),
          ],
        ),
      ),
    );
  }

  // ==================== 业务逻辑方法 ====================

  /// 保存所有配置
  Future<void> _saveAllSettings() async {
    setState(() => _isSaving = true);
    try {
      // 保存API Key到加密存储
      await StorageUtil.saveApiKeys({
        ApiConfig.zhipuApiKeyKey: _zhipuKeyController.text.trim(),
        ApiConfig.siliconFlowApiKeyKey: _siliconFlowKeyController.text.trim(),
        ApiConfig.aliBailianApiKeyKey: _aliBailianKeyController.text.trim(),
        ApiConfig.tikhubApiKeyKey: _tikhubKeyController.text.trim(),
        ApiConfig.ai32ApiKeyKey: _ai32KeyController.text.trim(),
        ApiConfig.agnesApiKeyKey: _agnesKeyController.text.trim(),
      });

      // 保存模型偏好到SharedPreferences
      await StorageUtil.setRewriteModel(_rewriteModel);
      await StorageUtil.setAuditModel(_auditModel);
      await StorageUtil.setTtsEngine(_ttsEngine);
      await StorageUtil.setScriptModel(_scriptModel);
      await StorageUtil.setVideoModel(_videoModel);
      await StorageUtil.setTtsVoiceModel(_ttsVoiceModel);

      _showSnackBar('配置已保存');
    } catch (e) {
      _showSnackBar('保存失败：$e');
    } finally {
      setState(() => _isSaving = false);
    }
  }

  /// 检测单个API Key有效性
  Future<void> _testApiKey(String platform) async {
    setState(() => _testingKey = platform);

    try {
      String apiKey;
      String testUrl;
      String model;

      switch (platform) {
        case 'zhipu':
          apiKey = _zhipuKeyController.text.trim();
          testUrl = '${ApiConfig.zhipuBaseUrl}/chat/completions';
          model = ApiConfig.zhipuModelFlash;
          break;
        case 'siliconflow':
          apiKey = _siliconFlowKeyController.text.trim();
          testUrl = '${ApiConfig.siliconFlowBaseUrl}/chat/completions';
          model = ApiConfig.siliconFlowModelQwen;
          break;
        case 'alibailian':
          apiKey = _aliBailianKeyController.text.trim();
          testUrl = '${ApiConfig.aliBailianBaseUrl}/services/aigc/text2audio/generation';
          model = '';
          break;
        case 'tikhub':
          apiKey = _tikhubKeyController.text.trim();
          testUrl = '${ApiConfig.tikhubBaseUrl}${ApiConfig.tikhubVideoDataEndpoint}';
          model = '';
          break;
        case 'ai32':
          apiKey = _ai32KeyController.text.trim();
          testUrl = '${ApiConfig.ai32BaseUrl}/chat/completions';
          model = 'qwen-plus';
          break;
        case 'agnes':
          apiKey = _agnesKeyController.text.trim();
          testUrl = '${ApiConfig.agnesBaseUrl}/chat/completions';
          model = ApiConfig.agnesModelFlash;
          break;
        default:
          return;
      }

      if (apiKey.isEmpty) {
        _showSnackBar('请先输入API Key');
        return;
      }

      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30),
      ));
      bool isValid = false;

      if (platform == 'tikhub') {
        // TikHub验证：用douyin/web端点测试，只要不返回401就说明Key有效
        // 注意：hybrid/video_data对抖音链接返回400，不适合做验证
        try {
          await dio.get(
            '${ApiConfig.tikhubBaseUrl}/douyin/web/fetch_one_video',
            queryParameters: {'aweme_id': '1'}, // 假ID，只要不返回401就行
            options: Options(headers: {
              'Authorization': 'Bearer $apiKey',
              'Accept': 'application/json',
            }),
          );
          // 能走通（不管返回什么状态码），说明Key有效
          isValid = true;
        } on DioException catch (e) {
          // 400/404/422等说明Key被接受但请求参数有问题 → Key有效
          // 401/403 → Key无效
          final status = e.response?.statusCode ?? 0;
          isValid = status != 401 && status != 403;
        }
      } else if (platform == 'alibailian') {
        // 阿里百炼用兼容模式chat接口验证（更可靠）
        final response = await dio.post(
          'https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions',
          data: {
            'model': 'qwen-plus',
            'messages': [{'role': 'user', 'content': 'Hi'}],
            'max_tokens': 5,
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
        );
        isValid = response.statusCode == 200;
      } else {
        // 大模型平台用chat接口测试
        final response = await dio.post(
          testUrl,
          data: {
            'model': model,
            'messages': [{'role': 'user', 'content': 'Hi'}],
            'max_tokens': 5,
          },
          options: Options(headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          }),
        );
        isValid = response.statusCode == 200;
      }

      // 更新检测状态
      setState(() {
        switch (platform) {
          case 'zhipu': _zhipuKeyStatus = isValid ? 'valid' : 'invalid'; break;
          case 'siliconflow': _siliconFlowKeyStatus = isValid ? 'valid' : 'invalid'; break;
          case 'alibailian': _aliBailianKeyStatus = isValid ? 'valid' : 'invalid'; break;
          case 'tikhub': _tikhubKeyStatus = isValid ? 'valid' : 'invalid'; break;
          case 'ai32': _ai32KeyStatus = isValid ? 'valid' : 'invalid'; break;
            case 'agnes': _agnesKeyStatus = isValid ? 'valid' : 'invalid'; break;
        }
      });

      _showSnackBar(isValid ? '✓ API Key有效' : '✗ API Key无效，请检查是否正确');
    } on DioException catch (e) {
      // 区分网络错误和密钥错误
      String hint;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        hint = '网络超时，请检查网络后重试';
        // 网络问题不清除状态，保留之前的
      } else if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        hint = 'API Key无效或无权限';
        setState(() {
          switch (platform) {
            case 'zhipu': _zhipuKeyStatus = 'invalid'; break;
            case 'siliconflow': _siliconFlowKeyStatus = 'invalid'; break;
            case 'alibailian': _aliBailianKeyStatus = 'invalid'; break;
            case 'tikhub': _tikhubKeyStatus = 'invalid'; break;
            case 'ai32': _ai32KeyStatus = 'invalid'; break;
            case 'agnes': _agnesKeyStatus = 'invalid'; break;
          }
        });
      } else if (e.response?.statusCode == 429) {
        hint = '请求过于频繁，稍后再试';
      } else {
        final statusCode = e.response?.statusCode ?? 0;
        final body = e.response?.data?.toString() ?? '';
        // 尝试从响应体中提取具体错误信息
        String detail = '';
        if (body.isNotEmpty) {
          try {
            final errData = body.startsWith('{') ? body : null;
            if (errData != null) {
              // 尝试解析JSON提取error message
              final decoded = Uri.decodeComponent(body);
              if (decoded.contains('message')) {
                final msgMatch = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(decoded);
                if (msgMatch != null) detail = msgMatch.group(1)!;
              }
            }
          } catch (_) {}
        }
        if (statusCode == 402) {
          hint = '余额不足，请到平台充值后再试';
        } else if (statusCode > 0) {
          hint = detail.isNotEmpty
              ? '$statusCode: $detail'
              : '服务器返回$statusCode，Key可能无效';
        } else {
          hint = '网络异常，请检查网络连接';
        }
        setState(() {
          switch (platform) {
            case 'zhipu': _zhipuKeyStatus = 'invalid'; break;
            case 'siliconflow': _siliconFlowKeyStatus = 'invalid'; break;
            case 'alibailian': _aliBailianKeyStatus = 'invalid'; break;
            case 'tikhub': _tikhubKeyStatus = 'invalid'; break;
            case 'ai32': _ai32KeyStatus = 'invalid'; break;
            case 'agnes': _agnesKeyStatus = 'invalid'; break;
          }
        });
      }
      _showSnackBar('✗ $hint');
    } catch (e) {
      setState(() {
        switch (platform) {
          case 'zhipu': _zhipuKeyStatus = 'invalid'; break;
          case 'siliconflow': _siliconFlowKeyStatus = 'invalid'; break;
          case 'alibailian': _aliBailianKeyStatus = 'invalid'; break;
          case 'tikhub': _tikhubKeyStatus = 'invalid'; break;
          case 'ai32': _ai32KeyStatus = 'invalid'; break;
          case 'agnes': _agnesKeyStatus = 'invalid'; break;
        }
      });
      _showSnackBar('✗ 检测失败，请稍后重试');
    } finally {
      setState(() => _testingKey = null);
    }
  }

  /// 清除指定API Key
  Future<void> _clearApiKey(String platform) async {
    String storageKey;
    switch (platform) {
      case 'zhipu':
        storageKey = ApiConfig.zhipuApiKeyKey;
        _zhipuKeyController.clear();
        _zhipuKeyStatus = null;
        break;
      case 'siliconflow':
        storageKey = ApiConfig.siliconFlowApiKeyKey;
        _siliconFlowKeyController.clear();
        _siliconFlowKeyStatus = null;
        break;
      case 'alibailian':
        storageKey = ApiConfig.aliBailianApiKeyKey;
        _aliBailianKeyController.clear();
        _aliBailianKeyStatus = null;
        break;
      case 'tikhub':
        storageKey = ApiConfig.tikhubApiKeyKey;
        _tikhubKeyController.clear();
        _tikhubKeyStatus = null;
        break;
      case 'ai32':
        storageKey = ApiConfig.ai32ApiKeyKey;
        _ai32KeyController.clear();
        _ai32KeyStatus = null;
        break;
      case 'agnes':
        storageKey = ApiConfig.agnesApiKeyKey;
        _agnesKeyController.clear();
        _agnesKeyStatus = null;
        break;
      default:
        return;
    }
    await StorageUtil.deleteSecure(storageKey);
    setState(() {});
  }

  /// 添加自定义敏感词
  Future<void> _addCustomWord() async {
    final word = _customWordController.text.trim();
    if (word.isEmpty) return;

    final id = await StorageUtil.insertCustomWord(word);
    if (id > 0) {
      _customWordController.clear();
      await _loadCustomWords();
      _countBuiltinWords();
      setState(() {});
      _showSnackBar('已添加：$word');
    } else {
      _showSnackBar('该词已存在');
    }
  }

  /// 删除自定义敏感词
  Future<void> _deleteCustomWord(int id) async {
    await StorageUtil.deleteCustomWord(id);
    await _loadCustomWords();
    _countBuiltinWords();
    setState(() {});
  }

  /// 导入自定义词库
  Future<void> _importCustomWords() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入词库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('请粘贴JSON格式词库数据：', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            const SizedBox(height: 8),
            TextField(
              controller: controller,
              maxLines: 8,
              style: const TextStyle(fontSize: 13, color: AppTheme.textPrimary),
              decoration: const InputDecoration(
                hintText: '[{"word":"示例词","category":"自定义"}]',
                hintStyle: TextStyle(fontSize: 12, color: AppTheme.textHint),
                filled: true,
                fillColor: AppTheme.darkSurface,
                border: OutlineInputBorder(borderSide: BorderSide.none),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('导入')),
        ],
      ),
    );

    if (result == true && controller.text.isNotEmpty) {
      try {
        final List<dynamic> data = jsonDecode(controller.text);
        final words = data.map((e) => e as Map<String, dynamic>).toList();
        final count = await StorageUtil.importCustomWords(words);
        await _loadCustomWords();
        _countBuiltinWords();
        setState(() {});
        _showSnackBar('成功导入 $count 个词');
      } catch (e) {
        _showSnackBar('导入失败，请检查JSON格式');
      }
    }
    controller.dispose();
  }

  /// 导出自定义词库
  Future<void> _exportCustomWords() async {
    final words = await StorageUtil.exportCustomWords();
    final jsonStr = const JsonEncoder.withIndent('  ').convert(words);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导出词库'),
        content: SingleChildScrollView(
          child: SelectableText(
            jsonStr,
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }

  /// 显示清理缓存对话框
  Future<void> _showClearCacheDialog() async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('清理缓存'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('选择要清理的缓存类型：'),
            SizedBox(height: 8),
            Text('• 音频缓存：TTS生成的音频文件', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            Text('• 视频缓存：数字人视频文件', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            Text('• 临时缓存：运行时临时文件', style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
            SizedBox(height: 8),
            Text('注意：不会删除API Key和历史记录', style: TextStyle(fontSize: 12, color: AppTheme.textHint)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await StorageUtil.clearCache('all');
              await _loadCacheStats();
              setState(() {});
              _showSnackBar('缓存已清理');
            },
            child: const Text('全部清理'),
          ),
        ],
      ),
    );
  }

  /// 显示清除全部历史对话框
  Future<void> _showClearAllHistoryDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('⚠️ 清除全部历史'),
        content: const Text('此操作将删除所有文案记录、音频文件和视频文件，且不可恢复。\n\n确定要继续吗？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppTheme.highRiskColor),
            child: const Text('确定清除'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageUtil.clearAllHistory();
      await _loadCacheStats();
      setState(() {});
      _showSnackBar('全部历史已清除');
    }
  }

  /// 带描述的模型选择器（从ApiConfig的选项列表构建）
  Widget _buildModelSelectorWithDesc({
    required String value,
    required List<Map<String, String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    // 确保当前值在选项列表中，否则回退到第一个
    final validValues = items.map((e) => e['value']!).toList();
    final currentValue = validValues.contains(value) ? value : validValues.first;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.darkSurface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: currentValue,
          isExpanded: true,
          dropdownColor: AppTheme.darkSurface,
          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary),
          items: items.map((item) {
            return DropdownMenuItem(
              value: item['value'],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item['label']!, style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary)),
                  if (item['desc'] != null && item['desc']!.isNotEmpty)
                    Text(item['desc']!, style: const TextStyle(fontSize: 10, color: AppTheme.textHint)),
                ],
              ),
            );
          }).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}
