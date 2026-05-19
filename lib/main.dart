import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'utils/storage_util.dart';
import 'utils/permission_util.dart';

/// App入口 - 初始化并启动应用
void main() async {
  // 确保Flutter绑定初始化
  WidgetsFlutterBinding.ensureInitialized();

  // 捕获Flutter框架异常
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exceptionAsString()}');
  };

  try {
    // 1. 初始化SharedPreferences
    await StorageUtil.init();

    // 2. 初始化SQLite数据库
    await StorageUtil.initDatabase();

    // 3. 请求必要权限（不阻塞启动）
    _requestPermissions();
  } catch (e) {
    debugPrint('初始化异常：$e');
  }

  // 启动App
  runApp(const ProviderScope(child: KouboApp()));
}

/// 请求必要权限（异步，不阻塞启动）
void _requestPermissions() {
  // 延迟请求权限，避免影响启动速度
  Future.delayed(const Duration(seconds: 2), () async {
    await PermissionUtil.requestStorage();
  });
}
