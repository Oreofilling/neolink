/// 协议黄金向量（骨架）：M1 从 CT_PROV_PROTOCOL §15 测试矩阵生成。
final class ProvVector {
  const ProvVector({required this.id, required this.description, this.wireBytes = const [], this.decoded = const {}});
  final String id;
  final String description;
  final List<int> wireBytes;
  final Map<String, Object?> decoded;
}

/// M1 填充：分片/CRC/信封/错误码向量（含 MTU 23 最大消息 3825B、坏 CRC、未知 op）。
const List<ProvVector> kProvVectors = [
  ProvVector(id: 'placeholder', description: 'M1 从协议测试矩阵生成'),
];
