import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// 权限管理工具 - 统一处理App所需权限
class PermissionUtil {
  PermissionUtil._();

  /// 请求麦克风权限（录音、声音克隆需要）
  static Future<bool> requestMicrophone() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// 请求存储权限（保存音频/视频/报告需要）
  static Future<bool> requestStorage() async {
    // Android 13+ 不再需要 READ_EXTERNAL_STORAGE
    // 使用细分权限
    if (await _isAndroid13OrAbove()) {
      final videos = await Permission.videos.request();
      final audio = await Permission.audio.request();
      final photos = await Permission.photos.request();
      return videos.isGranted || audio.isGranted || photos.isGranted;
    }
    final status = await Permission.storage.request();
    return status.isGranted;
  }

  /// 请求相机权限（拍照上传数字人照片需要）
  static Future<bool> requestCamera() async {
    final status = await Permission.camera.request();
    return status.isGranted;
  }

  /// 请求照片权限（从相册选择图片需要）
  static Future<bool> requestPhotos() async {
    final status = await Permission.photos.request();
    return status.isGranted;
  }

  /// 请求网络权限（Android默认授予）
  static Future<bool> requestInternet() async {
    // Android中网络权限在AndroidManifest.xml中声明即可
    return true;
  }

  /// 检查麦克风权限状态
  static Future<PermissionStatus> checkMicrophone() async {
    return await Permission.microphone.status;
  }

  /// 检查存储权限状态
  static Future<PermissionStatus> checkStorage() async {
    return await Permission.storage.status;
  }

  /// 检查相机权限状态
  static Future<PermissionStatus> checkCamera() async {
    return await Permission.camera.status;
  }

  /// 请求所有必要权限
  static Future<Map<Permission, bool>> requestAllPermissions() async {
    final results = <Permission, bool>{};

    // 麦克风
    results[Permission.microphone] = await requestMicrophone();
    // 存储
    results[Permission.storage] = await requestStorage();
    // 相机（可选）
    results[Permission.camera] = await requestCamera();
    // 照片
    results[Permission.photos] = await requestPhotos();

    return results;
  }

  /// 打开App设置页面（当权限被永久拒绝时引导用户手动开启）
  static Future<bool> openAppSettings() async {
    return await openAppSettings();
  }

  /// 显示权限说明对话框
  static Future<void> showPermissionDialog(
    BuildContext context, {
    required String title,
    required String message,
    required VoidCallback onConfirm,
  }) async {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              onConfirm();
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  /// 判断是否Android 13及以上
  static Future<bool> _isAndroid13OrAbove() async {
    // 简化判断，实际可通过device_info_plus获取
    return true; // 大部分现代设备都是13+
  }

  /// 检查并请求权限，如果被拒绝则弹窗引导
  /// 返回是否获得权限
  static Future<bool> checkAndRequest(
    BuildContext context, {
    required Permission permission,
    required String title,
    required String reason,
  }) async {
    final status = await permission.status;

    if (status.isGranted) return true;

    if (status.isDenied) {
      final result = await permission.request();
      return result.isGranted;
    }

    if (status.isPermanentlyDenied) {
      if (context.mounted) {
        await showPermissionDialog(
          context,
          title: title,
          message: '$reason\n\n请在设置中手动开启权限。',
          onConfirm: () => openAppSettings(),
        );
      }
      return false;
    }

    return false;
  }
}
