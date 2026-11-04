// Config workspace (v6): the caps checklist and the delivery form merged
// into one page behind a context bar — choose sections, edit them, preview
// the masked payload and deliver, without page flips between rounds. Hosts
// phases choosingSections / editingConfig / delivering / operationError.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
import '../../provisioning/provisioning_controller.dart';
import '../../provisioning/section_editing.dart';
import 'scan_page.dart';
import 'section_form.dart';

/// Text-editable fields per section (switches/dropdowns bind directly).
const _textFieldsBySection = <String, List<String>>{
  'wifi': ['ssid', 'password', 'bssid'],
  'cellular': ['apn', 'username', 'password', 'pin'],
  'halow': ['ssid', 'password', 'country'],
  'comm': <String>[],
  'ethernet': <String>[],
  'mqtt': ['host', 'port', 'client_id', 'username', 'password', 'topic'],
  'webhook': ['url', 'secret', 'header'],
};

/// Credential-ish wire fields masked in the payload preview unless the
/// operator explicitly reveals them.
const _secretKeys = {'password', 'secret', 'pin'};
const _mask = '••••••••';

class ConfigPage extends StatefulWidget {
  const ConfigPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage>
    with SingleTickerProviderStateMixin {
  final Map<String, TextEditingController> _textControllers = {};
  final Set<String> _selected = {};
  TabController? _tabController;
  bool _showPlain = false;

  ProvisioningController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    _ensureTextControllers();
    controller.addListener(_syncControllers);
  }

  @override
  void dispose() {
    controller.removeListener(_syncControllers);
    _tabController?.dispose();
    for (final textController in _textControllers.values) {
      textController.dispose();
    }
    super.dispose();
  }

  /// Creates controllers for text fields of the editing sections (the field
  /// must also be declared by the capability, otherwise no input exists).
  void _ensureTextControllers() {
    for (final name in controller.editingSections) {
      final declared = controller.capabilities!.sections
          .firstWhere((section) => section.name == name)
          .fields;
      for (final field in _textFieldsBySection[name] ?? const <String>[]) {
        if (!declared.contains(field)) continue;
        final key = '$name.$field';
        _textControllers.putIfAbsent(
          key,
          () => TextEditingController(text: _draftText(name, field)),
        );
      }
    }
    final services = _serviceSections;
    if (services.length >= 2) {
      _tabController = TabController(length: services.length, vsync: this);
    }
  }

  String _draftText(String section, String field) {
    final draft = controller.drafts[section];
    if (draft == null) return '';
    final value = fieldValue(draft, field);
    return value == null ? '' : '$value';
  }

  /// Keeps controllers aligned with drafts when values change outside text
  /// input (config.get prefill, scan-result pick). Only touches fields whose
  /// text actually differs.
  void _syncControllers() {
    for (final entry in _textControllers.entries) {
      final parts = entry.key.split('.');
      final text = _draftText(parts.first, parts.last);
      if (entry.value.text != text) {
        entry.value.text = text;
      }
    }
  }

  List<String> get _serviceSections => [
    for (final name in controller.editingSections)
      if (_sectionKind(name) == ConfigSectionKind.service) name,
  ];

  List<String> get _networkSections => [
    for (final name in controller.editingSections)
      if (_sectionKind(name) != ConfigSectionKind.service) name,
  ];

  ConfigSectionKind? _sectionKind(String name) {
    for (final section in controller.capabilities?.sections ?? const []) {
      if (section.name == name) return section.kind;
    }
    return null;
  }

  /// Leading icon per known section name (v6 icon pass) — unknown names fall
  /// back to a generic slider so future sections still get a mark.
  static IconData _sectionIcon(String name) => switch (name) {
    'wifi' => Icons.wifi,
    'cellular' => Icons.cell_tower,
    'mqtt' => Icons.cloud_upload,
    'ethernet' => Icons.lan,
    'webhook' => Icons.webhook,
    _ => Icons.tune,
  };

  bool _isScannable(String name) =>
      controller.capabilities?.sections.any(
        (section) => section.name == name && section.scannable,
      ) ??
      false;

  void _onFieldChanged(String section, String field, Object? value) {
    final draft = controller.drafts[section];
    if (draft == null) return;
    // Numeric text fields parse to int; an unparseable port keeps the last
    // valid value (port is required), qos may go back to null.
    var effective = value;
    if (field == 'port' || field == 'qos') {
      if (value is String) {
        final parsed = int.tryParse(value);
        if (field == 'port' && parsed == null) return;
        effective = parsed;
      }
    }
    controller.updateDraft(applyFieldValue(draft, field, effective));
  }

  Object _maskValue(Object? node) {
    if (node is Map) {
      return {
        for (final entry in node.entries)
          entry.key:
              entry.value is String &&
                  entry.value.isNotEmpty &&
                  _secretKeys.contains(entry.key)
              ? _mask
              : _maskValue(entry.value),
      };
    }
    if (node is List) return [for (final item in node) _maskValue(item)];
    return node ?? const {};
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // The page mounts at choosingSections and transitions in place when
        // the operator starts editing — controllers/tabs must materialize on
        // that notification, not only in initState (fields render only when
        // their controller exists).
        _ensureTextControllers();
        final phase = controller.phase;
        final choosing = phase == SessionPhase.choosingSections;
        final delivering = phase == SessionPhase.delivering;
        final rejected = phase == SessionPhase.operationError;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ctxBar(c, l),
                const SizedBox(height: 16),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final left = choosing
                        ? _checklistPane(c, l)
                        : controller.editingSections.isEmpty
                        ? const SizedBox.shrink()
                        : _editingPane(c, l, delivering, rejected);
                    final right = _sidePane(c, l, delivering);
                    // Below ~940px the side column drops under the forms
                    // instead of squeezing them.
                    if (constraints.maxWidth < 940) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [left, const SizedBox(height: 14), right],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const SizedBox(width: 14),
                        SizedBox(width: 320, child: right),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Session context strip: connected device identity + way out of the
  /// session. The connected badge stays visible through every config phase.
  Widget _ctxBar(NLColors c, AppLocalizations l) {
    final info = controller.deviceInfo;
    final candidate = controller.selectedCandidate;
    final name = info?.deviceName ?? candidate?.modelHint ?? '';
    final serial = info?.serialNumber;
    final signal = candidate?.signal;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: c.border),
        borderRadius: BorderRadius.circular(NLRadii.radiusLg),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.link, size: 16, color: c.success),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          if (serial != null) ...[
            const SizedBox(width: 10),
            Text(
              serial,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
                color: c.mutedForeground,
              ),
            ),
          ],
          if (signal != null) ...[
            const SizedBox(width: 10),
            SignalBars(signal: signal),
            const SizedBox(width: 5),
            Text(
              l.scanSignal(signal),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
                color: c.mutedForeground,
              ),
            ),
          ],
          const SizedBox(width: 10),
          NLBadge(label: l.topbarConnected, variant: NLBadgeVariant.success),
          const Spacer(),
          NLButton(
            label: l.btnCancelSession,
            variant: NLButtonVariant.secondary,
            size: NLButtonSize.sm,
            onPressed: controller.rescan,
          ),
        ],
      ),
    );
  }

  /// choosingSections round: capability-driven checklist (§10 — the form is
  /// built from capabilities, never hardcoded per model).
  Widget _checklistPane(NLColors c, AppLocalizations l) {
    final caps = controller.capabilities;
    final info = controller.deviceInfo;
    if (caps == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              l.cfgSectionsTitle,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 10),
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
        const SizedBox(height: 10),
        for (final section in caps.sections)
          _sectionRow(
            c,
            l,
            section,
            poePower: info?.power.contains('poe') ?? false,
          ),
        const SizedBox(height: 12),
        NLButton(
          label: l.capsBegin,
          onPressed: _selected.isEmpty
              ? null
              : () => controller.beginEditing(_selected),
        ),
      ],
    );
  }

  Widget _sectionRow(
    NLColors c,
    AppLocalizations l,
    ConfigSection section, {
    bool poePower = false,
  }) {
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
                        Icon(
                          _sectionIcon(section.name),
                          size: 15,
                          color: c.mutedForeground,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            l.sectionLabel(section.name),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
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
                        // PoE is a power attribute of device.info (§13.3):
                        // shown on the ethernet row when power contains poe.
                        if (poePower && section.name == 'ethernet') ...[
                          const SizedBox(width: 8),
                          NLBadge(
                            label: l.capsPoePower,
                            variant: NLBadgeVariant.info,
                          ),
                        ],
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
                      section.fields.isEmpty
                          ? '${section.name} · —'
                          : '${section.name} · ${section.fields.join(", ")}',
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

  /// editingConfig / delivering / operationError rounds: section form cards
  /// for network sections, service tabs when both services are edited.
  Widget _editingPane(
    NLColors c,
    AppLocalizations l,
    bool delivering,
    bool rejected,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rejected) ...[
          _rejectedBanner(c, l),
          const SizedBox(height: 12),
        ],
        for (final name in _networkSections)
          SectionFormCard(
            section: controller.drafts[name]!,
            fields: _declaredFields(name),
            problems: controller.sectionProblems[name] ?? const [],
            declaredNetworks: controller.declaredNetworks,
            enabled: !delivering,
            textController: (field) => _textControllers['$name.$field'],
            onFieldChanged: (field, value) =>
                _onFieldChanged(name, field, value),
            scanPanel: _isScannable(name)
                ? _scanPanel(c, l, name, enabled: !delivering)
                : null,
          ),
        if (_serviceSections.isNotEmpty)
          _serviceBlock(l, delivering),
      ],
    );
  }

  List<String> _declaredFields(String name) =>
      controller.capabilities!.sections
          .firstWhere((section) => section.name == name)
          .fields;

  Widget _rejectedBanner(NLColors c, AppLocalizations l) {
    final problem = controller.lastProblem;
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.error_outline, size: 16, color: c.destructive),
                const SizedBox(width: 6),
                Text(
                  l.formErrorTitle,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.destructive,
                  ),
                ),
              ],
            ),
            if (problem != null) ...[
              const SizedBox(height: 6),
              Text(
                problem.message ?? problem.reason,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  color: c.mutedForeground,
                ),
              ),
            ],
            const SizedBox(height: 10),
            NLButton(
              label: l.formBackToEdit,
              size: NLButtonSize.sm,
              onPressed: controller.editAgain,
            ),
          ],
        ),
      ),
    );
  }

  Widget _serviceBlock(AppLocalizations l, bool delivering) {
    final services = _serviceSections;
    if (services.length < 2) {
      return SectionFormCard(
        section: controller.drafts[services.first]!,
        fields: _declaredFields(services.first),
        problems: controller.sectionProblems[services.first] ?? const [],
        declaredNetworks: controller.declaredNetworks,
        enabled: !delivering,
        textController: (field) =>
            _textControllers['${services.first}.$field'],
        onFieldChanged: (field, value) =>
            _onFieldChanged(services.first, field, value),
      );
    }
    final tabController = _tabController!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        NLTabBar(
          tabs: [for (final name in services) l.sectionLabel(name)],
          controller: tabController,
        ),
        AnimatedBuilder(
          animation: tabController,
          builder: (context, _) {
            final name = services[tabController.index];
            return SectionFormCard(
              key: ValueKey('service-$name'),
              section: controller.drafts[name]!,
              fields: _declaredFields(name),
              problems: controller.sectionProblems[name] ?? const [],
              declaredNetworks: controller.declaredNetworks,
              enabled: !delivering,
              textController: (field) => _textControllers['$name.$field'],
              onFieldChanged: (field, value) =>
                  _onFieldChanged(name, field, value),
            );
          },
        ),
      ],
    );
  }

  Widget _scanPanel(
    NLColors c,
    AppLocalizations l,
    String name, {
    required bool enabled,
  }) {
    final active = controller.scanSection == name;
    final scanning = controller.networkScanning && active;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            NLButton(
              label: scanning ? l.formScanning : l.formScanNetworks,
              size: NLButtonSize.sm,
              variant: NLButtonVariant.secondary,
              onPressed: enabled && !scanning
                  ? () => controller.scanNetworks(name)
                  : null,
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                l.formHiddenHint,
                style: TextStyle(fontSize: 11, color: c.mutedForeground),
              ),
            ),
          ],
        ),
        if (active && controller.scanItems.isNotEmpty) ...[
          const SizedBox(height: 10),
          for (final network in controller.scanItems)
            _scanTile(c, l, network),
          if (controller.scanMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: NLButton(
                label: l.formLoadMore,
                size: NLButtonSize.sm,
                variant: NLButtonVariant.ghost,
                onPressed: enabled && !controller.networkScanning
                    ? controller.loadMoreNetworks
                    : null,
              ),
            ),
        ],
      ],
    );
  }

  Widget _scanTile(NLColors c, AppLocalizations l, ScanNetwork network) {
    final country = network.extras['country'];
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        borderRadius: BorderRadius.circular(NLRadii.radiusMd),
        onTap: () => controller.pickNetwork(network),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(NLRadii.radiusMd),
            border: Border.all(color: c.border),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  network.displayName,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                l.scanSignal(network.signal),
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'JetBrains Mono',
                  color: c.mutedForeground,
                ),
              ),
              if (network.channel != null) ...[
                const SizedBox(width: 8),
                Text(
                  l.formScanChannel(network.channel!),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: c.mutedForeground,
                  ),
                ),
              ],
              if (country is String) ...[
                const SizedBox(width: 8),
                Text(
                  l.formScanCountry(country),
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: c.mutedForeground,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Right rail: device identity always; payload preview + deliver action
  /// once the editing round started.
  Widget _sidePane(NLColors c, AppLocalizations l, bool delivering) {
    final info = controller.deviceInfo;
    final editing = controller.editingSections.isNotEmpty;
    final caps = controller.capabilities;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NLCard(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.cfgDeviceInfo,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (info != null)
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      NLBadge(
                        label: l.capsDeviceModel(info.model),
                        variant: NLBadgeVariant.info,
                      ),
                      NLBadge(
                        label: l.capsDeviceFirmware(info.firmware),
                        variant: NLBadgeVariant.muted,
                      ),
                      NLBadge(
                        label: l.capsDeviceSerial(info.serialNumber),
                        variant: NLBadgeVariant.muted,
                      ),
                    ],
                  )
                else
                  const NLSkeleton(width: 240, height: 22),
                if (caps != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    caps.currentNetwork == null
                        ? l.capsNetworkNever
                        : l.capsCurrentNetwork(caps.currentNetwork!),
                    style: TextStyle(
                      fontSize: 11,
                      color: c.mutedForeground,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (editing) ...[
          const SizedBox(height: 14),
          _previewCard(c, l, delivering),
        ],
      ],
    );
  }

  /// Payload preview with credential masking (§13 masking applies to
  /// display; the delivered payload itself stays plaintext over the link).
  Widget _previewCard(NLColors c, AppLocalizations l, bool delivering) {
    final payload = controller.assembleDraftPayload();
    final body = _showPlain
        ? payload.payload
        : _maskValue(payload.payload);
    final text = const JsonEncoder.withIndent('  ').convert(body);
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l.cfgPreview,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                NLButton(
                  label: _showPlain ? l.btnHidePlain : l.btnShowPlain,
                  variant: NLButtonVariant.ghost,
                  size: NLButtonSize.sm,
                  onPressed: () => setState(() => _showPlain = !_showPlain),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              l.cfgPreviewSub,
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: SingleChildScrollView(
                child: SelectableText(
                  text,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'JetBrains Mono',
                    color: c.mutedForeground,
                  ),
                ),
              ),
            ),
            Divider(height: 1, thickness: 1, color: c.border),
            const SizedBox(height: 12),
            Text(
              l.cfgDeliverCount(controller.editingSections.length),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l.cfgDeliverAtomic,
              style: TextStyle(fontSize: 11, color: c.mutedForeground),
            ),
            const SizedBox(height: 12),
            NLButton(
              label: delivering ? l.formDelivering : l.formSubmit,
              onPressed: delivering ? null : controller.submit,
            ),
          ],
        ),
      ),
    );
  }
}
