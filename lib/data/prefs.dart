import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Remembers the last folder used in a file dialog, in the app support folder.
/// Failures are ignored: it's a convenience, never a reason to block loading.
class Prefs {
  Prefs._();

  static Future<File> _file() async => File('${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}prefs.json');

  static Future<String?> lastDir() async {
    try {
      final f = await _file();
      if (!await f.exists()) return null;
      final j = jsonDecode(await f.readAsString());
      final d = j is Map ? j['last_dir'] : null;
      return d is String && await Directory(d).exists() ? d : null;
    } catch (_) {
      return null;
    }
  }

  static Future<void> setLastDir(String dir) async {
    try {
      final f = await _file();
      await f.parent.create(recursive: true);
      await f.writeAsString(jsonEncode({'last_dir': dir}));
    } catch (_) {
      // Not worth interrupting the user over.
    }
  }
}
