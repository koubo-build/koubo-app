import 'package:flutter/material.dart';
import 'config/theme.dart';
import 'config/routes.dart';

class KouboApp extends StatefulWidget {
  final String? initError;
  const KouboApp({super.key, this.initError});

  @override
  State<KouboApp> createState() => _KouboAppState();
}

class _KouboAppState extends State<KouboApp> {
  @override
  void initState() {
    super.initState();
    // Set error widget builder once
    ErrorWidget.builder = (FlutterErrorDetails details) {
      return Material(
        child: Container(
          color: const Color(0xFF1A1A2E),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: Colors.red),
                const SizedBox(height: 16),
                const Text('渲染出错', style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    details.exceptionAsString(),
                    style: const TextStyle(fontSize: 11, color: Colors.orange, fontFamily: 'monospace'),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    };
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '口播智能体',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: ThemeMode.dark,
      home: widget.initError != null ? _ErrorPage(error: widget.initError!) : null,
      initialRoute: widget.initError != null ? null : '/',
      routes: widget.initError != null ? {} : AppRoutes.routes,
      onGenerateRoute: widget.initError != null ? null : AppRoutes.onGenerateRoute,
    );
  }
}

class _ErrorPage extends StatelessWidget {
  final String error;
  const _ErrorPage({required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text('初始化失败', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(fontSize: 13, color: Colors.orange), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
