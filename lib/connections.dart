library connections;

import 'dart:async';
import 'peers.dart';
import 'package:route/server.dart';
import 'dart:io';
import 'dart:math';
import 'package:locking/locking.dart';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

final Logger log = new Logger('Connections');
final Set<String> DO_NO_PERSIST = new Set.from(['LEAVE', 'EXPIRE']);
  
class PeerConnections {
  Object _obj = new Object();
  Map<String, Client> _clients = {};
  List<Client> _activeClients = [];

  Map<String, Client> get clients => _clients;
  List<Client> get activeClients => _activeClients;

  PeerConnection() {
    Logger.root.onRecord.listen(new LogPrintHandler());
    log.onRecord.listen(new LogPrintHandler()); 
  }
  
  Future handleConfigRequest(HttpRequest request) async {
    setAccessHeaders(request);
    request.response.headers.add('Content-Type', 'application/octet-stream');
    var params = PATTERN.parse(request.uri.path);
    var id = params[0];
    var pad = '00';
    for (var i = 0; i < 10; i++) {
      pad += pad;
    }
    request.response.write(pad + '\n');
    (lock(_obj, () => addNewClient(id, request.connectionInfo))).whenComplete(() {
      // TODO: Send outstanding data.
      request.response.write("{\"type\":\"OPEN\"}");
      request.response.close();
    });
  }
   
  Future registerWebSocket(id, WebSocket webSocket, HttpRequest request) async {
    Client client = _clients[id];
    if (client == null) {
      // If no client then register one now!
      int a = new Random().nextInt(0xffffffff);
      id = "id-${a.toRadixString(16)}";
      log.info("No existing client while registring websocket, creating one $id");
      return (lock(_obj, () => addNewClient(id, request.connectionInfo))).then((client) {
         _registerWebSocket(id, webSocket);
      });
    }
    log.info("Registering websocket for $id");
    return _registerWebSocket(id, webSocket);
  }

  Future _registerWebSocket(id, WebSocket webSocket) async {
    Client client = _clients[id];
    if (client == null || client.closed) {
      // Client was closed for some reason.
      webSocket.close(1002, "No associated client");
      log.warning("No client to register websocket with for ${id}! Only ${_clients}");
      return;
    }
    client.webSocket = webSocket;
    // Listen for incoming data. We expect the data to be a JSON-encoded String.
    webSocket.map((string)=> JSON.decode(string))
        .listen((json) {
      client.handleWebSocketMessage(json);
    }, onError: (error) {
      log.warning('Bad WebSocket request ${error} ${client.id} closed');
      client.closed = true;
    }, onDone: () {
      log.info("Websocket for ${client.id} closed");
      client.closed = true;
    });
    // Send list of active peers.
    lock(_obj, () => listActiveClientIdsAndPurgeOld() ).then((List<Client> active) {
      List<Client> activeCopy = new List.from(_activeClients);
      sortByClosestIp(activeCopy, client);
      List<String> closeActiveIds = activeCopy.map((Client c) => c.id).toList();
      // Also send he self id here.
      Map data = {'type':'ACTIVE_IDS', 'ids': closeActiveIds, 'id': id};
      log.info("Sending current client data ${data}");
      client.send(JSON.encode(data));
    });
  }

  Future<List<Client>> listActiveClientIdsAndPurgeOld() async {
    List<Client> ids = new List();
    Map<String, Client> clients = new Map();
    _clients.forEach((id, Client client) {
      if (!client.invalid()) {
        clients[id] = client;
        if (client.active()) {
          ids.add(client);
        }
      }
    });
    _clients = clients;
    _activeClients = ids;
    return _activeClients;
  }


  Future addNewClient(String id, HttpConnectionInfo connectionInfo) async {
    String ip = connectionInfo.remoteAddress.address;
    _clients[id] = new Client(this, ip, id, connectionInfo.remoteAddress.rawAddress);
    log.info("Added client $id $ip as ${_clients[id]}");
    return _clients[id];
  }

  /**
   * Return a list sorted with the closest matching IP to ours first.
   * This means users on the same private network is more likely to connect to
   * eachother.
   */
  List<Client> sortByClosestIp(List<Client> clients, Client selfClient) {
    int selfRawIp = selfClient.rawIp;
    clients.sort((Client a, Client b) {
      int aDistance = a.rawIp ^ selfRawIp;
      int bDistance = b.rawIp ^ selfRawIp;
      return aDistance > bDistance ? 1 : -1;
    });
    return clients;
  }
}

int _toSingleIntRepr(List<int> rawIp) => rawIp[0] << 24 | rawIp[1] << 16 | rawIp[2] << 8 | rawIp[3];

class Client {
  static Duration WEB_SOCKET_GRACE_TIME = new Duration(seconds: 20);
  PeerConnections peerConnections;
  DateTime created;
  String ip;
  int rawIp;
  String id;
  WebSocket webSocket = null;
  bool closed = false;
  
  Client(this.peerConnections, this.ip, this.id, List<int> rawIp) {
    created = new DateTime.now();
    // We expect only ipv4 addresses right now.
    this.rawIp = _toSingleIntRepr(rawIp);
  }
  
  /**
   * Client will be invalid if closed or a websocket has not been opened within WEB_SOCKET_GRACE_TIME.
   */
  bool invalid() {
    DateTime now = new DateTime.now();
    return closed || 
        (webSocket == null && now.millisecondsSinceEpoch - created.millisecondsSinceEpoch > WEB_SOCKET_GRACE_TIME.inMilliseconds);
  }

  /**
   * If this client has an active websocket.
   */
  bool active() => webSocket != null;
  
  void handleWebSocketMessage(json) {
    var type = json['type'];
    var dst = json['dst'];
    json['src'] = id;
    var data = JSON.encode(json);
    
    Client destination = peerConnections._clients[dst];
    if (destination != null) {
      log.info("$id -> $dst: $data");
      destination.send(JSON.encode(json));
    } else {
      send(JSON.encode(leaveMessage(dst)));
    }
  }
  
  send(var data) {
    if (webSocket == null) {
      log.warning("Attempting to send to client without initalized socket ${this.id}");
      return;
    }
    webSocket.add(data);
  }

  Map leaveMessage(dst) {
    return {
      'type': 'LEAVE',
      'src': dst,
      'dst': id
    };
  }

  toString() => "Client $ip $id";
}

