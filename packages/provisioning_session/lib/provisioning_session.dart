/// 配置会话领域层：统一状态机（技术设计 §11）+ CT-Prov 会话客户端
/// （device.info / capabilities / config.set / communication.scan /
/// config.get / session.close）。状态机只做相位迁移、问题发布与注入式
/// 资源释放；适配器回调不直接导航页面。
library;

export 'src/capabilities.dart';
export 'src/config_ops.dart';
export 'src/ct_session_client.dart';
export 'src/provisioning_machine.dart';
export 'src/session_exception.dart';
