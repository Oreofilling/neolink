/// CT-Prov/1 v2.0 协议核心：操作与错误码、GATT 分片（§5）重组/切片、
/// JSON 信封（§6）编解码。字节与行为以黄金向量（test_vectors 包）为准。
/// 协议文档：lowpower_camera/docs/CT_PROV_PROTOCOL.md（无事务模型，C-11）。

library;

export 'src/envelope.dart';
export 'src/fragment.dart';
export 'src/ops.dart';
export 'src/slicer.dart';
