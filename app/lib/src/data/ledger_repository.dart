import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import '../importer/suishouji_backup_recovery.dart';

class LedgerRepository {
  static const int maxLedgerNameLength = 40;

  Future<LedgerStoreState> loadStoreState() async {
    final store = await _readStore();
    return LedgerStoreState(
      ledgers: store.ledgers,
      lastLedgerId: store.lastLedgerId,
    );
  }

  Future<LedgerInfo?> loadLastLedger() async {
    final store = await _readStore();
    final lastLedgerId = store.lastLedgerId;
    if (lastLedgerId == null) {
      return null;
    }

    for (final ledger in store.ledgers) {
      if (ledger.id == lastLedgerId && File(ledger.path).existsSync()) {
        return ledger;
      }
    }

    return null;
  }

  Future<File> importSqliteFile({
    required String name,
    required String sourcePath,
  }) async {
    await _ensureNameAvailable(name);
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw ArgumentError('SQLite file does not exist: $sourcePath');
    }

    final destination = await _newLedgerFile();
    await source.copy(destination.path);
    await migrateLedger(destination.path);
    await _registerLedger(
      name: name,
      path: destination.path,
      sourceKind: LedgerSourceKind.sqlite,
    );
    return destination;
  }

  Future<File> importKbfFile({
    required String name,
    required String sourcePath,
  }) async {
    await _ensureNameAvailable(name);
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw ArgumentError('KBF file does not exist: $sourcePath');
    }

    final recovered = SuiShouJiBackupRecovery().recoverSqlite(
      await source.readAsBytes(),
    );
    final destination = await _newLedgerFile();
    await destination.writeAsBytes(recovered, flush: true);
    await migrateLedger(destination.path);
    await _registerLedger(
      name: name,
      path: destination.path,
      sourceKind: LedgerSourceKind.kbf,
    );
    return destination;
  }

  Future<File> createEmptyLedger({required String name}) async {
    await _ensureNameAvailable(name);
    final file = await _newLedgerFile();
    sqlite3.open(file.path).dispose();
    await migrateLedger(file.path);
    await _registerLedger(
      name: name,
      path: file.path,
      sourceKind: LedgerSourceKind.blank,
    );
    return file;
  }

  Future<void> setLastLedger(String ledgerId) async {
    final store = await _readStore();
    final exists = store.ledgers.any((ledger) => ledger.id == ledgerId);
    if (!exists) {
      throw ArgumentError('Ledger does not exist: $ledgerId');
    }
    await _writeStore(store.copyWith(lastLedgerId: ledgerId));
  }

  Future<void> migrateLedger(String databasePath) async {
    final db = sqlite3.open(databasePath);
    try {
      db.execute('pragma foreign_keys = on');
      db.execute('''
        create table if not exists app_schema_migrations (
          version integer primary key,
          applied_at text not null
        )
      ''');
      db.execute('''
        create table if not exists app_ledger_metadata (
          key text primary key,
          value text not null
        )
      ''');
      db.execute('''
        create table if not exists app_transaction_extensions (
          transaction_id text primary key,
          currency_code text not null default 'CNY',
          encrypted_note integer not null default 0
        )
      ''');
      db.execute('''
        create table if not exists app_attachment_metadata (
          id text primary key,
          transaction_id text,
          file_path text not null,
          mime_type text,
          created_at text not null
        )
      ''');

      final now = DateTime.now().toUtc().toIso8601String();
      final insertMigration = db.prepare(
        'insert or ignore into app_schema_migrations(version, applied_at) values (?, ?)',
      );
      final upsertMetadata = db.prepare(
        'insert into app_ledger_metadata(key, value) values (?, ?) on conflict(key) do update set value = excluded.value',
      );
      try {
        insertMigration.execute([1, now]);
        upsertMetadata
          ..execute(['app_schema_version', '1'])
          ..execute(['last_migrated_at', now]);
      } finally {
        insertMigration.dispose();
        upsertMetadata.dispose();
      }

      db.execute('pragma user_version = 1');
    } finally {
      db.dispose();
    }
  }

  Future<File> _newLedgerFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'ledgers'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return File(p.join(directory.path, 'ledger_$timestamp.sqlite'));
  }

  Future<File> _storeFile() async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'ledgers'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }
    return File(p.join(directory.path, 'ledger_store.json'));
  }

  Future<void> _ensureNameAvailable(String name) async {
    validateLedgerName(name);
    final store = await _readStore();
    final normalized = normalizeLedgerName(name);
    final duplicate = store.ledgers.any(
      (ledger) => normalizeLedgerName(ledger.name) == normalized,
    );
    if (duplicate) {
      throw ArgumentError('账本名称已存在');
    }
  }

  Future<LedgerInfo> _registerLedger({
    required String name,
    required String path,
    required LedgerSourceKind sourceKind,
  }) async {
    final store = await _readStore();
    final now = DateTime.now().toUtc();
    final ledger = LedgerInfo(
      id: 'ledger_${now.microsecondsSinceEpoch}',
      name: name.trim(),
      path: path,
      sourceKind: sourceKind,
      createdAt: now,
    );
    await _writeStore(
      store.copyWith(
        ledgers: [...store.ledgers, ledger],
        lastLedgerId: ledger.id,
      ),
    );
    return ledger;
  }

  Future<_LedgerStore> _readStore() async {
    final file = await _storeFile();
    if (!file.existsSync()) {
      return const _LedgerStore(ledgers: [], lastLedgerId: null);
    }

    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, Object?>) {
        return const _LedgerStore(ledgers: [], lastLedgerId: null);
      }
      final ledgersJson = json['ledgers'];
      return _LedgerStore(
        ledgers: [
          if (ledgersJson is List)
            for (final item in ledgersJson)
              if (item is Map<String, Object?>) LedgerInfo.fromJson(item),
        ],
        lastLedgerId: json['lastLedgerId'] as String?,
      );
    } on FormatException {
      return const _LedgerStore(ledgers: [], lastLedgerId: null);
    }
  }

  Future<void> _writeStore(_LedgerStore store) async {
    final file = await _storeFile();
    await file.writeAsString(jsonEncode(store.toJson()), flush: true);
  }
}

String normalizeLedgerName(String name) => name.trim().toLowerCase();

void validateLedgerName(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError('账本名称不能为空');
  }
  if (trimmed.length > LedgerRepository.maxLedgerNameLength) {
    throw ArgumentError('账本名称不能超过 ${LedgerRepository.maxLedgerNameLength} 个字符');
  }
  if (RegExp(r'[\\/:*?"<>|]').hasMatch(trimmed)) {
    throw ArgumentError('账本名称不能包含 \\ / : * ? " < > |');
  }
}

class LedgerStoreState {
  const LedgerStoreState({required this.ledgers, required this.lastLedgerId});

  final List<LedgerInfo> ledgers;
  final String? lastLedgerId;
}

class LedgerInfo {
  const LedgerInfo({
    required this.id,
    required this.name,
    required this.path,
    required this.sourceKind,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String path;
  final LedgerSourceKind sourceKind;
  final DateTime createdAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'sourceKind': sourceKind.name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory LedgerInfo.fromJson(Map<String, Object?> json) {
    return LedgerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      sourceKind: LedgerSourceKind.values.byName(json['sourceKind'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

enum LedgerSourceKind {
  blank,
  sqlite,
  kbf;

  String get label {
    return switch (this) {
      LedgerSourceKind.blank => '空白账本',
      LedgerSourceKind.sqlite => 'SQLite 导入',
      LedgerSourceKind.kbf => 'KBF 导入',
    };
  }
}

class _LedgerStore {
  const _LedgerStore({required this.ledgers, required this.lastLedgerId});

  final List<LedgerInfo> ledgers;
  final String? lastLedgerId;

  _LedgerStore copyWith({List<LedgerInfo>? ledgers, String? lastLedgerId}) {
    return _LedgerStore(
      ledgers: ledgers ?? this.ledgers,
      lastLedgerId: lastLedgerId ?? this.lastLedgerId,
    );
  }

  Map<String, Object?> toJson() => {
    'ledgers': [for (final ledger in ledgers) ledger.toJson()],
    'lastLedgerId': lastLedgerId,
  };
}
