import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/session.dart';

abstract class HistoryFileStorage {
  Future<String?> read();
  Future<void> write(String contents);
}

class LocalHistoryFileStorage implements HistoryFileStorage {
  static const _fileName = 'history.json';

  @override
  Future<String?> read() async {
    final file = await _file();
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  @override
  Future<void> write(String contents) async {
    final file = await _file();
    await file.writeAsString(contents);
  }

  Future<File> _file() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_fileName');
  }
}

class HistoryRepository {
  HistoryRepository({HistoryFileStorage? storage})
      : _storage = storage ?? LocalHistoryFileStorage();

  final HistoryFileStorage _storage;
  static const _retentionWindow = Duration(days: 30);

  Future<List<ExplanationSession>> loadAll() async {
    final all = await _readAll();
    final cutoff = DateTime.now().subtract(_retentionWindow);
    final fresh = all.where((s) => s.lastActivityAt.isAfter(cutoff)).toList()
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    if (fresh.length != all.length) {
      await _writeAll(fresh);
    }
    return fresh;
  }

  Future<void> save(ExplanationSession session) async {
    final all = await _readAll();
    final index = all.indexWhere((s) => s.id == session.id);
    if (index >= 0) {
      all[index] = session;
    } else {
      all.add(session);
    }
    await _writeAll(all);
  }

  Future<void> delete(String id) async {
    final all = await _readAll();
    all.removeWhere((s) => s.id == id);
    await _writeAll(all);
  }

  Future<List<ExplanationSession>> _readAll() async {
    final contents = await _storage.read();
    if (contents == null || contents.isEmpty) return [];
    try {
      final list = jsonDecode(contents) as List;
      return list.map((e) => ExplanationSession.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeAll(List<ExplanationSession> sessions) async {
    await _storage.write(jsonEncode(sessions.map((s) => s.toJson()).toList()));
  }
}
