import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/channel_labels.dart';
import '../../provisioning/provisioning_controller.dart';

/// Boot self-check page (v6): the app opens here — a centered card walks the
/// three discovery channels, then counts down into the scan automatically.
/// v7d: the implicit click-anywhere-to-stay is gone — an explicit pause
/// button beside the countdown stops the auto-jump; the re-check icon in
/// the card's top-right corner persists across states. Later re-checks
/// refresh the report from the settings page's adapter rows too.
class SelfcheckPage extends StatefulWidget {
  const SelfcheckPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<SelfcheckPage> createState() => _SelfcheckPageState();
}

class _SelfcheckPageState extends State<SelfcheckPage> {
  @override
  void initState() {
    super.initState();
    // Run the check after the first frame (setState inside the build cycle
    // would collide with widget construction).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.controller.runSelfCheck();
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    final controller = widget.controller;

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // The report must be read inside the builder: the shell only
        // rebuilds this page on phase changes, in-phase notifications flow
        // through ListenableBuilder alone.
        final report = controller.environmentReport;
        final counting = controller.selfCheckCountdown;
        final held = controller.selfCheckHeld;
        // v6 walk: after the report lands the rows are revealed one-by-one —
        // the row at selfCheckWalkIndex is mid-check, later rows stay queued.
        final walkIndex = controller.selfCheckWalkIndex;
        final idle = controller.phase != SessionPhase.selfChecking;
        // Round-3 A2: every check gives visible feedback — the running label
        // while in flight, and a last-checked stamp afterwards.
        final busy = controller.selfChecking;
        final status = busy || report == null
            ? l.selfcheckRunning
            : (idle || counting != null)
            ? (report.canProceed ? l.selfcheckReadyIdle : l.selfcheckBlocked)
            : held
            ? l.selfcheckHeld
            : (report.canProceed ? l.selfcheckReady : l.selfcheckBlocked);
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const NLLogo(size: 26),
                        const SizedBox(width: 9),
                        const Text(
                          'NeoLink',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          l.brandSubtitle,
                          style: TextStyle(
                            fontSize: 11,
                            color: c.mutedForeground,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    NLCard(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header: title/status on the left, the re-check
                            // icon pinned to the card's top-right corner —
                            // the only control that persists across states.
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        l.navSelfcheck,
                                        style: NLType.pageTitle,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        status,
                                        style: NLType.aux.copyWith(
                                          color: c.mutedForeground,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                _recheckIcon(c, l),
                              ],
                            ),
                            const SizedBox(height: 12),
                            if (report == null)
                              ...List.generate(
                                3,
                                (index) => const Padding(
                                  padding: EdgeInsets.only(bottom: 12),
                                  child: NLSkeleton(width: 320, height: 14),
                                ),
                              )
                            else
                              for (var i = 0; i < report.channels.length; i++)
                                _channelRow(
                                  c,
                                  l,
                                  report.channels[i],
                                  index: i,
                                  walkIndex: walkIndex,
                                ),
                            const SizedBox(height: 16),
                            // Round-2 A1: big countdown digits plus a draining
                            // bar sitting right above the action buttons.
                            // v7d: the pause button beside the digits is the
                            // one explicit way to stop the auto-jump — no
                            // more click-anywhere.
                            if (counting != null) ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '$counting',
                                    style: const TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w800,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 3),
                                    child: Text(
                                      l.selfcheckCountdownHint,
                                      style: NLType.aux.copyWith(
                                        color: c.mutedForeground,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    tooltip: l.btnPauseCountdown,
                                    icon: Icon(
                                      Icons.pause_circle_outline,
                                      size: 26,
                                      color: c.accentCyan,
                                    ),
                                    onPressed: controller.stayOnSelfCheck,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                height: 6,
                                decoration: BoxDecoration(
                                  color: c.muted,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                clipBehavior: Clip.antiAlias,
                                alignment: Alignment.centerLeft,
                                child: AnimatedFractionallySizedBox(
                                  duration: const Duration(milliseconds: 900),
                                  curve: Curves.linear,
                                  widthFactor:
                                      (counting /
                                              controller
                                                  .selfCheckHold
                                                  .inSeconds)
                                          .clamp(0.0, 1.0),
                                  child: ColoredBox(
                                    color: c.foreground,
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                            ],
                            // v7d: while the walk plays, the pause button in
                            // the header-less state is the scan-now jump —
                            // the row-level walk cannot be paused anymore
                            // (it reveals in under two seconds total).
                            if (counting != null || held)
                              NLButton(
                                label: l.btnScanNow,
                                size: NLButtonSize.sm,
                                onPressed: controller.startScanNow,
                              ),
                            if (controller.selfCheckAt != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  l.selfcheckLastRun(
                                    _clock(controller.selfCheckAt!),
                                  ),
                                  style: NLType.mono.copyWith(
                                    color: c.mutedForeground,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Wall-clock stamp for the last completed check (locale-independent
  /// HH:mm:ss — proves a re-check ran even when the rows are unchanged).
  static String _clock(DateTime at) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${two(at.hour)}:${two(at.minute)}:${two(at.second)}';
  }

  /// Icon-only re-check control for the card's top-right corner (v6) — the
  /// tooltip carries the full action name; disabled while a check runs.
  Widget _recheckIcon(NLColors c, AppLocalizations l) {
    final controller = widget.controller;
    return IconButton(
      tooltip: l.btnRecheck,
      icon: Icon(Icons.refresh, size: 18, color: c.mutedForeground),
      onPressed: controller.selfChecking ? null : controller.runSelfCheck,
      visualDensity: VisualDensity.compact,
    );
  }

  /// One channel row. During the v6 walk (walkIndex >= 0) the row at
  /// [index] == walkIndex is mid-check (spinner + checking badge), rows after
  /// it stay queued (dimmed, verdict hidden); reason/detail only render once
  /// a row has settled.
  Widget _channelRow(
    NLColors c,
    AppLocalizations l,
    ChannelReadiness entry, {
    int index = -1,
    int walkIndex = -1,
  }) {
    final variant = switch (entry.capability) {
      ChannelCapability.available => NLBadgeVariant.success,
      ChannelCapability.limited => NLBadgeVariant.warning,
      ChannelCapability.unavailable => NLBadgeVariant.error,
    };
    final isWalking = walkIndex >= 0;
    final isActive = isWalking && index == walkIndex;
    final isQueued = isWalking && index > walkIndex;
    return Opacity(
      opacity: isQueued ? 0.45 : 1,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isActive)
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: c.info,
                    ),
                  )
                else if (isQueued)
                  Icon(
                    Icons.hourglass_empty,
                    size: 18,
                    color: c.mutedForeground,
                  )
                else
                  _channelIcon(c, entry.capability),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l.channelLabel(entry.channel),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (isActive)
                  NLBadge(
                    label: l.badgeChecking,
                    variant: NLBadgeVariant.info,
                  )
                else if (isQueued)
                  NLBadge(label: l.selfcheckQueued)
                else
                  NLBadge(
                    label: l.capabilityLabel(entry.capability),
                    variant: variant,
                  ),
              ],
            ),
            if (!isWalking) ...[
              const SizedBox(height: 4),
              Text(
                l.reasonLabel(entry.reason),
                style: TextStyle(fontSize: 12, color: c.mutedForeground),
              ),
              if (entry.detail != null && entry.reason != 'ready')
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    entry.detail!,
                    style: TextStyle(
                      fontSize: 10,
                      fontFamily: 'JetBrains Mono',
                      color: c.mutedForeground,
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: c.border),
          ],
        ),
      ),
    );
  }

  Widget _channelIcon(NLColors c, ChannelCapability capability) {
    return switch (capability) {
      ChannelCapability.available => Icon(
        Icons.check_circle,
        size: 18,
        color: c.success,
      ),
      ChannelCapability.limited => Icon(
        Icons.error_outline,
        size: 18,
        color: c.warning,
      ),
      ChannelCapability.unavailable => Icon(
        Icons.cancel_outlined,
        size: 18,
        color: c.destructive,
      ),
    };
  }
}
