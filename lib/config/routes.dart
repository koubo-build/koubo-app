import 'package:flutter/material.dart';
import '../pages/home/home_page.dart';
import '../pages/extract/extract_page.dart';
import '../pages/rewrite/rewrite_page.dart';
import '../pages/rewrite/rewrite_compare.dart';
import '../pages/audit/audit_page.dart';
import '../pages/voice/voice_page.dart';
import '../pages/digital_human/digital_human_page.dart';
import '../pages/settings/settings_page.dart';
import '../pages/history/history_page.dart';
import '../pages/help/help_page.dart';

/// 路由配置 - 统一管理所有页面路由
class AppRoutes {
  AppRoutes._();

  // ==================== 路由名称常量 ====================
  static const String home = '/';
  static const String extract = '/extract';           // 创作工作台（一站式）
  static const String rewrite = '/rewrite';           // AI改写（独立入口）
  static const String rewriteCompare = '/rewrite/compare';
  static const String audit = '/audit';               // 法务审核（独立入口）
  static const String voice = '/voice';
  static const String digitalHuman = '/digital_human';
  static const String settings = '/settings';
  static const String history = '/history';           // 历史记录
  static const String help = '/help';                 // 使用帮助

  // ==================== 路由表 ====================
  static final Map<String, WidgetBuilder> routes = {
    home: (context) => const HomePage(),
    extract: (context) => const ExtractPage(),
    rewrite: (context) => const RewritePage(),
    audit: (context) => const AuditPage(),
    settings: (context) => const SettingsPage(),
    history: (context) => const HistoryPage(),
    help: (context) => const HelpPage(),
  };

  // ==================== 动态路由 ====================
  static Route<dynamic>? onGenerateRoute(RouteSettings settings) {
    final String routeName = settings.name ?? '';
    final args = settings.arguments as Map<String, dynamic>? ?? {};

    switch (routeName) {
      case rewriteCompare:
        return MaterialPageRoute(
          builder: (context) => RewriteComparePage(
            sourceText: args['sourceText'] as String? ?? '',
            rewrittenText: args['rewrittenText'] as String? ?? '',
            score: args['score'] as int? ?? 0,
          ),
          settings: settings,
        );

      case voice:
        // 语音合成页面，支持接收文案和音频参数
        return MaterialPageRoute(
          builder: (context) => VoicePage(
            initialText: args['text'] as String?,
            audioPath: args['audioPath'] as String?,
          ),
          settings: settings,
        );

      case digitalHuman:
        // 数字人视频页面，支持接收文案和音频参数
        return MaterialPageRoute(
          builder: (context) => DigitalHumanPage(
            initialText: args['text'] as String?,
            audioPath: args['audioPath'] as String?,
          ),
          settings: settings,
        );

      default:
        return null;
    }
  }
}
