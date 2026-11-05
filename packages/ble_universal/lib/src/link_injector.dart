// Host-side link kill for device-in-the-loop testing: drops the BLE
// connection the same way a radio-level loss would surface to the app
// (the connection stream fires false and the session enters linkLost).
// The device keeps running, so a follow-up reconnect proves the
// in-place recovery path on real hardware.
library;

import 'package:universal_ble/universal_ble.dart';

/// Disconnects [deviceId] from the host side. Safe to call on an already
/// down link (the plugin treats it as a no-op).
Future<void> forceLinkDown(String deviceId) async {
  await UniversalBle.disconnect(deviceId);
}
