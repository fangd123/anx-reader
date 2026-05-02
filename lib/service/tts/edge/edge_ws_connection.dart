abstract class EdgeWsConnection {
  Stream<Object> get messages;

  Future<void> sendText(String text);

  Future<void> close();
}
