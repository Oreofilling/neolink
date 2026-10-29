import 'package:flutter_gen/gen_l10n/app_localizations.dart';

/// 导航组 / 导航项 / 页面标题 的本地化查表（键 → ARB 文案）。
/// 页面标题复用导航词条，避免两套译文漂移。
extension NavL10n on AppLocalizations {
  String groupLabel(String key) => switch (key) {
        'navGroupFlow' => navGroupFlow,
        'navGroupConfig' => navGroupConfig,
        'navGroupDeliver' => navGroupDeliver,
        _ => key,
      };

  String navLabel(String id) => switch (id) {
        'selfcheck' => navSelfcheck,
        'scan' => navScan,
        'empty' => navEmpty,
        'guide' => navGuide,
        'connect' => navConnect,
        'caps' => navCaps,
        'wifi' => navWifi,
        'cat1' => navCat1,
        'svc' => navSvc,
        'deliver' => navDeliver,
        'result' => navResult,
        _ => id,
      };
}
