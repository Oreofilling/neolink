/// CT-Prov GATT 通道端口：传输层依赖的最小原语集。
/// 具体实现由 universal_ble 适配器提供；接口于 2026-11-03 真机 PoC
/// 通过后冻结（NE101 + Windows 往返 3 连，已验证加密特征访问、系统
/// 配对与 bonding 行为（§4.4））。
library;

/// CT-Prov Service UUID。
const String kCtProvServiceUuid = '7B1E0001-9D5B-4B5B-8F6D-2A4C0B7E0100';

/// C2D 写 Characteristic（客户端到设备，配置写入通道）。
const String kC2dCharacteristicUuid = '7B1E0002-9D5B-4B5B-8F6D-2A4C0B7E0100';

/// D2C 指示 Characteristic（设备到客户端，响应与事件通道）。
const String kD2cCharacteristicUuid = '7B1E0003-9D5B-4B5B-8F6D-2A4C0B7E0100';

/// META 只读 Characteristic。
const String kMetaCharacteristicUuid = '7B1E0004-9D5B-4B5B-8F6D-2A4C0B7E0100';

/// 已连接的 CT-Prov GATT 通道抽象。实现负责：连接与断开、加密配对
/// 前置（首次请求前完成）、订阅 D2C 指示、按 Characteristic 读写。
abstract interface class CtGattChannel {
  /// 当前 ATT_MTU；协商完成前为 23。
  int get mtu;

  /// MTU 协商结果通知（每方向一次，会话中途不回退）。
  Stream<int> get mtuChanges;

  /// 向 C2D Characteristic 写一帧。必须按调用顺序完成，逐帧可等待。
  Future<void> writeC2d(List<int> frame);

  /// D2C Characteristic 的指示帧流（实现保证已订阅后才发首个请求）。
  Stream<List<int>> get d2cFrames;
}
