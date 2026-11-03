import 'package:communication_domain/communication_domain.dart';

import 'app_localizations.dart';

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

  /// Form field label by wire field name (CT_CONFIG_SCHEMA.md).
  String fieldLabel(String field) => switch (field) {
        'ssid' => formFieldSsid,
        'password' => formFieldPassword,
        'bssid' => formFieldBssid,
        'apn' => formFieldApn,
        'username' => formFieldUsername,
        'pin' => formFieldPin,
        'auth' => formFieldAuth,
        'roaming' => formFieldRoaming,
        'country' => formFieldCountry,
        'type' => formFieldType,
        'enable' => formFieldEnable,
        'host' => formFieldHost,
        'port' => formFieldPort,
        'client_id' => formFieldClientId,
        'tls' => formFieldTls,
        'topic' => formFieldTopic,
        'qos' => formFieldQos,
        'url' => formFieldUrl,
        'secret' => formFieldSecret,
        'header' => formFieldHeader,
        _ => field,
      };

  /// Validation problem text for one field (field name kept for context).
  String problemLabel(FieldProblemCode code, String field) => switch (code) {
        FieldProblemCode.required => problemRequired(field),
        FieldProblemCode.tooShort => problemTooShort(field),
        FieldProblemCode.tooLong => problemTooLong(field),
        FieldProblemCode.invalidFormat => problemInvalidFormat(field),
        FieldProblemCode.invalidValue => problemInvalidValue(field),
        FieldProblemCode.notDeclared => problemNotDeclared(field),
      };
}
