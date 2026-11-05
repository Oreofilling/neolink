/// CT-Prov over device softAP HTTP (protocol doc section 16): one whole
/// envelope per POST /api/v1/ctprov, no GATT fragmentation, session
/// semantics identical to BLE.
library;

export 'src/softap_ct_transport.dart';
