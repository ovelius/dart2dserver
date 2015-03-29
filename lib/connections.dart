library connections;

import 'peers.dart';
import 'package:route/server.dart';
import 'dart:io';
import 'dart:convert';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

final Logger log = new Logger('Connections');
final Set<String> DO_NO_PERSIST = new Set.from(['LEAVE', 'EXPIRE']);
  
class PeerConnections {
  Map<String, Client> _clients = {};
  Map<String, List<String>> _outstanding = {};
  Map<dynamic, int> _ips = {};
    
  PeerConnection() {
    Logger.root.onRecord.listen(new LogPrintHandler());
    log.onRecord.listen(new LogPrintHandler()); 
  }
  
  void handleConfigRequest(HttpRequest request) {
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
    _clients[id] = new Client(this, ip, id, token, null);
    // TODO: Send outstanding data.
    request.response.write("{\"type\":\"OPEN\"}");
    request.response.close();
  }
   
  void registerWebSocket(id, webSocket) {
    Client client = _clients[id];
    client.webSocket = webSocket;
    // Listen for incoming data. We expect the data to be a JSON-encoded String.
    webSocket.map((string)=> JSON.decode(string))
      .listen((json) {
        client.handleWebSocketMessage(json);
      }, onError: (error) {
        print('Bad WebSocket request');
      });
  }
}

class Client {
  PeerConnections peerConnections;
  var ip;
  var id;
  var token;
  WebSocket webSocket;
  Client(this.peerConnections, this.ip, this.id, this.token, this.webSocket);
  
  void handleWebSocketMessage(json) {
    var type = json['type'];
    var dst = json['dst'];
    json['src'] = id;
    var data = JSON.encode(json);
    
    Client destination = peerConnections._clients[dst];
    if (destination != null) {
      log.info("$id -> $dst: $data");
      destination.send(JSON.encode(json));
      // Send LEAVE back if failing.
    } else if (!DO_NO_PERSIST.contains(type)) {
      // Add to outstanding.
      if (!peerConnections._outstanding.containsKey(dst)) {
        peerConnections._outstanding[dst] = new List();
      }
      peerConnections._outstanding[dst].add(data);
    }
  }
  
  send(var data) {
    webSocket.add(data);
  }
}


Map leaveMessage(src, dst) {
  return {
    'type': 'LEAVE',
    'src': src,
    'dst': dst
  };
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
