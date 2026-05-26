import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../config/api_config.dart';
import '../../config/theme.dart';
import '../../utils/storage_util.dart';

/// API配置状态
class ApiConfigState {
  final String? zhipuApiKey;
  final String? aliBailianApiKey;
  final String? deepseekApiKey;
  final String? siliconFlowApiKey;
  final String ttsEngine;
  final String rewriteModel;
  final String auditModel;

  const ApiConfigState({
    this.zhipuApiKey,
    this.aliBailianApiKey,
    this.deepseekApiKey,
    this.siliconFlowApiKey,
    this.ttsEngine = 'cosyvoice',
    this.rewriteModel = 'GLM-4-Flash',
    this.auditModel = 'DeepSeek-V3',
  });

  bool get hasZhipu => zhipuApiKey != null && zhipuApiKey!.isNotEmpty;
  bool get hasAliBailian => aliBailianApiKey != null && aliBailianApiKey!.isNotEmpty;
  bool get hasDeepseek => deepseekApiKey != null && deepseekApiKey!.isNotEmpty;
  bool get hasSiliconFlow => siliconFlowApiKey != null && siliconFlowApiKey!.isNotEmpty;

  bool get hasAnyMissing {
    return !hasZhipu || !hasAliBailian || !hasDeepseek;
  }

  String get statusSummary {
    final parts = <String>[];
    if (hasZhipu) parts.add('智谱✅');
    if (hasAliBailian) parts.add('阿里✅');
    if (hasDeepseek) parts.add('DeepSeek✅');
    if (parts.isEmpty) return '未配置任何API';
    final missing = <String>[];
    if (!hasZhipu) missing.add('智谱');
    if (!hasAliBailian) missing.add('阿里');
    if (!hasDeepseek) missing.add('DeepSeek');
    if (missing.isEmpty) return '全部已配置';
    return '${parts.join(' ')} | 缺失: ${missing.join(', ')}';
  }
}

/// API配置状态Provider
final apiConfigProvider = StateNotifierProvider<ApiConfigNotifier, ApiConfigState>((ref) {
  return ApiConfigNotifier();
});

/// API配置状态管理
class ApiConfigNotifier extends StateNotifier<ApiConfigState> {
  ApiConfigNotifier() : super(const ApiConfigState()) {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final zhipu = await StorageUtil.getSecure(ApiConfig.zhipuApiKeyKey);
    final ali = await StorageUtil.getSecure(ApiConfig.aliBailianApiKeyKey);
    final deepseek = await StorageUtil.getSecure(ApiConfig.deepseekApiKeyKey);
    final silicon = await StorageUtil.getSecure(ApiConfig.siliconFlowApiKeyKey);
    final ttsEngine = StorageUtil.getTtsEngine();
    final rewriteModel = StorageUtil.getRewriteModel();
    final auditModel = StorageUtil.getAuditModel();

    state = ApiConfigState(
      zhipuApiKey: zhipu,
      aliBailianApiKey: ali,
      deepseekApiKey: deepseek,
      siliconFlowApiKey: silicon,
      ttsEngine: ttsEngine,
      rewriteModel: rewriteModel,
      auditModel: auditModel,
    );
  }

  Future<void> setZhipuApiKey(String key) async {
    await StorageUtil.setSecure(ApiConfig.zhipuApiKeyKey, key);
    state = ApiConfigState(
      zhipuApiKey: key,
      aliBailianApiKey: state.aliBailianApiKey,
      deepseekApiKey: state.deepseekApiKey,
      siliconFlowApiKey: state.siliconFlowApiKey,
      ttsEngine: state.ttsEngine,
      rewriteModel: state.rewriteModel,
      auditModel: state.auditModel,
    );
  }

  Future<void> setAliBailianApiKey(String key) async {
    await StorageUtil.setSecure(ApiConfig.aliBailianApiKeyKey, key);
    state = ApiConfigState(
      zhipuApiKey: state.zhipuApiKey,
      aliBailianApiKey: key,
      deepseekApiKey: state.deepseekApiKey,
      siliconFlowApiKey: state.siliconFlowApiKey,
      ttsEngine: state.ttsEngine,
      rewriteModel: state.rewriteModel,
      auditModel: state.auditModel,
    );
  }

  Future<void> setDeepseekApiKey(String key) async {
    await StorageUtil.setSecure(ApiConfig.deepseekApiKeyKey, key);
    state = ApiConfigState(
      zhipuApiKey: state.zhipuApiKey,
      aliBailianApiKey: state.aliBailianApiKey,
      deepseekApiKey: key,
      siliconFlowApiKey: state.siliconFlowApiKey,
      ttsEngine: state.ttsEngine,
      rewriteModel: state.rewriteModel,
      auditModel: state.auditModel,
    );
  }

  Future<void> setTtsEngine(String engine) async {
    await StorageUtil.setTtsEngine(engine);
    state = ApiConfigState(
      zhipuApiKey: state.zhipuApiKey,
      aliBailianApiKey: state.aliBailianApiKey,
      deepseekApiKey: state.deepseekApiKey,
      siliconFlowApiKey: state.siliconFlowApiKey,
      ttsEngine: engine,
      rewriteModel: state.rewriteModel,
      auditModel: state.auditModel,
    );
  }

  Future<void> setRewriteModel(String model) async {
    await StorageUtil.setRewriteModel(model);
    state = ApiConfigState(
      zhipuApiKey: state.zhipuApiKey,
      aliBailianApiKey: state.aliBailianApiKey,
      deepseekApiKey: state.deepseekApiKey,
      siliconFlowApiKey: state.siliconFlowApiKey,
      ttsEngine: state.ttsEngine,
      rewriteModel: model,
      auditModel: state.auditModel,
    );
  }

  Future<void> setAuditModel(String model) async {
    await StorageUtil.setAuditModel(model);
    state = ApiConfigState(
      zhipuApiKey: state.zhipuApiKey,
      aliBailianApiKey: state.aliBailianApiKey,
      deepseekApiKey: state.deepseekApiKey,
      siliconFlowApiKey: state.siliconFlowApiKey,
      ttsEngine: state.ttsEngine,
      rewriteModel: state.rewriteModel,
      auditModel: model,
    );
  }

  void refresh() {
    _loadConfig();
  }
}

/// API配置指示器类型
enum ApiConfigIndicatorType {
  voice,     // 语音合成页
  extract,   // 创作工作台
  audit,     // 法务审核页
}

/// API配置指示器组件
/// 在功能页顶部显示当前API配置状态，支持点击配置
class ApiConfigIndicator extends ConsumerWidget {
  final ApiConfigIndicatorType type;
  final VoidCallback? onConfigChanged;

  const ApiConfigIndicator({
    super.key,
    required this.type,
    this.onConfigChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(apiConfigProvider);
    final hasWarning = config.hasAnyMissing;

    return GestureDetector(
      onTap: () => _showConfigSheet(context, ref, config),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: hasWarning 
              ? AppTheme.highRiskColor.withOpacity(0.1)
              : AppTheme.safeColor.withOpacity(0.1),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: hasWarning
                ? AppTheme.highRiskColor.withOpacity(0.3)
                : AppTheme.safeColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // 状态图标
            Icon(
              hasWarning ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              size: 16,
              color: hasWarning ? AppTheme.highRiskColor : AppTheme.safeColor,
            ),
            const SizedBox(width: 8),
            // 配置状态文本
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasWarning ? '⚠️ API Key未配置' : '🤖 当前模型',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: hasWarning ? AppTheme.highRiskColor : AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _getConfigSummary(config),
                    style: TextStyle(
                      fontSize: 10,
                      color: AppTheme.textHint,
                    ),
                  ),
                ],
              ),
            ),
            // 配置按钮
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.settings,
                    size: 12,
                    color: AppTheme.primaryColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '配置',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.primaryColor,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getConfigSummary(ApiConfigState config) {
    switch (type) {
      case ApiConfigIndicatorType.voice:
        final engine = config.ttsEngine == 'qwen_tts' ? 'Qwen-TTS' 
            : config.ttsEngine == 'edge_tts' ? 'Edge-TTS' : 'CosyVoice';
        return 'TTS: $engine ${config.hasAliBailian ? "✅" : "❌"}';
      case ApiConfigIndicatorType.extract:
        return '改写: ${config.rewriteModel} ${config.hasZhipu ? "✅" : "❌"} | 审核: ${config.auditModel} ${config.hasDeepseek ? "✅" : "❌"}';
      case ApiConfigIndicatorType.audit:
        return '审核: ${config.auditModel} ${config.hasDeepseek ? "✅" : "❌"}';
    }
  }

  void _showConfigSheet(BuildContext context, WidgetRef ref, ApiConfigState config) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ApiConfigSheet(
        type: type,
        config: config,
        onSave: (newConfig) {
          // 更新配置
          if (config.zhipuApiKey != newConfig.zhipuApiKey) {
            ref.read(apiConfigProvider.notifier).setZhipuApiKey(newConfig.zhipuApiKey ?? '');
          }
          if (config.aliBailianApiKey != newConfig.aliBailianApiKey) {
            ref.read(apiConfigProvider.notifier).setAliBailianApiKey(newConfig.aliBailianApiKey ?? '');
          }
          if (config.deepseekApiKey != newConfig.deepseekApiKey) {
            ref.read(apiConfigProvider.notifier).setDeepseekApiKey(newConfig.deepseekApiKey ?? '');
          }
          if (config.ttsEngine != newConfig.ttsEngine) {
            ref.read(apiConfigProvider.notifier).setTtsEngine(newConfig.ttsEngine);
          }
          if (config.rewriteModel != newConfig.rewriteModel) {
            ref.read(apiConfigProvider.notifier).setRewriteModel(newConfig.rewriteModel);
          }
          if (config.auditModel != newConfig.auditModel) {
            ref.read(apiConfigProvider.notifier).setAuditModel(newConfig.auditModel);
          }
          onConfigChanged?.call();
        },
      ),
    );
  }
}

/// API配置底部弹窗
class _ApiConfigSheet extends StatefulWidget {
  final ApiConfigIndicatorType type;
  final ApiConfigState config;
  final Function(ApiConfigState) onSave;

  const _ApiConfigSheet({
    required this.type,
    required this.config,
    required this.onSave,
  });

  @override
  State<_ApiConfigSheet> createState() => _ApiConfigSheetState();
}

class _ApiConfigSheetState extends State<_ApiConfigSheet> {
  late TextEditingController _zhipuController;
  late TextEditingController _aliController;
  late TextEditingController _deepseekController;
  late String _ttsEngine;
  late String _rewriteModel;
  late String _auditModel;
  bool _obscureZhipu = true;
  bool _obscureAli = true;
  bool _obscureDeepseek = true;

  @override
  void initState() {
    super.initState();
    _zhipuController = TextEditingController(text: widget.config.zhipuApiKey ?? '');
    _aliController = TextEditingController(text: widget.config.aliBailianApiKey ?? '');
    _deepseekController = TextEditingController(text: widget.config.deepseekApiKey ?? '');
    _ttsEngine = widget.config.ttsEngine;
    _rewriteModel = widget.config.rewriteModel;
    _auditModel = widget.config.auditModel;
  }

  @override
  void dispose() {
    _zhipuController.dispose();
    _aliController.dispose();
    _deepseekController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.darkCard,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 标题栏
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.textHint.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.settings, color: AppTheme.primaryColor, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _getSheetTitle(),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 根据类型显示不同的配置项
              if (widget.type == ApiConfigIndicatorType.voice) ...[
                _buildTtsConfig(),
              ] else if (widget.type == ApiConfigIndicatorType.extract) ...[
                _buildAliBailianConfig(),
                const SizedBox(height: 16),
                _buildZhipuConfig(),
                const SizedBox(height: 16),
                _buildDeepseekConfig(),
                const SizedBox(height: 16),
                _buildRewriteModelConfig(),
              ] else if (widget.type == ApiConfigIndicatorType.audit) ...[
                _buildDeepseekConfig(),
                const SizedBox(height: 16),
                _buildAuditModelConfig(),
              ],

              const SizedBox(height: 24),
              // 保存按钮
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveConfig,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    ),
                  ),
                  child: const Text(
                    '保存配置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSheetTitle() {
    switch (widget.type) {
      case ApiConfigIndicatorType.voice:
        return '语音合成配置';
      case ApiConfigIndicatorType.extract:
        return '创作工作台配置';
      case ApiConfigIndicatorType.audit:
        return '法务审核配置';
    }
  }

  Widget _buildTtsConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildApiKeyField(
          label: '阿里百炼 API Key',
          controller: _aliController,
          obscure: _obscureAli,
          onToggleObscure: () => setState(() => _obscureAli = !_obscureAli),
          hint: 'sk-xxxxxxxx 用于语音合成和声音克隆',
        ),
        const SizedBox(height: 16),
        const Text(
          'TTS 引擎选择',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        _buildEngineSelector(),
      ],
    );
  }

  Widget _buildAliBailianConfig() {
    return _buildApiKeyField(
      label: '阿里百炼 API Key',
      controller: _aliController,
      obscure: _obscureAli,
      onToggleObscure: () => setState(() => _obscureAli = !_obscureAli),
      hint: '用于语音合成、声音克隆、文案提取',
    );
  }

  Widget _buildZhipuConfig() {
    return _buildApiKeyField(
      label: '智谱 AI API Key',
      controller: _zhipuController,
      obscure: _obscureZhipu,
      onToggleObscure: () => setState(() => _obscureZhipu = !_obscureZhipu),
      hint: '用于文案改写（GLM-4-Flash 永久免费）',
    );
  }

  Widget _buildDeepseekConfig() {
    return _buildApiKeyField(
      label: 'DeepSeek API Key',
      controller: _deepseekController,
      obscure: _obscureDeepseek,
      onToggleObscure: () => setState(() => _obscureDeepseek = !_obscureDeepseek),
      hint: '用于法务审核（需强推理能力）',
    );
  }

  Widget _buildApiKeyField({
    required String label,
    required TextEditingController controller,
    required bool obscure,
    required VoidCallback onToggleObscure,
    required String hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppTheme.textSecondary,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.safeColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '必填',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.safeColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          obscureText: obscure,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(
              color: AppTheme.textHint,
              fontSize: 13,
            ),
            filled: true,
            fillColor: AppTheme.darkSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: const BorderSide(color: AppTheme.primaryColor, width: 1.5),
            ),
            suffixIcon: IconButton(
              icon: Icon(
                obscure ? Icons.visibility_off : Icons.visibility,
                size: 18,
                color: AppTheme.textHint,
              ),
              onPressed: onToggleObscure,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEngineSelector() {
    return Column(
      children: [
        _buildEngineOption('cosyvoice', 'CosyVoice', '阿里百炼主力TTS，支持情感控制'),
        const SizedBox(height: 8),
        _buildEngineOption('qwen_tts', 'Qwen TTS', '最新模型，适合克隆音色合成'),
        const SizedBox(height: 8),
        _buildEngineOption('edge_tts', 'Edge-TTS', '微软免费TTS，无需API Key'),
      ],
    );
  }

  Widget _buildEngineOption(String value, String label, String desc) {
    final isSelected = _ttsEngine == value;
    return GestureDetector(
      onTap: () => setState(() => _ttsEngine = value),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.primaryColor.withOpacity(0.15) : AppTheme.darkSurface,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
          border: Border.all(
            color: isSelected ? AppTheme.primaryColor : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? AppTheme.primaryColor : Colors.transparent,
                border: Border.all(
                  color: isSelected ? AppTheme.primaryColor : AppTheme.textHint,
                  width: 1.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? AppTheme.primaryColor : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    desc,
                    style: TextStyle(
                      fontSize: 11,
                      color: isSelected ? AppTheme.primaryColor.withOpacity(0.7) : AppTheme.textHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRewriteModelConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '改写模型',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _rewriteModel,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.darkSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: AppTheme.darkCard,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
          items: const [
            DropdownMenuItem(value: 'GLM-4-Flash', child: Text('GLM-4-Flash (免费)')),
            DropdownMenuItem(value: 'GLM-4', child: Text('GLM-4')),
            DropdownMenuItem(value: 'Qwen2.5-7B', child: Text('Qwen2.5-7B (硅基流动)')),
            DropdownMenuItem(value: 'DeepSeek-V3', child: Text('DeepSeek-V3')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _rewriteModel = value);
            }
          },
        ),
      ],
    );
  }

  Widget _buildAuditModelConfig() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '审核模型',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _auditModel,
          decoration: InputDecoration(
            filled: true,
            fillColor: AppTheme.darkSurface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              borderSide: BorderSide.none,
            ),
          ),
          dropdownColor: AppTheme.darkCard,
          style: const TextStyle(
            fontSize: 14,
            color: AppTheme.textPrimary,
          ),
          items: const [
            DropdownMenuItem(value: 'DeepSeek-V3', child: Text('DeepSeek-V3 (推荐)')),
            DropdownMenuItem(value: 'DeepSeek-R1', child: Text('DeepSeek-R1 (强推理)')),
            DropdownMenuItem(value: 'GLM-4', child: Text('GLM-4')),
          ],
          onChanged: (value) {
            if (value != null) {
              setState(() => _auditModel = value);
            }
          },
        ),
      ],
    );
  }

  void _saveConfig() {
    widget.onSave(ApiConfigState(
      zhipuApiKey: _zhipuController.text,
      aliBailianApiKey: _aliController.text,
      deepseekApiKey: _deepseekController.text,
      ttsEngine: _ttsEngine,
      rewriteModel: _rewriteModel,
      auditModel: _auditModel,
    ));
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('配置已保存'),
        backgroundColor: AppTheme.safeColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
