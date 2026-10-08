import 'dart:async';
import 'dart:convert';
import 'dart:io';

class _Bm {
  _Bm(this.starred, this.note);
  bool starred;
  String note;
}

/// Stars + one-line notes, keyed by "formation time|dir", saved to
/// fvg_bookmarks.json next to the events file (debounced).
class BookmarkStore {
  BookmarkStore(this.path);
  final String? path;
  final Map<String, _Bm> _m = {};
  Timer? _timer;

  static Future<BookmarkStore> load(String path) async {
    final s = BookmarkStore(path);
    final f = File(path);
    if (await f.exists()) {
      try {
        final j = jsonDecode(await f.readAsString());
        if (j is Map) {
          j.forEach((k, v) {
            if (v is Map) s._m['$k'] = _Bm(v['starred'] == true, '${v['note'] ?? ''}');
          });
        }
      } catch (_) {
        // A broken bookmarks file shouldn't block loading events.
      }
    }
    return s;
  }

  bool starred(String id) => _m[id]?.starred ?? false;
  String note(String id) => _m[id]?.note ?? '';
  int get starredCount => _m.values.where((b) => b.starred).length;

  void toggleStar(String id) {
    final b = _m.putIfAbsent(id, () => _Bm(false, ''));
    b.starred = !b.starred;
    _schedule();
  }

  void setNote(String id, String text) {
    _m.putIfAbsent(id, () => _Bm(false, '')).note = text;
    _schedule();
  }

  void _schedule() {
    if (path == null) return;
    _timer?.cancel();
    _timer = Timer(const Duration(milliseconds: 500), save);
  }

  Future<void> save() async {
    final p = path;
    if (p == null) return;
    final out = <String, dynamic>{};
    _m.forEach((k, b) {
      if (b.starred || b.note.trim().isNotEmpty) out[k] = {'starred': b.starred, 'note': b.note};
    });
    await File(p).writeAsString(const JsonEncoder.withIndent('  ').convert(out));
  }
}
