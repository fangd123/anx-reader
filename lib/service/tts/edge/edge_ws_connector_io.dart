import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/edge/edge_ws_connection.dart';
import 'package:crypto/crypto.dart';

Future<EdgeWsConnection> openEdgeWsConnection(
  Uri url,
  Map<String, String> headers, {
  Duration? connectTimeout,
}) async {
  SecureSocket? socket;

  try {
    final host = url.host;
    final port = url.hasPort ? url.port : 443;
    final connectFuture = SecureSocket.connect(
      host,
      port,
      supportedProtocols: const [],
    );
    socket = connectTimeout == null
        ? await connectFuture
        : await connectFuture.timeout(connectTimeout);

    final handshake = _EdgeWsHandshake(url, headers);
    socket.write(handshake.requestText);
    await socket.flush();

    final reader = _SocketReader(socket);
    final response = await reader.readHttpResponse();
    handshake.validate(response);

    return _IoEdgeWsConnection(socket, reader);
  } catch (_) {
    await socket?.close();
    rethrow;
  }
}

class _IoEdgeWsConnection implements EdgeWsConnection {
  _IoEdgeWsConnection(this._socket, this._reader) {
    _startReading();
  }

  final SecureSocket _socket;
  final _SocketReader _reader;
  final StreamController<Object> _messages = StreamController<Object>();
  final Random _random = Random.secure();

  bool _closed = false;
  bool _closeFrameSent = false;

  @override
  Stream<Object> get messages => _messages.stream;

  void _startReading() {
    unawaited(_readLoop());
  }

  Future<void> _readLoop() async {
    try {
      while (!_closed) {
        final frame = await _reader.readFrame();
        switch (frame.opcode) {
          case _EdgeWsOpcode.text:
            _messages.add(utf8.decode(frame.payload, allowMalformed: true));
            break;
          case _EdgeWsOpcode.binary:
            _messages.add(frame.payload);
            break;
          case _EdgeWsOpcode.close:
            if (!_closeFrameSent) {
              await _sendFrame(_EdgeWsOpcode.close, frame.payload);
              _closeFrameSent = true;
            }
            await _shutdown();
            return;
          case _EdgeWsOpcode.ping:
            await _sendFrame(_EdgeWsOpcode.pong, frame.payload);
            break;
          case _EdgeWsOpcode.pong:
            break;
          default:
            throw WebSocketException(
              'Unsupported Edge WS opcode: ${frame.opcode}',
            );
        }
      }
    } catch (error, stackTrace) {
      if (!_messages.isClosed) {
        _messages.addError(error, stackTrace);
      }
      await _shutdown();
    }
  }

  @override
  Future<void> sendText(String text) async {
    await _sendFrame(_EdgeWsOpcode.text, Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _sendFrame(int opcode, Uint8List payload) async {
    if (_closed) {
      throw StateError('Edge WS connection is closed.');
    }

    final header = BytesBuilder(copy: false);
    header.addByte(0x80 | opcode);

    final maskKey = Uint8List.fromList(
      List<int>.generate(4, (_) => _random.nextInt(256)),
    );

    final payloadLength = payload.length;
    if (payloadLength < 126) {
      header.addByte(0x80 | payloadLength);
    } else if (payloadLength <= 0xFFFF) {
      header.addByte(0x80 | 126);
      header.add(_encode16(payloadLength));
    } else {
      header.addByte(0x80 | 127);
      header.add(_encode64(payloadLength));
    }

    final masked = Uint8List(payloadLength);
    for (var i = 0; i < payloadLength; i++) {
      masked[i] = payload[i] ^ maskKey[i % 4];
    }

    header.add(maskKey);
    header.add(masked);
    _socket.add(header.toBytes());
    await _socket.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    if (!_closeFrameSent) {
      try {
        await _sendFrame(_EdgeWsOpcode.close, Uint8List(0));
      } finally {
        _closeFrameSent = true;
      }
    }
    await _shutdown();
  }

  Future<void> _shutdown() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _reader.close();
    await _socket.close();
    await _messages.close();
  }
}

class _EdgeWsHandshake {
  _EdgeWsHandshake(this.url, Map<String, String> headers)
      : _headers = Map<String, String>.from(headers),
        _key = base64.encode(
          List<int>.generate(16, (_) => Random.secure().nextInt(256)),
        );

  final Uri url;
  final Map<String, String> _headers;
  final String _key;

  String get requestText {
    final lines = <String>[
      'GET ${_pathWithQuery(url)} HTTP/1.1',
      'Host: ${_hostHeader(url)}',
      'Upgrade: websocket',
      'Connection: Upgrade',
      'Sec-WebSocket-Key: $_key',
      'Sec-WebSocket-Version: 13',
      ..._headers.entries.map((entry) => '${entry.key}: ${entry.value}'),
      '',
      '',
    ];
    return lines.join('\r\n');
  }

  void validate(_HttpResponseHead response) {
    if (response.statusCode != 101) {
      throw WebSocketException(
        "Connection to '${url.toString()}' was not upgraded to websocket, "
        'HTTP status code: ${response.statusCode}',
      );
    }

    final upgrade = response.header('upgrade');
    final connection = response.header('connection');
    final accept = response.header('sec-websocket-accept');
    final expectedAccept = base64.encode(
      sha1
          .convert(
            ascii.encode(
              '${_key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11',
            ),
          )
          .bytes,
    );

    if (upgrade?.toLowerCase() != 'websocket') {
      throw WebSocketException('Invalid websocket upgrade response.');
    }
    if (connection?.toLowerCase().contains('upgrade') != true) {
      throw WebSocketException('Invalid websocket connection response.');
    }
    if (accept != expectedAccept) {
      throw WebSocketException('Invalid websocket accept response.');
    }
  }

  static String _pathWithQuery(Uri uri) {
    final query = uri.hasQuery ? '?${uri.query}' : '';
    return '${uri.path}$query';
  }

  static String _hostHeader(Uri uri) {
    final defaultPort = uri.scheme == 'wss' ? 443 : 80;
    if (!uri.hasPort || uri.port == defaultPort) {
      return uri.host;
    }
    return '${uri.host}:${uri.port}';
  }
}

class _HttpResponseHead {
  _HttpResponseHead(this.statusCode, this.headers);

  final int statusCode;
  final Map<String, String> headers;

  String? header(String name) => headers[name.toLowerCase()];
}

class _SocketReader {
  _SocketReader(this._socket) {
    _subscription = _socket.listen(
      (data) {
        _buffer.addAll(data);
        _drainWaiters();
      },
      onError: (Object error, StackTrace stackTrace) {
        _error = error;
        _errorStackTrace = stackTrace;
        _drainWaiters();
      },
      onDone: () {
        _done = true;
        _drainWaiters();
      },
      cancelOnError: false,
    );
  }

  final SecureSocket _socket;
  final Queue<int> _buffer = Queue<int>();
  late final StreamSubscription<Uint8List> _subscription;
  final List<VoidCallback> _waiters = <VoidCallback>[];

  Object? _error;
  StackTrace? _errorStackTrace;
  bool _done = false;

  Future<_HttpResponseHead> readHttpResponse() async {
    final bytes = await _readUntilHeaderTerminator();
    final text = latin1.decode(bytes, allowInvalid: true);
    final lines = text.split('\r\n');
    if (lines.isEmpty) {
      throw WebSocketException('Invalid websocket handshake response.');
    }

    final statusLine = lines.first;
    final statusMatch = RegExp(r'^HTTP/\d+\.\d+\s+(\d+)').firstMatch(statusLine);
    if (statusMatch == null) {
      throw WebSocketException('Invalid websocket handshake status line.');
    }

    final headers = <String, String>{};
    for (final line in lines.skip(1)) {
      if (line.isEmpty) {
        continue;
      }
      final separator = line.indexOf(':');
      if (separator <= 0) {
        continue;
      }
      final name = line.substring(0, separator).trim().toLowerCase();
      final value = line.substring(separator + 1).trim();
      headers[name] = value;
    }

    return _HttpResponseHead(int.parse(statusMatch.group(1)!), headers);
  }

  Future<_EdgeWsFrame> readFrame() async {
    final firstTwoBytes = await _readBytes(2);
    final first = firstTwoBytes[0];
    final second = firstTwoBytes[1];

    final fin = (first & 0x80) != 0;
    final opcode = first & 0x0F;
    final masked = (second & 0x80) != 0;
    var payloadLength = second & 0x7F;

    if (!fin) {
      throw WebSocketException('Fragmented Edge WS frames are not supported.');
    }
    if (masked) {
      throw WebSocketException('Server-sent Edge WS frames must not be masked.');
    }

    if (payloadLength == 126) {
      final extended = await _readBytes(2);
      payloadLength = (extended[0] << 8) | extended[1];
    } else if (payloadLength == 127) {
      final extended = await _readBytes(8);
      final value = ByteData.sublistView(extended).getUint64(0);
      if (value > 0x7FFFFFFF) {
        throw WebSocketException('Edge WS frame payload is too large.');
      }
      payloadLength = value.toInt();
    }

    final payload = await _readBytes(payloadLength);
    return _EdgeWsFrame(opcode, payload);
  }

  Future<Uint8List> _readUntilHeaderTerminator() async {
    while (true) {
      final index = _findHeaderTerminator();
      if (index != -1) {
        return _consumeBytes(index + 4);
      }
      await _waitForData();
    }
  }

  int _findHeaderTerminator() {
    if (_buffer.length < 4) {
      return -1;
    }

    final list = _buffer.toList(growable: false);
    for (var i = 0; i <= list.length - 4; i++) {
      if (list[i] == 13 &&
          list[i + 1] == 10 &&
          list[i + 2] == 13 &&
          list[i + 3] == 10) {
        return i;
      }
    }
    return -1;
  }

  Future<Uint8List> _readBytes(int count) async {
    while (_buffer.length < count) {
      await _waitForData();
    }
    return _consumeBytes(count);
  }

  Uint8List _consumeBytes(int count) {
    final result = Uint8List(count);
    for (var i = 0; i < count; i++) {
      result[i] = _buffer.removeFirst();
    }
    return result;
  }

  Future<void> _waitForData() {
    if (_error != null) {
      Error.throwWithStackTrace(_error!, _errorStackTrace!);
    }
    if (_done) {
      throw WebSocketException('Edge WS connection closed unexpectedly.');
    }

    final completer = Completer<void>();
    void waiter() {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }

    _waiters.add(waiter);
    return completer.future;
  }

  void _drainWaiters() {
    final waiters = List<VoidCallback>.from(_waiters);
    _waiters.clear();
    for (final waiter in waiters) {
      waiter();
    }
  }

  Future<void> close() async {
    await _subscription.cancel();
  }
}

class _EdgeWsFrame {
  _EdgeWsFrame(this.opcode, this.payload);

  final int opcode;
  final Uint8List payload;
}

class _EdgeWsOpcode {
  static const int text = 0x1;
  static const int binary = 0x2;
  static const int close = 0x8;
  static const int ping = 0x9;
  static const int pong = 0xA;
}

Uint8List _encode16(int value) {
  final bytes = ByteData(2)..setUint16(0, value);
  return bytes.buffer.asUint8List();
}

Uint8List _encode64(int value) {
  final bytes = ByteData(8)..setUint64(0, value);
  return bytes.buffer.asUint8List();
}

typedef VoidCallback = void Function();
