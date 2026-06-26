import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

class LedgerRepository {
  Future<File> importSqliteFile(String sourcePath) async {
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw ArgumentError('SQLite file does not exist: $sourcePath');
    }

    final destination = await _newLedgerFile('imported');
    await source.copy(destination.path);
    await migrateLedger(destination.path);
    return destination;
  }

  Future<File> createEmptyLedger() async {
    final file = await _newLedgerFile('blank');
    sqlite3.open(file.path).dispose();
    await migrateLedger(file.path);
    return file;
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

  Future<File> _newLedgerFile(String prefix) async {
    final root = await getApplicationDocumentsDirectory();
    final directory = Directory(p.join(root.path, 'ledgers'));
    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final timestamp = DateTime.now().toUtc().millisecondsSinceEpoch;
    return File(p.join(directory.path, '${prefix}_$timestamp.sqlite'));
  }
}
