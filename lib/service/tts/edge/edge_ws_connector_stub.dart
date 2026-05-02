import 'package:anx_reader/service/tts/edge/edge_ws_connection.dart';

Future<EdgeWsConnection> openEdgeWsConnection(
  Uri url,
  Map<String, String> headers, {
  Duration? connectTimeout,
}) {
  throw UnsupportedError('Edge TTS is only supported on native platforms.');
}
