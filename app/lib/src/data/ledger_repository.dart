import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

import 'ledger_configuration_store.dart';
import '../importer/suishouji_backup_recovery.dart';

class LedgerRepository {
  static const int maxLedgerNameLength = 40;
  final LedgerConfigurationStore _configurationStore =
      LedgerConfigurationStore();

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
        final configFile = await ensureLedgerConfiguration(ledger);
        return ledger.copyWith(configurationPath: configFile.path);
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

  Future<LedgerInfo> renameLedger({
    required String ledgerId,
    required String name,
  }) async {
    validateLedgerName(name);
    final store = await _readStore();
    final normalized = normalizeLedgerName(name);
    final duplicate = store.ledgers.any(
      (ledger) =>
          ledger.id != ledgerId &&
          normalizeLedgerName(ledger.name) == normalized,
    );
    if (duplicate) {
      throw ArgumentError('账本名称已存在');
    }

    LedgerInfo? updatedLedger;
    final ledgers = [
      for (final ledger in store.ledgers)
        if (ledger.id == ledgerId)
          updatedLedger = ledger.copyWith(name: name.trim())
        else
          ledger,
    ];
    if (updatedLedger == null) {
      throw ArgumentError('Ledger does not exist: $ledgerId');
    }
    await _writeStore(store.copyWith(ledgers: ledgers));
    return updatedLedger;
  }

  Future<LedgerInfo> updateLedgerNote({
    required String ledgerId,
    required String note,
  }) async {
    LedgerInfo? updatedLedger;
    final store = await _readStore();
    final ledgers = [
      for (final ledger in store.ledgers)
        if (ledger.id == ledgerId)
          updatedLedger = ledger.copyWith(note: note.trim())
        else
          ledger,
    ];
    if (updatedLedger == null) {
      throw ArgumentError('Ledger does not exist: $ledgerId');
    }
    await _writeStore(store.copyWith(ledgers: ledgers));
    return updatedLedger;
  }

  Future<void> deleteLedger(String ledgerId) async {
    final store = await _readStore();
    LedgerInfo? target;
    final ledgers = <LedgerInfo>[];
    for (final ledger in store.ledgers) {
      if (ledger.id == ledgerId) {
        target = ledger;
      } else {
        ledgers.add(ledger);
      }
    }
    if (target == null) {
      throw ArgumentError('Ledger does not exist: $ledgerId');
    }

    final ledgerFile = File(target.path);
    if (ledgerFile.existsSync()) {
      await ledgerFile.delete();
    }
    final configurationFile = target.configurationPath == null
        ? await _configurationStore.configurationFile(target.id)
        : File(target.configurationPath!);
    if (configurationFile.existsSync()) {
      await configurationFile.delete();
    }

    await _writeStore(
      _LedgerStore(
        ledgers: ledgers,
        lastLedgerId: store.lastLedgerId == ledgerId
            ? null
            : store.lastLedgerId,
      ),
    );
  }

  Future<void> exportLedger({
    required LedgerInfo ledger,
    required String destinationPath,
  }) async {
    final source = File(ledger.path);
    if (!source.existsSync()) {
      throw ArgumentError('账本文件不存在：${ledger.path}');
    }
    await source.copy(destinationPath);
  }

  Future<File> ensureLedgerConfiguration(LedgerInfo ledger) {
    return _ensureLedgerConfigurationAndExchangeRates(ledger);
  }

  Future<File> _ensureLedgerConfigurationAndExchangeRates(
    LedgerInfo ledger,
  ) async {
    return _configurationStore.ensureConfiguration(
      ledgerId: ledger.id,
      databasePath: ledger.path,
      preferDatabase: ledger.sourceKind != LedgerSourceKind.blank,
    );
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
      configurationPath: null,
      note: '',
    );
    final configurationFile = await _configurationStore.ensureConfiguration(
      ledgerId: ledger.id,
      databasePath: ledger.path,
      preferDatabase: sourceKind != LedgerSourceKind.blank,
    );
    final registeredLedger = ledger.copyWith(
      configurationPath: configurationFile.path,
    );
    await _writeStore(
      store.copyWith(
        ledgers: [...store.ledgers, registeredLedger],
        lastLedgerId: registeredLedger.id,
      ),
    );
    return registeredLedger;
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
      final ledgers = <LedgerInfo>[];
      var relocated = false;
      if (ledgersJson is List) {
        for (final item in ledgersJson) {
          if (item is Map<String, Object?>) {
            final ledger = LedgerInfo.fromJson(item);
            final relocatedLedger = await _relocateLedgerPaths(ledger);
            relocated =
                relocated ||
                relocatedLedger.path != ledger.path ||
                relocatedLedger.configurationPath != ledger.configurationPath;
            ledgers.add(relocatedLedger);
          }
        }
      }
      final store = _LedgerStore(
        ledgers: ledgers,
        lastLedgerId: json['lastLedgerId'] as String?,
      );
      if (relocated) {
        await _writeStore(store);
      }
      return _LedgerStore(
        ledgers: store.ledgers,
        lastLedgerId: store.lastLedgerId,
      );
    } on FormatException {
      return const _LedgerStore(ledgers: [], lastLedgerId: null);
    }
  }

  Future<LedgerInfo> _relocateLedgerPaths(LedgerInfo ledger) async {
    var path = ledger.path;
    if (!File(path).existsSync()) {
      final currentPath = await _ledgerFileInCurrentContainer(path);
      if (currentPath != null) {
        path = currentPath;
      }
    }

    var configurationPath = ledger.configurationPath;
    if (configurationPath != null && !File(configurationPath).existsSync()) {
      final currentConfiguration = await _configurationStore.configurationFile(
        ledger.id,
      );
      if (currentConfiguration.existsSync()) {
        configurationPath = currentConfiguration.path;
      }
    }

    if (path == ledger.path && configurationPath == ledger.configurationPath) {
      return ledger;
    }
    return ledger.copyWith(path: path, configurationPath: configurationPath);
  }

  Future<String?> _ledgerFileInCurrentContainer(String previousPath) async {
    final root = await getApplicationDocumentsDirectory();
    final currentPath = p.join(root.path, 'ledgers', p.basename(previousPath));
    return File(currentPath).existsSync() ? currentPath : null;
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
    required this.configurationPath,
    required this.note,
  });

  final String id;
  final String name;
  final String path;
  final LedgerSourceKind sourceKind;
  final DateTime createdAt;
  final String? configurationPath;
  final String note;

  LedgerInfo copyWith({
    String? name,
    String? path,
    String? configurationPath,
    String? note,
  }) {
    return LedgerInfo(
      id: id,
      name: name ?? this.name,
      path: path ?? this.path,
      sourceKind: sourceKind,
      createdAt: createdAt,
      configurationPath: configurationPath ?? this.configurationPath,
      note: note ?? this.note,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'sourceKind': sourceKind.name,
    'createdAt': createdAt.toIso8601String(),
    'configurationPath': configurationPath,
    'note': note,
  };

  factory LedgerInfo.fromJson(Map<String, Object?> json) {
    return LedgerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      path: json['path'] as String,
      sourceKind: LedgerSourceKind.values.byName(json['sourceKind'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      configurationPath: json['configurationPath'] as String?,
      note: json['note'] as String? ?? '',
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
