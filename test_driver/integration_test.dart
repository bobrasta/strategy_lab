import 'package:integration_test/integration_test_driver.dart';

/// `flutter drive --profile -d linux --driver=test_driver/integration_test.dart --target=integration_test/<file>.dart`
/// runs an integration test in profile (AOT) mode, for timings like the installed app's.
Future<void> main() => integrationDriver();
