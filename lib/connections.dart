library connections;

import 'dart:async';
import 'peers.dart';
import 'package:route/server.dart';
import 'dart:io';
import 'package:locking/locking.dart';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

final Logger log = new Logger('Connections');
final Set<String> DO_NO_PERSIST = new Set.from(['LEAVE', 'EXPIRE']);
  
class PeerConnections {
  Object _obj = new Object();
  Map<String, Client> _clients = {};
  List<String> _activeClients = [];
    
  PeerConnection() {
    Logger.root.onRecord.listen(new LogPrintHandler());
    log.onRecord.listen(new LogPrintHandler()); 
  }
  
  Future handleConfigRequest(HttpRequest request) async {
    setAccessHeaders(request);
    request.response.headers.add('Content-Type', 'application/octet-stream');
    var params = PATTERN.parse(request.uri.path);
    var id = params[0];
    var token = params[1];
    var ip = request.connectionInfo.remoteAddress.address;
    var pad = '00';
    for (var i = 0; i < 10; i++) {
      pad += pad;
    }
    request.response.write(pad + '\n');
    (lock(_obj, () { addNewClient(id, ip); })).whenComplete(() {
      // TODO: Send outstanding data.
      request.response.write("{\"type\":\"OPEN\"}");
      request.response.close();
    });
  }
   
  Future registerWebSocket(id, WebSocket webSocket) async {
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
    lock(_obj, () {listActiveClientIdsAndPurgeOld(); }).then((value) {
      Map data = {'type':'ACTIVE_IDS', 'ids': _activeClients};
      log.info("Sending current client data ${data}");
      client.send(JSON.encode(data));
    });
  }

  Future<List<String>> listActiveClientIdsAndPurgeOld() async {
    List<String> ids = new List();
    Map<String, Client> clients = new Map();
    _clients.forEach((id, Client client) {
      if (!client.invalid()) {
        clients[id] = client;
        ids.add(id);
      }
    });
    _clients = clients;
    _activeClients = ids;
  }


  Future addNewClient(id, ip) async {
    _clients[id] = new Client(this, ip, id);
    log.info("Added client $id $ip as ${_clients[id]}");
  }
}

class Client {
  static final Duration WEB_SOCKET_GRACE_TIME = new Duration(seconds: 30);
  PeerConnections peerConnections;
  DateTime created;
  var ip;
  var id;
  WebSocket webSocket = null;
  bool closed = false;
  
  Client(this.peerConnections, this.ip, this.id) {
    created = new DateTime.now();
  }
  
  /**
   * Client will be invalid if closed or a websocket has not been opened within WEB_SOCKET_GRACE_TIME.
   */
  bool invalid() {
    DateTime now = new DateTime.now();
    return closed || 
        (webSocket == null && now.millisecondsSinceEpoch - created.millisecondsSinceEpoch > WEB_SOCKET_GRACE_TIME.inMilliseconds);
  }
  
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


/*
  // User is connected!
  if (destination) {
    try {
      util.log(type, 'from', src, 'to', dst);
      if (destination.socket) {
        destination.socket.send(data);
      } else if (destination.res) {
        data += '\n';
        destination.res.write(data);
      } else {
        // Neither socket no res available. Peer dead?
        throw "Peer dead";
      }
    } catch (e) {
      // This happens when a peer disconnects without closing connections and
      // the associated WebSocket has not closed.
      util.prettyError(e);
      // Tell other side to stop trying.
      this._removePeer(key, dst);
      this._handleTransmission(key, {
        type: 'LEAVE',
        src: dst,
        dst: src
      });
    }
  } else {
    // Wait for this client to connect/reconnect (XHR) for important
    // messages.
    if (type !== 'LEAVE' && type !== 'EXPIRE' && dst) {
      var self = this;
      if (!this._outstanding[key][dst]) {
        this._outstanding[key][dst] = [];
      }
      this._outstanding[key][dst].push(message);
    } else if (type === 'LEAVE' && !dst) {
      this._removePeer(key, src);
    } else {
      // Unavailable destination specified with message LEAVE or EXPIRE
      // Ignore
    }
  }
}; */
