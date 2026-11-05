/// 链路状态桥（断连检测）：universal_ble 的连接事件流直接透出。
///
/// BLE 链路断开由链路层 supervision 定时器判定（连接建立后 OS 持续监督，
/// 超时未听到对端即推送 ConnectionStatusChanged），插件转成 per-device
/// 的 true/false 流——检测不产生任何应用层流量，协议零改动。
library;

import 'package:universal_ble/universal_ble.dart';

/// [deviceId] 的连接事件：true = 已连接，false = 已断开。
Stream<bool> universalLinkEvents(String deviceId) =>
    UniversalBle.connectionStream(deviceId);
