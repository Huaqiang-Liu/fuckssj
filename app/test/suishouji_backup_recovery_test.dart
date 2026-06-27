import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fuckssj/src/importer/suishouji_backup_recovery.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('recovers mymoney.sqlite from a synthetic kbf zip', () {
    final original = _createSqliteBytes();
    final modified = Uint8List.fromList(original);
    modified.fillRange(0, SuiShouJiBackupRecovery.sqliteHeader.length, 0);

    final archive = Archive()
      ..addFile(ArchiveFile.string('backup_info', 'test'))
      ..addFile(ArchiveFile.bytes('nested/mymoney.sqlite', modified));
    final kbfBytes = Uint8List.fromList(ZipEncoder().encode(archive));

    final recovered = SuiShouJiBackupRecovery().recoverSqlite(kbfBytes);

    expect(recovered, original);
  });

  test(
    'recovers local kbf to the same bytes as recovered sqlite when present',
    () {
      final repoRoot = Directory.current.parent;
      final recovered = File(
        '${repoRoot.path}${Platform.pathSeparator}recovered${Platform.pathSeparator}mymoney.sqlite',
      );
      final backups = repoRoot
          .listSync()
          .whereType<File>()
          .where((file) => file.path.toLowerCase().endsWith('.kbf'))
          .toList();

      if (!recovered.existsSync() || backups.isEmpty) {
        markTestSkipped('本地没有同时提供 .kbf 和 recovered/mymoney.sqlite');
        return;
      }

      final recoveredFromKbf = SuiShouJiBackupRecovery().recoverSqlite(
        backups.first.readAsBytesSync(),
      );

      expect(recoveredFromKbf, recovered.readAsBytesSync());
    },
  );
}

Uint8List _createSqliteBytes() {
  final tempDir = Directory.systemTemp.createTempSync('fuckssj_recovery_test_');
  final file = File('${tempDir.path}${Platform.pathSeparator}sample.sqlite');
  final db = sqlite3.open(file.path);
  try {
    db
      ..execute('create table sample (id integer primary key, name text)')
      ..execute("insert into sample(name) values ('ok')");
  } finally {
    db.dispose();
  }

  try {
    return file.readAsBytesSync();
  } finally {
    tempDir.deleteSync(recursive: true);
  }
}
