import 'dart:io';
import 'dart:isolate';

import 'run_data.dart';

/// Past runs in the runs folder (directories with a run.json), newest first.
/// A directory without run.json (a stopped or crashed run) is skipped. Runs inside an isolate.
Future<List<RunManifest>> scanRuns(String runsDir) => Isolate.run(() {
      final d = Directory(runsDir);
      if (!d.existsSync()) return <RunManifest>[];
      final out = <RunManifest>[];
      for (final e in d.listSync(followLinks: false)) {
        if (e is! Directory || !File(joinPath(e.path, 'run.json')).existsSync()) continue;
        try {
          out.add(readManifest(e.path));
        } on RunLoadError {
          // unreadable run.json: not listed
        }
      }
      out.sort((a, b) => b.modifiedMs.compareTo(a.modifiedMs));
      return out;
    });
