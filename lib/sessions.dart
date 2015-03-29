int FRESH_MILLIS = 60 * 1000;
List<Session> _sessions = new List<Session>();

List<Session> getSessions(int max) {
  List<Session> result = _copyActiveSessionsAndAdd(null);
  while (result.length > max) {
    result.removeLast();
  }
  return result;
}

reportSessionFromUri(Uri uri) {
  Map<String, String> parameters = uri.queryParameters;
  if (!parameters.containsKey("r") || !parameters.containsKey("p")) {
    throw new ArgumentError("Incorrect URI parameters");
  }
  Session reportedSession = new Session.fromUri(parameters["r"], parameters["p"]);
  _sessions = _copyActiveSessionsAndAdd(reportedSession);
}

List<Session> _copyActiveSessionsAndAdd(Session session) {
  List<Session> result = new List.from(_sessions);
  result.removeWhere((s) => !s.isFresh(FRESH_MILLIS)
      || (session != null && s.reportingPeer == session.reportingPeer));
  if (session != null) {
    result.add(session);
  }
  return result;
}

class Session {
  String reportingPeer;
  List<String> peers;
  DateTime reportedAt;
  
  Map asMap() {
    return {"r": reportingPeer, "p": peers.join(",")};
  }

  bool isFresh(int freshMillis) {
    int nowMillis = new DateTime.now().millisecondsSinceEpoch;
    int minAgeFresh = nowMillis - freshMillis;
    return reportedAt.millisecondsSinceEpoch >= minAgeFresh;
  }

  Session.fromUri(String reportingPeer, String peersString) {
    reportedAt = new DateTime.now();
    this.reportingPeer = reportingPeer;
    this.peers = peersString.split(",");
  }
}