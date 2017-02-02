library peers;

import 'dart:io';
import 'dart:math';
import 'dart:convert';
import 'package:route/server.dart';
import 'connections.dart';
import 'package:logging/logging.dart';
import 'package:logging_handlers/logging_handlers_shared.dart';

final Logger log = new Logger('PeerServer');

setAccessHeaders(HttpRequest request) {
  request.response.headers.add('Access-Control-Allow-Origin', '*');
  request.response.headers.add('Access-Control-Allow-Methods', 'GET,PUT,POST,DELETE');
  request.response.headers.add('Access-Control-Allow-Headers', 'Content-Type');
}

UrlPattern PATTERN = new UrlPattern(r'/peerconfig/(.*)/(.*)/id');

class PeerServer {
  
  PeerConnections peerConnections;
  
  PeerServer(Router router) {
    Logger.root.level = Level.ALL;
    log.onRecord.listen(new LogPrintHandler()); 
    peerConnections = new PeerConnections();
    router.serve('/peerconfig/id').listen(responseWithNewId);
    router.serve('/peerjs')
        .listen((HttpRequest request) {
           if (WebSocketTransformer.isUpgradeRequest(request)) {
             var id = request.uri.queryParameters['id'];
             WebSocketTransformer.upgrade(request).then((WebSocket socket) {
                 peerConnections.registerWebSocket(id, socket, request);
             });
           }
        });
    router.serve(PATTERN).listen(peerConnections.handleConfigRequest);
  }

  void responseWithNewId(HttpRequest request) {
    int a = new Random().nextInt(0xffffffff);
    setAccessHeaders(request);
    String id = "id-${a.toRadixString(16)}";
    log.info("Generated id ${id} for ${request.connectionInfo.remoteAddress.address}");
    request.response.write(id);
    request.response.close();
  }
}
