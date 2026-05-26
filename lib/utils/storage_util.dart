import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

/// 本地存储工具 - 统一管理本地存储操作
/// 包含：安全存储（API Key）、SharedPreferences（轻量配置）、SQLite数据库（历史记录）、文件目录管理
class StorageUtil {
  StorageUtil._();

  // 安全存储实例（用于加密存储API Key等敏感信息）
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: false),
  );

  // SharedPreferences实例（缓存）
  static SharedPreferences? _prefs;

  // SQLite数据库实例
  static Database? _database;

  // 数据库名称
  static const String _dbName = 'koubo_app.db';

  // 数据库版本
  static const int _dbVersion = 1;

  /// 初始化SharedPreferences
  static Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  /// 初始化数据库
  static Future<void> initDatabase() async {
    final dbPath = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dbPath, _dbName),
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// 获取数据库实例
  static Database get _ensureDb {
    if (_database == null) {
      throw Exception('数据库未初始化，请先调用StorageUtil.initDatabase()');
    }
    return _database!;
  }

  /// 确保Prefs已初始化
  static SharedPreferences get _ensurePrefs {
    if (_prefs == null) {
      throw Exception('StorageUtil未初始化，请先调用StorageUtil.init()');
    }
    return _prefs!;
  }

  // ==================== 数据库建表 ====================

  /// 数据库创建时执行 - 建表
  static Future<void> _onCreate(Database db, int version) async {
    // 文案记录表
    await db.execute('''
      CREATE TABLE scripts (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_url TEXT,
        source_text TEXT NOT NULL,
        rewritten_text TEXT,
        rewrite_mode TEXT,
        rewrite_style TEXT,
        model_name TEXT,
        risk_level TEXT,
        platform TEXT,
        word_count INTEGER DEFAULT 0,
        audit_status TEXT DEFAULT '未审核',
        created_at TEXT NOT NULL,
        updated_at TEXT
      )
    ''');

    // 改写版本表
    await db.execute('''
      CREATE TABLE rewrite_versions (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_id INTEGER NOT NULL,
        version_number INTEGER DEFAULT 1,
        rewritten_text TEXT NOT NULL,
        content TEXT,
        mode TEXT,
        style TEXT,
        similarity_score REAL,
        quality_score REAL,
        score INTEGER DEFAULT 0,
        score_details TEXT,
        similarity REAL,
        is_selected INTEGER DEFAULT 0,
        selected INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
      )
    ''');

    // 审核记录表
    await db.execute('''
      CREATE TABLE audit_records (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_id INTEGER NOT NULL,
        overall_risk TEXT,
        ad_law_risk TEXT,
        sensitive_risk TEXT,
        platform_risk TEXT,
        copyright_risk TEXT,
        fraud_risk TEXT,
        fixed INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE CASCADE
      )
    ''');

    // 克隆音色表
    await db.execute('''
      CREATE TABLE voice_clones (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        voice_id TEXT NOT NULL,
        sample_path TEXT,
        duration REAL DEFAULT 0,
        created_at TEXT NOT NULL
      )
    ''');

    // 音频文件表
    await db.execute('''
      CREATE TABLE audio_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_id INTEGER,
        voice_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        duration REAL DEFAULT 0,
        file_size INTEGER DEFAULT 0,
        created_at TEXT NOT NULL,
        FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE SET NULL
      )
    ''');

    // 视频文件表
    await db.execute('''
      CREATE TABLE video_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        script_id INTEGER,
        audio_id INTEGER,
        avatar_name TEXT NOT NULL,
        file_path TEXT NOT NULL,
        duration REAL DEFAULT 0,
        file_size INTEGER DEFAULT 0,
        resolution TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY (script_id) REFERENCES scripts(id) ON DELETE SET NULL,
        FOREIGN KEY (audio_id) REFERENCES audio_files(id) ON DELETE SET NULL
      )
    ''');

    // 自定义敏感词表
    await db.execute('''
      CREATE TABLE custom_words (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        word TEXT NOT NULL UNIQUE,
        category TEXT NOT NULL,
        created_at TEXT NOT NULL
      )
    ''');
  }

  /// 数据库升级
  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // 后续版本升级时添加迁移逻辑
  }

  // ==================== 安全存储（加密） ====================

  /// 安全存储 - 保存加密数据
  static Future<void> setSecure(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  /// 安全存储 - 读取加密数据
  static Future<String?> getSecure(String key) async {
    return await _secureStorage.read(key: key);
  }

  /// 安全存储 - 删除加密数据
  static Future<void> deleteSecure(String key) async {
    await _secureStorage.delete(key: key);
  }

  /// 安全存储 - 保存所有API Key
  static Future<void> saveApiKeys(Map<String, String> keys) async {
    for (final entry in keys.entries) {
      if (entry.value.isNotEmpty) {
        await _secureStorage.write(key: entry.key, value: entry.value);
      } else {
        // 空值则删除该Key
        await _secureStorage.delete(key: entry.key);
      }
    }
  }

  /// 安全存储 - 获取所有API Key
  static Future<Map<String, String>> getAllApiKeys(List<String> keyNames) async {
    final result = <String, String>{};
    for (final key in keyNames) {
      final value = await _secureStorage.read(key: key);
      if (value != null && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }

  /// 检查是否已配置任何API Key
  static Future<bool> hasAnyApiKey() async {
    final keys = await getAllApiKeys([
      'zhipu_api_key',
      'siliconflow_api_key',
      'ali_bailian_api_key',
      'hifly_agent_token',
    ]);
    return keys.isNotEmpty;
  }

  // ==================== SharedPreferences（轻量配置） ====================

  /// 保存字符串
  static Future<bool> setString(String key, String value) async {
    return _ensurePrefs.setString(key, value);
  }

  /// 读取字符串
  static String? getString(String key) {
    return _ensurePrefs.getString(key);
  }

  /// 保存布尔值
  static Future<bool> setBool(String key, bool value) async {
    return _ensurePrefs.setBool(key, value);
  }

  /// 读取布尔值
  static bool? getBool(String key) {
    return _ensurePrefs.getBool(key);
  }

  /// 保存整数
  static Future<bool> setInt(String key, int value) async {
    return _ensurePrefs.setInt(key, value);
  }

  /// 读取整数
  static int? getInt(String key) {
    return _ensurePrefs.getInt(key);
  }

  /// 删除指定key
  static Future<bool> remove(String key) async {
    return _ensurePrefs.remove(key);
  }

  /// 清空所有数据
  static Future<bool> clear() async {
    return _ensurePrefs.clear();
  }

  // ==================== 模型偏好配置 ====================

  /// 获取改写模型偏好
  static String getRewriteModel() {
    return getString('rewrite_model') ?? 'GLM-4-Flash';
  }

  /// 保存改写模型偏好
  static Future<bool> setRewriteModel(String model) {
    return setString('rewrite_model', model);
  }

  /// 获取审核模型偏好
  static String getAuditModel() {
    return getString('audit_model') ?? 'qwen-plus';
  }

  /// 保存审核模型偏好
  static Future<bool> setAuditModel(String model) {
    return setString('audit_model', model);
  }

  /// 获取TTS引擎偏好
  static String getTtsEngine() {
    return getString('tts_engine') ?? 'Edge-TTS';
  }

  /// 保存TTS引擎偏好
  static Future<bool> setTtsEngine(String engine) {
    return setString('tts_engine', engine);
  }

  // ==================== 文案记录 CRUD ====================

  /// 新增文案记录
  static Future<int> insertScript(Map<String, dynamic> script) async {
    script['created_at'] ??= DateTime.now().toIso8601String();
    script['word_count'] ??= (script['source_text'] as String?)?.length ?? 0;
    return await _ensureDb.insert('scripts', script);
  }

  /// 查询所有文案记录（按时间倒序）
  static Future<List<Map<String, dynamic>>> getAllScripts({int? limit, int? offset}) async {
    final results = await _ensureDb.query(
      'scripts',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
    return results;
  }

  /// 按ID查询文案记录
  static Future<Map<String, dynamic>?> getScriptById(int id) async {
    final results = await _ensureDb.query(
      'scripts',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 搜索文案记录（按内容关键词搜索）
  static Future<List<Map<String, dynamic>>> searchScripts(String keyword) async {
    return await _ensureDb.query(
      'scripts',
      where: 'source_text LIKE ? OR rewritten_text LIKE ?',
      whereArgs: ['%$keyword%', '%$keyword%'],
      orderBy: 'created_at DESC',
    );
  }

  /// 更新文案记录
  static Future<int> updateScript(int id, Map<String, dynamic> values) async {
    values['updated_at'] = DateTime.now().toIso8601String();
    return await _ensureDb.update(
      'scripts',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 删除文案记录
  static Future<int> deleteScript(int id) async {
    return await _ensureDb.delete(
      'scripts',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量删除文案记录
  static Future<void> deleteScripts(List<int> ids) async {
    await _ensureDb.transaction((txn) async {
      for (final id in ids) {
        await txn.delete('scripts', where: 'id = ?', whereArgs: [id]);
      }
    });
  }

  /// 获取文案记录数量
  static Future<int> getScriptCount() async {
    final result = await _ensureDb.rawQuery('SELECT COUNT(*) as count FROM scripts');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 清空所有文案记录
  static Future<int> deleteAllScripts() async {
    return await _ensureDb.delete('scripts');
  }

  // ==================== 改写版本 CRUD ====================

  /// 新增改写版本
  static Future<int> insertRewriteVersion(Map<String, dynamic> version) async {
    version['created_at'] ??= DateTime.now().toIso8601String();
    return await _ensureDb.insert('rewrite_versions', version);
  }

  /// 查询指定文案的改写版本
  static Future<List<Map<String, dynamic>>> getRewriteVersions(int scriptId) async {
    return await _ensureDb.query(
      'rewrite_versions',
      where: 'script_id = ?',
      whereArgs: [scriptId],
      orderBy: 'version_number ASC',
    );
  }

  /// 删除指定文案的改写版本
  static Future<int> deleteRewriteVersions(int scriptId) async {
    return await _ensureDb.delete(
      'rewrite_versions',
      where: 'script_id = ?',
      whereArgs: [scriptId],
    );
  }

  // ==================== 审核记录 CRUD ====================

  /// 新增审核记录
  static Future<int> insertAuditRecord(Map<String, dynamic> record) async {
    record['created_at'] ??= DateTime.now().toIso8601String();
    return await _ensureDb.insert('audit_records', record);
  }

  /// 查询指定文案的审核记录
  static Future<List<Map<String, dynamic>>> getAuditRecords(int scriptId) async {
    return await _ensureDb.query(
      'audit_records',
      where: 'script_id = ?',
      whereArgs: [scriptId],
      orderBy: 'created_at DESC',
    );
  }

  // ==================== 音频文件 CRUD ====================

  /// 新增音频文件记录
  static Future<int> insertAudioFile(Map<String, dynamic> audio) async {
    audio['created_at'] ??= DateTime.now().toIso8601String();
    return await _ensureDb.insert('audio_files', audio);
  }

  /// 查询所有音频文件（按时间倒序）
  static Future<List<Map<String, dynamic>>> getAllAudioFiles({int? limit, int? offset}) async {
    return await _ensureDb.query(
      'audio_files',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 按ID查询音频文件
  static Future<Map<String, dynamic>?> getAudioFileById(int id) async {
    final results = await _ensureDb.query(
      'audio_files',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 删除音频文件记录
  static Future<int> deleteAudioFile(int id) async {
    // 先获取文件路径，删除实际文件
    final audio = await getAudioFileById(id);
    if (audio != null) {
      final filePath = audio['file_path'] as String?;
      if (filePath != null && File(filePath).existsSync()) {
        await File(filePath).delete();
      }
    }
    return await _ensureDb.delete(
      'audio_files',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量删除音频文件
  static Future<void> deleteAudioFiles(List<int> ids) async {
    for (final id in ids) {
      await deleteAudioFile(id);
    }
  }

  /// 获取音频文件数量
  static Future<int> getAudioFileCount() async {
    final result = await _ensureDb.rawQuery('SELECT COUNT(*) as count FROM audio_files');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 清空所有音频文件记录
  static Future<int> deleteAllAudioFiles() async {
    // 删除实际文件
    final audios = await getAllAudioFiles();
    for (final audio in audios) {
      final filePath = audio['file_path'] as String?;
      if (filePath != null && File(filePath).existsSync()) {
        await File(filePath).delete();
      }
    }
    return await _ensureDb.delete('audio_files');
  }

  // ==================== 视频文件 CRUD ====================

  /// 新增视频文件记录
  static Future<int> insertVideoFile(Map<String, dynamic> video) async {
    video['created_at'] ??= DateTime.now().toIso8601String();
    return await _ensureDb.insert('video_files', video);
  }

  /// 查询所有视频文件（按时间倒序）
  static Future<List<Map<String, dynamic>>> getAllVideoFiles({int? limit, int? offset}) async {
    return await _ensureDb.query(
      'video_files',
      orderBy: 'created_at DESC',
      limit: limit,
      offset: offset,
    );
  }

  /// 按ID查询视频文件
  static Future<Map<String, dynamic>?> getVideoFileById(int id) async {
    final results = await _ensureDb.query(
      'video_files',
      where: 'id = ?',
      whereArgs: [id],
    );
    return results.isNotEmpty ? results.first : null;
  }

  /// 删除视频文件记录
  static Future<int> deleteVideoFile(int id) async {
    // 先获取文件路径，删除实际文件
    final video = await getVideoFileById(id);
    if (video != null) {
      final filePath = video['file_path'] as String?;
      if (filePath != null && File(filePath).existsSync()) {
        await File(filePath).delete();
      }
    }
    return await _ensureDb.delete(
      'video_files',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 批量删除视频文件
  static Future<void> deleteVideoFiles(List<int> ids) async {
    for (final id in ids) {
      await deleteVideoFile(id);
    }
  }

  /// 获取视频文件数量
  static Future<int> getVideoFileCount() async {
    final result = await _ensureDb.rawQuery('SELECT COUNT(*) as count FROM video_files');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 清空所有视频文件记录
  static Future<int> deleteAllVideoFiles() async {
    // 删除实际文件
    final videos = await getAllVideoFiles();
    for (final video in videos) {
      final filePath = video['file_path'] as String?;
      if (filePath != null && File(filePath).existsSync()) {
        await File(filePath).delete();
      }
    }
    return await _ensureDb.delete('video_files');
  }

  // ==================== 自定义敏感词 CRUD ====================

  /// 新增自定义敏感词
  static Future<int> insertCustomWord(String word, {String category = '自定义'}) async {
    return await _ensureDb.insert(
      'custom_words',
      {
        'word': word,
        'category': category,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  /// 查询所有自定义敏感词
  static Future<List<Map<String, dynamic>>> getAllCustomWords() async {
    return await _ensureDb.query(
      'custom_words',
      orderBy: 'created_at DESC',
    );
  }

  /// 删除自定义敏感词
  static Future<int> deleteCustomWord(int id) async {
    return await _ensureDb.delete(
      'custom_words',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// 按词删除自定义敏感词
  static Future<int> deleteCustomWordByText(String word) async {
    return await _ensureDb.delete(
      'custom_words',
      where: 'word = ?',
      whereArgs: [word],
    );
  }

  /// 清空自定义敏感词
  static Future<int> deleteAllCustomWords() async {
    return await _ensureDb.delete('custom_words');
  }

  /// 获取自定义敏感词数量
  static Future<int> getCustomWordCount() async {
    final result = await _ensureDb.rawQuery('SELECT COUNT(*) as count FROM custom_words');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// 批量导入自定义敏感词（JSON格式）
  static Future<int> importCustomWords(List<Map<String, dynamic>> words) async {
    int count = 0;
    await _ensureDb.transaction((txn) async {
      for (final w in words) {
        final word = w['word'] as String?;
        final category = w['category'] as String? ?? '自定义';
        if (word != null && word.isNotEmpty) {
          await txn.insert(
            'custom_words',
            {
              'word': word,
              'category': category,
              'created_at': DateTime.now().toIso8601String(),
            },
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          count++;
        }
      }
    });
    return count;
  }

  /// 导出自定义敏感词为JSON格式
  static Future<List<Map<String, dynamic>>> exportCustomWords() async {
    final words = await getAllCustomWords();
    return words.map((w) => {
      'word': w['word'],
      'category': w['category'],
    }).toList();
  }

  // ==================== 最近记录（首页用） ====================

  /// 获取最近创作记录（混排文案/音频/视频，最多3条）
  static Future<List<Map<String, dynamic>>> getRecentRecords({int limit = 3}) async {
    final records = <Map<String, dynamic>>[];

    // 获取最近的文案记录
    final scripts = await _ensureDb.query(
      'scripts',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    for (final s in scripts) {
      records.add({
        'type': 'script',
        'id': s['id'],
        'title': (s['source_text'] as String?)?.substring(0, (s['source_text'] as String).length > 20 ? 20 : (s['source_text'] as String).length) ?? '',
        'time': s['created_at'],
        'status': s['audit_status'] ?? '未审核',
        'risk_level': s['risk_level'] ?? '',
      });
    }

    // 获取最近的音频记录
    final audios = await _ensureDb.query(
      'audio_files',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    for (final a in audios) {
      records.add({
        'type': 'audio',
        'id': a['id'],
        'title': a['voice_name'] ?? '音频',
        'time': a['created_at'],
        'status': '已完成',
        'duration': a['duration'] ?? 0,
      });
    }

    // 获取最近的视频记录
    final videos = await _ensureDb.query(
      'video_files',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    for (final v in videos) {
      records.add({
        'type': 'video',
        'id': v['id'],
        'title': v['avatar_name'] ?? '视频',
        'time': v['created_at'],
        'status': '已完成',
        'duration': v['duration'] ?? 0,
      });
    }

    // 按时间排序，取最新的N条
    records.sort((a, b) {
      final timeA = a['time'] as String? ?? '';
      final timeB = b['time'] as String? ?? '';
      return timeB.compareTo(timeA);
    });

    return records.take(limit).toList();
  }

  // ==================== 缓存管理 ====================

  /// 获取缓存大小统计
  static Future<Map<String, int>> getCacheStats() async {
    final stats = <String, int>{};

    // 音频文件缓存大小
    try {
      final audioDir = await getAudioDirectory();
      stats['audio'] = await getDirectorySize(audioDir);
    } catch (_) {
      stats['audio'] = 0;
    }

    // 视频文件缓存大小
    try {
      final videoDir = await getVideoDirectory();
      stats['video'] = await getDirectorySize(videoDir);
    } catch (_) {
      stats['video'] = 0;
    }

    // 临时缓存大小
    try {
      final cacheDir = await getCacheDirectory();
      stats['cache'] = await getDirectorySize(cacheDir);
    } catch (_) {
      stats['cache'] = 0;
    }

    return stats;
  }

  /// 清理指定类型的缓存
  static Future<void> clearCache(String type) async {
    switch (type) {
      case 'audio':
        final audioDir = await getAudioDirectory();
        await _clearDirectory(audioDir);
        break;
      case 'video':
        final videoDir = await getVideoDirectory();
        await _clearDirectory(videoDir);
        break;
      case 'cache':
        final cacheDir = await getCacheDirectory();
        await _clearDirectory(cacheDir);
        break;
      case 'all':
        await _clearDirectory(await getAudioDirectory());
        await _clearDirectory(await getVideoDirectory());
        await _clearDirectory(await getCacheDirectory());
        break;
    }
  }

  /// 清空目录下的所有文件
  static Future<void> _clearDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File) {
        await entity.delete();
      }
    }
  }

  /// 清除全部历史记录（数据库+文件）
  static Future<void> clearAllHistory() async {
    await deleteAllScripts();
    await deleteAllAudioFiles();
    await deleteAllVideoFiles();
  }

  // ==================== 文件目录 ====================

  /// 获取应用文档目录
  static Future<String> getAppDirectory() async {
    final directory = await getApplicationDocumentsDirectory();
    return directory.path;
  }

  /// 获取音频文件目录
  static Future<String> getAudioDirectory() async {
    final appDir = await getAppDirectory();
    final audioDir = Directory('$appDir/音频');
    if (!await audioDir.exists()) {
      await audioDir.create(recursive: true);
    }
    return audioDir.path;
  }

  /// 获取视频文件目录
  static Future<String> getVideoDirectory() async {
    final appDir = await getAppDirectory();
    final videoDir = Directory('$appDir/视频');
    if (!await videoDir.exists()) {
      await videoDir.create(recursive: true);
    }
    return videoDir.path;
  }

  /// 获取审核报告目录
  static Future<String> getReportDirectory() async {
    final appDir = await getAppDirectory();
    final reportDir = Directory('$appDir/报告');
    if (!await reportDir.exists()) {
      await reportDir.create(recursive: true);
    }
    return reportDir.path;
  }

  /// 获取缓存目录
  static Future<String> getCacheDirectory() async {
    final directory = await getTemporaryDirectory();
    return directory.path;
  }

  /// 获取目录下所有文件
  static Future<List<File>> getFilesInDirectory(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        files.add(entity);
      }
    }
    // 按修改时间倒序排列
    files.sort((a, b) {
      final aTime = a.lastAccessedSync();
      final bTime = b.lastAccessedSync();
      return bTime.compareTo(aTime);
    });
    return files;
  }

  /// 计算目录大小（字节）
  static Future<int> getDirectorySize(String directoryPath) async {
    final dir = Directory(directoryPath);
    if (!await dir.exists()) return 0;

    int totalSize = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }

  /// 格式化文件大小
  static String formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
