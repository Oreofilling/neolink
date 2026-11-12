import 'dart:async';

import 'package:discovery_domain/discovery_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';

/// 建立连接页（v7d timeline）：配对 → GATT 链路 → 读设备信息 → 读能力，
/// 纵向时间线呈现——已完成绿勾、当前步青色脉冲点、未开始灰圈，连接线
/// 按进度着色，右侧显示每步耗时；连接/能力失败给出原因并可返回候选
/// 列表重试（NE101 断开后仍在配置模式，可立即重试）。
class ConnectPage extends StatefulWidget {
  const ConnectPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<ConnectPage> createState() => _ConnectPageState();
}

class _ConnectPageState extends State<ConnectPage> {
  /// 1s repaint while the link is advancing — keeps the current step's
  /// elapsed counter alive even when no controller notification fires
  /// (a hung read shows a growing timer, which is exactly the diagnostic
  /// signal this page wants to give).
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  ProvisioningController get controller => widget.controller;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    // The ticker only runs while the chain is advancing — it stops on the
    // error pages so the failure state stays static.
    final advancing =
        controller.phase == SessionPhase.connecting ||
        controller.phase == SessionPhase.readingCapabilities;
    if (advancing && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!advancing && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }

    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final phase = controller.phase;
        final failed =
            phase == SessionPhase.connectionError ||
            phase == SessionPhase.capabilityError;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l.navConnect, style: NLType.pageTitle),
                const SizedBox(height: 16),
                if (phase == SessionPhase.webBrowsing)
                  _webHoldCard(c, l)
                else if (failed)
                  _errorBanner(c, l, phase)
                else
                  _timelineCard(c, l),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Fallback identity while caps have not arrived yet: the scan row's
  /// model-suffix pair (e.g. NE101-A1B2C3).
  String _deviceLabel() {
    final candidate = controller.selectedCandidate;
    if (candidate == null) return '';
    return '${candidate.modelHint ?? ''}-${candidate.macSuffix ?? ''}';
  }

  Widget _timelineCard(NLColors c, AppLocalizations l) {
    final phase = controller.phase;
    // M5: the timeline's first two steps describe the link being built —
    // pairing/GATT for BLE rows, Wi-Fi join/gateway for softAP rows. The
    // reading steps are shared.
    final viaAp = controller.selectedCandidate != null &&
        !controller.selectedCandidate!.channels
            .contains(DiscoveryChannel.ble);
    final steps = [
      viaAp ? l.connectJoinWlan : l.connectPairing,
      viaAp ? l.connectDeviceLink : l.connectOpening,
      l.connectReadingInfo,
      l.connectReadingCaps,
    ];
    // 相位 → 当前步序：connecting 覆盖前两步，readingCapabilities 后两步。
    final currentIndex = switch (phase) {
      SessionPhase.connecting => controller.connectSteps.isEmpty ? 0 : 1,
      SessionPhase.readingCapabilities => controller.deviceInfo == null ? 2 : 3,
      _ => steps.length - 1,
    };
    final deviceLabel = _deviceLabel();
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NLBadge(
              label: deviceLabel.isEmpty
                  ? l.badgeChecking
                  : l.connectWith(deviceLabel),
              variant: NLBadgeVariant.info,
              dot: true,
            ),
            const SizedBox(height: 16),
            // v7d vertical timeline: done steps get a green check, the
            // current one a pulsing brand-cyan dot (the one moving part),
            // later ones hollow circles; the connecting rail is green up
            // to the current step and hairline after it.
            for (var index = 0; index < steps.length; index++)
              _timelineRow(
                c,
                steps[index],
                index,
                currentIndex,
                total: steps.length,
              ),
            if (controller.connectSteps.isNotEmpty) ...[
              const SizedBox(height: 8),
              Divider(height: 1, thickness: 1, color: c.border),
              const SizedBox(height: 10),
              Text(
                controller.connectSteps.last,
                style: NLType.mono.copyWith(color: c.mutedForeground),
              ),
            ],
            const SizedBox(height: 12),
            // v6: an explicit way out while the link hangs — back to the
            // continuous scan instead of waiting for the step timeout.
            NLButton(
              label: l.connectCancel,
              variant: NLButtonVariant.ghost,
              size: NLButtonSize.sm,
              onPressed: controller.rescan,
            ),
          ],
        ),
      ),
    );
  }

  /// Web mode hold panel (M5): the join succeeded and the device console
  /// is in the browser — the app's remaining job is to make the held
  /// state legible (hotspot kept, no internet, idle-sleep behavior) and
  /// offer the one meaningful action: restore the previous Wi-Fi.
  Widget _webHoldCard(NLColors c, AppLocalizations l) {
    final deviceLabel = _deviceLabel();
    final url = controller.webPageUrl;
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            NLBadge(
              label: deviceLabel.isEmpty
                  ? l.badgeChecking
                  : l.connectWith(deviceLabel),
              variant: NLBadgeVariant.success,
              dot: true,
            ),
            const SizedBox(height: 16),
            Text(l.webHoldTitle, style: NLType.cardTitle),
            const SizedBox(height: 8),
            if (controller.webPageOpened && url != null)
              Text(
                l.webHoldOpenedAt,
                style: NLType.body.copyWith(color: c.mutedForeground),
              )
            else
              Text(
                l.webHoldOpenFailed,
                style: NLType.body.copyWith(color: c.error),
              ),
            if (url != null) ...[
              const SizedBox(height: 6),
              Text(
                url.toString(),
                style: NLType.mono.copyWith(color: c.foreground),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              l.webHoldKeepNote,
              style: NLType.aux.copyWith(color: c.mutedForeground),
            ),
            const SizedBox(height: 4),
            Text(
              l.webHoldIdleNote,
              style: NLType.aux.copyWith(color: c.mutedForeground),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                NLButton(
                  label: l.webHoldReopen,
                  variant: NLButtonVariant.secondary,
                  size: NLButtonSize.sm,
                  onPressed: controller.reopenWebPage,
                ),
                const SizedBox(width: 8),
                NLButton(
                  label: l.webHoldDisconnect,
                  size: NLButtonSize.sm,
                  onPressed: controller.finishWebBrowsing,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One timeline row: leading status marker + connector down to the next
  /// row, label, and the step's elapsed time on the right.
  Widget _timelineRow(
    NLColors c,
    String label,
    int index,
    int currentIndex, {
    required int total,
  }) {
    final done = index < currentIndex;
    final current = index == currentIndex;
    final hasConnector = index < total - 1;
    final duration = _stepDuration(index, currentIndex);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 22,
            child: Column(
              children: [
                SizedBox(
                  height: 20,
                  child: Center(
                    child: done
                        ? Icon(Icons.check_circle, size: 17, color: c.success)
                        : current
                        ? const _PulseDot()
                        : Icon(
                            Icons.circle_outlined,
                            size: 12,
                            color: c.mutedForeground,
                          ),
                  ),
                ),
                if (hasConnector)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: done ? c.success : c.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: hasConnector ? 14 : 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: NLType.body.copyWith(
                        color: index <= currentIndex
                            ? c.foreground
                            : c.mutedForeground,
                        fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (duration != null)
                    Text(
                      duration,
                      style: NLType.mono.copyWith(color: c.mutedForeground),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Elapsed for step [index]: stamped steps bracket the duration; the
  /// running step counts up from its stamp to now (null = not started).
  String? _stepDuration(int index, int currentIndex) {
    final times = controller.connectStepTimes;
    if (index >= times.length) return null;
    if (index < currentIndex && index + 1 < times.length) {
      return _formatElapsed(times[index + 1].difference(times[index]));
    }
    if (index == currentIndex) {
      return _formatElapsed(DateTime.now().difference(times[index]));
    }
    return null;
  }

  static String _formatElapsed(Duration d) {
    if (d.inMilliseconds < 1000) return '<1s';
    return '${(d.inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  /// v7d error treatment: light red fill with a 3px red left bar instead
  /// of a bordered card — errors are states, not content blocks.
  Widget _errorBanner(NLColors c, AppLocalizations l, SessionPhase phase) {
    final problem = controller.lastProblem;
    final detail = problem == null ? '' : (problem.message ?? problem.reason);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.errorBg,
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
        border: Border(left: BorderSide(color: c.error, width: 3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            phase == SessionPhase.capabilityError
                ? l.connectCapsErrorTitle
                : l.connectErrorTitle,
            style: NLType.cardTitle.copyWith(color: c.error),
          ),
          const SizedBox(height: 6),
          Text(
            l.connectRetryHint,
            style: NLType.aux.copyWith(color: c.mutedForeground),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(detail, style: NLType.mono.copyWith(color: c.mutedForeground)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              // Same candidate straight through the connect chain again —
              // the device stays in config mode after the dropped link.
              NLButton(
                label: l.connectRetry,
                onPressed: controller.retryConnect,
              ),
              const SizedBox(width: 8),
              NLButton(
                label: l.connectBackToList,
                variant: NLButtonVariant.secondary,
                onPressed: controller.switchCandidate,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Pulsing brand-cyan marker for the in-flight timeline step: a 10px dot
/// breathing between 0.85–1.15 scale with a soft halo. The only looping
/// animation on the page — one moving part reads "working", five read
/// "carnival".
class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    return ScaleTransition(
      scale: Tween(
        begin: 0.85,
        end: 1.15,
      ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut)),
      child: Container(
        width: 11,
        height: 11,
        decoration: BoxDecoration(
          color: c.accentCyan,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: c.accentCyan.withValues(alpha: 0.35),
              blurRadius: 7,
              spreadRadius: 1.5,
            ),
          ],
        ),
      ),
    );
  }
}
