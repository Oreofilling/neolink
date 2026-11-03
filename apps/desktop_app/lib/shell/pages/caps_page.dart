import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// 配置节页（M2-4）：能力驱动展示——设备信息卡 + 当前网络 + 节列表
/// 勾选。表单构造与 config.set 下发属于 M3，这里先落「读能力 → 勾选」
/// 的链路终点（技术设计 §10：表单由能力构造，不按型号硬编码）。
class CapsPage extends StatefulWidget {
  const CapsPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<CapsPage> createState() => _CapsPageState();
}

class _CapsPageState extends State<CapsPage> {
  /// 勾选的节名（本地态，M3 提交时使用；不落盘）。
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final info = controller.deviceInfo;
        final caps = controller.capabilities;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      l.navCaps,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (caps != null)
                      NLBadge(
                        label: l.capsFieldsCount(
                          caps.sections
                              .map((section) => section.fields.length)
                              .fold(0, (sum, count) => sum + count),
                        ),
                        variant: NLBadgeVariant.muted,
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  l.capsSelectNote,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
                if (info != null) _deviceCard(c, l, info),
                if (caps != null) ...[
                  const SizedBox(height: 14),
                  _currentNetworkRow(c, l, caps),
                  const SizedBox(height: 14),
                  for (final section in caps.sections)
                    _sectionRow(c, l, section),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _deviceCard(NLColors c, AppLocalizations l, DeviceInfoResult info) {
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  info.deviceName,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                NLBadge(
                  label: l.capsDeviceModel(info.model),
                  variant: NLBadgeVariant.info,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                NLBadge(
                  label: l.capsDeviceFirmware(info.firmware),
                  variant: NLBadgeVariant.muted,
                ),
                NLBadge(
                  label: l.capsDeviceSerial(info.serialNumber),
                  variant: NLBadgeVariant.muted,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _currentNetworkRow(
    NLColors c,
    AppLocalizations l,
    CapabilitiesResult caps,
  ) {
    return Row(
      children: [
        Text(
          caps.currentNetwork == null
              ? l.capsNetworkNever
              : l.capsCurrentNetwork(caps.currentNetwork!),
          style: TextStyle(fontSize: 12, color: c.mutedForeground),
        ),
      ],
    );
  }

  Widget _sectionRow(NLColors c, AppLocalizations l, ConfigSection section) {
    final checked = _selected.contains(section.name);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: NLCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: section.configurable ? checked : false,
                onChanged: section.configurable
                    ? (value) => setState(() {
                        if (value == true) {
                          _selected.add(section.name);
                        } else {
                          _selected.remove(section.name);
                        }
                      })
                    : null,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          section.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(width: 8),
                        NLBadge(
                          label: section.configurable
                              ? l.capsSectionConfigurable
                              : l.capsSectionReadonly,
                          variant: section.configurable
                              ? NLBadgeVariant.success
                              : NLBadgeVariant.muted,
                        ),
                        if (section.scannable) ...[
                          const SizedBox(width: 8),
                          NLBadge(
                            label: l.capsSectionScannable,
                            variant: NLBadgeVariant.info,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      section.fields.isEmpty ? '—' : section.fields.join(', '),
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'JetBrains Mono',
                        color: c.mutedForeground,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
