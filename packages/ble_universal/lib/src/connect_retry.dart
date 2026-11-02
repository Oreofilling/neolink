/// 连接后步骤失败的整轮重试工具。
///
/// Windows 端 universal_ble 在连接成功瞬间一次性缓存整个 GATT 表
/// （GetGattServicesAsync + GetCharacteristicsAsync 各跑一遍即存档），
/// 缓存坏掉（空表/陈旧句柄）后，后续任何基于它的 GATT 操作
/// （枚举校验、读、订阅）都会挂起或报 Unreachable；重新调用
/// discoverServices 只会读到同一份缓存快照，唯一可靠的修复是
/// 断开重连让插件重建缓存。本工具把「尝试 → 失败由调用方回滚断开
/// → 停顿 → 全新重试」的循环收敛在此。
library;

import 'dart:async';

/// 默认整轮次数：首连 + 2 次重试（真机缓存竞态通常第 2 轮即恢复）。
const int kConnectRetryAttempts = 3;

/// 默认重试前停顿：给外设留出重新广播、系统留出释放链路的时间。
const Duration kConnectRetryPause = Duration(milliseconds: 800);

/// 执行 [attempt]；失败且还有剩余次数时，等待 [pause] 后整轮重试。
/// 次数耗尽抛出最后一个错误。
///
/// [retryOn] 判定某次错误是否值得重试，默认全部重试（枚举/读/订阅
/// 的 WinRT 竞态都属于「重连可解」类）；传入谓词可排除确定性失败
/// （如参数错误）。[attempt] 自身负责失败时回滚（断开连接），
/// 本函数不感知连接语义。
Future<T> runWithConnectRetry<T>(
  Future<T> Function() attempt, {
  int maxAttempts = kConnectRetryAttempts,
  Duration pause = kConnectRetryPause,
  bool Function(Object error)? retryOn,
}) async {
  if (maxAttempts < 1) {
    throw ArgumentError.value(maxAttempts, 'maxAttempts', 'must be >= 1');
  }
  Object? lastError;
  for (var attemptNo = 1; attemptNo <= maxAttempts; attemptNo++) {
    try {
      return await attempt();
    } catch (error) {
      if (retryOn != null && !retryOn(error)) {
        rethrow;
      }
      lastError = error;
      if (attemptNo < maxAttempts) {
        await Future<void>.delayed(pause);
      }
    }
  }
  throw lastError!;
}
