// Delivery form page (M3): hosts section form cards for the editing round,
// service tabs when both mqtt and webhook are edited, a network scan panel
// for scannable sections, a payload preview and the submit / error banner
// states (editingConfig / delivering / operationError phases).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';
import 'package:provisioning_session/provisioning_session.dart' hide ConfigSection;

import '../../l10n/app_localizations.dart';
import '../../provisioning/provisioning_controller.dart';
import '../../provisioning/section_editing.dart';
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

class FormPage extends StatefulWidget {
  const FormPage({super.key, required this.controller});

  final ProvisioningController controller;

  @override
  State<FormPage> createState() => _FormPageState();
}

class _FormPageState extends State<FormPage>
    with SingleTickerProviderStateMixin {
  final Map<String, TextEditingController> _textControllers = {};
  TabController? _tabController;

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
          () => TextEditingController(
            text: _draftText(name, field),
          ),
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

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        if (controller.editingSections.isEmpty) {
          return const SizedBox.shrink();
        }
        final phase = controller.phase;
        final delivering = phase == SessionPhase.delivering;
        final rejected = phase == SessionPhase.operationError;
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 860),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.navDeliver,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  l.formNote,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                ),
                const SizedBox(height: 16),
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
                _payloadPreview(c, l),
                const SizedBox(height: 16),
                _submitRow(l, delivering),
              ],
            ),
          ),
        );
      },
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
          tabs: services,
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

  Widget _payloadPreview(NLColors c, AppLocalizations l) {
    final payload = controller.assembleDraftPayload();
    final text = const JsonEncoder.withIndent('  ').convert(payload.payload);
    return NLCard(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.formPayloadPreview,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(
              text,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'JetBrains Mono',
                color: c.mutedForeground,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _submitRow(AppLocalizations l, bool delivering) {
    return Row(
      children: [
        NLButton(
          label: delivering ? l.formDelivering : l.formSubmit,
          onPressed: delivering ? null : controller.submit,
        ),
      ],
    );
  }
}
