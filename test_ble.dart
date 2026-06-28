import 'dart:typed_data';

enum BleConnectionState { connected, disconnected }

abstract class UniversalBle {
  static void Function(String, BleConnectionState)? onConnectionChange;
}

void main() {
  UniversalBle.onConnectionChange = (String deviceId, BleConnectionState state) {};
}
