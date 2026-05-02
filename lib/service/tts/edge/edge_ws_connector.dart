import 'package:anx_reader/service/tts/edge/edge_ws_connection.dart';

import 'edge_ws_connector_stub.dart'
    if (dart.library.io) 'edge_ws_connector_io.dart' as impl;

Future<EdgeWsConnection> openEdgeWsConnection(
  Uri url,
  Map<String, String> headers, {
  Duration? connectTimeout,
}) {
  return impl.openEdgeWsConnection(
    url,
    headers,
    connectTimeout: connectTimeout,
  );
}
