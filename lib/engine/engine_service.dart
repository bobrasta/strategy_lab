import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';

/// The `hummer serve` protocol this app speaks (SPEC §8.2). A different engine is refused.
const kProtocol = 1;

enum EngineStatus { stopped, starting, ready, error }

class EngineError implements Exception {
  const EngineError(this.code, this.message);
  final String code, message;
  @override
  String toString() => message;
}

/// Owns the `hummer serve` child process: JSON lines over stdin/stdout, requests by id,
/// events to [events]. No engine code runs in the app; runs and builds are the service's children.
class EngineService extends ChangeNotifier {
  EngineService({required this.binary, required this.workingDir});

  String binary, workingDir;
  EngineStatus status = EngineStatus.stopped;
  String? message;
  Map<String, dynamic> version = const {};
  Process? _p;
  int _seq = 0;
  final _pending = <int, Completer<dynamic>>{};
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final List<String> stderrTail = [];
  bool _stopping = false;

  Stream<Map<String, dynamic>> get events => _events.stream;
  bool get ready => status == EngineStatus.ready;
  int? get pid => _p?.pid;
  String get runsDir => '${version['runs_dir'] ?? ''}';

  void _set(EngineStatus s, [String? msg]) {
    status = s;
    message = msg;
    notifyListeners();
  }

  /// Starts the service and waits for `ready` + `version` (protocol checked).
  Future<void> start() async {
    if (_p != null) return;
    _stopping = false;
    stderrTail.clear();
    _set(EngineStatus.starting, 'Starting the engine…');
    if (!await File(binary).exists()) {
      _set(EngineStatus.error, 'No engine binary at $binary. Use Build engine, or set the path in the engine settings.');
      return;
    }
    final ready = Completer<Map<String, dynamic>>();
    try {
      final p = await Process.start(binary, ['serve'], workingDirectory: workingDir);
      _p = p;
      p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((line) => _onLine(line, ready));
      p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen((l) {
        stderrTail.add(l);
        if (stderrTail.length > 200) stderrTail.removeAt(0);
      });
      p.exitCode.then((code) => _onExit(p, code, ready));
    } catch (e) {
      _p = null;
      _set(EngineStatus.error, "The engine couldn't be started: $e");
      return;
    }
    try {
      final r = await ready.future.timeout(const Duration(seconds: 10));
      if (r['protocol'] != kProtocol) {
        await shutdown();
        _set(EngineStatus.error, 'This engine speaks protocol ${r['protocol']}, but Strategy Lab needs protocol $kProtocol. '
            'Rebuild the engine or update the app.');
        return;
      }
      version = ((await request('version')) as Map).cast<String, dynamic>();
      _set(EngineStatus.ready, 'Engine ${version['engine_version']} (${version['git']}) ready · pid ${version['pid']}');
    } on TimeoutException {
      await _kill();
      _set(EngineStatus.error, "The engine didn't report ready within 10 s.");
    } catch (e) {
      if (status != EngineStatus.error) _set(EngineStatus.error, 'Engine start failed: $e');
    }
  }

  void _onLine(String line, Completer<Map<String, dynamic>> ready) {
    Map<String, dynamic> m;
    try {
      final j = jsonDecode(line);
      if (j is! Map) return;
      m = j.cast<String, dynamic>();
    } catch (_) {
      return; // stdout carries only JSON; anything else is ignored
    }
    final id = m['id'];
    if (id is int && _pending.containsKey(id)) {
      final c = _pending.remove(id)!;
      final err = m['error'];
      if (err is Map) {
        c.completeError(EngineError('${err['code']}', '${err['message']}'));
      } else {
        c.complete(m['result']);
      }
      return;
    }
    if (m['event'] == 'ready' && !ready.isCompleted) ready.complete(m);
    if (m['event'] is String) _events.add(m);
  }

  void _onExit(Process p, int code, Completer<Map<String, dynamic>> ready) {
    if (!identical(_p, p)) return;
    _p = null;
    for (final c in _pending.values) {
      c.completeError(const EngineError('engine_exited', 'The engine stopped.'));
    }
    _pending.clear();
    if (!ready.isCompleted) ready.completeError(EngineError('engine_exited', 'The engine exited with code $code before it was ready.'));
    if (_stopping) {
      _set(EngineStatus.stopped, 'Engine stopped.');
    } else {
      final tail = stderrTail.isEmpty ? '' : ' Last output: ${stderrTail.last}';
      _set(EngineStatus.error, 'The engine stopped unexpectedly (${code < 0 ? 'signal ${-code}' : 'exit code $code'}).$tail');
    }
    _events.add({'event': 'engine_exited', 'code': code});
  }

  Future<dynamic> request(String method, [Map<String, dynamic>? params]) {
    final p = _p;
    if (p == null) return Future.error(const EngineError('not_running', 'The engine is not running.'));
    final id = ++_seq;
    final c = Completer<dynamic>();
    _pending[id] = c;
    p.stdin.writeln(jsonEncode({'id': id, 'method': method, 'params': params ?? const {}}));
    return c.future;
  }

  /// `shutdown`, then up to [wait] for a clean exit, then SIGKILL. The service's workers
  /// die with it (their parent-death signal), so nothing outlives the app.
  Future<void> shutdown({Duration wait = const Duration(seconds: 2)}) async {
    final p = _p;
    if (p == null) return;
    _stopping = true;
    try {
      unawaited(request('shutdown').catchError((_) => null));
      await p.stdin.close();
    } catch (_) {}
    try {
      await p.exitCode.timeout(wait);
    } on TimeoutException {
      await _kill();
    }
  }

  Future<void> _kill() async {
    final p = _p;
    if (p == null) return;
    _stopping = true;
    p.kill(ProcessSignal.sigkill);
    await p.exitCode.timeout(const Duration(seconds: 2), onTimeout: () => -9);
  }

  Future<void> restart() async {
    await shutdown();
    await start();
  }

  @override
  void dispose() {
    _p?.kill(ProcessSignal.sigkill);
    _events.close();
    super.dispose();
  }
}

/// Whether the engine binary is missing or older than its sources (SPEC §14, M6 lifecycle).
class EngineFreshness {
  const EngineFreshness(this.missing, this.newerSource);
  final bool missing;
  final String? newerSource;
  bool get needsBuild => missing || newerSource != null;
}

Future<EngineFreshness> checkEngineFreshness(String repo, String binary) => Isolate.run(() {
      final bin = File(binary);
      if (!bin.existsSync()) return const EngineFreshness(true, null);
      final t = bin.lastModifiedSync();
      String? newer;
      void visit(FileSystemEntity e) {
        if (newer != null) return;
        if (e is File && e.lastModifiedSync().isAfter(t)) newer = e.path;
        if (e is Directory) {
          for (final c in e.listSync(followLinks: false)) {
            visit(c);
          }
        }
      }

      for (final p in ['engine', 'cli', 'sdk', 'CMakeLists.txt']) {
        final path = '$repo${Platform.pathSeparator}$p';
        final type = FileSystemEntity.typeSync(path);
        if (type == FileSystemEntityType.directory) visit(Directory(path));
        if (type == FileSystemEntityType.file) visit(File(path));
      }
      return EngineFreshness(false, newer);
    });

/// `cmake --preset release && cmake --build --preset release`, streamed line by line.
class EngineBuild {
  EngineBuild._(this._p);
  final Process _p;
  final lines = <String>[];

  static Future<EngineBuild> start(String repo, void Function(String line) onLine) async {
    final p = await Process.start('bash', ['-c', 'cmake --preset release && cmake --build --preset release'], workingDirectory: repo);
    final b = EngineBuild._(p);
    void add(String l) {
      b.lines.add(l);
      onLine(l);
    }

    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen(add);
    p.stderr.transform(utf8.decoder).transform(const LineSplitter()).listen(add);
    return b;
  }

  Future<int> get exitCode => _p.exitCode;
  void kill() => _p.kill(ProcessSignal.sigkill);
}
