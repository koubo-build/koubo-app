/// API地址配置 - 各平台API地址常量
class ApiConfig {
  ApiConfig._();

  // ==================== 智谱AI（GLM-4-Flash 永久免费） ====================
  static const String zhipuBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const String zhipuChatEndpoint = '/chat/completions';
  static const String zhipuModelFlash = 'glm-4-flash';
  static const String zhipuModel4 = 'glm-4';

  // ==================== 硅基流动（Qwen2.5-7B 免费模型） ====================
  static const String siliconFlowBaseUrl = 'https://api.siliconflow.cn/v1';
  static const String siliconFlowChatEndpoint = '/chat/completions';
  static const String siliconFlowModelQwen = 'Qwen/Qwen2.5-7B-Instruct';
  static const String siliconFlowModelDeepSeek = 'deepseek-ai/DeepSeek-V2.5';

  // ==================== DeepSeek（法务审核，需强推理） ====================
  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';
  static const String deepseekChatEndpoint = '/chat/completions';
  static const String deepseekModelV3 = 'deepseek-chat';
  static const String deepseekModelR1 = 'deepseek-reasoner';

  // ==================== 阿里百炼（CosyVoice语音 + ASR） ====================
  static const String aliBailianBaseUrl = 'https://dashscope.aliyuncs.com/api/v1';
  static const String aliBailianCompatUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const String aliCosyvoiceEndpoint = '/services/audio/tts/SpeechSynthesizer';
  static const String aliVoiceRegisterEndpoint = '/services/audio/tts/customization';
  static const String aliAsrEndpoint = '/services/audio/asr/transcription';
  
  // ==================== 阿里百炼 Qwen TTS VC（声音克隆后合成） ====================
  static const String aliQwenTtsVcModel = 'qwen3-tts-vc-2026-01-22';
  static const String aliQwenVoiceEnrollmentModel = 'qwen-voice-enrollment';
  static const String aliMultimodalGenerationEndpoint = '/services/aigc/multimodal-generation/generation';

  // ==================== 飞影数字人API ====================
  static const String hiflyBaseUrl = 'https://hifly.cc/api/v2';
  static const String hiflyCreateVideoEndpoint = '/create_lipsync_video';
  static const String hiflyInspectStatusEndpoint = '/inspect_video_creation_status';
  static const String hiflyVoiceListEndpoint = '/voice/list';
  static const String hiflyAvatarListEndpoint = '/avatar/list';

  // ==================== 第三方文案提取API（兜底） ====================
  static const String kuhuyunBaseUrl = 'https://api.kuhuyun.com/api/aibasic';
  static const String kuhuyunVideoAnalysisEndpoint = '/videoanalysis';

  // ==================== Edge-TTS（免费基础配音） ====================
  static const String edgeTtsBaseUrl = 'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  // ==================== 模型优先级配置 ====================
  /// 改写场景：主模型改写 + 辅助模型评分
  static const Map<String, String> rewriteStrategy = {
    'main_model': zhipuModelFlash,       // 主力改写模型（免费）
    'score_model': siliconFlowModelQwen, // 改写质量评分（免费）
    'review_model': deepseekModelV3,     // 法务审核（需强推理能力）
  };

  // ==================== API Key存储键名 ====================
  static const String zhipuApiKeyKey = 'zhipu_api_key';
  static const String siliconFlowApiKeyKey = 'siliconflow_api_key';
  static const String deepseekApiKeyKey = 'deepseek_api_key';
  static const String aliBailianApiKeyKey = 'ali_bailian_api_key';
  static const String hiflyApiKeyKey = 'hifly_agent_token';
  static const String kuhuyunApiKeyKey = 'kuhuyun_api_key';
}
