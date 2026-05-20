import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'utils/storage_util.dart';

/// App入口 - 初始化并启动应用
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  _initAndRun();
}

Future<void> _initAndRun() async {
  String? errorMsg;

  try {
    await StorageUtil.init();
  } catch (e) {
    errorMsg = '存储初始化失败: $e';
    debugPrint(errorMsg);
  }

  try {
    await StorageUtil.initDatabase();
  } catch (e) {
    errorMsg = '数据库初始化失败: $e';
    debugPrint(errorMsg);
  }

  // 无论是否初始化成功，都启动App
  runApp(ProviderScope(
    child: KouboApp(initError: errorMsg),
  ));
}
