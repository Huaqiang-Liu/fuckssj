import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:sqlite3/sqlite3.dart';

class SuiShouJiBackupRecovery {
  static final Uint8List sqliteHeader = Uint8List.fromList(
    'SQLite format 3\u0000'.codeUnits,
  );

  Uint8List recoverSqlite(Uint8List backupBytes) {
    final candidates = _readCandidates(backupBytes);
    final ordered = _orderCandidates(candidates);

    for (final candidate in ordered) {
      final restored = _restoreSqliteHeader(candidate.data);
      if (_isReadableSqlite(restored)) {
        return restored;
      }
    }

    throw const FormatException('未在 .kbf 文件中找到可恢复的 mymoney.sqlite');
  }

  List<_RecoveryCandidate> _readCandidates(Uint8List backupBytes) {
    final candidates = <_RecoveryCandidate>[
      _RecoveryCandidate(name: 'input', data: backupBytes),
    ];

    try {
      final archive = ZipDecoder().decodeBytes(backupBytes);
      for (final file in archive.files) {
        if (!file.isFile) {
          continue;
        }
        candidates.add(
          _RecoveryCandidate(
            name: file.name,
            data: Uint8List.fromList(file.content),
          ),
        );
      }
    } on ArchiveException {
      // Keep the raw-file candidate for callers that pass a bare SQLite file.
    }

    return candidates;
  }

  List<_RecoveryCandidate> _orderCandidates(
    List<_RecoveryCandidate> candidates,
  ) {
    final mymoney = candidates.where((candidate) {
      final normalized = candidate.name.replaceAll('\\', '/');
      return normalized.split('/').last == 'mymoney.sqlite';
    }).toList();

    if (mymoney.isEmpty) {
      return candidates;
    }

    return [
      ...mymoney,
      ...candidates.where((candidate) => !mymoney.contains(candidate)),
    ];
  }

  Uint8List _restoreSqliteHeader(Uint8List data) {
    if (data.length < sqliteHeader.length) {
      return data;
    }

    final restored = Uint8List.fromList(data);
    restored.setRange(0, sqliteHeader.length, sqliteHeader);
    return restored;
  }

  bool _isReadableSqlite(Uint8List data) {
    if (data.length < sqliteHeader.length) {
      return false;
    }

    final tempDir = Directory.systemTemp.createTempSync('fuckssj_kbf_');
    final tempFile = File(
      '${tempDir.path}${Platform.pathSeparator}probe.sqlite',
    );
    Database? db;
    try {
      tempFile.writeAsBytesSync(data, flush: true);
      db = sqlite3.open(tempFile.path);
      final row = db.select('pragma integrity_check').first;
      return row.values.first == 'ok';
    } on SqliteException {
      return false;
    } finally {
      db?.dispose();
      tempDir.deleteSync(recursive: true);
    }
  }
}

class _RecoveryCandidate {
  const _RecoveryCandidate({required this.name, required this.data});

  final String name;
  final Uint8List data;
}
