import 'package:dart2dserver/connections.dart';
import 'package:test/test.dart';
import 'dart:async';
import 'package:mockito/mockito.dart';
import 'dart:io';

class FakeHttpConnectionInfo extends Mock implements HttpConnectionInfo {
  FakeHttpConnectionInfo(String ip) {
    remoteAddress = new InternetAddress(ip);
  }
  InternetAddress remoteAddress;
}

class MockHttpHeaders extends Mock implements HttpHeaders { }

class MockHttpResponse extends Mock implements HttpResponse {
  MockHttpHeaders headers = new MockHttpHeaders();
  void write(Object s) {
    print(s);
  }
}

class MockWebSocket extends Mock implements WebSocket {
  Stream/*<S>*/ map/*<S>*/(/*=S*/ convert(event)) {
    return this;
  }
}

class MockHttpRequest extends Mock implements HttpRequest {
  MockHttpResponse response = new MockHttpResponse();
  Uri uri = Uri.parse("http://www.test.com/peerconfig/something/myid/id");
  FakeHttpConnectionInfo connectionInfo = new FakeHttpConnectionInfo("1.2.3.4");
}

void main() {
  PeerConnections connections;

  setUp(() {
    connections = new PeerConnections();
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
    await connections.addNewClient("1234", info).then(expectAsync1((Client client){
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

    expect(connections.sortByClosestIp(list, c1), equals([
       c1, c2, c6, c5, c3, c4]));

    expect(connections.sortByClosestIp(list, c4), equals([
      c4, c3, c2, c1, c6, c5]));
  });
  test('TestUpdateActiveClientsAndRegisterSocket', () async {
    Client.WEB_SOCKET_GRACE_TIME = new Duration(milliseconds: 25);
    await connections.addNewClient("1234", new FakeHttpConnectionInfo("1.2.3.4"));
    await connections.addNewClient("4321", new FakeHttpConnectionInfo("4.3.2.1"));
    await connections.addNewClient("1111", new FakeHttpConnectionInfo("1.1.1.1"));
    expect(connections.clients.length, equals(3));
    await connections.listActiveClientIdsAndPurgeOld();
    expect(connections.clients.length, equals(3));

    MockWebSocket socket = new MockWebSocket();
    await connections.registerWebSocket("missing", socket);
    verify(socket.close(1002, "No associated client"));

    MockWebSocket socket1 = new MockWebSocket();
    MockWebSocket socket4 = new MockWebSocket();
    when(socket1.add(any)).thenAnswer((Invocation i) {
      String data = i.positionalArguments[0];
      expect(data, equals("{\"type\":\"ACTIVE_IDS\",\"ids\":[\"1111\",\"4321\"]}"));
    });
    when(socket4.add(any)).thenAnswer((Invocation i) {
      String data = i.positionalArguments[0];
      expect(data, equals("{\"type\":\"ACTIVE_IDS\",\"ids\":[\"4321\",\"1111\"]}"));
    });
    await connections.registerWebSocket("1111", socket1);
    await connections.registerWebSocket("4321", socket4);
    sleep(new Duration(milliseconds: 50));

    // The client with missing socket got purged. OOps.
    await connections.listActiveClientIdsAndPurgeOld();
    expect(connections.clients.length, equals(2));
  });
}