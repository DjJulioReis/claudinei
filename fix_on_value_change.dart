import 'dart:typed_data';
import 'package:universal_ble/universal_ble.dart';

void main() {
  UniversalBle.onValueChange = (String deviceId, String characteristicId, Uint8List value) {};
}
