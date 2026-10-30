/// 枚举类失败整轮重试工具。
///
/// Windows 端 universal_ble 在连接成功瞬间一次性缓存整个 GATT 表
/// （GetGattServicesAsync + GetCharacteristicsAsync 各跑一遍即存档），
/// 偶发缓存到空/缺特征的服务表；此后再调 discoverServices 只会读到
/// 同一份缓存快照，唯一可靠的修复是断开重连让插件重建缓存。
/// 本工具把「尝试 → 失败由调用方回滚断开 → 停顿 → 全新重试」的
/// 循环收敛在此，仅对 StateError（枚举失败）重试，其余异常
/// 立即上抛。
library;

import 'dart:async';

/// 默认整轮次数：首连 + 2 次重试（真机空表竞态通常第 2 轮即恢复）。
const int kEnumRetryAttempts = 3;

/// 默认重试前停顿：给外设留出重新广播、系统留出释放链路的时间。
const Duration kEnumRetryPause = Duration(milliseconds: 800);

/// 执行 [attempt]；仅当其抛出 StateError（枚举失败）且还有剩余次数时，
/// 等待 [pause] 后整轮重试。次数耗尽抛出最后一个错误。
///
/// [attempt] 自身负责失败时回滚（断开连接），本函数不感知连接语义。
Future<T> runWithEnumRetry<T>(
  Future<T> Function() attempt, {
  int maxAttempts = kEnumRetryAttempts,
  Duration pause = kEnumRetryPause,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be >= 1');
  }
  Object? lastError;
  for (var attemptNo = 1; attemptNo <= maxAttempts; attemptNo++) {
    try {
      return await attempt();
    } on StateError catch (error) {
      lastError = error;
      if (attemptNo < maxAttempts) {
        await Future<void>.delayed(pause);
      }
    }
  }
  throw lastError!;
}
