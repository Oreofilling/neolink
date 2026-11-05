/// universal_ble 具体适配层（ble_adapter 的可替换实现之一）。
///
/// 扫描侧把各平台 Service Data 归一成 §4.2.2 的 27 字节广播再交给
/// ble_adapter 解析，并经 [BleDiscoverySource] 接入 discovery_domain；
/// 通道侧实现 [CtGattChannel] 的连接/配对/订阅序列；配对编排见
/// [establishSystemBond]。Windows 优先真机 PoC 于 2026-11-03 验证通过，
/// 通道实现冻结。
library;

export 'package:ble_adapter/ble_adapter.dart'
    show CtDiscoveredDevice, CtGattChannel, CtMetaInfo, parseMeta;

export 'package:discovery_domain/discovery_domain.dart';

export 'src/ble_discovery_source.dart';
export 'src/ct_adv_source.dart';
export 'src/environment_check.dart';
export 'src/link_events.dart';
export 'src/link_injector.dart';
export 'src/system_pairing.dart';
export 'src/universal_ct_channel.dart';
export 'src/universal_ct_scanner.dart';
