import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// scripts/check_repo.sh (also the pre-commit hook): no run outputs, build trees, market data or
/// equity CSVs in the git index, and .gitignore keeps ignoring them. The engine repo's
/// python/tests/test_check_repo.py tests the same script against each forbidden kind of file.
void main() {
  final inRepo = Directory('.git').existsSync();
  test('the git index holds no run outputs, build trees, market data or equity files', () {
    final r = Process.runSync('scripts/check_repo.sh', []);
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
  }, skip: inRepo ? null : 'not a git checkout');
}
