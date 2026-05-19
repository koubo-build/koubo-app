# 口播智能体 App

> AI口播文案创作助手 - 从文案提取到数字人视频的全流程工具

## 📱 项目简介

口播智能体是一款面向短视频创作者的AI口播文案创作助手，支持以下完整创作流程：

1. **文案提取** - 粘贴抖音链接，自动提取视频口播文案
2. **法务审核** - 关键词快速过滤 + 大模型深度审核双重机制
3. **AI改写** - 6种改写模式，多版本并行生成，智能评分排序
4. **语音合成** - Edge-TTS免费配音 + CosyVoice声音克隆
5. **数字人视频** - 上传照片一键生成数字人口播视频（飞影API）

### ✨ 核心功能

| 功能模块 | 描述 |
|---------|------|
| 🎬 创作工作台 | 一站式：链接提取→AI改写→法务审核→定稿 |
| ✍️ AI改写 | 6种模式（同义/口语化/缩写/扩写/风格转换/去重），3版本并行+质量评分 |
| 🛡️ 法务审核 | 广告法违禁词+敏感词+平台违规+侵权风险，支持一键修正 |
| 🎙️ 语音合成 | Edge-TTS免费配音 + CosyVoice高质量合成 + 声音克隆 |
| 🤖 数字人视频 | 飞影API驱动，选择数字人+配音一键生成 |
| 📋 历史记录 | 文案/音频/视频三分栏管理，搜索+批量删除 |
| ⚙️ 设置中心 | API Key加密管理+模型偏好+词库管理+缓存管理 |

## 🛠️ 技术栈

| 类别 | 技术 |
|------|------|
| **框架** | Flutter 3.x (Dart) |
| **状态管理** | flutter_riverpod |
| **网络请求** | dio（支持SSE流式请求） |
| **本地数据库** | sqflite（7张表完整CRUD） |
| **安全存储** | flutter_secure_storage（API Key加密） |
| **轻量配置** | shared_preferences（模型偏好等） |
| **音频处理** | record + just_audio |
| **视频播放** | video_player |
| **图片选择** | image_picker |
| **权限管理** | permission_handler |
| **文本对比** | diff_match_patch |
| **文件分享** | share_plus |
| **URL跳转** | url_launcher |

## 🏗️ 项目结构

```
lib/
├── main.dart                  # 入口（初始化+ProviderScope）
├── app.dart                   # MaterialApp配置（主题+路由+全局错误处理）
├── config/
│   ├── api_config.dart        # 各平台API地址常量+Key存储键名
│   ├── routes.dart            # 路由配置（静态路由+动态路由）
│   └── theme.dart             # 深色/浅色主题配置
├── models/
│   ├── script.dart            # 文案模型
│   ├── rewrite_version.dart   # 改写版本模型
│   ├── audit_result.dart      # 审核结果模型（含AuditIssue）
│   └── voice_model.dart       # 音色模型
├── pages/
│   ├── home/home_page.dart         # 首页（6宫格+最近创作+首次引导）
│   ├── extract/extract_page.dart   # 创作工作台（一站式流程）
│   ├── rewrite/
│   │   ├── rewrite_page.dart       # AI改写页
│   │   └── rewrite_compare.dart    # 改写对比页
│   ├── audit/audit_page.dart       # 法务审核页
│   ├── voice/voice_page.dart       # 语音合成+声音克隆
│   ├── digital_human/              # 数字人视频生成
│   │   └── digital_human_page.dart
│   ├── settings/settings_page.dart # 设置页（Key+模型+词库+缓存+关于）
│   ├── history/history_page.dart   # 历史记录（三Tab+搜索+批量操作）
│   └── help/help_page.dart         # 使用帮助（入门+FAQ+Key教程）
├── providers/
│   ├── workflow_provider.dart      # 创作工作流状态
│   ├── script_provider.dart        # 文案状态
│   ├── rewrite_provider.dart       # 改写状态
│   ├── audit_provider.dart         # 审核状态
│   ├── voice_provider.dart         # 语音状态
│   └── digital_human_provider.dart # 数字人状态
├── services/
│   ├── api_client.dart        # 统一网络客户端（Dio+拦截器+SSE）
│   ├── douyin_service.dart    # 抖音文案提取
│   ├── ai_rewrite_service.dart# AI改写服务
│   ├── legal_audit_service.dart# 法务审核服务
│   ├── tts_service.dart       # TTS语音合成
│   ├── voice_clone_service.dart# 声音克隆
│   └── digital_human_service.dart# 数字人视频
├── utils/
│   ├── storage_util.dart      # 存储工具（SecureStorage+Prefs+SQLite+文件目录）
│   ├── word_filter.dart       # 关键词过滤引擎（精确+模糊+拼音匹配）
│   └── permission_util.dart   # 权限管理
└── widgets/
    ├── common/
    │   ├── app_button.dart    # 通用按钮
    │   ├── app_card.dart      # 通用卡片+信息卡片
    │   ├── app_input.dart     # 通用输入框+多行文本框
    │   └── loading_widget.dart# 加载组件
    └── risk_badge.dart        # 风险等级徽章
```

## 🚀 如何配置和运行

### 前置要求

- Flutter SDK >= 3.0.0
- Android Studio / VS Code
- Android SDK（compileSdkVersion 33+）
- JDK 17

### 安装步骤

```bash
# 1. 进入项目目录
cd koubo_app

# 2. 获取依赖
flutter pub get

# 3. 运行到安卓设备/模拟器
flutter run

# 4. 或构建APK
flutter build apk --release
```

### 首次运行配置

1. 启动App后，首页会显示「快速配置」引导卡片
2. 点击「去配置」进入设置页
3. 至少配置 **智谱AI** 的API Key（永久免费，推荐首选）
4. 配置完成后即可开始使用文案改写功能

## 🔑 API Key申请指南

| 平台 | 用途 | 免费额度 | 申请地址 |
|------|------|---------|---------|
| **智谱AI** | 文案改写（GLM-4-Flash） | 永久免费，2000万Token | https://open.bigmodel.cn/ |
| **硅基流动** | 备用改写（Qwen2.5-7B） | 9B以下模型永久免费 | https://siliconflow.cn/ |
| **DeepSeek** | 法务审核（强推理） | 100万Token（30天） | https://platform.deepseek.com/ |
| **阿里百炼** | 语音合成/克隆 | 每模型100万Token | https://dashscope.console.aliyun.com/ |
| **飞影数字人** | 数字人视频生成 | 新用户体验时长 | https://hifly.cc/ |

### API Key获取步骤

**智谱AI（推荐优先配置）：**
1. 注册智谱AI账号 → https://open.bigmodel.cn/
2. 登录控制台 → API Keys
3. 点击「创建新Key」→ 复制Key到App设置页

**硅基流动：**
1. 注册硅基流动账号 → https://siliconflow.cn/
2. 登录控制台 → API Keys
3. 创建新Key → 复制到App设置页

**DeepSeek：**
1. 注册DeepSeek账号 → https://platform.deepseek.com/
2. 登录控制台 → API Keys
3. 创建新Key → 复制到App设置页

## 📦 打包APK说明

### Release打包

```bash
# 构建release APK
flutter build apk --release

# 构建分架构APK（更小体积）
flutter build apk --split-per-abi --release

# 构建AppBundle（上架Google Play用）
flutter build appbundle --release
```

### 签名配置

1. 生成签名密钥：
```bash
keytool -genkey -v -keystore koubo-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias koubo
```

2. 在 `android/key.properties` 中配置：
```properties
storePassword=你的密码
keyPassword=你的密码
keyAlias=koubo
storeFile=../koubo-release.jks
```

3. 修改 `android/app/build.gradle` 添加签名配置（参考Flutter官方文档）

### 输出路径

- APK: `build/app/outputs/flutter-apk/app-release.apk`
- AppBundle: `build/app/outputs/bundle/release/app-release.aab`

## 📊 数据库设计

| 表名 | 用途 | 核心字段 |
|------|------|---------|
| `scripts` | 文案记录 | id, source_text, rewritten_text, risk_level, audit_status |
| `rewrite_versions` | 改写版本 | id, script_id, rewritten_text, score, similarity |
| `audit_records` | 审核记录 | id, script_id, overall_risk, ad_law_risk, sensitive_risk |
| `voice_clones` | 克隆音色 | id, name, voice_id, sample_path |
| `audio_files` | 音频文件 | id, script_id, voice_name, file_path, duration |
| `video_files` | 视频文件 | id, script_id, avatar_name, file_path, duration |
| `custom_words` | 自定义敏感词 | id, word, category |

## ⚠️ 注意事项

1. **API Key安全**：所有API Key使用 `flutter_secure_storage` 加密存储，不会上传服务器
2. **数据本地**：文案、音频、视频数据均保存在本地，AI处理通过各平台官方API直连
3. **网络依赖**：核心功能（提取/改写/审核/合成）需要网络连接
4. **免费优先**：推荐优先使用智谱AI的GLM-4-Flash（永久免费），其他Key按需配置
5. **缓存管理**：定期在设置页清理缓存，避免占用过多存储空间

## 📄 版本信息

- **版本号**: v1.0.0
- **最低SDK**: Android 5.0 (API 21)
- **目标SDK**: Android 14 (API 34)
