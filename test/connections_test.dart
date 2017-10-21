import 'package:dart2dserver/connections.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'dart:convert';
import 'package:mockito/mockito.dart';
import 'dart:io';
import 'package:logging/logging.dart' show Logger, Level, LogRecord;

class FakeHttpConnectionInfo extends Mock implements HttpConnectionInfo {
  FakeHttpConnectionInfo(String ip) {
    remoteAddress = new InternetAddress(ip);
  }
  InternetAddress remoteAddress;
}

class MockHttpHeaders extends Mock implements HttpHeaders {}

class MockHttpResponse extends Mock implements HttpResponse {
  MockHttpHeaders headers = new MockHttpHeaders();
  void write(Object s) {
    print(s);
  }
}

class MockWebSocket extends Mock implements WebSocket {
  List<Map> sentData = [];

  Stream/*<S>*/ map/*<S>*/(/*=S*/ convert(event)) {
    return this;
  }

  void add(String data) {
    sentData.add(JSON.decode(data));
  }
}

class MockHttpRequest extends Mock implements HttpRequest {
  MockHttpResponse response = new MockHttpResponse();
  Uri uri = Uri.parse("http://www.test.com/peerconfig/something/myid/id");
  FakeHttpConnectionInfo connectionInfo = new FakeHttpConnectionInfo("1.2.3.4");
}

logOutputForTest() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((LogRecord rec) {
    String msg = '${rec.loggerName}: ${rec.level.name}: ${rec.time}: ${rec.message}';
    print(msg);
  });
}

void main() {
  PeerConnections connections;

  setUp(() {
    connections = new PeerConnections();
    logOutputForTest();
  });

  Client clientForTest(String ip) {
    InternetAddress address = new InternetAddress(ip);
    return new Client(connections, ip, "id_$ip", address.rawAddress);
  }

  test('TestGeConfig', () async {
    MockHttpRequest request = new MockHttpRequest();
    await connections.handleConfigRequest(request);
    // TODO assert things?
    print("hello!");
  });
  test('TestAddClient', () async {
    FakeHttpConnectionInfo info = new FakeHttpConnectionInfo("1.2.3.4");
    await connections
        .addNewClient("1234", info)
        .then(expectAsync1((Client client) {
      expect(client.id, equals("1234"));
      expect(client.ip, equals("1.2.3.4"));
      int expectedRawIp = 1 << 24 | 2 << 16 | 3 << 8 | 4;
      expect(client.rawIp, equals(expectedRawIp));
      expect(connections.clients["1234"], equals(client));
    }));
  });
  test('TestSortByIp', () {
    Client c1 = clientForTest("1.1.1.1");
    Client c2 = clientForTest("1.1.1.2");
    Client c3 = clientForTest("2.1.1.2");
    Client c4 = clientForTest("2.3.1.2");
    Client c5 = clientForTest("1.192.1.2");
    Client c6 = clientForTest("1.1.244.244");

    List<Client> list = [c1, c2, c3, c4, c5, c6];

    expect(connections.sortByClosestIp(list, c1),
        equals([c1, c2, c6, c5, c3, c4]));

    expect(connections.sortByClosestIp(list, c4),
        equals([c4, c3, c2, c1, c6, c5]));
  });
  test('TestUpdateActiveClientsAndRegisterSocket', () async {
    MockHttpRequest request = new MockHttpRequest();
    request.connectionInfo = new FakeHttpConnectionInfo("5.5.4.2");
    Client.WEB_SOCKET_GRACE_TIME = new Duration(milliseconds: 80);
    await connections.addNewClient(
        "1234", new FakeHttpConnectionInfo("1.2.3.4"));
    await connections.addNewClient(
        "4321", new FakeHttpConnectionInfo("4.3.2.1"));
    await connections.addNewClient(
        "1111", new FakeHttpConnectionInfo("1.1.1.1"));
    expect(connections.clients.length, equals(3));
    // No web sockets yet so no active clients.
    expect(connections.activeClients.length, equals(0));
    await connections.listActiveClientIdsAndPurgeOld();
    expect(connections.clients.length, equals(3));
    expect(connections.activeClients.length, equals(0));

    MockWebSocket socket = new MockWebSocket();
    await connections.registerWebSocket(
        "no-client-succeeeds-anyway", socket, request);

    expect(socket.sentData, hasLength(1));
    Map data = socket.sentData[0];
    expect(data, equals({
      'type': 'ACTIVE_IDS',
      'ids': ['no-client-succeeeds-anyway'],
      'id': 'no-client-succeeeds-anyway'
    }));

    await connections.listActiveClientIdsAndPurgeOld();
    expect(connections.activeClients.length, equals(1));

    MockWebSocket socket1 = new MockWebSocket();
    MockWebSocket socket4 = new MockWebSocket();
    // Close one of them.
    connections.clients["1111"].closed = true;
    await connections.registerWebSocket("1111", socket1, request);
    expect(connections.clients["1111"].closed, isFalse);

    expect(socket1.sentData, hasLength(1));
    expect(socket1.sentData[0], equals({
      'type': 'ACTIVE_IDS',
      'ids': ['1111', 'no-client-succeeeds-anyway'],
      'id': '1111'
    }));

    await connections.registerWebSocket("4321", socket4, request);

    expect(socket4.sentData, hasLength(1));
    expect(socket4.sentData[0], equals({
      'type': 'ACTIVE_IDS',
      'ids': ['4321', 'no-client-succeeeds-anyway', '1111'],
      'id': '4321'
    }));

    sleep(new Duration(milliseconds: 70));
    // The old client got purged.
    expect(connections.clients.length, equals(4));
    await connections.listActiveClientIdsAndPurgeOld();
    expect(connections.clients.length, equals(3));
    expect(connections.activeClients.length, equals(3));
  });

  test('TestUnresponsiveClient', () async {
    Client.UNRESPONSIVE_TIMEOUT = new Duration(milliseconds: 60);
    await connections.addNewClient(
      "1234", new FakeHttpConnectionInfo("1.2.3.4"));
    await connections.addNewClient(
      "4321", new FakeHttpConnectionInfo("4.3.2.1"));

    MockWebSocket socket1 = new MockWebSocket();
    MockWebSocket socket2 = new MockWebSocket();

    await connections.registerWebSocket("1234", socket1, new MockHttpRequest());
    await connections.registerWebSocket("4321", socket2, new MockHttpRequest());

    expect(connections.clients["1234"].active(), isTrue);
    expect(connections.clients["4321"].active(), isTrue);

    connections.clients["1234"].handleWebSocketMessage({"type": "test", "dst":"4321"});
    expect(socket2.sentData, hasLength(2));
    sleep(new Duration(milliseconds: 50));

    connections.clients["1234"].handleWebSocketMessage({"type": "respond please!", "dst":"4321"});
    expect(socket2.sentData, hasLength(3));

    expect(connections.clients["4321"].sinceLastResponse().inMilliseconds, greaterThan(30));

    sleep(new Duration(milliseconds: 50));

    connections.clients["1234"].handleWebSocketMessage({"type": "goodbye :(", "dst":"4321"});
    expect(socket2.sentData, hasLength(4));

    expect(connections.clients["4321"].validState(), equals(ClientState.UNRESPONSIVE));
  });
}
