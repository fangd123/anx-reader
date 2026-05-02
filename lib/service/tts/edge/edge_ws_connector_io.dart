import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/edge/edge_ws_connection.dart';

Future<EdgeWsConnection> openEdgeWsConnection(
  Uri url,
  Map<String, String> headers, {
  Duration? connectTimeout,
}) async {
  Future<WebSocket> connection = WebSocket.connect(
    url.toString(),
    headers: headers,
  );
  if (connectTimeout != null) {
    connection = connection.timeout(connectTimeout);
  }
  final socket = await connection;
  return _IoEdgeWsConnection(socket);
}

class _IoEdgeWsConnection implements EdgeWsConnection {
  _IoEdgeWsConnection(this._socket);

  final WebSocket _socket;

  @override
  Stream<Object> get messages => _socket.map<Object>((event) {
        if (event is String) {
          return event;
        }
        if (event is Uint8List) {
          return event;
        }
        if (event is List<int>) {
          return Uint8List.fromList(event);
        }
        throw StateError('Unsupported Edge WS frame: ${event.runtimeType}');
      });

  @override
  Future<void> sendText(String text) async {
    _socket.add(text);
  }

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
