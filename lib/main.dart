import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'utils/storage_util.dart';

/// App入口 - 初始化并启动应用
void main() {
  // 确保Flutter绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 捕获Flutter框架异常
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exceptionAsString()}');
  };

  // 异步初始化后启动
  _initAndRun();
}

/// 初始化并启动App
Future<void> _initAndRun() async {
  bool initSuccess = true;
  String? errorMsg;

  try {
    // 1. 初始化SharedPreferences
    await StorageUtil.init();
  } catch (e) {
    initSuccess = false;
    errorMsg = 'SharedPreferences初始化失败: $e';
    debugPrint(errorMsg);
  }

  try {
    // 2. 初始化SQLite数据库
    await StorageUtil.initDatabase();
  } catch (e) {
    initSuccess = false;
    errorMsg = '数据库初始化失败: $e';
    debugPrint(errorMsg);
  }

  // 即使初始化部分失败也要启动App，显示错误信息
  runApp(ProviderScope(
    child: KouboApp(initError: initSuccess ? null : errorMsg),
  ));
}
