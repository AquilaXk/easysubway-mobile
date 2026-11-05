import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

const bundledDatapackAssetPath = 'assets/datapacks/nationwide.sqlite.gz';

T openBundledDatapack<T>(
  T Function(Database db) action, {
  String packAssetPath = bundledDatapackAssetPath,
  OpenMode mode = OpenMode.readOnly,
}) {
  final workDir = Directory.systemTemp.createTempSync('bundled-datapack-');
  try {
    final pack = File('${workDir.path}/pack.sqlite')
      ..writeAsBytesSync(gzip.decode(File(packAssetPath).readAsBytesSync()));
    final db = sqlite3.open(pack.path, mode: mode);
    try {
      return action(db);
    } finally {
      db.close();
    }
  } finally {
    workDir.deleteSync(recursive: true);
  }
}
