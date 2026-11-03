// Capability-driven section form card: renders one editable section from its
// declared field list. Field widgets are chosen by field name (text, secret,
// switch, dropdown); the hosting page owns text controllers and the draft
// mutation callback, this widget stays presentational.
library;

import 'package:communication_domain/communication_domain.dart';
import 'package:flutter/material.dart';
import 'package:neolink_ui/neolink_ui.dart';

import '../../l10n/app_localizations.dart';
import '../../l10n/labels.dart';
import '../../provisioning/section_editing.dart';

/// Auth method options (cellular).
const kAuthOptions = ['none', 'pap', 'chap', 'pap_or_chap'];

class SectionFormCard extends StatelessWidget {
  const SectionFormCard({
    super.key,
    required this.section,
    required this.fields,
    required this.problems,
    required this.declaredNetworks,
    required this.enabled,
    required this.textController,
    required this.onFieldChanged,
    this.scanPanel,
  });

  /// Current draft of this section.
  final ConfigSection section;

  /// Declared field names in capability order.
  final List<String> fields;

  /// Validation problems for this section (rendered per field).
  final List<FieldProblem> problems;

  /// Network section names usable as comm.type options.
  final Set<String> declaredNetworks;

  /// False while delivering (inputs disabled).
  final bool enabled;

  /// Text controller lookup by field name (null for non-text fields).
  final TextEditingController? Function(String field) textController;

  /// Emits a new value for one field (the page applies it to the draft).
  final void Function(String field, Object? value) onFieldChanged;

  /// Optional scan list block injected by the hosting page (wifi/halow).
  final Widget? scanPanel;

  @override
  Widget build(BuildContext context) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    final sectionProblem = problems
        .where((problem) => problem.field == section.name)
        .toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: NLCard(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                section.name,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (sectionProblem.isNotEmpty) ...[
                const SizedBox(height: 6),
                for (final problem in sectionProblem)
                  Text(
                    l.problemLabel(problem.code, problem.field),
                    style: TextStyle(fontSize: 11, color: c.destructive),
                  ),
              ],
              const SizedBox(height: 4),
              if (fields.isEmpty)
                Text(
                  section.name == 'ethernet'
                      ? l.formEthernetNote
                      : l.formNoFields,
                  style: TextStyle(fontSize: 12, color: c.mutedForeground),
                )
              else ...[
                for (final field in fields)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _fieldRow(context, field),
                  ),
              ],
              if (scanPanel != null) ...[
                const SizedBox(height: 12),
                scanPanel!,
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _fieldRow(BuildContext context, String field) {
    final c = context.nl;
    final l = AppLocalizations.of(context)!;
    final fieldProblems = problems
        .where((problem) => problem.field == field)
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.fieldLabel(field),
          style: TextStyle(fontSize: 11, color: c.mutedForeground),
        ),
        const SizedBox(height: 4),
        _fieldInput(context, field),
        for (final problem in fieldProblems)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              l.problemLabel(problem.code, field),
              style: TextStyle(fontSize: 11, color: c.destructive),
            ),
          ),
      ],
    );
  }

  Widget _fieldInput(BuildContext context, String field) {
    switch (field) {
      // Plain text fields.
      case 'ssid':
      case 'apn':
      case 'username':
      case 'client_id':
      case 'topic':
      case 'url':
      case 'header':
        return _textField(context, field, mono: false);
      // Monospace identifier-ish fields.
      case 'bssid':
      case 'country':
        return _textField(context, field, mono: true);
      // Secret fields with masking toggle.
      case 'password':
      case 'secret':
      case 'pin':
        return _secretField(context, field);
      // Numeric text field.
      case 'port':
        return _textField(context, field, mono: true, numeric: true);
      // Boolean switches.
      case 'enable':
      case 'tls':
      case 'roaming':
        return _switchRow(context, field);
      // Dropdowns.
      case 'auth':
        return _dropdown<String>(
          context,
          field,
          kAuthOptions,
          fieldValue(section, field) as String?,
        );
      case 'qos':
        return _dropdown<int>(
          context,
          field,
          const [0, 1, 2],
          fieldValue(section, field) as int?,
        );
      case 'type':
        final options = [
          for (final mode in CommunicationMode.values)
            if (declaredNetworks.contains(mode.wireName)) mode,
        ];
        final current = section is CommSection
            ? (section as CommSection).type
            : CommunicationMode.wifi;
        return _dropdown<CommunicationMode>(
          context,
          field,
          options,
          options.contains(current) ? current : options.first,
        );
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _textField(
    BuildContext context,
    String field, {
    bool mono = false,
    bool numeric = false,
  }) {
    final controller = textController(field);
    if (controller == null) return const SizedBox.shrink();
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: numeric ? TextInputType.number : null,
      style: TextStyle(
        fontSize: 13,
        fontFamily: mono ? 'JetBrains Mono' : null,
      ),
      decoration: _inputDecoration(context).copyWith(
        hintText: numeric ? '1883' : null,
      ),
      onChanged: (value) => onFieldChanged(field, value),
    );
  }

  Widget _secretField(BuildContext context, String field) {
    final c = context.nl;
    final controller = textController(field);
    if (controller == null) return const SizedBox.shrink();
    return _SecretField(
      controller: controller,
      enabled: enabled,
      decoration: _inputDecoration(context),
      iconColor: c.mutedForeground,
      onChanged: (value) => onFieldChanged(field, value),
    );
  }

  Widget _switchRow(BuildContext context, String field) {
    final value = fieldValue(section, field);
    return Switch(
      value: value is bool ? value : false,
      onChanged: enabled ? (next) => onFieldChanged(field, next) : null,
    );
  }

  Widget _dropdown<T>(
    BuildContext context,
    String field,
    List<T> options,
    T? current,
  ) {
    final c = context.nl;
    return DropdownButtonFormField<T>(
      value: current,
      items: [
        for (final option in options)
          DropdownMenuItem(
            value: option,
            child: Text(
              option is CommunicationMode ? option.wireName : '$option',
              style: const TextStyle(fontSize: 13),
            ),
          ),
      ],
      onChanged: enabled ? (next) => onFieldChanged(field, next) : null,
      decoration: _inputDecoration(context),
      iconEnabledColor: c.mutedForeground,
    );
  }

  InputDecoration _inputDecoration(BuildContext context) {
    final c = context.nl;
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NLRadii.radiusMd),
        borderSide: BorderSide(color: c.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NLRadii.radiusMd),
        borderSide: BorderSide(color: c.foreground),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(NLRadii.radiusMd),
        borderSide: BorderSide(color: c.border),
      ),
    );
  }
}

/// Secret input with a local visibility toggle (own state so the card can
/// stay stateless).
class _SecretField extends StatefulWidget {
  const _SecretField({
    required this.controller,
    required this.enabled,
    required this.decoration,
    required this.iconColor,
    required this.onChanged,
  });

  final TextEditingController controller;
  final bool enabled;
  final InputDecoration decoration;
  final Color iconColor;
  final ValueChanged<String> onChanged;

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      enabled: widget.enabled,
      obscureText: _obscure,
      style: const TextStyle(fontSize: 13),
      decoration: widget.decoration.copyWith(
        suffixIcon: IconButton(
          visualDensity: VisualDensity.compact,
          icon: Icon(
            _obscure
                ? Icons.visibility_outlined
                : Icons.visibility_off_outlined,
            size: 16,
            color: widget.iconColor,
          ),
          onPressed: () => setState(() => _obscure = !_obscure),
        ),
      ),
      onChanged: widget.onChanged,
    );
  }
}
