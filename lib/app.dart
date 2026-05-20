import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'config/routes.dart';

/// App根组件 - 配置MaterialApp
class KouboApp extends StatefulWidget {
  final String? initError;
  const KouboApp({super.key, this.initError});

  @override
  State<KouboApp> createState() => _KouboAppState();
}

class _KouboAppState extends State<KouboApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '口播智能体',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: widget.initError != null
          ? _ErrorPage(error: widget.initError!)
          : null,
      initialRoute: widget.initError != null ? null : '/',
      routes: widget.initError != null ? {} : AppRoutes.routes,
      onGenerateRoute: widget.initError != null ? null : AppRoutes.onGenerateRoute,
      onUnknownRoute: (RouteSettings settings) {
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            appBar: AppBar(title: const Text('页面不存在')),
            body: const Center(child: Text('页面不存在，请返回首页重试')),
          ),
        );
      },
      // Catch rendering errors - show fallback UI instead of grey screen
      builder: (context, widget) {
        ErrorWidget.builder = (FlutterErrorDetails details) {
          return Material(
            child: Container(
              color: AppTheme.darkBackground,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.red),
                      const SizedBox(height: 16),
                      const Text('页面渲染出错', style: TextStyle(fontSize: 18, color: Colors.white)),
                      const SizedBox(height: 8),
                      Text(
                        details.exceptionAsString(),
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        textAlign: TextAlign.center,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        };
        return widget ?? const SizedBox.shrink();
      },
    );
  }
}

/// 初始化错误页面
class _ErrorPage extends StatelessWidget {
  final String error;
  const _ErrorPage({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('口播智能体')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('初始化失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(fontSize: 14, color: Colors.grey), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
