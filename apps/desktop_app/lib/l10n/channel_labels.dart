import 'app_localizations.dart';

import 'package:discovery_domain/discovery_domain.dart';

/// 通道 / 通道能力 / 自检原因 的本地化查表（稳定标识 → ARB 文案）。
/// 未覆盖的 reason 原样返回，页面可同时展示 detail 诊断串。
extension ChannelL10n on AppLocalizations {
  String channelLabel(DiscoveryChannel channel) => switch (channel) {
    DiscoveryChannel.ble => channelBle,
    DiscoveryChannel.accessPoint => channelAp,
    DiscoveryChannel.ctDisc => channelCtDisc,
  };

  String capabilityLabel(ChannelCapability capability) => switch (capability) {
    ChannelCapability.available => capAvailable,
    ChannelCapability.limited => capLimited,
    ChannelCapability.unavailable => capUnavailable,
  };

  String reasonLabel(String reason) => switch (reason) {
    'ready' => reasonReady,
    'transient' => reasonTransient,
    'poweredOff' => reasonPoweredOff,
    'unauthorized' => reasonUnauthorized,
    'unsupported' => reasonUnsupported,
    'no_wlan_adapter' => reasonNoWlanAdapter,
    'wlan_disabled' => reasonWlanDisabled,
    'adapter_probe_failed' => reasonAdapterProbeFailed,
    'reserved' => reasonReserved,
    'no_nic' => reasonNoNic,
    'only_virtual_nics' => reasonOnlyVirtualNics,
    'nic_probe_failed' => reasonAdapterProbeFailed,
    _ => reason,
  };
}
