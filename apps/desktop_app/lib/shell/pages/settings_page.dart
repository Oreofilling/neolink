import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// Settings page (v6): language / theme mirrors of the topbar toggles plus
/// discovery adapter rows (BLE / AP) from the last environment report.
class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.controller,
    required this.dark,
    required this.langLabel,
    required this.onToggleTheme,
    required this.onToggleLocale,
  });

  final ProvisioningController controller;
  final bool dark;
  final String langLabel;
  final VoidCallback onToggleTheme;
  final VoidCallback onToggleLocale;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.settings_outlined,
                      size: 18,
                      color: c.mutedForeground,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.navSettings,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                NLCard(
                  child: Column(
                    children: [
                      _toggleRow(
                        c,
                        icon: Icons.translate,
                        title: l.setLang,
                        note: l.setLangNote,
                        control: NLButton(
                          label: langLabel,
                          variant: NLButtonVariant.secondary,
                          size: NLButtonSize.sm,
                          onPressed: onToggleLocale,
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: c.border),
                      _toggleRow(
                        c,
                        icon: dark
                            ? Icons.dark_mode_outlined
                            : Icons.light_mode_outlined,
                        title: l.setTheme,
                        note: l.setThemeNote,
                        control: NLButton(
                          // v7c: chip states the current theme, matching the
                          // topbar toggle (a "Light" chip on a dark UI reads
                          // as a bug).
                          label: dark ? l.themeDark : l.themeLight,
                          variant: NLButtonVariant.secondary,
                          size: NLButtonSize.sm,
                          onPressed: onToggleTheme,
                        ),
                      ),
                      Divider(height: 1, thickness: 1, color: c.border),
                      _channelRow(
                        c,
                        l,
                        DiscoveryChannel.ble,
                        l.setBle,
                        icon: Icons.bluetooth,
                      ),
                      Divider(height: 1, thickness: 1, color: c.border),
                      _channelRow(
                        c,
                        l,
                        DiscoveryChannel.accessPoint,
                        l.setAp,
                        icon: Icons.wifi,
                        note: l.setApNote,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _toggleRow(
    NLColors c, {
    IconData? icon,
    required String title,
    required String note,
    required Widget control,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.mutedForeground),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note,
                  style: TextStyle(
                    fontSize: 11,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          control,
        ],
      ),
    );
  }

  /// Adapter readiness row. The AP row carries the admin-rights remark from
  /// the mockup copy — the most common "why is it grey" question.
  Widget _channelRow(
    NLColors c,
    AppLocalizations l,
    DiscoveryChannel channel,
    String title, {
    IconData? icon,
    String? note,
  }) {
    final entry = controller.environmentReport?.channels
        .where((row) => row.channel == channel)
        .firstOrNull;
    final (label, variant) = switch (entry?.capability) {
      null => (l.topbarBleChecking, NLBadgeVariant.info),
      ChannelCapability.available => (
        l.capabilityLabel(ChannelCapability.available),
        NLBadgeVariant.success,
      ),
      ChannelCapability.limited => (
        l.capabilityLabel(ChannelCapability.limited),
        NLBadgeVariant.warning,
      ),
      ChannelCapability.unavailable => (
        l.capabilityLabel(ChannelCapability.unavailable),
        NLBadgeVariant.error,
      ),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: c.mutedForeground),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  note ?? l.channelLabel(channel),
                  style: TextStyle(
                    fontSize: 11,
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          NLBadge(label: label, variant: variant),
        ],
      ),
    );
  }
}
