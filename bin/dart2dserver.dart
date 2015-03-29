library dart2dserver;

import 'dart:io';
import 'dart:convert';
import 'dart:async';

import '../lib/sessions.dart';
import '../lib/peers.dart';
import 'package:route/server.dart';

HttpServer _server;
PeerServer _peerServer;
const PORT = 8089;

stopServer() {
  if (_server == null) {
    throw new ArgumentError("No server to stop");
  }
  _server.close();
  _server = null;
}

Future<HttpServer> startServer() {
  Future<HttpServer> serverFuture = HttpServer.bind(InternetAddress.ANY_IP_V4, PORT);
  serverFuture.then((server) {
    _server = server;
    var router = new Router(server);
    _peerServer = new PeerServer(router);
    router.serve('/').listen((HttpRequest request) {
      try {
        handleRequest(request);
      } catch (e) {
        print("Error handling request ${e}");
        request.response.write("Boom!");
        request.response.close();
      }
    });
  });
  return serverFuture;
}

handleRequest(var request) {
  var uri = request.uri;
  if (uri.queryParameters.containsKey("r")) {
    reportSessionFromUri(uri);
    request.response.write('OK');
  } else if (uri.queryParameters.containsKey("g")) {
    int max = int.parse(uri.queryParameters["g"]);
    List<Session> sessions = getSessions(max);
    List<Map> maps = new List<Map>.from(sessions.map((e) => e.asMap()));
    request.response.write(JSON.encode(maps));
  } else {
    request.response.write('This isn\'t where you parked your car!');
  }
  request.response.close();
}

main() {
  startServer();
}