import 'package:integration_test/integration_test_driver.dart';

/// Required by `flutter drive` for web integration tests - the driver
/// process that pumps results out of the browser-hosted test back to the
/// CLI. See integration_test/staff_leave_flow_test.dart for the actual test.
Future<void> main() => integrationDriver();
