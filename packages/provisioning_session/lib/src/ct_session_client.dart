/// CT-Prov 会话客户端：把已建立的 GATT 通道与传输层组装成一次配置会话
/// 的操作序列（§7 device.info.get、§11 session.close）。通道的连接、配对
/// 加密与 D2C 订阅由通道实现负责；本层只做请求/响应编排与结果形状校验。
library;

import 'package:ble_adapter/ble_adapter.dart';
import 'package:ct_prov_core/ct_prov_core.dart';

import 'capabilities.dart';
import 'session_exception.dart';

/// device.info.get 的解析结果（§7 固定字段集，形状不符即抛错）。
final class DeviceInfoResult {
  const DeviceInfoResult({
    required this.deviceName,
    required this.serialNumber,
    required this.model,
    required this.firmware,
    required this.power,
    required this.protocolVersion,
  });

  final String deviceName;
  final String serialNumber;
  final String model;
  final String firmware;
  final List<String> power;
  final int protocolVersion;

  /// 只接受 ok 响应 + 逐字段类型校验；设备是我们自己的固件，形状偏差
  /// 属于协议违例，必须显式失败而不是静默缺省。
  factory DeviceInfoResult.fromResponse(ProvResponse response) {
    if (!response.ok) {
      throw ProvSessionException(
        'device_info_error',
        '${response.error?.codeName}: ${response.error?.message}',
      );
    }
    if (response.opName != '${ProvOp.deviceInfoGet.wireName}.result') {
      throw ProvSessionException('device_info_op', response.opName);
    }
    final data = response.data;
    final deviceName = data?['device_name'];
    final serialNumber = data?['serial_number'];
    final model = data?['model'];
    final firmware = data?['firmware'];
    final power = data?['power'];
    final protocolVersion = data?['protocol_version'];
    if (deviceName is! String ||
        serialNumber is! String ||
        model is! String ||
        firmware is! String) {
      throw const ProvSessionException(
        'device_info_shape',
        'device_name/serial_number/model/firmware must be strings',
      );
    }
    if (power is! List || power.any((entry) => entry is! String)) {
      throw const ProvSessionException(
        'device_info_shape',
        'power must be an array of strings',
      );
    }
    if (protocolVersion is! int || protocolVersion != 1) {
      throw ProvSessionException(
        'device_info_version',
        'protocol_version=$protocolVersion',
      );
    }
    return DeviceInfoResult(
      deviceName: deviceName,
      serialNumber: serialNumber,
      model: model,
      firmware: firmware,
      power: List<String>.from(power),
      protocolVersion: protocolVersion,
    );
  }
}

/// F1 会话客户端：open → fetchDeviceInfo → closeSession → dispose。
/// 请求 id（信封 id）由本层分配，分片 message id 由传输层分配。
final class CtSessionClient {
  CtSessionClient(this._channel);

  final CtGattChannel _channel;
  CtProvGattTransport? _transport;
  int _nextRequestId = 1;

  /// 启动传输泵（通道应已完成连接、配对加密与 D2C 订阅）。
  Future<void> open() async {
    if (_transport != null) return;
    final transport = CtProvGattTransport(_channel);
    transport.start();
    _transport = transport;
  }

  CtProvGattTransport _requireTransport() {
    final transport = _transport;
    if (transport == null) {
      throw const ProvSessionException(
        'not_open',
        'call open() before sending requests',
      );
    }
    return transport;
  }

  /// 读取设备信息（§7）。
  Future<DeviceInfoResult> fetchDeviceInfo({
    Duration timeout = kDefaultRequestTimeout,
  }) async {
    final response = await _requireTransport().sendRequest(
      ProvRequest(
        id: _nextRequestId++,
        opName: ProvOp.deviceInfoGet.wireName,
        data: const {},
      ),
      timeout: timeout,
    );
    return DeviceInfoResult.fromResponse(response);
  }

  /// 读取配置能力（§8）：Client 必须在写入配置前完成本调用。
  Future<CapabilitiesResult> fetchCapabilities({
    Duration timeout = kDefaultRequestTimeout,
  }) async {
    final response = await _requireTransport().sendRequest(
      ProvRequest(
        id: _nextRequestId++,
        opName: ProvOp.communicationCapabilitiesGet.wireName,
        data: const {},
      ),
      timeout: timeout,
    );
    return CapabilitiesResult.fromResponse(response);
  }

  /// 结束会话（§11）：设备回 ok:true 空 data 后主动断链；链路级断开由
  /// 通道实现的 close() 完成，不在这里等待。
  Future<void> closeSession({
    Duration timeout = kDefaultRequestTimeout,
  }) async {
    final response = await _requireTransport().sendRequest(
      ProvRequest(
        id: _nextRequestId++,
        opName: ProvOp.sessionClose.wireName,
        data: const {},
      ),
      timeout: timeout,
    );
    if (!response.ok) {
      throw ProvSessionException('close_rejected', response.error?.codeName);
    }
  }

  /// 释放传输层资源。可重复调用；不触碰通道本身。
  Future<void> dispose() async {
    final transport = _transport;
    _transport = null;
    await transport?.close();
  }
}
