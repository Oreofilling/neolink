/// Embedded device web console for web mode: the console renders inside
/// the app (WebView2 via flutter_inappwebview) instead of a browser tab.
///
/// The controller carries only the builder seam — mirroring
/// [DeviceWebOpener]: the production builder is wired once at app
/// assembly (app.dart) and tests inject a fake, because the default must
/// never instantiate a real WebView2 inside a widget test (the suite runs
/// on the Windows host too).
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Builds the embedded console surface for [url]. [reloadLabel] and
/// [loadFailedText] flow in from the page so copy stays in the ARB files
/// (C-12). Null from [defaultWebConsoleBuilder] means "embed unavailable"
/// and the caller falls back to the browser hold panel.
typedef WebConsoleBuilder = Widget Function(
  Uri url,
  String reloadLabel,
  String loadFailedText,
);

/// Production builder: Windows-only. Other platforms return null and web
/// mode keeps the system-browser behavior.
WebConsoleBuilder? defaultWebConsoleBuilder() {
  if (!Platform.isWindows) return null;
  return (url, reloadLabel, loadFailedText) => DeviceWebConsole(
    url: url,
    reloadLabel: reloadLabel,
    loadFailedText: loadFailedText,
  );
}

/// WebView2 surface with a writable profile directory (WebView2's default
/// sits next to the exe, which is read-only under a Program Files install)
/// and a corner reload chip — after the device's idle sleep a reload is
/// the wake action for the held link.
class DeviceWebConsole extends StatefulWidget {
  const DeviceWebConsole({
    super.key,
    required this.url,
    required this.reloadLabel,
    required this.loadFailedText,
  });

  final Uri url;
  final String reloadLabel;
  final String loadFailedText;

  @override
  State<DeviceWebConsole> createState() => _DeviceWebConsoleState();
}

class _DeviceWebConsoleState extends State<DeviceWebConsole> {
  WebViewEnvironment? _environment;
  Object? _environmentError;
  InAppWebViewController? _webController;

  @override
  void initState() {
    super.initState();
    unawaited(_createEnvironment());
  }

  Future<void> _createEnvironment() async {
    final appData = Platform.environment['APPDATA'];
    final profile = appData == null ? null : '$appData\\NeoLink\\WebView2';
    final environment = WebViewEnvironment(
      settings: WebViewEnvironmentSettings(userDataFolder: profile),
    );
    try {
      await environment.create();
    } catch (error) {
      if (mounted) setState(() => _environmentError = error);
      return;
    }
    if (mounted) setState(() => _environment = environment);
  }

  Future<void> _retryEnvironment() async {
    setState(() => _environmentError = null);
    await _createEnvironment();
  }

  @override
  void dispose() {
    unawaited(_environment?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_environmentError != null) {
      // WebView2 runtime missing/broken: the panel's browser button is the
      // real fallback; this surface just explains and offers a retry.
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                widget.loadFailedText,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _retryEnvironment,
              child: Text(widget.reloadLabel),
            ),
          ],
        ),
      );
    }
    if (_environment == null) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    return Stack(
      children: [
        InAppWebView(
          key: ValueKey(widget.url),
          webViewEnvironment: _environment,
          initialUrlRequest: URLRequest(url: WebUri(widget.url.toString())),
          initialSettings: InAppWebViewSettings(javaScriptEnabled: true),
          onWebViewCreated: (controller) => _webController = controller,
        ),
        // Corner reload chip: wakes the console after an idle sleep.
        Positioned(
          top: 8,
          right: 8,
          child: Tooltip(
            message: widget.reloadLabel,
            child: Material(
              color: theme.colorScheme.surface,
              shape: const CircleBorder(),
              elevation: 2,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => _webController?.reload(),
                child: Padding(
                  padding: const EdgeInsets.all(7),
                  child: Icon(
                    Icons.refresh,
                    size: 15,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
