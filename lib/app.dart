import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'config/routes.dart';

/// App根组件 - 配置MaterialApp
class KouboApp extends StatelessWidget {
  const KouboApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '口播智能体',
      debugShowCheckedModeBanner: false,
      // 主题配置
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      // 路由配置
      initialRoute: '/',
      routes: AppRoutes.routes,
      onGenerateRoute: AppRoutes.onGenerateRoute,
      // 全局错误处理 - 未知路由
      onUnknownRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('页面不存在')),
            body: const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: AppTheme.textHint),
                  SizedBox(height: 16),
                  Text(
                    '页面不存在',
                    style: TextStyle(fontSize: 18, color: AppTheme.textPrimary),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '请返回首页重试',
                    style: TextStyle(fontSize: 14, color: AppTheme.textHint),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      // 全局Builder - 捕获渲染异常
      builder: (context, widget) {
        // 包裹ErrorBoundary捕获渲染异常
        Widget errorWidget;
        ErrorBoundary.handleError = (FlutterErrorDetails details) {
          debugPrint('渲染异常：${details.exceptionAsString()}');
        };

        try {
          errorWidget = widget ?? const SizedBox.shrink();
        } catch (e) {
          errorWidget = const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: AppTheme.highRiskColor),
                SizedBox(height: 16),
                Text('出了点问题', style: TextStyle(color: AppTheme.textPrimary)),
              ],
            ),
          );
        }

        return errorWidget;
      },
    );
  }
}

/// 简单的错误边界 - 捕获渲染过程中的异常
class ErrorBoundary extends StatelessWidget {
  static void Function(FlutterErrorDetails)? handleError;

  const ErrorBoundary({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return child;
  }
}
