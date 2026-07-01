/// API地址配置 - 各平台API地址常量
class ApiConfig {
  ApiConfig._();

  // ==================== 智谱AI（GLM-4.7-Flash 永久免费） ====================
  static const String zhipuBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const String zhipuChatEndpoint = '/chat/completions';
  static const String zhipuModelFlash = 'glm-4.7-flash';
  static const String zhipuModel4 = 'glm-4-plus';

  // ==================== 硅基流动（Qwen2.5-7B 免费模型） ====================
  static const String siliconFlowBaseUrl = 'https://api.siliconflow.cn/v1';
  static const String siliconFlowChatEndpoint = '/chat/completions';
  static const String siliconFlowModelQwen = 'Qwen/Qwen2.5-7B-Instruct';

  // ==================== 阿里百炼（语音 + 文案 + 数字人） ====================
  static const String aliBailianBaseUrl = 'https://dashscope.aliyuncs.com/api/v1';
  static const String aliBailianCompatUrl = 'https://dashscope.aliyuncs.com/compatible-mode/v1';
  static const String aliCosyvoiceEndpoint = '/services/audio/tts/SpeechSynthesizer';
  static const String aliVoiceRegisterEndpoint = '/services/audio/tts/customization';
  static const String aliAsrEndpoint = '/services/audio/asr/transcription';
  
  // ==================== 阿里百炼 声音复刻（qwen-voice-enrollment + qwen3.5-omni） ====================
  static const String aliQwenVoiceEnrollmentModel = 'qwen-voice-enrollment';
  static const String aliOmniModel = 'qwen3.5-omni-flash';  // 克隆音色驱动模型（免费flash版）
  static const String aliMultimodalGenerationEndpoint = '/services/aigc/multimodal-generation/generation';

  // ==================== 阿里百炼 万相(wan2.2-s2v) 数字人 ====================
  /// 文件上传接口 - 获取临时OSS上传凭证
  static const String bailianUploadUrl = 'https://dashscope.aliyuncs.com/api/v1/uploads';
  /// 万相图像检测接口（同步）
  static const String wanxDetectUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/image2video/face-detect';
  /// 万相视频生成提交接口（异步）
  static const String wanxVideoSubmitUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/image2video/video-synthesis';
  /// 万相任务状态查询接口
  static const String wanxTaskQueryUrl = 'https://dashscope.aliyuncs.com/api/v1/tasks/';
  /// 万相模型名
  static const String wanxS2vModel = 'wan2.2-s2v';
  /// 万相图像检测模型名
  static const String wanxDetectModel = 'wan2.2-s2v-detect';

  // ==================== 阿里百炼 HappyHorse 视频生成 ====================
  /// HappyHorse视频生成提交接口（与万相同路径，通过model字段区分）
  static const String happyHorseVideoSubmitUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/video-generation/video-synthesis';
  /// HappyHorse任务状态查询接口（与万相同）
  static const String happyHorseTaskQueryUrl = 'https://dashscope.aliyuncs.com/api/v1/tasks/';
  /// HappyHorse 1.0 图生视频模型名
  static const String happyHorseI2vModel = 'happyhorse-1.0-i2v';
  /// HappyHorse 1.0 文生视频模型名
  static const String happyHorseT2vModel = 'happyhorse-1.0-t2v';

  // ==================== 可选模型列表配置 ====================
  /// 文案生成可选模型（数字人页AI生成文案用）
  static const List<Map<String, String>> scriptModelOptions = [
    {'value': '自动选择', 'label': '自动选择', 'desc': '智能路由，自动选可用Key'},
    {'value': 'qwen-plus', 'label': 'qwen-plus', 'desc': '阿里百炼，效果好'},
    {'value': 'glm-4.7-flash', 'label': 'GLM-4-Flash', 'desc': '智谱AI，永久免费'},
    {'value': 'Qwen2.5-7B', 'label': 'Qwen2.5-7B', 'desc': '硅基流动，免费'},
    {'value': 'ai32-qwen-plus', 'label': '32AI/qwen-plus', 'desc': '中转站，约官方价56%'},
    {'value': 'ai32-deepseek', 'label': '32AI/DeepSeek', 'desc': '中转站，性价比高'},
    {'value': 'agnes-2.0-flash', 'label': 'Agnes-2.0-Flash', 'desc': 'Agnes AI，免费'},
  ];
  /// 数字人视频可选模型
  static const List<Map<String, String>> videoModelOptions = [
    {'value': 'wan2.2-s2v', 'label': '万相数字人', 'desc': '照片+音频→口型视频(百炼)'},
    {'value': 'happyhorse-1.0-i2v', 'label': 'HappyHorse图生视频', 'desc': '照片→动作视频(百炼)'},
    {'value': 'ai32-seedance', 'label': '豆包Seedance(32AI)', 'desc': '中转站，性价比高'},
  ];
  /// TTS引擎可选
  static const List<Map<String, String>> ttsEngineOptions = [
    {'value': 'Edge-TTS', 'label': 'Edge-TTS', 'desc': '免费，音质一般'},
    {'value': 'CosyVoice', 'label': 'CosyVoice', 'desc': '百炼，音质好'},
  ];
  /// CosyVoice音色模型可选
  static const List<Map<String, String>> cosyVoiceModelOptions = [
    {'value': 'cosyvoice-v3-flash', 'label': 'v3-flash', 'desc': '最新flash版，速度快'},
    {'value': 'cosyvoice-v2', 'label': 'v2', 'desc': '稳定版，音质好'},
  ];

  // ==================== Edge-TTS WebSocket（国内被墙，已改走qwen_tts，仅保留常量供旧代码编译） ====================
  static const String edgeTtsBaseUrl = 'wss://speech.platform.bing.com/consumer/speech/synthesize/readaloud/edge/v1';

  // ==================== 第三方文案提取API（兜底） ====================
  static const String kuhuyunBaseUrl = 'https://api.kuhuyun.com/api/aibasic';
  static const String kuhuyunVideoAnalysisEndpoint = '/videoanalysis';

  // ==================== 免费抖音解析API（apibyte.cn，无需Key） ====================
  static const String apibyteParseUrl = 'https://apione.apibyte.cn/douyinparse';

  // ==================== TikHub解析API（抖音/快手视频解析） ====================
  static const String tikhubBaseUrl = 'https://api.tikhub.dev/api/v1';
  static const String tikhubVideoDataEndpoint = '/hybrid/video_data';

  // ==================== 32AI中转站（约官方价56%） ====================
  static const String ai32BaseUrl = 'https://32ai.uk/v1';
  static const String ai32VolcBaseUrl = 'https://32ai.uk/volc/v1';
  /// 32AI视频生成接口（豆包Seedance等）
  static const String ai32VideoGenEndpoint = '/contents/generations/tasks';

  // ==================== Agnes AI（全模态免费平台） ====================
  static const String agnesBaseUrl = 'https://api.agnes-ai.com/v1';
  static const String agnesModelFlash = 'agnes-2.0-flash';

  // ==================== API Key存储键名 ====================
  static const String zhipuApiKeyKey = 'zhipu_api_key';
  static const String siliconFlowApiKeyKey = 'siliconflow_api_key';
  static const String aliBailianApiKeyKey = 'ali_bailian_api_key';
  static const String kuhuyunApiKeyKey = 'kuhuyun_api_key';
  static const String tikhubApiKeyKey = 'tikhub_api_key';
  static const String ai32ApiKeyKey = 'ai32_api_key';
  static const String agnesApiKeyKey = 'agnes_api_key';

  // ==================== 阿里百炼 Wanxiang 文生图 ====================
  /// Wanxiang文生图提交接口（异步）
  static const String wanxT2ISubmitUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis';
  /// Wanxiang任务状态查询接口
  static const String wanxT2ITaskQueryUrl = 'https://dashscope.aliyuncs.com/api/v1/tasks/';
  /// Wanxiang文生图模型名
  static const String wanxT2IModel = 'wanx2.1-t2i-turbo';

  // ==================== 本地 Stable Diffusion ====================
  /// 本地SD WebUI默认地址（Android模拟器访问主机用10.0.2.2）
  static const String defaultLocalSdUrl = 'http://10.0.2.2:7860';
  /// 本地SD文生图接口
  static const String localSdTxt2ImgEndpoint = '/sdapi/v1/txt2img';
  /// 本地SD API Key配置键名
  static const String localSdUrlKey = 'local_sd_url';
}
