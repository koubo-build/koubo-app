import 'dart:convert';

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
  /// Fun-ASR-Realtime 实时识别 WebSocket 端点（北京地域）
  static const String aliAsrRealtimeWsUrl = 'wss://dashscope.aliyuncs.com/api-ws/v1/inference';
  /// Fun-ASR-Realtime 当前稳定版模型名
  static const String aliAsrRealtimeModel = 'fun-asr-realtime';
  /// Fun-ASR 同步兼容模式模型名（chat/completions input_audio 方式）
  static const String aliAsrCompatModel = 'fun-asr-realtime';
  /// 兼容模式 qwen3-asr-flash（保留旧实现作为回退）
  static const String aliAsrQwen3FlashModel = 'qwen3-asr-flash';
  
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
    {'value': 'agnes-2.0-flash', 'label': 'Agnes-2.0-Flash', 'desc': 'Agnes AI，免费'},
  ];
  /// 数字人视频可选模型
  static const List<Map<String, String>> videoModelOptions = [
    {'value': 'wan2.2-s2v', 'label': '万相数字人', 'desc': '照片+音频→口型视频(百炼)'},
    {'value': 'happyhorse-1.0-i2v', 'label': 'HappyHorse图生视频', 'desc': '照片→动作视频(百炼)'},
    {'value': 'feiying', 'label': '飞影数字人', 'desc': '音频驱动数字人视频(飞影)'},
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

  // ==================== 硅基流动 FLUX.1-schnell 免费文生图 ====================
  static const String siliconFlowImageEndpoint = 'https://api.siliconflow.cn/v1/images/generations';
  static const String siliconFlowFluxSchnellModel = 'black-forest-labs/FLUX.1-schnell';

  // ==================== Agnes AI（全模态免费平台） ====================
  static const String agnesBaseUrl = 'https://apihub.agnes-ai.cn/v1';
  static const String agnesModelFlash = 'agnes-2.0-flash';
  /// Agnes 2.5 Flash 文本模型（更强推理）
  static const String agnesModel25Flash = 'agnes-2.5-flash';

  // ==================== DeepSeek ====================
  static const String deepseekBaseUrl = 'https://api.deepseek.com/v1';
  static const String deepseekModelChat = 'deepseek-chat';
  static const String deepseekModelReasoner = 'deepseek-reasoner';

  // ==================== MiniMax(海螺AI) ====================
  static const String minimaxBaseUrl = 'https://api.minimax.chat/v1';
  static const String minimaxModelText = 'MiniMax-Text-01';

  // ==================== 火山引擎(豆包) ====================
  static const String doubaoBaseUrl = 'https://ark.cn-beijing.volces.com/api/v3';
  static const String doubaoModelLite = 'doubao-pro-32k';

  // ==================== 可灵AI（视频生成） ====================
  static const String klingBaseUrl = 'https://api.klingai.com';

  // ==================== Vidu 开放平台（视频生成） ====================
  static const String viduBaseUrl = 'https://api.vidu.cn';

  // ==================== 自定义API Provider ====================
  /// 自定义文本API Base URL（OpenAI兼容格式）
  static const String customTextBaseUrl = 'custom_text_base_url';
  static const String customTextApiKeyKey = 'custom_text_api_key';
  static const String customTextModelName = 'custom_text_model_name';
  /// 自定义图片API配置
  static const String customImageBaseUrl = 'custom_image_base_url';
  static const String customImageApiKeyKey = 'custom_image_api_key';
  static const String customImageModelName = 'custom_image_model_name';
  /// 自定义视频API配置
  static const String customVideoBaseUrl = 'custom_video_base_url';
  static const String customVideoApiKeyKey = 'custom_video_api_key';
  static const String customVideoModelName = 'custom_video_model_name';

  // ==================== API Key存储键名 ====================
  static const String zhipuApiKeyKey = 'zhipu_api_key';
  static const String siliconFlowApiKeyKey = 'siliconflow_api_key';
  static const String aliBailianApiKeyKey = 'ali_bailian_api_key';
  static const String kuhuyunApiKeyKey = 'kuhuyun_api_key';
  static const String tikhubApiKeyKey = 'tikhub_api_key';
  static const String agnesApiKeyKey = 'agnes_api_key';
  static const String deepseekApiKeyKey = 'deepseek_api_key';
  static const String minimaxApiKeyKey = 'minimax_api_key';
  static const String doubaoApiKeyKey = 'doubao_api_key';
  static const String feiyingApiKeyKey = 'feiying_api_key';

  // ==================== 内置默认API Key（首次安装自动填充） ====================
  /// 用户首次安装App时，自动填充以下API Key，免去手动配置的麻烦
  /// 用户仍可在设置页修改为自己的Key
  /// 注意：值为base64编码，运行时通过decodeDefaultKey解码
  static const Map<String, String> _defaultApiKeysEncoded = {
    zhipuApiKeyKey: 'ZjNkZWQ4NmVlZGRjNDI0OWE2ZTE1MGQ4YjY1NGQ4ZDIuSXdhaUVxNDZGYU9YOW01Ng==',
    siliconFlowApiKeyKey: 'c2stYmJqdHduZ2R1d3pjZWNqZ2NrdXVhaWxyaXljbnF3aWxoaGl0ZGdlbnd2cXd2dHd6',
    aliBailianApiKeyKey: 'c2stOTVlODI2NzE5ODIxNGU5NzkzYzEzY2ZmNTZjM2VkNzI=',
    deepseekApiKeyKey: 'c2stZGNlMGI3ZmNkMWY0NGI4MDliZWE1YmExMTI1OGYzMzQ=',
    feiyingApiKeyKey: 'dXU0YWl3V2xIbVEtaG4zREJocVhhQVdYQnJjTmh5ZEdRcHRNRG5mUUg2NA==',
    agnesApiKeyKey: 'c2stUmNiN0Z6aVdTeVBxM2NaUEVjckh4NFhoNE1PdGUxRGxVanVFZzZ3MFRCVnZoaXVi',
  };

  /// 获取解码后的默认API Key Map
  static Map<String, String> get defaultApiKeys {
    return _defaultApiKeysEncoded.map((key, encoded) => MapEntry(key, _decodeKey(encoded)));
  }

  /// base64解码辅助方法
  static String _decodeKey(String encoded) {
    try {
      final bytes = base64.decode(encoded);
      return String.fromCharCodes(bytes);
    } catch (_) {
      return encoded; // 解码失败时返回原值
    }
  }

  // ==================== 飞影数字人（AI数字人视频生成平台） ====================
  /// 飞影数字人 API Base URL
  static const String feiyingBaseUrl = 'https://hfw-api.hifly.cc';
  /// 创建视频数字人（通过视频URL）
  static const String feiyingCreateAvatarByVideo = '/api/v2/hifly/avatar/create_by_video';
  /// 创建图片数字人
  static const String feiyingCreateAvatarByImage = '/api/v2/hifly/avatar/create_by_image';
  /// 查询数字人克隆任务状态
  static const String feiyingAvatarTaskQuery = '/api/v2/hifly/avatar/task';
  /// 查询公共数字人列表
  static const String feiyingAvatarList = '/api/v2/hifly/avatar/list';
  /// 创建声音克隆
  static const String feiyingVoiceCreate = '/api/v2/hifly/voice/create';
  /// 查询声音列表
  static const String feiyingVoiceList = '/api/v2/hifly/voice/list';
  /// 查询声音克隆任务状态
  static const String feiyingVoiceTaskQuery = '/api/v2/hifly/voice/task';
  /// 视频创作（音频驱动）
  static const String feiyingVideoCreateByAudio = '/api/v2/hifly/video/create_by_audio';
  /// 视频创作（文本驱动TTS）
  static const String feiyingVideoCreateByTts = '/api/v2/hifly/video/create_by_tts';
  /// 查询创作任务状态
  static const String feiyingVideoTaskQuery = '/api/v2/hifly/video/task';
  /// 上传文件获取上传地址
  static const String feiyingCreateUploadUrl = '/api/v2/hifly/tool/create_upload_url';
  /// 查询账户积分
  static const String feiyingAccountCredit = '/api/v2/hifly/account/credit';

  // ==================== 火山引擎 豆包 Seedream 4.0 文生图 ====================
  /// Seedream 4.0 文生图接口（OpenAI兼容格式）
  static const String seedreamImageEndpoint = 'https://ark.cn-beijing.volces.com/api/v3/images/generations';
  /// Seedream 4.0 模型名
  static const String seedreamModel = 'doubao-seedream-4-0-250828';

  // ==================== 阿里百炼 Wan2.7-Image 文生图 ====================
  /// Wan2.7-Image 文生图接口（与Wanxiang共用路径，通过model字段区分）
  static const String wan27ImageSubmitUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/text2image/image-synthesis';
  /// Wan2.7-Image 模型名
  static const String wan27ImageModel = 'wan2.7-image';

  // ==================== 火山引擎 豆包 Seedance 1.0 Pro 图生视频 ====================
  /// Seedance 视频生成提交接口
  static const String seedanceVideoSubmitUrl = 'https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks';
  /// Seedance 任务状态查询接口
  static const String seedanceTaskQueryUrl = 'https://ark.cn-beijing.volces.com/api/v3/contents/generations/tasks/';
  /// Seedance 1.0 Pro 模型名
  static const String seedanceModel = 'doubao-seedance-1-0-pro-250528';

  // ==================== 阿里百炼 Wan2.7 图生视频 ====================
  /// Wan2.7-i2v 图生视频提交接口
  static const String wan27I2VSubmitUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/image2video/video-synthesis';
  /// Wan2.7-i2v 任务状态查询接口（与wanx共用）
  static const String wan27I2VTaskQueryUrl = 'https://dashscope.aliyuncs.com/api/v1/tasks/';
  /// Wan2.7-i2v 模型名
  static const String wan27I2VModel = 'wan2.7-i2v';

  // ==================== 阿里百炼 Wan2.1 图生视频（经典版） ====================
  /// Wan2.1-i2v 图生视频提交接口（与wan27共用同一端点）
  static const String wan21I2VSubmitUrl = 'https://dashscope.aliyuncs.com/api/v1/services/aigc/image2video/video-synthesis';
  /// Wan2.1-i2v 模型名
  static const String wan21I2VModel = 'wan2.1-i2v-plus';

  // ==================== 智谱 CogVideoX 图生视频 ====================
  /// CogVideoX 视频生成接口
  static const String cogVideoXSubmitUrl = 'https://open.bigmodel.cn/api/paas/v4/videos/generations';
  /// CogVideoX 任务状态查询接口
  static const String cogVideoXTaskQueryUrl = 'https://open.bigmodel.cn/api/paas/v4/async/result/';
  /// CogVideoX 模型名
  static const String cogVideoXModel = 'cogvideox-2';

  // ==================== 阿里百炼 万相风格化文生图 ====================
  /// 万相风格化模型名
  static const String wanxStyleModel = 'wanx2.1-t2i-plus';

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
